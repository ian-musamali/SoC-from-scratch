//-----------------------------------------------------------------------------
// Module: conv_engine
// Description: 3x3 convolution window-walker. One `start` computes ONE output
//              channel: walks output pixels row-major, gathers zero-padded
//              activation windows and weights from single-port (1-cycle
//              latency) memories, drives the mac_array in fully serialized
//              chained passes, then requantizes (arithmetic shift + int8
//              saturation) and writes each pixel to the ofm port.
//              Bit-exact vs model/golden_conv_model.py.
//
// Parameters:
//   NUM_LANES  - MAC lanes per pass
//   DATA_W     - int8 activation/weight width
//   ACC_W      - int32 accumulator width
//   KERNEL     - kernel size (3)
//   FM_ADDR_W  - feature-map buffer address width
//   WGT_ADDR_W - weight memory address width
//   SHIFT_W    - requantization shift amount width
//
// Interfaces:
//   clk/rst_n     - Clock (posedge) and active-low async reset
//   cfg_*         - sampled on the cycle start is accepted (start && !busy)
//   start/busy/done/sat_seen - channel-level control/status
//   ifm/wgt ports - read, 1-cycle latency (addr cycle n -> rdata cycle n+1)
//   mac_*         - valid/ready master into mac_array (or UVM responder)
//   ofm port      - one write per output pixel (int8 after shift+saturate)
//
// Throughput (not a goal): 2 cycles per tap gather, +2 cycles minimum per
// MAC pass, +1 write cycle per pixel. Fully serialized FSM.
//-----------------------------------------------------------------------------
module conv_engine #(
  parameter int NUM_LANES  = tinynpu_pkg::NUM_LANES,
  parameter int DATA_W     = tinynpu_pkg::DATA_W,
  parameter int ACC_W      = tinynpu_pkg::ACC_W,
  parameter int KERNEL     = tinynpu_pkg::KERNEL,
  parameter int FM_ADDR_W  = tinynpu_pkg::FM_ADDR_W,
  parameter int WGT_ADDR_W = tinynpu_pkg::WGT_ADDR_W,
  parameter int SHIFT_W    = tinynpu_pkg::SHIFT_W
)(
  input  logic                        clk,
  input  logic                        rst_n,
  // configuration, sampled on the cycle start is accepted (start && !busy)
  input  logic [5:0]                  cfg_img_w,     // 1..32
  input  logic [5:0]                  cfg_img_h,     // 1..32
  input  logic [3:0]                  cfg_in_ch,     // 1..8
  input  logic                        cfg_stride2,   // 0: stride 1, 1: stride 2
  input  logic                        cfg_pad,       // 0: none, 1: zero-pad by 1
  input  logic [SHIFT_W-1:0]          cfg_out_shift,
  input  logic [FM_ADDR_W-1:0]        cfg_ifm_base,
  input  logic [FM_ADDR_W-1:0]        cfg_ofm_base,
  input  logic [WGT_ADDR_W-1:0]       cfg_wgt_base,
  input  logic [ACC_W-1:0]            cfg_acc_init,  // signed; acc_in of first MAC pass
  // control
  input  logic                        start,         // pulse; one output channel per start
  output logic                        busy,
  output logic                        done,          // 1-cycle pulse when the channel completes
  output logic                        sat_seen,      // sticky since start: MAC sat or int8 clamp
  // ifm read port (1-cycle latency: addr in cycle n -> rdata valid cycle n+1)
  output logic                        ifm_re,
  output logic [FM_ADDR_W-1:0]        ifm_addr,
  input  logic [DATA_W-1:0]           ifm_rdata,
  // weight read port (1-cycle latency)
  output logic                        wgt_re,
  output logic [WGT_ADDR_W-1:0]       wgt_addr,
  input  logic [DATA_W-1:0]           wgt_rdata,
  // MAC master port (mac_array or a UVM responder on the other side)
  output logic                        mac_valid,
  input  logic                        mac_ready,
  output logic [NUM_LANES*DATA_W-1:0] mac_act,
  output logic [NUM_LANES*DATA_W-1:0] mac_wgt,
  output logic [ACC_W-1:0]            mac_acc_in,
  input  logic                        mac_res_valid,
  output logic                        mac_res_ready,
  input  logic [ACC_W-1:0]            mac_res_acc,
  input  logic                        mac_res_sat,
  // ofm write port (int8 result after shift + saturation)
  output logic                        ofm_wen,
  output logic [FM_ADDR_W-1:0]        ofm_addr,
  output logic [DATA_W-1:0]           ofm_wdata
);

  // ---------------------------------------------------------------------------
  // Local parameters
  // ---------------------------------------------------------------------------
  localparam int LANE_W = $clog2(NUM_LANES);
  // Tap counter sized for the full cfg_in_ch range (15*9 = 135 max).
  localparam int TAP_W  = $clog2(15 * KERNEL * KERNEL + 1);

  localparam logic [1:0] KM1 = 2'(KERNEL - 1);

  // int8 saturation rails, at DATA_W and sign-extended to ACC_W.
  localparam logic [DATA_W-1:0] QMAX_D = {1'b0, {(DATA_W-1){1'b1}}};  //  127
  localparam logic [DATA_W-1:0] QMIN_D = {1'b1, {(DATA_W-1){1'b0}}};  // -128
  localparam logic signed [ACC_W-1:0] QMAX_ACC =
      {{(ACC_W-DATA_W+1){1'b0}}, {(DATA_W-1){1'b1}}};
  localparam logic signed [ACC_W-1:0] QMIN_ACC =
      {{(ACC_W-DATA_W+1){1'b1}}, {(DATA_W-1){1'b0}}};

  // ---------------------------------------------------------------------------
  // FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE      = 3'd0,  // wait for start
    S_ADDR      = 3'd1,  // drive ifm/wgt addresses for the current tap
    S_DATA      = 3'd2,  // capture rdata into lane staging, advance tap
    S_MAC_ISSUE = 3'd3,  // mac_valid high until mac_ready sampled
    S_MAC_WAIT  = 3'd4,  // mac_res_ready high until result captured
    S_WRITE     = 3'd5   // requantize, one-cycle ofm write, advance pixel
  } state_t;

  state_t state;

  // ---------------------------------------------------------------------------
  // Registered configuration and derived geometry
  // ---------------------------------------------------------------------------
  logic [5:0]            img_w_q, img_h_q;
  logic                  stride2_q, pad_q;
  logic [SHIFT_W-1:0]    shift_q;
  logic [FM_ADDR_W-1:0]  ifm_base_q, ofm_base_q;
  logic [WGT_ADDR_W-1:0] wgt_base_q;
  logic [ACC_W-1:0]      acc_init_q;
  logic [5:0]            out_w_q, out_h_q;    // 1..32
  logic [TAP_W-1:0]      taps_m1_q;           // in_ch*K*K - 1

  // Output dimensions from raw cfg inputs (registered on start accept).
  // out_dim = (img + 2*pad - K)/s + 1; config guarantees out dims >= 1.
  logic [6:0] eff_w_c, eff_h_c;
  logic [5:0] out_w_c, out_h_c;

  always_comb begin
    eff_w_c = {1'b0, cfg_img_w} + (cfg_pad ? 7'd2 : 7'd0) - 7'd3;
    eff_h_c = {1'b0, cfg_img_h} + (cfg_pad ? 7'd2 : 7'd0) - 7'd3;
    out_w_c = cfg_stride2 ? (6'(eff_w_c >> 1) + 6'd1) : (6'(eff_w_c) + 6'd1);
    out_h_c = cfg_stride2 ? (6'(eff_h_c >> 1) + 6'd1) : (6'(eff_h_c) + 6'd1);
  end

  // ---------------------------------------------------------------------------
  // Walk counters
  // ---------------------------------------------------------------------------
  logic [5:0]        or_q, oc_q;      // output pixel row/col
  logic [3:0]        ch_q;            // input channel of current tap
  logic [1:0]        ky_q, kx_q;      // kernel row/col of current tap
  logic [TAP_W-1:0]  tap_q;           // flat tap index t = (ch*K + ky)*K + kx
  logic [LANE_W-1:0] lane_q;          // lane within the current MAC pass
  logic              last_pass_q;     // current staged pass is the pixel's last

  // ---------------------------------------------------------------------------
  // Lane staging and accumulator chain
  // ---------------------------------------------------------------------------
  logic [NUM_LANES*DATA_W-1:0] act_q, wgt_q;
  logic [ACC_W-1:0]            acc_q;

  // ---------------------------------------------------------------------------
  // Tap coordinates (signed: can be -1 with pad=1) and bounds check
  // ---------------------------------------------------------------------------
  logic signed [7:0] row_s, col_s;
  logic              in_bounds;

  always_comb begin
    row_s = $signed({2'b00, or_q});
    col_s = $signed({2'b00, oc_q});
    if (stride2_q) begin
      row_s = row_s <<< 1;
      col_s = col_s <<< 1;
    end
    row_s = row_s + $signed({6'b0, ky_q}) - (pad_q ? 8'sd1 : 8'sd0);
    col_s = col_s + $signed({6'b0, kx_q}) - (pad_q ? 8'sd1 : 8'sd0);
  end

  assign in_bounds = (row_s >= 8'sd0) && (row_s < $signed({2'b00, img_h_q})) &&
                     (col_s >= 8'sd0) && (col_s < $signed({2'b00, img_w_q}));

  // ---------------------------------------------------------------------------
  // Address math (never truncates before FM_ADDR_W: max linear offset is
  // (7*32 + 31)*32 + 31 = 8191 < 2^FM_ADDR_W; values fit by construction)
  // ---------------------------------------------------------------------------
  logic [FM_ADDR_W-1:0]  ifm_lin_c, ofm_lin_c;
  logic [FM_ADDR_W-1:0]  ifm_addr_c, ofm_addr_c;
  logic [WGT_ADDR_W-1:0] wgt_addr_c;

  always_comb begin
    // (ch*img_h + r)*img_w + c  (row_s/col_s are non-negative when in bounds)
    ifm_lin_c  = (FM_ADDR_W'(ch_q) * FM_ADDR_W'(img_h_q)
                  + FM_ADDR_W'(row_s[5:0])) * FM_ADDR_W'(img_w_q)
                 + FM_ADDR_W'(col_s[5:0]);
    ifm_addr_c = ifm_base_q + ifm_lin_c;
    wgt_addr_c = wgt_base_q + WGT_ADDR_W'(tap_q);
    ofm_lin_c  = FM_ADDR_W'(or_q) * FM_ADDR_W'(out_w_q) + FM_ADDR_W'(oc_q);
    ofm_addr_c = ofm_base_q + ofm_lin_c;
  end

  // ---------------------------------------------------------------------------
  // Requantization: arithmetic shift then int8 saturation
  // ---------------------------------------------------------------------------
  logic signed [ACC_W-1:0] shifted_s;
  logic [DATA_W-1:0]       quant_c;
  logic                    clamp_c;

  always_comb begin
    shifted_s = $signed(acc_q) >>> shift_q;
    if (shifted_s > QMAX_ACC) begin
      quant_c = QMAX_D;
      clamp_c = 1'b1;
    end else if (shifted_s < QMIN_ACC) begin
      quant_c = QMIN_D;
      clamp_c = 1'b1;
    end else begin
      quant_c = shifted_s[DATA_W-1:0];
      clamp_c = 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Pass/tap boundary detection (evaluated in S_DATA, before counters advance)
  // ---------------------------------------------------------------------------
  logic last_tap_c, pass_full_c;

  assign last_tap_c  = (tap_q == taps_m1_q);
  assign pass_full_c = (lane_q == LANE_W'(NUM_LANES - 1));

  // ---------------------------------------------------------------------------
  // Main FSM + datapath
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= S_IDLE;
      busy        <= 1'b0;
      done        <= 1'b0;
      sat_seen    <= 1'b0;
      img_w_q     <= '0;
      img_h_q     <= '0;
      stride2_q   <= 1'b0;
      pad_q       <= 1'b0;
      shift_q     <= '0;
      ifm_base_q  <= '0;
      ofm_base_q  <= '0;
      wgt_base_q  <= '0;
      acc_init_q  <= '0;
      out_w_q     <= '0;
      out_h_q     <= '0;
      taps_m1_q   <= '0;
      or_q        <= '0;
      oc_q        <= '0;
      ch_q        <= '0;
      ky_q        <= '0;
      kx_q        <= '0;
      tap_q       <= '0;
      lane_q      <= '0;
      last_pass_q <= 1'b0;
      act_q       <= '0;
      wgt_q       <= '0;
      acc_q       <= '0;
    end else begin
      done <= 1'b0;  // default: done is a 1-cycle pulse

      unique case (state)
        // -------------------------------------------------------------------
        S_IDLE: begin
          if (start && !busy) begin
            img_w_q     <= cfg_img_w;
            img_h_q     <= cfg_img_h;
            stride2_q   <= cfg_stride2;
            pad_q       <= cfg_pad;
            shift_q     <= cfg_out_shift;
            ifm_base_q  <= cfg_ifm_base;
            ofm_base_q  <= cfg_ofm_base;
            wgt_base_q  <= cfg_wgt_base;
            acc_init_q  <= cfg_acc_init;
            out_w_q     <= out_w_c;
            out_h_q     <= out_h_c;
            taps_m1_q   <= TAP_W'(cfg_in_ch) * TAP_W'(KERNEL * KERNEL)
                           - TAP_W'(1);
            or_q        <= '0;
            oc_q        <= '0;
            ch_q        <= '0;
            ky_q        <= '0;
            kx_q        <= '0;
            tap_q       <= '0;
            lane_q      <= '0;
            last_pass_q <= 1'b0;
            act_q       <= '0;
            wgt_q       <= '0;
            acc_q       <= cfg_acc_init;
            sat_seen    <= 1'b0;
            busy        <= 1'b1;
            state       <= S_ADDR;
          end
        end

        // -------------------------------------------------------------------
        // Addresses (and re) driven combinationally this cycle; rdata is
        // valid during the following S_DATA cycle.
        S_ADDR: begin
          state <= S_DATA;
        end

        // -------------------------------------------------------------------
        S_DATA: begin
          // Out-of-window taps stay 0 (staging was cleared at pass start).
          if (in_bounds) begin
            act_q[32'(lane_q)*DATA_W +: DATA_W] <= ifm_rdata;
          end
          wgt_q[32'(lane_q)*DATA_W +: DATA_W] <= wgt_rdata;

          // Advance tap: t = (ch*K + ky)*K + kx, kx innermost.
          tap_q <= tap_q + TAP_W'(1);
          if (kx_q == KM1) begin
            kx_q <= '0;
            if (ky_q == KM1) begin
              ky_q <= '0;
              ch_q <= ch_q + 4'd1;
            end else begin
              ky_q <= ky_q + 2'd1;
            end
          end else begin
            kx_q <= kx_q + 2'd1;
          end

          if (last_tap_c || pass_full_c) begin
            lane_q      <= '0;
            last_pass_q <= last_tap_c;
            state       <= S_MAC_ISSUE;
          end else begin
            lane_q <= lane_q + LANE_W'(1);
            state  <= S_ADDR;
          end
        end

        // -------------------------------------------------------------------
        // mac_valid high with stable buses until mac_ready sampled high.
        S_MAC_ISSUE: begin
          if (mac_ready) begin
            state <= S_MAC_WAIT;
          end
        end

        // -------------------------------------------------------------------
        // mac_res_ready high while waiting; capture on the handshake.
        S_MAC_WAIT: begin
          if (mac_res_valid) begin
            acc_q    <= mac_res_acc;
            sat_seen <= sat_seen | mac_res_sat;
            if (last_pass_q) begin
              state <= S_WRITE;
            end else begin
              act_q <= '0;   // clear staging for the next pass
              wgt_q <= '0;
              state <= S_ADDR;
            end
          end
        end

        // -------------------------------------------------------------------
        // One-cycle ofm write (wen/addr/wdata driven combinationally from
        // this state), then advance to the next pixel or finish.
        S_WRITE: begin
          if (clamp_c) begin
            sat_seen <= 1'b1;
          end
          // Re-arm the per-pixel walk.
          tap_q       <= '0;
          ch_q        <= '0;
          ky_q        <= '0;
          kx_q        <= '0;
          lane_q      <= '0;
          last_pass_q <= 1'b0;
          act_q       <= '0;
          wgt_q       <= '0;
          acc_q       <= acc_init_q;
          if (oc_q == out_w_q - 6'd1) begin
            oc_q <= '0;
            if (or_q == out_h_q - 6'd1) begin
              busy  <= 1'b0;
              done  <= 1'b1;
              state <= S_IDLE;
            end else begin
              or_q  <= or_q + 6'd1;
              state <= S_ADDR;
            end
          end else begin
            oc_q  <= oc_q + 6'd1;
            state <= S_ADDR;
          end
        end

        // -------------------------------------------------------------------
        default: state <= S_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Output drive
  // ---------------------------------------------------------------------------
  assign ifm_re   = (state == S_ADDR) && in_bounds;  // no read for padding taps
  assign ifm_addr = ifm_re ? ifm_addr_c : '0;

  assign wgt_re   = (state == S_ADDR);
  assign wgt_addr = wgt_re ? wgt_addr_c : '0;

  assign mac_valid     = (state == S_MAC_ISSUE);
  assign mac_act       = act_q;
  assign mac_wgt       = wgt_q;
  assign mac_acc_in    = acc_q;
  assign mac_res_ready = (state == S_MAC_WAIT);

  assign ofm_wen   = (state == S_WRITE);
  assign ofm_addr  = ofm_wen ? ofm_addr_c : '0;
  assign ofm_wdata = ofm_wen ? quant_c : '0;

endmodule : conv_engine
