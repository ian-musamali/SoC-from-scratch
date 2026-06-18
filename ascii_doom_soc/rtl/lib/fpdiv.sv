// Q16.16 signed fixed-point divider
// Computes result = (numerator << 16) / denominator using 32-cycle restoring division.
// Latency: 34 clock cycles after valid_in.
// div_by_zero asserted (with valid_out) when denominator == 0.
module fpdiv (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] numerator,
    input  logic [31:0] denominator,
    input  logic        valid_in,
    output logic [31:0] result,
    output logic        valid_out,
    output logic        div_by_zero
);

    // --- sign handling (combinational from inputs) ---
    logic        num_neg, den_neg;
    logic [31:0] abs_num, abs_den;

    assign num_neg = numerator[31];
    assign den_neg = denominator[31];
    assign abs_num = num_neg ? (~numerator   + 32'd1) : numerator;
    assign abs_den = den_neg ? (~denominator + 32'd1) : denominator;

    // --- state registers ---
    typedef enum logic [1:0] {IDLE, BUSY, DONE} state_t;
    state_t state;

    logic [31:0] quotient_r;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [32:0] remainder_r;   // 33-bit: MSB is overflow guard for trial subtraction
    /* verilator lint_on UNUSEDSIGNAL */
    logic [47:0] dividend_r;    // abs_num << 16, shifted left each BUSY cycle
    logic [31:0] divisor_r;
    logic [5:0]  bit_cnt;       // counts 47 → 0 (48 iterations for 48-bit dividend)
    logic        res_neg_r;

    // --- combinational restoring-division step (used in BUSY state) ---
    // Bring next dividend bit into LSB of remainder
    logic [32:0] shifted_rem;
    assign shifted_rem = {remainder_r[31:0], dividend_r[47]};

    // Trial subtract: if non-negative, keep; else restore
    logic [32:0] trial;
    assign trial = shifted_rem - {1'b0, divisor_r};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            quotient_r  <= '0;
            remainder_r <= '0;
            dividend_r  <= '0;
            divisor_r   <= '0;
            bit_cnt     <= '0;
            result      <= '0;
            valid_out   <= 1'b0;
            div_by_zero <= 1'b0;
            res_neg_r   <= 1'b0;
        end else begin
            valid_out   <= 1'b0;
            div_by_zero <= 1'b0;

            case (state)
                IDLE: begin
                    if (valid_in) begin
                        if (denominator == '0) begin
                            div_by_zero <= 1'b1;
                            result      <= 32'h7FFF_FFFF;
                            valid_out   <= 1'b1;
                        end else begin
                            dividend_r  <= {abs_num, 16'b0};
                            divisor_r   <= abs_den;
                            quotient_r  <= '0;
                            remainder_r <= '0;
                            bit_cnt     <= 6'd47;
                            res_neg_r   <= num_neg ^ den_neg;
                            state       <= BUSY;
                        end
                    end
                end

                BUSY: begin
                    if (!trial[32]) begin
                        remainder_r <= trial;
                        quotient_r  <= {quotient_r[30:0], 1'b1};
                    end else begin
                        remainder_r <= shifted_rem;
                        quotient_r  <= {quotient_r[30:0], 1'b0};
                    end
                    dividend_r <= {dividend_r[46:0], 1'b0};

                    if (bit_cnt == '0) state <= DONE;
                    else               bit_cnt <= bit_cnt - 6'd1;
                end

                DONE: begin
                    result    <= res_neg_r ? (~quotient_r + 32'd1) : quotient_r;
                    valid_out <= 1'b1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
