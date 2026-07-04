// -----------------------------------------------------------------------------
// npu_core control interface: layer program, run handshake and status flags.
// The driver owns cfg_*/start; the DUT owns busy/done/sat_seen (driven through
// tb_top port connections). Compiled before tinynpu_npu_uvm_pkg.sv.
// -----------------------------------------------------------------------------
interface npu_ctrl_if (
  input logic clk,
  input logic rst_n
);
  import tinynpu_pkg::*;

  // Layer program (element 0 = first layer), sampled by the DUT while running
  layer_desc_t [MAX_LAYERS-1:0] cfg_layers;
  logic [2:0]                   cfg_num_layers;  // 1..MAX_LAYERS

  logic start;     // 1-cycle pulse from the driver
  logic busy;      // DUT status
  logic done;      // 1-cycle pulse from the DUT
  logic sat_seen;  // sticky saturation flag since start

endinterface : npu_ctrl_if
