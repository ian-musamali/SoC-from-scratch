// -----------------------------------------------------------------------------
// Generic byte-wide ROM, BRAM-inferable, 1-cycle read latency (addr in cycle
// n with re high -> rdata valid cycle n+1) — the same contract as the
// behavioral rom_if used by the UVM environments. Contents come from a
// $readmemh image; unwritten locations are zero. Used for the demo image ROM
// and the weight ROM in the FPGA wrapper (Phase 7).
// -----------------------------------------------------------------------------
module byte_rom #(
  parameter int    ADDR_W    = tinynpu_pkg::WGT_ADDR_W,
  parameter int    DATA_W    = tinynpu_pkg::DATA_W,
  parameter string INIT_FILE = ""
)(
  input  logic              clk,
  input  logic              re,
  input  logic [ADDR_W-1:0] addr,
  output logic [DATA_W-1:0] rdata
);

  logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  always_ff @(posedge clk) begin
    if (re) rdata <= mem[addr];
  end

endmodule : byte_rom
