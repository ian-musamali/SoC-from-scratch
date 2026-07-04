// -----------------------------------------------------------------------------
// MAC-port interface between conv_engine (master) and the reactive golden
// MAC responder (slave). Protocol contract:
//   - mac_valid holds until mac_ready is sampled high at a posedge
//   - the DUT asserts mac_res_ready while waiting for its response
//   - transactions are fully serialized (never a second request before the
//     first response completes)
// Unparameterized on purpose: widths come from tinynpu_pkg, so the config-db
// virtual-interface type is a single specialization on both set and get.
// -----------------------------------------------------------------------------
interface conv_mac_if (
  input logic clk,
  input logic rst_n
);

  // Request channel (DUT master -> responder slave)
  logic                                                    mac_valid;
  logic                                                    mac_ready;
  logic [tinynpu_pkg::NUM_LANES*tinynpu_pkg::DATA_W-1:0]   mac_act;
  logic [tinynpu_pkg::NUM_LANES*tinynpu_pkg::DATA_W-1:0]   mac_wgt;
  logic [tinynpu_pkg::ACC_W-1:0]                           mac_acc_in;

  // Response channel (responder slave -> DUT master)
  logic                                                    mac_res_valid;
  logic                                                    mac_res_ready;
  logic [tinynpu_pkg::ACC_W-1:0]                           mac_res_acc;
  logic                                                    mac_res_sat;

endinterface : conv_mac_if
