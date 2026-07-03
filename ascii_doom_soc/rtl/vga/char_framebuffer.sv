`timescale 1ns/1ps
// 80×45 character framebuffer: 4 KB of block RAM.
// Write port: AXI4-Lite slave (GPU collector, byte-write, wstrb[0] only).
// Read port A: AXI4-Lite read (CPU debug, sys_clk).
// Read port B: synchronous VGA read (vga_top, same clk).
// BRAM inference: data arrays isolated in no-reset always_ff blocks.
(* ram_style = "block" *)
module char_framebuffer (
    input  logic        clk,      // sys_clk — AXI write + AXI read port
    input  logic        pix_clk,  // pixel clock — VGA read port (TDP BRAM Port B)
    input  logic        rst_n,

    // --- AXI4-Lite write port (GPU collector) ---
    input  logic [11:0] axi_awaddr,
    input  logic        axi_awvalid,
    output logic        axi_awready,
    input  logic [31:0] axi_wdata,
    input  logic [3:0]  axi_wstrb,
    input  logic        axi_wvalid,
    output logic        axi_wready,
    output logic [1:0]  axi_bresp,
    output logic        axi_bvalid,
    input  logic        axi_bready,
    // --- AXI4-Lite read port (CPU debug) ---
    input  logic [11:0] axi_araddr,
    input  logic        axi_arvalid,
    output logic        axi_arready,
    output logic [31:0] axi_rdata,
    output logic [1:0]  axi_rresp,
    output logic        axi_rvalid,
    input  logic        axi_rready,

    // --- Synchronous read port (VGA renderer) ---
    input  logic [11:0] vga_addr,
    output logic [7:0]  vga_data
);

    logic [7:0] mem [0:4095];  // 4096 bytes; [0:3599] used for 80×45 grid

    /* verilator lint_off INITIALDLY */
    initial begin
        for (int i = 0; i < 4096; i = i + 1) mem[i] = 8'h20;
    end
    /* verilator lint_on INITIALDLY */

    // -----------------------------------------------------------------------
    // AXI write state
    // -----------------------------------------------------------------------
    logic [11:0] aw_addr_r;
    logic        aw_valid_r;

    // AXI control signals — async reset supported here, no BRAM data
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_addr_r   <= '0;
            aw_valid_r  <= 1'b0;
            axi_awready <= 1'b1;
            axi_wready  <= 1'b1;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b00;
            axi_arready <= 1'b1;
            axi_rvalid  <= 1'b0;
            axi_rresp   <= 2'b00;
        end else begin
            if (axi_awvalid && axi_awready) begin
                aw_addr_r  <= axi_awaddr;
                aw_valid_r <= 1'b1;
                axi_awready <= 1'b0;
            end
            if (axi_wvalid && axi_wready && aw_valid_r) begin
                aw_valid_r  <= 1'b0;
                axi_bvalid  <= 1'b1;
                axi_awready <= 1'b1;
            end
            if (axi_bvalid && axi_bready) axi_bvalid <= 1'b0;
            if (axi_arvalid && axi_arready) begin
                axi_rvalid  <= 1'b1;
                axi_arready <= 1'b0;
            end
            if (axi_rvalid && axi_rready) begin
                axi_rvalid  <= 1'b0;
                axi_arready <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // BRAM port A: AXI write + AXI read (no reset — Xilinx BRAM requirement)
    // Write: single-byte at aw_addr_r (GPU collector always uses wstrb[0]).
    // Read: unconditional registered read; valid gated by axi_rvalid.
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (axi_wvalid && axi_wready && aw_valid_r)
            mem[aw_addr_r] <= axi_wdata[7:0];
        axi_rdata <= {24'b0, mem[axi_araddr]};
    end

    // -----------------------------------------------------------------------
    // BRAM port B: VGA read on pix_clk (true dual-port, independent clock)
    // -----------------------------------------------------------------------
    always_ff @(posedge pix_clk) begin
        vga_data <= mem[vga_addr];
    end

endmodule
