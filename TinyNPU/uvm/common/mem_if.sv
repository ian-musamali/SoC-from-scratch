// -----------------------------------------------------------------------------
// Behavioral memory interfaces shared by the conv and NPU UVM environments.
// Both model read-first BRAM with 1-cycle read latency (rdata follows raddr
// unconditionally). load() zeroes the array first, so .memh files only need
// to list their occupied regions (with @base offsets).
// -----------------------------------------------------------------------------

// Unified feature-map buffer: 1 read port + 1 write port.
interface fm_mem_if #(
  parameter int ADDR_W = tinynpu_pkg::FM_ADDR_W,
  parameter int DATA_W = tinynpu_pkg::DATA_W
) (
  input logic clk
);
  logic              re;
  logic [ADDR_W-1:0] raddr;
  logic [DATA_W-1:0] rdata;
  logic              wen;
  logic [ADDR_W-1:0] waddr;
  logic [DATA_W-1:0] wdata;

  logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

  always_ff @(posedge clk) begin
    rdata <= mem[raddr];
    if (wen) mem[waddr] <= wdata;
  end

  task automatic load(string path);
    foreach (mem[i]) mem[i] = '0;
    $readmemh(path, mem);
  endtask

  // Compare the whole array against a full-image .memh file; returns the
  // mismatch count and prints the first few offending addresses.
  task automatic compare_against(string path, output int mismatches);
    logic [DATA_W-1:0] exp [0:(1<<ADDR_W)-1];
    foreach (exp[i]) exp[i] = '0;
    $readmemh(path, exp);
    mismatches = 0;
    foreach (mem[i]) begin
      if (mem[i] !== exp[i]) begin
        mismatches++;
        if (mismatches <= 5)
          $display("[fm_mem_if] mismatch @%0h: got %02h expected %02h",
                   i, mem[i], exp[i]);
      end
    end
  endtask
endinterface : fm_mem_if

// Read-only memory (weights, and the conv env's isolated ifm).
interface rom_if #(
  parameter int ADDR_W = tinynpu_pkg::WGT_ADDR_W,
  parameter int DATA_W = tinynpu_pkg::DATA_W
) (
  input logic clk
);
  logic              re;
  logic [ADDR_W-1:0] addr;
  logic [DATA_W-1:0] rdata;

  logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

  always_ff @(posedge clk) begin
    rdata <= mem[addr];
  end

  task automatic load(string path);
    foreach (mem[i]) mem[i] = '0;
    $readmemh(path, mem);
  endtask
endinterface : rom_if
