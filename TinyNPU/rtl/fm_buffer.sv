// -----------------------------------------------------------------------------
// Unified feature-map buffer: byte-wide, 1 read + 1 write port, read-first,
// 1-cycle read latency — the BRAM-backed implementation of the exact contract
// modeled by uvm/common/mem_if.sv's fm_mem_if (Phase 7). Infers simple
// dual-port block RAM. Contents power up to zero; the wrapper's loader FSM
// copies the image in before each run.
// -----------------------------------------------------------------------------
module fm_buffer #(
  parameter int ADDR_W = tinynpu_pkg::FM_ADDR_W,
  parameter int DATA_W = tinynpu_pkg::DATA_W
)(
  input  logic              clk,
  // read port
  input  logic              re,
  input  logic [ADDR_W-1:0] raddr,
  output logic [DATA_W-1:0] rdata,
  // write port
  input  logic              wen,
  input  logic [ADDR_W-1:0] waddr,
  input  logic [DATA_W-1:0] wdata
);

  logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

  always_ff @(posedge clk) begin
    if (re) rdata <= mem[raddr];
    if (wen) mem[waddr] <= wdata;
  end

endmodule : fm_buffer
