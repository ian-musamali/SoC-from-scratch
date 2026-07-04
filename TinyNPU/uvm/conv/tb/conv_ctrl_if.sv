// -----------------------------------------------------------------------------
// Convolution engine control/config interface (Phase 4 isolated env).
// Carries the static per-start configuration, the start pulse, and the
// busy/done/sat_seen status outputs of conv_engine. Widths come straight
// from tinynpu_pkg so this interface is deliberately unparameterized (keeps
// the config-db virtual-interface type a single specialization).
// -----------------------------------------------------------------------------
interface conv_ctrl_if (
  input logic clk,
  input logic rst_n
);

  // Configuration (driven by the UVM driver, sampled by the DUT)
  logic [5:0]                        cfg_img_w;
  logic [5:0]                        cfg_img_h;
  logic [3:0]                        cfg_in_ch;
  logic                              cfg_stride2;
  logic                              cfg_pad;
  logic [tinynpu_pkg::SHIFT_W-1:0]   cfg_out_shift;
  logic [tinynpu_pkg::FM_ADDR_W-1:0] cfg_ifm_base;
  logic [tinynpu_pkg::FM_ADDR_W-1:0] cfg_ofm_base;
  logic [tinynpu_pkg::WGT_ADDR_W-1:0] cfg_wgt_base;
  logic [tinynpu_pkg::ACC_W-1:0]     cfg_acc_init;

  // Control / status
  logic start;     // 1-cycle pulse in
  logic busy;      // out
  logic done;      // 1-cycle pulse out
  logic sat_seen;  // sticky out

endinterface : conv_ctrl_if
