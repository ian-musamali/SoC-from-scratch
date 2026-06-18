// Collects ASCII results from NUM_CORES DDA cores and writes to char_framebuffer via AXI4-Lite.
// Per-core result latches capture done pulses; priority-encode services one per cycle.
/* verilator lint_off UNUSEDPARAM */
module gpu_collector #(
    parameter int NUM_CORES  = 4,
    parameter int TOTAL_COLS = 80,
    parameter logic [31:0] VGA_FB_BASE = 32'h2000_0000
) (
    input  logic        clk,
    input  logic        rst_n,
    // Per-core result inputs
    input  logic [NUM_CORES-1:0] core_done,
    input  logic [6:0]           core_col  [0:NUM_CORES-1],
    input  logic [7:0]           core_char [0:NUM_CORES-1],
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

    // Per-core result latches — set when core fires done, cleared when the AXI
    // write for that result has been dispatched (W_IDLE → W_ADDR transition).
    logic [NUM_CORES-1:0] pend_valid;
    logic [6:0]           pend_col  [0:NUM_CORES-1];
    logic [7:0]           pend_char [0:NUM_CORES-1];

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

    // AXI write FSM
    typedef enum logic [1:0] {W_IDLE, W_ADDR, W_DATA, W_RESP} w_state_t;
    w_state_t w_state;

    // Single always_ff: manages pend_valid latches AND AXI FSM outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_valid <= '0;
            for (int i = 0; i < NUM_CORES; i++) begin
                pend_col[i]  <= '0;
                pend_char[i] <= '0;
            end
            w_state   <= W_IDLE;
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
                    pend_valid[i] <= 1'b1;
                    pend_col[i]   <= core_col[i];
                    pend_char[i]  <= core_char[i];
                end
            end

            // --- AXI write FSM ---
            case (w_state)
                W_IDLE: begin
                    if (any_pend) begin
                        m_awaddr            <= VGA_FB_BASE + {25'b0, pend_col[serv_idx]};
                        m_wdata             <= {24'b0, pend_char[serv_idx]};
                        m_awvalid           <= 1'b1;
                        m_wvalid            <= 1'b1;
                        m_wstrb             <= 4'b0001;
                        pend_valid[serv_idx] <= 1'b0;  // consume the latch
                        w_state             <= W_ADDR;
                    end
                end

                W_ADDR: begin
                    if (m_awready) begin
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
                        w_state <= W_IDLE;
                    end
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end

endmodule
