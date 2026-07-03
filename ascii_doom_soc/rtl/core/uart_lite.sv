`timescale 1ns/1ps
// Minimal UART stub — AXI4-Lite slave, accepts all writes, returns 0 on reads.
// Replace with a full UART (e.g., Xilinx AXI UART Lite) for real FPGA use.
module uart_lite (
    input  logic        clk,
    input  logic        rst_n,
    // AXI4-Lite slave
    input  logic [31:0] s_awaddr,
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_wdata,
    input  logic [3:0]  s_wstrb,
    input  logic        s_wvalid,
    output logic        s_wready,
    output logic [1:0]  s_bresp,
    output logic        s_bvalid,
    input  logic        s_bready,
    input  logic [31:0] s_araddr,
    input  logic        s_arvalid,
    output logic        s_arready,
    output logic [31:0] s_rdata,
    output logic [1:0]  s_rresp,
    output logic        s_rvalid,
    input  logic        s_rready,
    // Physical UART
    output logic        tx,
    input  logic        rx
);
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused_strb, unused_rx;
    assign unused_strb = |s_wstrb;
    assign unused_rx   = rx;
    /* verilator lint_on UNUSEDSIGNAL */

    assign tx = 1'b1;

    // Accept AW+W simultaneously, respond immediately
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_awready <= 1'b1;
            s_wready  <= 1'b1;
            s_bvalid  <= 1'b0;
            s_bresp   <= 2'b00;
            s_arready <= 1'b1;
            s_rvalid  <= 1'b0;
            s_rdata   <= '0;
            s_rresp   <= 2'b00;
        end else begin
            // Write path
            if (s_awvalid && s_awready && s_wvalid && s_wready) begin
                s_bvalid  <= 1'b1;
                s_awready <= 1'b0;
                s_wready  <= 1'b0;
            end
            if (s_bvalid && s_bready) begin
                s_bvalid  <= 1'b0;
                s_awready <= 1'b1;
                s_wready  <= 1'b1;
            end
            // Read path: return 0 (TX_FIFO_EMPTY=1 at bit 2, status register)
            if (s_arvalid && s_arready) begin
                s_rdata   <= (s_araddr[3:0] == 4'h8) ? 32'h0000_0005 : 32'h0; // STAT: TX+RX empty
                s_rvalid  <= 1'b1;
                s_arready <= 1'b0;
            end
            if (s_rvalid && s_rready) begin
                s_rvalid  <= 1'b0;
                s_arready <= 1'b1;
            end
        end
    end
endmodule
