//-----------------------------------------------------------------------------
// Module: npu_core
// Description: TinyNPU layer-sequencing core. Walks a table of layer
//              descriptors and, for each layer, launches one conv_engine
//              run per output channel with derived per-channel weight and
//              OFM base addresses (bit-exact vs run_program() in
//              model/golden_conv_model.py).
//
// Parameters:
//   NUM_LANES  - MAC lanes per transaction
//   DATA_W     - signed activation/weight width (int8)
//   ACC_W      - signed accumulator width (int32)
//   KERNEL     - fixed square kernel size (3)
//   MAX_LAYERS - layer descriptor table depth
//   FM_ADDR_W  - unified feature-map buffer address width
//   WGT_ADDR_W - weight memory address width
//
// Interfaces:
//   clk/rst_n       - Clock (posedge) and active-low async reset
//   cfg_layers      - layer program, element 0 first; sampled while running
//   cfg_num_layers  - number of layers to execute (1..MAX_LAYERS)
//   start/busy/done - run handshake; done is a 1-cycle pulse
//   sat_seen        - sticky OR of conv saturation events since start
//   fm_*            - unified int8 feature-map buffer (1 read + 1 write port)
//   wgt_*           - int8 weight memory read port
//
// Sequencing (matches golden run_program()):
//   for l in 0..cfg_num_layers-1:
//     out_w = ((img_w + 2*pad - KERNEL) >> stride2) + 1  (same for out_h)
//     taps  = in_ch * KERNEL * KERNEL
//     for oc in 0..out_ch-1:
//       conv start with wgt_base + oc*taps, ofm_base + oc*out_w*out_h,
//       acc_init = 0; wait for conv done; OR conv sat_seen into sticky flag
//   pulse done, drop busy.
//-----------------------------------------------------------------------------
module npu_core #(
  parameter int NUM_LANES  = tinynpu_pkg::NUM_LANES,
  parameter int DATA_W     = tinynpu_pkg::DATA_W,
  parameter int ACC_W      = tinynpu_pkg::ACC_W,
  parameter int KERNEL     = tinynpu_pkg::KERNEL,
  parameter int MAX_LAYERS = tinynpu_pkg::MAX_LAYERS,
  parameter int FM_ADDR_W  = tinynpu_pkg::FM_ADDR_W,
  parameter int WGT_ADDR_W = tinynpu_pkg::WGT_ADDR_W
)(
  input  logic                                clk,
  input  logic                                rst_n,
  // layer program (element 0 = first layer), sampled while running
  input  tinynpu_pkg::layer_desc_t [MAX_LAYERS-1:0] cfg_layers,
  input  logic [2:0]                          cfg_num_layers,  // 1..MAX_LAYERS
  // control
  input  logic                                start,           // pulse
  output logic                                busy,
  output logic                                done,            // 1-cycle pulse
  output logic                                sat_seen,        // sticky since start
  // unified feature-map buffer (int8): 1 read + 1 write port
  output logic                                fm_re,
  output logic [FM_ADDR_W-1:0]                fm_raddr,
  input  logic [tinynpu_pkg::DATA_W-1:0]      fm_rdata,
  output logic                                fm_wen,
  output logic [FM_ADDR_W-1:0]                fm_waddr,
  output logic [tinynpu_pkg::DATA_W-1:0]      fm_wdata,
  // weight memory read port (int8)
  output logic                                wgt_re,
  output logic [WGT_ADDR_W-1:0]               wgt_addr,
  input  logic [tinynpu_pkg::DATA_W-1:0]      wgt_rdata
);

  localparam int SHIFT_W = tinynpu_pkg::SHIFT_W;

  //---------------------------------------------------------------------------
  // Sequencer FSM
  //---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IDLE        = 3'd0,  // wait for start
    LAYER_SETUP = 3'd1,  // latch descriptor, derive out dims / taps
    CH_START    = 3'd2,  // pulse conv start for one output channel
    CH_WAIT     = 3'd3,  // wait for conv done, advance oc / layer
    DONE_ST     = 3'd4   // 1-cycle done pulse
  } state_t;

  state_t state;

  // Sequencing registers
  logic [2:0]               layer_idx;  // current layer, 0..MAX_LAYERS-1
  logic [3:0]               oc_idx;     // current output channel, 0..out_ch-1
  tinynpu_pkg::layer_desc_t desc_q;     // latched descriptor of current layer
  logic [5:0]               out_w_q;    // derived output width  (1..32)
  logic [5:0]               out_h_q;    // derived output height (1..32)
  logic [6:0]               taps_q;     // in_ch * KERNEL * KERNEL (max 72)

  //---------------------------------------------------------------------------
  // Derived layer geometry (combinational, consumed in LAYER_SETUP)
  //   out_dim = ((dim + 2*pad - KERNEL) >> stride2) + 1
  //---------------------------------------------------------------------------
  tinynpu_pkg::layer_desc_t cur_desc;
  int unsigned tmp_w, tmp_h, ow_c, oh_c, taps_c;

  always_comb begin
    cur_desc = cfg_layers[layer_idx];
    tmp_w    = 32'(cur_desc.img_w) + (cur_desc.pad ? 32'd2 : 32'd0)
             - 32'(unsigned'(KERNEL));
    tmp_h    = 32'(cur_desc.img_h) + (cur_desc.pad ? 32'd2 : 32'd0)
             - 32'(unsigned'(KERNEL));
    ow_c     = (cur_desc.stride2 ? (tmp_w >> 1) : tmp_w) + 32'd1;
    oh_c     = (cur_desc.stride2 ? (tmp_h >> 1) : tmp_h) + 32'd1;
    taps_c   = 32'(cur_desc.in_ch) * unsigned'(KERNEL) * unsigned'(KERNEL);
  end

  //---------------------------------------------------------------------------
  // Per-output-channel base addresses (values fit by construction:
  //   oc*taps <= 7*72 = 504, oc*out_w*out_h <= 7*1024 = 7168)
  //---------------------------------------------------------------------------
  logic [WGT_ADDR_W-1:0] wgt_base_oc;
  logic [FM_ADDR_W-1:0]  ofm_base_oc;

  always_comb begin
    wgt_base_oc = WGT_ADDR_W'(32'(desc_q.wgt_base)
                            + 32'(oc_idx) * 32'(taps_q));
    ofm_base_oc = FM_ADDR_W'(32'(desc_q.ofm_base)
                           + 32'(oc_idx) * 32'(out_w_q) * 32'(out_h_q));
  end

  //---------------------------------------------------------------------------
  // FSM + datapath registers
  //---------------------------------------------------------------------------
  logic conv_start;
  logic conv_done;
  logic conv_sat;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= IDLE;
      layer_idx <= '0;
      oc_idx    <= '0;
      desc_q    <= '0;
      out_w_q   <= '0;
      out_h_q   <= '0;
      taps_q    <= '0;
      sat_seen  <= 1'b0;
    end else begin
      unique case (state)
        IDLE: begin
          if (start) begin
            layer_idx <= '0;
            sat_seen  <= 1'b0;
            state     <= LAYER_SETUP;
          end
        end

        LAYER_SETUP: begin
          desc_q  <= cur_desc;
          out_w_q <= 6'(ow_c);
          out_h_q <= 6'(oh_c);
          taps_q  <= 7'(taps_c);
          oc_idx  <= '0;
          state   <= CH_START;
        end

        CH_START: begin
          // conv_start pulses for exactly this one cycle (see assign below)
          state <= CH_WAIT;
        end

        CH_WAIT: begin
          if (conv_done) begin
            sat_seen <= sat_seen | conv_sat;
            if (4'(oc_idx + 4'd1) == desc_q.out_ch) begin
              if (3'(layer_idx + 3'd1) == cfg_num_layers) begin
                state <= DONE_ST;
              end else begin
                layer_idx <= layer_idx + 3'd1;
                state     <= LAYER_SETUP;
              end
            end else begin
              oc_idx <= oc_idx + 4'd1;
              state  <= CH_START;
            end
          end
        end

        DONE_ST: state <= IDLE;

        default: state <= IDLE;
      endcase
    end
  end

  assign busy       = (state != IDLE);
  assign done       = (state == DONE_ST);
  assign conv_start = (state == CH_START);

  //---------------------------------------------------------------------------
  // conv_engine <-> mac_array interconnect
  //---------------------------------------------------------------------------
  logic                        mac_valid;
  logic                        mac_ready;
  logic [NUM_LANES*DATA_W-1:0] mac_act;
  logic [NUM_LANES*DATA_W-1:0] mac_wgt;
  logic [ACC_W-1:0]            mac_acc_in;
  logic                        mac_res_valid;
  logic                        mac_res_ready;
  logic [ACC_W-1:0]            mac_res_acc;
  logic                        mac_res_sat;

  // Sequencing uses the conv done pulse only; busy is intentionally unobserved.
  /* verilator lint_off UNUSEDSIGNAL */
  logic conv_busy;
  /* verilator lint_on UNUSEDSIGNAL */

  conv_engine u_conv (
    .clk          (clk),
    .rst_n        (rst_n),
    // per-channel configuration (stable while conv is running)
    .cfg_img_w    (desc_q.img_w),
    .cfg_img_h    (desc_q.img_h),
    .cfg_in_ch    (desc_q.in_ch),
    .cfg_stride2  (desc_q.stride2),
    .cfg_pad      (desc_q.pad),
    .cfg_out_shift(desc_q.out_shift),
    .cfg_ifm_base (desc_q.ifm_base),
    .cfg_ofm_base (ofm_base_oc),
    .cfg_wgt_base (wgt_base_oc),
    .cfg_acc_init ({ACC_W{1'b0}}),
    // control
    .start        (conv_start),
    .busy         (conv_busy),
    .done         (conv_done),
    .sat_seen     (conv_sat),
    // input feature map read -> unified fm buffer read port
    .ifm_re       (fm_re),
    .ifm_addr     (fm_raddr),
    .ifm_rdata    (fm_rdata),
    // weight read -> weight memory port
    .wgt_re       (wgt_re),
    .wgt_addr     (wgt_addr),
    .wgt_rdata    (wgt_rdata),
    // MAC master port
    .mac_valid    (mac_valid),
    .mac_ready    (mac_ready),
    .mac_act      (mac_act),
    .mac_wgt      (mac_wgt),
    .mac_acc_in   (mac_acc_in),
    .mac_res_valid(mac_res_valid),
    .mac_res_ready(mac_res_ready),
    .mac_res_acc  (mac_res_acc),
    .mac_res_sat  (mac_res_sat),
    // output feature map write -> unified fm buffer write port
    .ofm_wen      (fm_wen),
    .ofm_addr     (fm_waddr),
    .ofm_wdata    (fm_wdata)
  );

  mac_array #(
    .NUM_LANES(NUM_LANES),
    .DATA_W   (DATA_W),
    .ACC_W    (ACC_W)
  ) u_mac (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_valid (mac_valid),
    .in_ready (mac_ready),
    .act      (mac_act),
    .wgt      (mac_wgt),
    .acc_in   (mac_acc_in),
    .out_valid(mac_res_valid),
    .out_ready(mac_res_ready),
    .acc_out  (mac_res_acc),
    .sat_flag (mac_res_sat)
  );

endmodule : npu_core
