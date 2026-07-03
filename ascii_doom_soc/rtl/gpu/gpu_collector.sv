`timescale 1ns/1ps
// Collects ASCII results from NUM_CORES DDA cores and writes a full NUM_ROWS-row
// wall-height column (ceiling/wall/floor) to char_framebuffer via AXI4-Lite.
// Per-core result latches capture done pulses; priority-encode services one per cycle.
//
// queue_empty backpressures gpu_dispatcher (see docs/decisions/soc_top.md,
// "wall height + collector backpressure"): draining one column now takes
// ~NUM_ROWS AXI writes instead of one, so a core can finish its next column
// well before this collector has even picked up its previous one. Without
// backpressure that would silently drop a column's data — the same failure
// mode dda_core.sv's map_read_req fix already had to work around once.
/* verilator lint_off UNUSEDPARAM */
module gpu_collector #(
    parameter int NUM_CORES  = 4,
    parameter int TOTAL_COLS = 80,
    parameter int NUM_ROWS   = 45,
    parameter logic [31:0] VGA_FB_BASE = 32'h2000_0000
) (
    input  logic        clk,
    input  logic        rst_n,
    // Per-core result inputs. Packed (not unpacked-array) ports so this
    // synthesizes under Yosys (OpenLane GDS flow) — see gpu_dispatcher.sv for
    // why. Bit i*W +: W is core i's W-bit value.
    input  logic [NUM_CORES-1:0]        core_done,
    input  logic [NUM_CORES*7-1:0]      core_col_flat,
    input  logic [NUM_CORES*8-1:0]      core_char_flat,
    input  logic [NUM_CORES*6-1:0]      core_wall_top_flat,
    input  logic [NUM_CORES*6-1:0]      core_wall_height_flat,
    // High when no core result is waiting to be picked up — gates gpu_dispatcher
    output logic        queue_empty,
    // AXI4-Lite write master (to fabric)
    output logic [31:0] m_awaddr,
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [31:0] m_wdata,
    output logic [3:0]  m_wstrb,
    output logic        m_wvalid,
    input  logic        m_wready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [1:0]  m_bresp,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        m_bvalid,
    output logic        m_bready
);

    // Per-core result latches — set when core fires done, cleared when the
    // collector accepts the entry into service (W_IDLE -> W_ADDR), not when
    // the resulting NUM_ROWS writes finish draining.
    logic [NUM_CORES-1:0] pend_valid;
    logic [6:0]           pend_col        [0:NUM_CORES-1];
    logic [7:0]           pend_char       [0:NUM_CORES-1];
    logic [5:0]           pend_wtop       [0:NUM_CORES-1];
    logic [5:0]           pend_wheight    [0:NUM_CORES-1];

    // Priority-encoded service: find lowest-indexed pending latch (combinational)
    logic       any_pend;
    logic [1:0] serv_idx;

    always_comb begin
        any_pend = 1'b0;
        serv_idx = 2'd0;
        for (int i = NUM_CORES-1; i >= 0; i--) begin
            if (pend_valid[i]) begin
                any_pend = 1'b1;
                serv_idx = 2'(i);
            end
        end
    end

    // AXI write FSM — one column drains as NUM_ROWS sequential single-byte
    // writes: ceiling (blank) above the wall, the wall's shade glyph, floor
    // (blank) below. active_* hold the in-service column steady across the
    // whole loop, decoupled from pend_* so a new pend entry for the same
    // core (post-backpressure, in the next round) can't corrupt it.
    typedef enum logic [1:0] {W_IDLE, W_ADDR, W_DATA, W_RESP} w_state_t;
    w_state_t w_state;

    // Must require w_state==W_IDLE too, not just an empty pend_valid queue:
    // pend_valid clears the instant an entry is *accepted* into service, long
    // before its ~45-row drain finishes. Gating only on an empty queue let a
    // fast next round refill it and re-lap a core's still-undrained previous
    // entry before the collector ever got to it, silently dropping data
    // (see docs/decisions/soc_top.md, "wall height + collector backpressure").
    assign queue_empty = (~|pend_valid) && (w_state == W_IDLE);

    logic [6:0] active_col;
    logic [7:0] active_char;
    logic [6:0] active_wtop, active_wheight, wall_bottom, row_cnt;

    assign wall_bottom = active_wtop + active_wheight;

    logic [7:0] row_char;
    assign row_char = (row_cnt < active_wtop)  ? 8'h20 :
                       (row_cnt < wall_bottom) ? active_char : 8'h20;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_valid <= '0;
            for (int i = 0; i < NUM_CORES; i++) begin
                pend_col[i]     <= '0;
                pend_char[i]    <= '0;
                pend_wtop[i]    <= '0;
                pend_wheight[i] <= '0;
            end
            w_state        <= W_IDLE;
            active_col     <= '0;
            active_char    <= '0;
            active_wtop    <= '0;
            active_wheight <= '0;
            row_cnt        <= '0;
            m_awaddr  <= '0;
            m_awvalid <= 1'b0;
            m_wdata   <= '0;
            m_wstrb   <= 4'b0001;
            m_wvalid  <= 1'b0;
            m_bready  <= 1'b1;
        end else begin
            // --- Latch incoming done pulses (set) ---
            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_done[i] && !pend_valid[i]) begin
                    pend_valid[i]   <= 1'b1;
                    pend_col[i]     <= core_col_flat[i*7 +: 7];
                    pend_char[i]    <= core_char_flat[i*8 +: 8];
                    pend_wtop[i]    <= core_wall_top_flat[i*6 +: 6];
                    pend_wheight[i] <= core_wall_height_flat[i*6 +: 6];
                end
            end

            // --- AXI write FSM ---
            case (w_state)
                W_IDLE: begin
                    if (any_pend) begin
                        active_col           <= pend_col[serv_idx];
                        active_char          <= pend_char[serv_idx];
                        active_wtop          <= {1'b0, pend_wtop[serv_idx]};
                        active_wheight       <= {1'b0, pend_wheight[serv_idx]};
                        row_cnt              <= '0;
                        pend_valid[serv_idx] <= 1'b0;  // consume the latch
                        w_state              <= W_ADDR;
                    end
                end

                // Uniform per-row step: assert address+data, then wait for
                // awready. Runs once per row (row 0 included — active_* was
                // registered on the W_IDLE->W_ADDR edge, so it's already
                // settled by the time this state's logic evaluates it).
                W_ADDR: begin
                    if (!m_awvalid) begin
                        m_awaddr  <= VGA_FB_BASE + ({24'b0, row_cnt} * 32'd80) + {25'b0, active_col};
                        m_wdata   <= {24'b0, row_char};
                        m_awvalid <= 1'b1;
                        m_wvalid  <= 1'b1;
                    end else if (m_awready) begin
                        m_awvalid <= 1'b0;
                        w_state   <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (m_wready) begin
                        m_wvalid <= 1'b0;
                        w_state  <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (m_bvalid) begin
                        if (row_cnt == 7'(NUM_ROWS - 1)) begin
                            w_state <= W_IDLE;
                        end else begin
                            row_cnt <= row_cnt + 7'd1;
                            w_state <= W_ADDR;
                        end
                    end
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end

endmodule
