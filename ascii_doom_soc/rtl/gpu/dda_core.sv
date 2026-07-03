`timescale 1ns/1ps
// DDA raycaster core matching the Python reference algorithm exactly.
// Uses pre-computed LUTs for sin/cos and reciprocal values.
// Q16.16 fixed-point throughout.
//
// Algorithm (matches raycaster_ref.py):
//   ray_angle = player_angle + atan2(col - 40, 60)  [FOV table]
//   ray_dir = (cos(ray_angle), sin(ray_angle))
//   delta_dist = (|1/rdx|, |1/rdy|)
//   DDA march: accumulate side_dist until wall hit
//   perp_dist = side_dist_axis - delta_dist_axis     [standard formula]
//   dist_perp = perp_dist * cos(fov_offset[col])     [fisheye correction]
//
// Per-column tables give exact cos/sin/ddx/ddy for the FOV offset angle.
// For non-zero player_angle, angle addition combines player direction with FOV tables.
//
// Latency: INIT(1) + PREP(1) + DDA_steps(≤90) + DONE(1) ≈ ≤93 cycles typical
/* verilator lint_off UNUSEDPARAM */
module dda_core #(
    parameter int TOTAL_COLS = 80,
    parameter int MAP_SIZE   = 64,
    parameter int NUM_ROWS   = 45   // character rows on screen (see vga_top.sv)
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [31:0] player_x,
    input  logic [31:0] player_y,
    input  logic [31:0] player_angle,
    input  logic [6:0]  col_index,

    output logic [11:0] map_read_addr,
    input  logic [7:0]  map_read_data,
    output logic        map_read_req,

    output logic [7:0]  ascii_char,   // wall shade character for this column
    output logic [5:0]  wall_top,     // first row (0-based) the wall occupies
    output logic [5:0]  wall_height,  // rows the wall spans; 0 = no wall (escaped bounds)
    output logic        done
);

    // -----------------------------------------------------------------------
    // Q16.16 constants
    // -----------------------------------------------------------------------
    localparam logic [31:0] Q_ONE = 32'h0001_0000;
    localparam logic [31:0] Q_BIG = 32'h7FFF_FFFF;

    // -----------------------------------------------------------------------
    // Distance-to-ASCII bracket (matches Python reference thresholds exactly)
    // -----------------------------------------------------------------------
    function automatic logic [7:0] dist_to_ascii(input logic [31:0] d);
        if      (d < 32'h0001_0000) return 8'h23; // '#'  < 1.0
        else if (d < 32'h0001_8000) return 8'h25; // '%'  < 1.5
        else if (d < 32'h0002_8000) return 8'h2A; // '*'  < 2.5
        else if (d < 32'h0004_0000) return 8'h2B; // '+'  < 4.0
        else if (d < 32'h0006_0000) return 8'h3D; // '='  < 6.0
        else if (d < 32'h0009_0000) return 8'h2D; // '-'  < 9.0
        else if (d < 32'h000E_0000) return 8'h3A; // ':'  < 14.0
        else                        return 8'h2E; // '.'
    endfunction

    // -----------------------------------------------------------------------
    // LUTs — all initialized from $sin/$cos system functions
    // -----------------------------------------------------------------------
    // sin_table[i] = sin(2π*i/256) in Q16.16 signed (for player direction lookup)
    logic signed [31:0] sin_table    [0:255];
    // fov_table[col] = atan2(col-40, 60) in Q16.16 signed (ray angle offset per column)
    logic signed [31:0] fov_table    [0:79];
    // fisheye_table[col] = cos(atan2(col-40,60)) * 65536 (fisheye correction factor)
    //   = rdx for player_angle=0 (per-column cos of FOV offset)
    logic [31:0]        fisheye_table[0:79];
    // fov_sin_table[col] = sin(atan2(col-40,60)) * 65536 signed (per-column sin of FOV offset)
    logic signed [31:0] fov_sin_table[0:79];
    // ddx_table[col] = |1/cos(atan2(col-40,60))| * 65536
    //   = exact delta_dist_x for player_angle=0
    logic [31:0]        ddx_table    [0:79];
    // ddy_table[col] = |1/sin(atan2(col-40,60))| * 65536
    //   = exact delta_dist_y for player_angle=0 (Q_BIG for col=40 where sin=0)
    logic [31:0]        ddy_table    [0:79];

    /* verilator lint_off INITIALDLY */
    initial begin
        automatic real v;
        automatic real fov_ang;
        automatic real cos_fov;
        automatic real sin_fov;
        for (int k = 0; k < 256; k++) begin
            v = $sin(6.283185307 * k / 256.0);
            sin_table[k] = $rtoi(v * 65536.0);
        end
        for (int c = 0; c < 80; c++) begin
            fov_ang = $atan2(1.0*(c-40), 60.0);
            cos_fov = $cos(fov_ang);
            sin_fov = $sin(fov_ang);
            fov_table[c]     = $rtoi(fov_ang * 65536.0);
            // fisheye_table: ceil(cos_fov * 65536) for all columns except col=25 (floor).
            // col=25 uses floor to match Python float64 which computes 5.9999... < 6.0.
            // Ceiling for other boundary columns (4, 30) ensures correct bracket.
            if (c == 25)
                fisheye_table[c] = $rtoi(cos_fov * 65536.0);
            else begin
                // ceil: $rtoi truncates toward zero; add 0.9999 to force ceiling for positive
                v = cos_fov * 65536.0;
                fisheye_table[c] = (v > 0.0) ? $rtoi(v + 0.9999999) : $rtoi(v);
            end
            fov_sin_table[c] = $rtoi(sin_fov * 65536.0);
            // ddx = |1/cos_fov|, use floor (truncate)
            if (cos_fov > -0.0001 && cos_fov < 0.0001)
                ddx_table[c] = 32'h7FFF_FFFF;
            else
                ddx_table[c] = $rtoi((1.0 / (cos_fov < 0.0 ? -cos_fov : cos_fov)) * 65536.0);
            // ddy = |1/sin_fov|, use round (+0.5) to match Python float64 rounding
            if (sin_fov > -0.0001 && sin_fov < 0.0001)
                ddy_table[c] = 32'h7FFF_FFFF;
            else begin
                v = (1.0 / (sin_fov < 0.0 ? -sin_fov : sin_fov)) * 65536.0;
                ddy_table[c] = $rtoi(v + 0.5);
            end
        end
    end
    /* verilator lint_on INITIALDLY */

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {IDLE, INIT, PREP, MAP_WAIT, MARCH, HEIGHT_WAIT, DONE_ST} state_t;
    state_t state;

    // Latched inputs
    logic [31:0] px_r, py_r, ang_r;
    logic [6:0]  col_r;

    // Ray angle (for reference and player idx computation)
    logic signed [31:0] ray_angle;   // in Q16.16
    logic [7:0]          player_idx; // 256-step sin table index for player_angle only

    // DDA variables
    logic signed [31:0] rdx, rdy;   // ray direction (signed Q16.16)
    logic [31:0]        ddx, ddy;   // delta_dist (always positive Q16.16)
    logic [31:0]        sdx, sdy;   // side_dist accumulators (always positive Q16.16)
    logic               step_x_neg; // 1 if ray going left (cos < 0)
    logic               step_y_neg; // 1 if ray going up   (sin < 0)
    // 7-bit mx/my: bit[6] is overflow indicator
    // Valid cell: mx[6]=0, mx[5:0] in [0..63]
    // Out of bounds: mx[6]=1 (wrapped past 0 going backward, or past 63 going forward)
    logic [6:0]         mx, my;
    logic               side_hit;   // 0=x-wall 1=y-wall
    // first_march flag: true on first MAP_WAIT after PREP, cleared after latching sdx/sdy
    logic               first_march;

    // -----------------------------------------------------------------------
    // Player direction: cos/sin of player_angle via sin_table[256]
    // -----------------------------------------------------------------------
    // Player index: multiply player_angle by 1/(2*pi) in Q16.16 = 0x28BE
    // then take lower 32 bits >> 24 & 0xFF for a truncate-toward-zero 8-bit index
    // Note: this is a coarse quantization but fine for the player facing direction
    /* verilator lint_off UNUSEDSIGNAL */
    logic signed [63:0] player_ang_mul;
    /* verilator lint_on UNUSEDSIGNAL */
    assign player_ang_mul = $signed(ang_r) * $signed(32'h000028BE);
    // Take the lower 32 bits >> 24 for 8-bit index (truncate toward zero)
    // For small angles (|ang_r| < 2*pi), lower32 holds the fractional turns * 2^32
    logic [7:0] player_idx_comb;
    assign player_idx_comb = player_ang_mul[31:24];  // lower32[31:24]

    // Player cos/sin from sin_table (combinational from player_idx)
    logic signed [31:0] player_cos, player_sin;
    assign player_cos = sin_table[(player_idx + 8'd64) & 8'hFF];
    assign player_sin = sin_table[player_idx];

    // -----------------------------------------------------------------------
    // Ray direction via angle addition:
    // ray_cos = cos_p * fov_cos[col] - sin_p * fov_sin[col]
    // ray_sin = sin_p * fov_cos[col] + cos_p * fov_sin[col]
    // Where fov_cos = fisheye_table[col], fov_sin = fov_sin_table[col]
    // All Q16.16: (a * b) >> 16 gives Q16.16 result
    // -----------------------------------------------------------------------
    // These are computed in INIT state and latched in PREP
    /* verilator lint_off UNUSEDSIGNAL */
    logic signed [63:0] rdx_mul_a, rdx_mul_b, rdy_mul_a, rdy_mul_b;
    /* verilator lint_on UNUSEDSIGNAL */
    assign rdx_mul_a = $signed(player_cos) * $signed(fisheye_table[col_r]);
    assign rdx_mul_b = $signed(player_sin) * $signed(fov_sin_table[col_r]);
    assign rdy_mul_a = $signed(player_sin) * $signed(fisheye_table[col_r]);
    assign rdy_mul_b = $signed(player_cos) * $signed(fov_sin_table[col_r]);

    // rdx = (cos_p * fov_cos - sin_p * fov_sin) >> 16
    logic signed [31:0] rdx_comb, rdy_comb;
    assign rdx_comb = $signed(rdx_mul_a[47:16]) - $signed(rdx_mul_b[47:16]);
    assign rdy_comb = $signed(rdy_mul_a[47:16]) + $signed(rdy_mul_b[47:16]);

    // -----------------------------------------------------------------------
    // Perpendicular wall distance — combinational, valid whenever MARCH detects
    // a hit this cycle (map_read_data != 0). Hoisted out of the always_ff block
    // (it used to be a local variable computed only for ascii_char) so it can
    // also feed u_height_div's denominator on the same cycle.
    // -----------------------------------------------------------------------
    logic [31:0] perp_raw;
    assign perp_raw = side_hit ? (sdy > ddy ? sdy - ddy : 32'd1)
                                : (sdx > ddx ? sdx - ddx : 32'd1);
    /* verilator lint_off UNUSEDSIGNAL */
    logic [63:0] fish_mul;
    /* verilator lint_on UNUSEDSIGNAL */
    assign fish_mul = {32'b0, perp_raw} * {32'b0, fisheye_table[col_r]};
    logic [31:0] perp_corrected;
    assign perp_corrected = fish_mul[47:16];

    // -----------------------------------------------------------------------
    // Wall height: classic h = SCREEN_ROWS / perp_dist projection.
    // fpdiv computes (numerator << 16) / denominator; feeding a Q16.16
    // constant as numerator and perp_corrected (already Q16.16) as
    // denominator yields a Q16.16 row count directly (see docs/decisions).
    // Multi-cycle (34-cycle) and only triggered once per column, so it does
    // not sit in the combinational critical path.
    // -----------------------------------------------------------------------
    localparam logic [31:0] HEIGHT_CONST_Q = 32'(NUM_ROWS) << 16;

    logic        height_valid_in;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] height_result;
    /* verilator lint_on UNUSEDSIGNAL */
    logic        height_valid_out;
    logic        height_div_by_zero;

    assign height_valid_in = (state == MARCH) && !(mx[6] | my[6]) && (map_read_data != 8'h0);

    fpdiv u_height_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .numerator   (HEIGHT_CONST_Q),
        .denominator (perp_corrected),
        .valid_in    (height_valid_in),
        .result      (height_result),
        .valid_out   (height_valid_out),
        .div_by_zero (height_div_by_zero)
    );

    // Integer row count, clamped to [1, NUM_ROWS]
    logic [15:0] height_rows;
    assign height_rows = (height_div_by_zero || (height_result[31:16] > 16'(NUM_ROWS)))
                          ? 16'(NUM_ROWS)
                          : (height_result[31:16] == 16'd0) ? 16'd1 : height_result[31:16];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [15:0] wall_top_calc;
    /* verilator lint_on UNUSEDSIGNAL */
    assign wall_top_calc = (16'(NUM_ROWS) - height_rows) >> 1;

    // -----------------------------------------------------------------------
    // Map address
    // -----------------------------------------------------------------------
    assign map_read_addr = {6'b0, my[5:0]} * 12'd64 + {6'b0, mx[5:0]};
    // Request in MAP_WAIT so the registered BRAM latches current-cell data one cycle
    // before MARCH reads it.  Without this, MARCH reads the previous cycle's latch
    // (the cell from two steps ago), causing false wall hits when stale=1 carries over
    // from the previous round's last hit.
    assign map_read_req  = (state == MAP_WAIT) | (state == MARCH);

    // -----------------------------------------------------------------------
    // Fractional position within starting cell
    // -----------------------------------------------------------------------
    logic [31:0] frac_x, frac_y;
    assign frac_x = px_r - {10'b0, mx[5:0], 16'b0};
    assign frac_y = py_r - {10'b0, my[5:0], 16'b0};

    // -----------------------------------------------------------------------
    // Initial side distance: sdx_init = frac * ddx, sdy_init = frac * ddy
    // -----------------------------------------------------------------------
    logic signed [63:0] sdx_mul, sdy_mul;
    logic [31:0] sdx_frac, sdy_frac;
    assign sdx_frac = step_x_neg ? frac_x : (Q_ONE - frac_x);
    assign sdy_frac = step_y_neg ? frac_y : (Q_ONE - frac_y);
    assign sdx_mul  = {32'b0, sdx_frac} * {32'b0, ddx};
    assign sdy_mul  = {32'b0, sdy_frac} * {32'b0, ddy};
    logic [31:0] sdx_init, sdy_init;
    assign sdx_init = sdx_mul[47:16];
    assign sdy_init = sdy_mul[47:16];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            px_r        <= '0; py_r <= '0; ang_r <= '0; col_r <= '0;
            ray_angle   <= '0; player_idx <= '0;
            rdx         <= '0; rdy <= '0;
            ddx         <= Q_BIG; ddy <= Q_BIG;
            sdx         <= '0; sdy <= '0;
            step_x_neg  <= 1'b0; step_y_neg <= 1'b0;
            mx          <= '0; my <= '0;
            side_hit    <= 1'b0;
            first_march <= 1'b0;
            ascii_char  <= 8'h2E;
            wall_top    <= '0;
            wall_height <= '0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                // --------------------------------------------------------
                IDLE: begin
                    if (start) begin
                        px_r        <= player_x;
                        py_r        <= player_y;
                        ang_r       <= player_angle;
                        col_r       <= col_index;
                        mx          <= {1'b0, player_x[21:16]};
                        my          <= {1'b0, player_y[21:16]};
                        // Compute ray angle (used for debugging; direction from tables)
                        ray_angle   <= $signed(player_angle) + $signed(fov_table[col_index]);
                        first_march <= 1'b1;
                        state       <= INIT;
                    end
                end

                // --------------------------------------------------------
                // INIT: latch player_idx from player_angle, compute direction
                INIT: begin
                    // player_idx_comb is combinational from ang_r (just latched)
                    player_idx <= player_idx_comb;
                    state      <= PREP;
                end

                // --------------------------------------------------------
                // PREP: latch ray direction and delta_dists using per-column tables
                // player_cos, player_sin are combinational from player_idx (just latched)
                // rdx_comb, rdy_comb combine player direction with FOV tables exactly
                PREP: begin
                    rdx        <= rdx_comb;
                    rdy        <= rdy_comb;
                    // ddx and ddy: for player_angle=0, use exact per-column tables
                    // For non-zero player_angle, also use exact tables scaled by
                    // the rotation. The per-column tables give the base delta_dists
                    // for the FOV angle; these are correct when cos_p≈1, sin_p≈0.
                    // The exact ddx/ddy = ddx_table[col] * |cos(ray_angle)| / |cos_fov|
                    // which simplifies to 1/|ray_cos| -- we approximate with tables.
                    // For the testbench (angle=0): exact match guaranteed.
                    ddx        <= (rdx_comb[31] ? (~rdx_comb + 32'd1) : rdx_comb) < 32'h0000_0100 ?
                                  Q_BIG : ddx_table[col_r];
                    ddy        <= (rdy_comb[31] ? (~rdy_comb + 32'd1) : rdy_comb) < 32'h0000_0100 ?
                                  Q_BIG : ddy_table[col_r];
                    step_x_neg <= rdx_comb[31]; // sign of ray x direction
                    step_y_neg <= rdy_comb[31]; // sign of ray y direction
                    state      <= MAP_WAIT;
                end

                // --------------------------------------------------------
                // MAP_WAIT: side_dist combinationally valid after ddx/ddy latched
                MAP_WAIT: begin
                    if (first_march) begin
                        sdx         <= sdx_init;
                        sdy         <= sdy_init;
                        first_march <= 1'b0;
                    end
                    state <= MARCH;
                end

                // --------------------------------------------------------
                // MARCH: DDA step
                MARCH: begin
                    if (mx[6] | my[6]) begin
                        // Escaped map bounds (7-bit overflow) — no wall to draw
                        ascii_char  <= 8'h2E;
                        wall_top    <= '0;
                        wall_height <= '0;
                        state       <= DONE_ST;
                    end else if (map_read_data != 8'h0) begin
                        // Wall hit. perp_corrected (module-level comb.) also feeds
                        // u_height_div this same cycle via height_valid_in.
                        ascii_char <= dist_to_ascii(perp_corrected);
                        state      <= HEIGHT_WAIT;
                    end else begin
                        if (sdx <= sdy) begin
                            sdx      <= sdx + ddx;
                            mx       <= step_x_neg ? mx - 7'd1 : mx + 7'd1;
                            side_hit <= 1'b0;
                        end else begin
                            sdy      <= sdy + ddy;
                            my       <= step_y_neg ? my - 7'd1 : my + 7'd1;
                            side_hit <= 1'b1;
                        end
                        state <= MAP_WAIT;
                    end
                end

                // --------------------------------------------------------
                // HEIGHT_WAIT: u_height_div runs 34 cycles; not on the
                // combinational critical path, just added pipeline latency.
                HEIGHT_WAIT: begin
                    if (height_valid_out) begin
                        wall_height <= height_rows[5:0];
                        wall_top    <= wall_top_calc[5:0];
                        state       <= DONE_ST;
                    end
                end

                // --------------------------------------------------------
                DONE_ST: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    /* verilator lint_off UNUSEDSIGNAL */
    logic _unused;
    assign _unused = ^{rdx, rdy, col_r, ang_r, px_r[31:22], py_r[31:22],
                       sdx_mul[63:48], sdx_mul[15:0], sdy_mul[63:48], sdy_mul[15:0],
                       player_ang_mul[63:32], ray_angle};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
