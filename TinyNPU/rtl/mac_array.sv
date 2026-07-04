//-----------------------------------------------------------------------------
// Module: mac_array
// Description: 64-lane signed integer MAC array with accumulator chaining
//              and saturation to ACC_W. One transaction = one NUM_LANES-wide
//              signed dot product added to acc_in, clamped to signed ACC_W.
//
// Parameters:
//   NUM_LANES - parallel multiply lanes per transaction (power of two)
//   DATA_W    - signed activation/weight width (int8)
//   ACC_W     - signed accumulator width (int32)
//
// Interfaces:
//   clk/rst_n          - Clock (posedge) and active-low async reset
//   in_valid/in_ready  - input handshake (accepted when both high)
//   act/wgt            - flat packed lanes; lane i = bus[i*DATA_W +: DATA_W],
//                        signed two's complement, lane 0 in LSBs
//   acc_in             - signed chaining accumulator input
//   out_valid/out_ready- output handshake; acc_out/sat_flag stable while
//                        out_valid is high
//   acc_out            - signed saturated result
//   sat_flag           - 1 = acc_out was clipped this transaction
//
// Math (bit-exact vs model/golden_mac_model.py):
//   dot  = sum_i act[i]*wgt[i]      (exact, DOT_W  = 2*DATA_W+clog2(NUM_LANES))
//   full = dot + acc_in             (exact, FULL_W = max(DOT_W,ACC_W)+1)
//   acc_out = clamp(full, -2^(ACC_W-1), 2^(ACC_W-1)-1)
//   Every intermediate is wide enough that association order cannot matter,
//   so the pipelined balanced tree is bit-identical to a linear sum.
//
// Handshake: in_ready = !out_valid || out_ready (global pipeline advance).
// 4-stage pipeline — DSP products, half the adder tree, the other half,
// accumulate + saturate — latency 4, full throughput when out_ready is high,
// whole pipe stalls while out_valid is blocked. Results appear strictly in
// acceptance order; reset discards everything in flight. (A single-cycle
// combinational datapath misses 50 MHz timing by tens of ns on Artix-7.)
//-----------------------------------------------------------------------------
module mac_array #(
  parameter int NUM_LANES = tinynpu_pkg::NUM_LANES,
  parameter int DATA_W    = tinynpu_pkg::DATA_W,
  parameter int ACC_W     = tinynpu_pkg::ACC_W
)(
  input  logic                        clk,
  input  logic                        rst_n,
  input  logic                        in_valid,
  output logic                        in_ready,
  input  logic [NUM_LANES*DATA_W-1:0] act,
  input  logic [NUM_LANES*DATA_W-1:0] wgt,
  input  logic [ACC_W-1:0]            acc_in,
  output logic                        out_valid,
  input  logic                        out_ready,
  output logic [ACC_W-1:0]            acc_out,
  output logic                        sat_flag
);

  // Widths chosen so no intermediate can ever wrap.
  localparam int DOT_W  = 2*DATA_W + $clog2(NUM_LANES);           // 22 @ defaults
  localparam int FULL_W = ((DOT_W > ACC_W) ? DOT_W : ACC_W) + 1;  // 33 @ defaults

  localparam int TREE_LEVELS = $clog2(NUM_LANES);                 // 6 @ defaults
  localparam int HALF_NODES  = NUM_LANES >> (TREE_LEVELS / 2);    // 8 @ defaults

  if (NUM_LANES != (1 << TREE_LEVELS)) begin : g_param_check
    $error("mac_array: NUM_LANES must be a power of two");
  end

  // Signed saturation rails, built without 32-bit integer-literal overflow.
  localparam logic signed [FULL_W-1:0] SAT_MAX =
      {{(FULL_W-ACC_W){1'b0}}, 1'b0, {(ACC_W-1){1'b1}}};  //  2^(ACC_W-1)-1
  localparam logic signed [FULL_W-1:0] SAT_MIN =
      {{(FULL_W-ACC_W){1'b1}}, 1'b1, {(ACC_W-1){1'b0}}};  // -2^(ACC_W-1)

  // ---------------------------------------------------------------------------
  // Global pipeline advance: accept when the output register is empty or
  // draining this cycle; everything in flight stalls together otherwise.
  // ---------------------------------------------------------------------------
  logic advance;
  assign advance  = !out_valid || out_ready;
  assign in_ready = advance;

  logic v1, v2, v3;

  // ---------------------------------------------------------------------------
  // Stage 1: lane products in DSP blocks (exact int16 at default widths)
  // ---------------------------------------------------------------------------
  (* use_dsp = "yes" *) logic signed [2*DATA_W-1:0] prod_c [0:NUM_LANES-1];

  for (genvar gi = 0; gi < NUM_LANES; gi++) begin : g_prod
    assign prod_c[gi] = $signed(act[gi*DATA_W +: DATA_W])
                      * $signed(wgt[gi*DATA_W +: DATA_W]);
  end

  logic signed [2*DATA_W-1:0] s1_prod [0:NUM_LANES-1];
  logic [ACC_W-1:0]           a1, a2, a3;

  // ---------------------------------------------------------------------------
  // Stage 2: first half of the balanced adder tree (heap indexing: leaves at
  // na[NUM_LANES..2*NUM_LANES-1], na[k] = na[2k] + na[2k+1]; the stage
  // registers the HALF_NODES partial sums na[HALF_NODES..2*HALF_NODES-1]).
  // Discrete continuous assigns so synthesis cannot mistake the tree for RAM.
  // ---------------------------------------------------------------------------
  logic signed [DOT_W-1:0] na [HALF_NODES:2*NUM_LANES-1];

  for (genvar gi = 0; gi < NUM_LANES; gi++) begin : g_leaf
    assign na[NUM_LANES + gi] = DOT_W'(s1_prod[gi]);
  end
  for (genvar gk = HALF_NODES; gk < NUM_LANES; gk++) begin : g_tree_a
    assign na[gk] = na[2*gk] + na[2*gk + 1];
  end

  logic signed [DOT_W-1:0] s2_part [0:HALF_NODES-1];

  // ---------------------------------------------------------------------------
  // Stage 3: second half of the tree down to the dot product
  // ---------------------------------------------------------------------------
  logic signed [DOT_W-1:0] nb [1:2*HALF_NODES-1];

  for (genvar gi = 0; gi < HALF_NODES; gi++) begin : g_mid
    assign nb[HALF_NODES + gi] = s2_part[gi];
  end
  for (genvar gk = 1; gk < HALF_NODES; gk++) begin : g_tree_b
    assign nb[gk] = nb[2*gk] + nb[2*gk + 1];
  end

  logic signed [DOT_W-1:0] s3_dot;

  // ---------------------------------------------------------------------------
  // Stage 4: chain accumulate + saturate (combinational, registered into the
  // output stage below)
  // ---------------------------------------------------------------------------
  logic signed [FULL_W-1:0] full;
  logic signed [ACC_W-1:0]  result;
  logic                     sat;

  always_comb begin
    full = FULL_W'(s3_dot) + FULL_W'($signed(a3));
    if (full > SAT_MAX) begin
      result = ACC_W'(SAT_MAX);
      sat    = 1'b1;
    end else if (full < SAT_MIN) begin
      result = ACC_W'(SAT_MIN);
      sat    = 1'b1;
    end else begin
      result = ACC_W'(full);
      sat    = 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Pipeline registers (all stages move together on advance)
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v1        <= 1'b0;
      v2        <= 1'b0;
      v3        <= 1'b0;
      out_valid <= 1'b0;
      a1        <= '0;
      a2        <= '0;
      a3        <= '0;
      s3_dot    <= '0;
      acc_out   <= '0;
      sat_flag  <= 1'b0;
      for (int i = 0; i < NUM_LANES; i++)  s1_prod[i] <= '0;
      for (int i = 0; i < HALF_NODES; i++) s2_part[i] <= '0;
    end else if (advance) begin
      v1 <= in_valid;                       // in_ready == advance here
      for (int i = 0; i < NUM_LANES; i++)  s1_prod[i] <= prod_c[i];
      a1 <= acc_in;

      v2 <= v1;
      for (int i = 0; i < HALF_NODES; i++) s2_part[i] <= na[HALF_NODES + i];
      a2 <= a1;

      v3     <= v2;
      s3_dot <= nb[1];
      a3     <= a2;

      out_valid <= v3;
      acc_out   <= result;
      sat_flag  <= sat;
    end
  end

endmodule : mac_array
