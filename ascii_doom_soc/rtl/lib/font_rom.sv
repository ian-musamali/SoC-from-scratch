`timescale 1ns/1ps
// 8x8 font ROM: 128 ASCII characters × 8 rows × 8 bits.
// addr[9:0] = {char_index[6:0], row[2:0]}. data_out[7:0] = pixel row bitmap.
// Bit 7 is the leftmost pixel. Initialized from fonts/font8x8.hex.
(* rom_style = "block" *)
module font_rom (
    input  logic        clk,
    input  logic [9:0]  addr,
    output logic [7:0]  data_out
);

    logic [7:0] rom [0:1023];

    initial $readmemh("fonts/font8x8.hex", rom);

    always_ff @(posedge clk) begin
        data_out <= rom[addr];
    end

endmodule
