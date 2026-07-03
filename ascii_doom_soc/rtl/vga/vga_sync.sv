`timescale 1ns/1ps
// VGA 640x480 @ 60 Hz timing generator, 25.175 MHz pixel clock input.
// All timing parameters annotated per VESA standard.
module vga_sync (
    input  logic        pix_clk,
    input  logic        rst_n,
    output logic        hsync,
    output logic        vsync,
    output logic        h_active,
    output logic        v_active,
    output logic [9:0]  pixel_x,
    output logic [9:0]  pixel_y
);

    // --- Horizontal timing (pixels at 25.175 MHz) ---
    localparam int H_ACTIVE      = 640; // visible pixels per line
    localparam int H_FRONT_PORCH = 16;  // pixels before sync pulse
    localparam int H_SYNC_PULSE  = 96;  // sync pulse width
    localparam int H_BACK_PORCH  = 48;  // pixels after sync pulse
    localparam int H_TOTAL       = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    // Sync pulse occupies [H_ACTIVE + H_FRONT_PORCH, H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE - 1]
    localparam int H_SYNC_START  = H_ACTIVE + H_FRONT_PORCH;       // 656
    localparam int H_SYNC_END    = H_SYNC_START + H_SYNC_PULSE - 1; // 751

    // --- Vertical timing (lines at ~31.469 kHz) ---
    localparam int V_ACTIVE      = 480; // visible lines
    localparam int V_FRONT_PORCH = 10;  // lines before sync pulse
    localparam int V_SYNC_PULSE  = 2;   // sync pulse width
    localparam int V_BACK_PORCH  = 33;  // lines after sync pulse
    localparam int V_TOTAL       = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    localparam int V_SYNC_START  = V_ACTIVE + V_FRONT_PORCH;       // 490
    localparam int V_SYNC_END    = V_SYNC_START + V_SYNC_PULSE - 1; // 491

    logic [9:0] h_count; // 0..799
    logic [9:0] v_count; // 0..524

    always_ff @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= '0;
            v_count <= '0;
        end else begin
            if (h_count == 10'(H_TOTAL - 1)) begin
                h_count <= '0;
                v_count <= (v_count == 10'(V_TOTAL - 1)) ? 10'd0 : v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Sync pulses are active-low per VGA standard
    assign hsync    = ~((h_count >= 10'(H_SYNC_START)) && (h_count <= 10'(H_SYNC_END)));
    assign vsync    = ~((v_count >= 10'(V_SYNC_START)) && (v_count <= 10'(V_SYNC_END)));
    assign h_active = (h_count < 10'(H_ACTIVE));
    assign v_active = (v_count < 10'(V_ACTIVE));
    assign pixel_x  = h_count[9:0];
    assign pixel_y  = v_count[9:0];

endmodule
