`timescale 1ns/1ps
// VGA top-level: composites char_framebuffer + font_rom into RGB pixel stream.
// Pixel clock domain (25.175 MHz). CDC boundary with sys_clk is at char_framebuffer
// read port — Xilinx true dual-port BRAM handles independent port clocks.
//
// Character grid: 80 columns × 45 rows → 640×360 pixels. Bottom 120 lines blank.
// Column = pixel_x / 8, Row = pixel_y / 8, FB addr = row*80 + col.
// Glyph pixel = font_rom[{char[6:0], pixel_y[2:0]}][7 - pixel_x[2:0]].
module vga_top (
    input  logic        pix_clk,
    input  logic        rst_n,

    // Framebuffer sync read port (driven by this module)
    output logic [11:0] fb_addr,
    input  logic [7:0]  fb_data,

    // Font ROM port (driven by this module)
    output logic [9:0]  font_addr,
    input  logic [7:0]  font_data,

    // VGA outputs
    output logic        vga_hsync,
    output logic        vga_vsync,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b
);

    logic        h_active, v_active;
    logic [9:0]  pixel_x, pixel_y;

    vga_sync u_vga_sync (
        .pix_clk  (pix_clk),
        .rst_n    (rst_n),
        .hsync    (vga_hsync),
        .vsync    (vga_vsync),
        .h_active (h_active),
        .v_active (v_active),
        .pixel_x  (pixel_x),
        .pixel_y  (pixel_y)
    );

    // --- Pipeline stage 0: compute framebuffer address ---
    // pixel_y / 8 = row (0..44 for y in 0..359; >= 45 for y in 360..479 → blank)
    // pixel_x / 8 = col (0..79)
    /* verilator lint_off UNUSEDSIGNAL */
    logic [6:0]  col_0, row_0;   // computed for clarity; fb_addr_0 is the canonical form
    /* verilator lint_on UNUSEDSIGNAL */
    logic [11:0] fb_addr_0;
    logic        in_char_region_0;
    logic [2:0]  sub_x_0, sub_y_0;

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            col_0           <= '0;
            row_0           <= '0;
            fb_addr_0       <= '0;
            in_char_region_0<= 1'b0;
            sub_x_0         <= '0;
            sub_y_0         <= '0;
        end else begin
            col_0            <= pixel_x[9:3];           // pixel_x / 8
            row_0            <= pixel_y[9:3];           // pixel_y / 8
            sub_x_0          <= pixel_x[2:0];
            sub_y_0          <= pixel_y[2:0];
            // Active region: x < 640 (always when h_active), y < 360 (rows 0..44)
            in_char_region_0 <= h_active && v_active && (pixel_y < 10'd360);
            // row * 80 + col (row ≤ 44, col ≤ 79 → max 44*80+79 = 3599 < 4096)
            fb_addr_0        <= {5'b0, pixel_y[9:3]} * 12'd80 + {5'b0, pixel_x[9:3]};
        end
    end

    // Drive framebuffer address to external BRAM read port
    assign fb_addr = fb_addr_0;

    // --- Pipeline stage 1: framebuffer data arrives (1-cycle BRAM latency) ---
    // Also forward sub-pixel offsets and region flag
    /* verilator lint_off UNUSEDSIGNAL */
    logic [7:0]  char_r;  // bit 7 unused (font_rom uses only [6:0] for ASCII)
    /* verilator lint_on UNUSEDSIGNAL */
    logic        in_char_region_1;
    logic [2:0]  sub_x_1, sub_y_1;

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            char_r           <= 8'h20;
            in_char_region_1 <= 1'b0;
            sub_x_1          <= '0;
            sub_y_1          <= '0;
        end else begin
            char_r           <= fb_data;
            in_char_region_1 <= in_char_region_0;
            sub_x_1          <= sub_x_0;
            sub_y_1          <= sub_y_0;
        end
    end

    // Drive font ROM address: {char[6:0], row[2:0]}
    assign font_addr = {char_r[6:0], sub_y_1};

    // --- Pipeline stage 2: font ROM data arrives (1-cycle BRAM latency) ---
    logic [7:0]  glyph_row;
    logic        in_char_region_2;
    logic [2:0]  sub_x_2;

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            glyph_row        <= '0;
            in_char_region_2 <= 1'b0;
            sub_x_2          <= '0;
        end else begin
            glyph_row        <= font_data;
            in_char_region_2 <= in_char_region_1;
            sub_x_2          <= sub_x_1;
        end
    end

    // --- Stage 2 output: extract font pixel and generate RGB ---
    // Bit 7 is leftmost (col 0 within glyph), bit 0 is rightmost.
    logic font_pixel;
    assign font_pixel = in_char_region_2 ? glyph_row[3'h7 - sub_x_2] : 1'b0;

    assign vga_r = font_pixel ? 4'hF : 4'h0;
    assign vga_g = font_pixel ? 4'hF : 4'h0;
    assign vga_b = font_pixel ? 4'hF : 4'h0;

endmodule
