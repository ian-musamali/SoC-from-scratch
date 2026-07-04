// -----------------------------------------------------------------------------
// MAC array interface. Same valid/ready contract the convolution engine and
// NPU core will drive in Phases 4-5, so it must not change after this pass.
//
// Input handshake : in_valid/in_ready  (transaction accepted when both high)
// Output handshake: out_valid/out_ready (result consumed when both high)
// Data buses are flat packed vectors; lane i occupies bits [i*DATA_W +: DATA_W]
// and is interpreted as signed two's complement.
// -----------------------------------------------------------------------------
interface mac_if #(
  parameter int NUM_LANES = tinynpu_pkg::NUM_LANES,
  parameter int DATA_W    = tinynpu_pkg::DATA_W,
  parameter int ACC_W     = tinynpu_pkg::ACC_W
) (
  input logic clk,
  input logic rst_n
);

  // Input side
  logic                        in_valid;
  logic                        in_ready;
  logic [NUM_LANES*DATA_W-1:0] act;     // 64 signed int8 activations, lane 0 in LSBs
  logic [NUM_LANES*DATA_W-1:0] wgt;     // 64 signed int8 weights,     lane 0 in LSBs
  logic [ACC_W-1:0]            acc_in;  // signed chaining accumulator input

  // Output side
  logic                        out_valid;
  logic                        out_ready;
  logic [ACC_W-1:0]            acc_out; // signed saturated result
  logic                        sat_flag; // 1 = acc_out was clipped this transaction

endinterface : mac_if
