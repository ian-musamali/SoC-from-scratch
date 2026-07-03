`timescale 1ns/1ps
// GPU top: wires dispatcher, NUM_CORES dda_cores, collector, and MMIO register block.
/* verilator lint_off UNUSEDPARAM */
module gpu_top #(
    parameter int NUM_CORES  = 4,
    parameter int TOTAL_COLS = 80,
    parameter int MAP_SIZE   = 64,
    parameter int NUM_ROWS   = 45
) (
    input  logic        clk,
    input  logic        rst_n,
    // Player input — synchronized upstream, {btnc, btnr, btnl, btnd, btnu}
    input  logic [4:0]  buttons,
    // AXI4-Lite slave — GPU MMIO (from CPU/fabric)
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
    // AXI4-Lite master — framebuffer writes (to fabric → char_framebuffer)
    output logic [31:0] m_awaddr,
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [31:0] m_wdata,
    output logic [3:0]  m_wstrb,
    output logic        m_wvalid,
    input  logic        m_wready,
    input  logic [1:0]  m_bresp,
    input  logic        m_bvalid,
    output logic        m_bready,
    // Map memory read port (shared round-robin across cores)
    // Each core gets its own map read port (replicated read-only BRAM in hardware)
    output logic [11:0] map_read_addr [0:NUM_CORES-1],
    input  logic [7:0]  map_read_data [0:NUM_CORES-1],
    output logic        map_read_req  [0:NUM_CORES-1]
);

    // Player registers from MMIO
    logic [31:0] player_x, player_y, player_angle;
    logic        frame_start, frame_done;

    // Per-core signals
    logic [NUM_CORES-1:0] core_start;
    logic [6:0]           core_col  [0:NUM_CORES-1];
    logic [31:0]          core_px   [0:NUM_CORES-1];
    logic [31:0]          core_py   [0:NUM_CORES-1];
    logic [31:0]          core_pang [0:NUM_CORES-1];
    logic [NUM_CORES-1:0] core_done;
    logic [7:0]           core_char [0:NUM_CORES-1];
    logic [5:0]           core_wall_top    [0:NUM_CORES-1];
    logic [5:0]           core_wall_height [0:NUM_CORES-1];
    logic                 collector_ready;   // queue_empty from u_coll — gates u_disp rounds
    // Per-core map ports wire directly to top-level ports


    // GPU cycle counter
    logic [31:0] cycle_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          cycle_cnt <= '0;
        else if (frame_start) cycle_cnt <= '0;
        else if (!frame_done) cycle_cnt <= cycle_cnt + 32'd1;
    end

    // Core utilization tracking (simply whether each core is not done/idle — use busy as proxy)
    logic [3:0] core_util;
    assign core_util = core_done[3:0]; // placeholder: 1 while done pulse

    // MMIO
    gpu_mmio u_mmio (
        .clk, .rst_n,
        .buttons,
        .s_awaddr, .s_awvalid, .s_awready,
        .s_wdata,  .s_wvalid,  .s_wready, .s_wstrb,
        .s_bresp,  .s_bvalid,  .s_bready,
        .s_araddr, .s_arvalid, .s_arready,
        .s_rdata,  .s_rresp,   .s_rvalid, .s_rready,
        .frame_start, .frame_done,
        .player_x, .player_y, .player_angle,
        .core_busy(core_done[3:0]),
        .gpu_cycles(cycle_cnt),
        .core_util
    );

    // Dispatcher
    gpu_dispatcher #(.NUM_CORES(NUM_CORES), .TOTAL_COLS(TOTAL_COLS)) u_disp (
        .clk, .rst_n,
        .frame_start, .frame_done,
        .player_x, .player_y, .player_angle,
        .core_start, .core_col, .core_px, .core_py, .core_pang,
        .core_done,
        .collector_ready
    );

    // DDA cores — each gets its own map port (replicated read-only BRAM in hardware)
    genvar g;
    generate
        for (g = 0; g < NUM_CORES; g++) begin : gen_cores
            dda_core #(.TOTAL_COLS(TOTAL_COLS), .MAP_SIZE(MAP_SIZE), .NUM_ROWS(NUM_ROWS)) u_core (
                .clk, .rst_n,
                .start        (core_start[g]),
                .player_x     (core_px[g]),
                .player_y     (core_py[g]),
                .player_angle (core_pang[g]),
                .col_index    (core_col[g]),
                .map_read_addr(map_read_addr[g]),
                .map_read_data(map_read_data[g]),
                .map_read_req (map_read_req[g]),
                .ascii_char   (core_char[g]),
                .wall_top     (core_wall_top[g]),
                .wall_height  (core_wall_height[g]),
                .done         (core_done[g])
            );
        end
    endgenerate

    // Collector
    gpu_collector #(.NUM_CORES(NUM_CORES), .TOTAL_COLS(TOTAL_COLS), .NUM_ROWS(NUM_ROWS)) u_coll (
        .clk, .rst_n,
        .core_done, .core_col, .core_char,
        .core_wall_top, .core_wall_height,
        .queue_empty (collector_ready),
        .m_awaddr, .m_awvalid, .m_awready,
        .m_wdata,  .m_wvalid,  .m_wready, .m_wstrb,
        .m_bresp,  .m_bvalid,  .m_bready
    );

endmodule
