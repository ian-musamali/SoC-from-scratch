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
    // Per-core dispatch signals (flattened arrays)
    output logic [NUM_CORES-1:0]        core_start,
    output logic [6:0]                  core_col   [0:NUM_CORES-1],
    output logic [31:0]                 core_px    [0:NUM_CORES-1],
    output logic [31:0]                 core_py    [0:NUM_CORES-1],
    output logic [31:0]                 core_pang  [0:NUM_CORES-1],
    input  logic [NUM_CORES-1:0]        core_done
);

    localparam int ROUNDS = TOTAL_COLS / NUM_CORES; // 20 for 4 cores

    typedef enum logic [1:0] {IDLE, DISPATCH, WAIT} state_t;
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
                core_col[i]  <= '0;
                core_px[i]   <= '0;
                core_py[i]   <= '0;
                core_pang[i] <= '0;
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
                        core_col[i]   <= 7'(round * NUM_CORES + i);
                        core_px[i]    <= player_x;
                        core_py[i]    <= player_y;
                        core_pang[i]  <= player_angle;
                        core_start[i] <= 1'b1;
                    end
                    state <= WAIT;
                end

                WAIT: begin
                    // Accumulate done pulses — cores finish at different cycles
                    done_accum <= done_accum | core_done;
                    if ((done_accum | core_done) == {NUM_CORES{1'b1}}) begin
                        done_accum <= '0;
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
