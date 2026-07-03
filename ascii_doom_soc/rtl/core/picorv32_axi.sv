`timescale 1ns/1ps
// PicoRV32 AXI4-Lite master stub for simulation (SIMULATION=1).
// Synthesis uses the real picorv32.v; this stub exists so Verilator can
// elaborate soc_top without the full picorv32 source.
// Port and parameter list mirrors picorv32_axi from picorv32.v.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off DECLFILENAME */
module picorv32_axi #(
    parameter [ 0:0] ENABLE_COUNTERS   = 1,
    parameter [ 0:0] ENABLE_MUL        = 0,
    parameter [ 0:0] ENABLE_FAST_MUL   = 0,
    parameter [ 0:0] ENABLE_DIV        = 0,
    parameter [ 0:0] ENABLE_IRQ        = 0,
    parameter [ 0:0] ENABLE_IRQ_QREGS  = 1,
    parameter [ 0:0] ENABLE_IRQ_TIMER  = 1,
    parameter [31:0] MASKED_IRQ        = 32'h0000_0000,
    parameter [31:0] LATCHED_IRQ       = 32'hffff_ffff,
    parameter [31:0] PROGADDR_RESET    = 32'h0000_0000,
    parameter [31:0] PROGADDR_IRQ      = 32'h0000_0010,
    parameter [31:0] STACKADDR         = 32'hffff_ffff
) (
    input  logic        clk,
    input  logic        resetn,
    output logic        trap,

    output logic [31:0] mem_axi_awaddr,
    output logic        mem_axi_awvalid,
    input  logic        mem_axi_awready,
    output logic [ 2:0] mem_axi_awprot,

    output logic [31:0] mem_axi_wdata,
    output logic [ 3:0] mem_axi_wstrb,
    output logic        mem_axi_wvalid,
    input  logic        mem_axi_wready,

    input  logic        mem_axi_bvalid,
    output logic        mem_axi_bready,

    output logic [31:0] mem_axi_araddr,
    output logic        mem_axi_arvalid,
    input  logic        mem_axi_arready,
    output logic [ 2:0] mem_axi_arprot,

    input  logic [31:0] mem_axi_rdata,
    input  logic        mem_axi_rvalid,
    output logic        mem_axi_rready,

    input  logic [31:0] irq,
    output logic [31:0] eoi
);
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on DECLFILENAME */
    assign mem_axi_awaddr  = '0;
    assign mem_axi_awvalid = 1'b0;
    assign mem_axi_awprot  = '0;
    assign mem_axi_wdata   = '0;
    assign mem_axi_wstrb   = 4'h0;
    assign mem_axi_wvalid  = 1'b0;
    assign mem_axi_bready  = 1'b1;
    assign mem_axi_araddr  = '0;
    assign mem_axi_arvalid = 1'b0;
    assign mem_axi_arprot  = '0;
    assign mem_axi_rready  = 1'b0;
    assign trap            = 1'b0;
    assign eoi             = '0;
endmodule
