`timescale 1ns/1ps
// Dispatches 80 columns across NUM_CORES DDA cores.
// Static assignment: col N → core (N % NUM_CORES).
// Fires all cores for each round simultaneously; waits for all cores done before next round.
/* verilator lint_off UNUSEDPARAM */
module gpu_dispatcher #(
    parameter int NUM_CORES  = 4,
    parameter int TOTAL_COLS = 80
) (
    input  logic        clk,
    input  logic        rst_n,
    // Control
    input  logic        frame_start,
    output logic        frame_done,
    // Player state
    input  logic [31:0] player_x,
    input  logic [31:0] player_y,
    input  logic [31:0] player_angle,
    // Per-core dispatch signals. Packed (not unpacked-array) ports so this
    // synthesizes under Yosys (OpenLane GDS flow) — "input/output/inout ports
    // cannot have unpacked dimensions" is a hard Yosys restriction, verified
    // directly against Yosys 0.46. Bit i*W +: W is core i's W-bit value.
    output logic [NUM_CORES-1:0]        core_start,
    output logic [NUM_CORES*7-1:0]      core_col_flat,
    output logic [NUM_CORES*32-1:0]     core_px_flat,
    output logic [NUM_CORES*32-1:0]     core_py_flat,
    output logic [NUM_CORES*32-1:0]     core_pang_flat,
    input  logic [NUM_CORES-1:0]        core_done,
    // High when gpu_collector has no pending core result waiting to be
    // picked up. A column now drains as NUM_ROWS AXI writes (wall-height
    // rendering) instead of one, so without this a core could finish its
    // next column before the collector even picked up its previous one,
    // silently dropping data — gating the round on it prevents that.
    input  logic                        collector_ready
);

    localparam int ROUNDS = TOTAL_COLS / NUM_CORES; // 20 for 4 cores

    typedef enum logic [1:0] {IDLE, DISPATCH, WAIT, DRAIN_WAIT} state_t;
    state_t state;

    logic [4:0]           round;        // 0..19
    logic [NUM_CORES-1:0] done_accum;  // accumulates per-round done pulses

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            round      <= '0;
            frame_done <= 1'b0;
            core_start <= '0;
            done_accum <= '0;
            for (int i = 0; i < NUM_CORES; i++) begin
                core_col_flat[i*7 +: 7]     <= '0;
                core_px_flat[i*32 +: 32]    <= '0;
                core_py_flat[i*32 +: 32]    <= '0;
                core_pang_flat[i*32 +: 32]  <= '0;
            end
        end else begin
            core_start <= '0;
            frame_done <= 1'b0;

            case (state)
                IDLE: begin
                    if (frame_start) begin
                        round      <= '0;
                        done_accum <= '0;
                        state      <= DISPATCH;
                    end
                end

                DISPATCH: begin
                    // Fire all cores for this round
                    done_accum <= '0;
                    for (int i = 0; i < NUM_CORES; i++) begin
                        core_col_flat[i*7 +: 7]    <= 7'(round * NUM_CORES + i);
                        core_px_flat[i*32 +: 32]   <= player_x;
                        core_py_flat[i*32 +: 32]   <= player_y;
                        core_pang_flat[i*32 +: 32] <= player_angle;
                        core_start[i]              <= 1'b1;
                    end
                    state <= WAIT;
                end

                WAIT: begin
                    // Accumulate done pulses — cores finish at different cycles
                    done_accum <= done_accum | core_done;
                    if ((done_accum | core_done) == {NUM_CORES{1'b1}}) begin
                        done_accum <= '0;
                        state      <= DRAIN_WAIT;
                    end
                end

                // Separate state, checked on a *later* cycle than the one that
                // just captured this round's done pulses into the collector's
                // queue. Checking collector_ready in the same cycle as WAIT's
                // final done pulse reads a stale pre-capture snapshot — the
                // collector captures that same pulse on that same edge, so
                // "ready" from a moment ago says nothing about whether the
                // queue it just received has drained (see docs/decisions).
                DRAIN_WAIT: begin
                    if (collector_ready) begin
                        if (round == 5'(ROUNDS - 1)) begin
                            frame_done <= 1'b1;
                            state      <= IDLE;
                        end else begin
                            round <= round + 5'd1;
                            state <= DISPATCH;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
