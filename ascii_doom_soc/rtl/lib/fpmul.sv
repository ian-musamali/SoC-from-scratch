`timescale 1ns/1ps
// Q16.16 signed fixed-point multiplier
// Extracts bits [47:16] from the 64-bit product (upper 16 are overflow, lower 16 are sub-LSB fraction).
module fpmul (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic        valid_in,
    output logic [31:0] result,
    output logic        valid_out
);

    /* verilator lint_off UNUSEDSIGNAL */
    logic signed [63:0] product_full;
    /* verilator lint_on UNUSEDSIGNAL */

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_full <= '0;
            valid_out    <= 1'b0;
        end else begin
            product_full <= $signed(a) * $signed(b);
            valid_out    <= valid_in;
        end
    end

    assign result = product_full[47:16];

endmodule
