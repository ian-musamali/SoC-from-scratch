// AXI DMA controller — autonomous memory-to-memory transfer.
// CPU writes DMA_SRC, DMA_DST, DMA_LEN, then DMA_CTRL.start=1.
// DMA reads from src via AXI master read port, writes to dst via AXI master write port.
// Both ports connect to the axi4lite_fabric as master 1 (M1).
// Transfer is word-granular (4 bytes per beat). DMA_LEN is byte count (must be multiple of 4).
// Done flag in DMA_CTRL is set by the fabric's GPU MMIO register (bit1); the DMA top exposes
// the done signal externally rather than re-reading via AXI.
module axi_dma (
    input  logic        clk,
    input  logic        rst_n,
    // CPU-facing control
    input  logic        start,       // one-cycle pulse: begin transfer
    input  logic [31:0] src_addr,    // source byte address
    input  logic [31:0] dst_addr,    // destination byte address
    input  logic [31:0] byte_len,    // number of bytes to transfer (must be multiple of 4)
    output logic        done,        // one-cycle pulse when transfer complete

    // AXI4-Lite read master (DMA reads source)
    output logic [31:0] m_ar_addr,
    output logic        m_ar_valid,
    input  logic        m_ar_ready,
    input  logic [31:0] m_r_data,
    input  logic [1:0]  m_r_resp,
    input  logic        m_r_valid,
    output logic        m_r_ready,

    // AXI4-Lite write master (DMA writes destination)
    output logic [31:0] m_aw_addr,
    output logic        m_aw_valid,
    input  logic        m_aw_ready,
    output logic [31:0] m_w_data,
    output logic [3:0]  m_w_strb,
    output logic        m_w_valid,
    input  logic        m_w_ready,
    input  logic [1:0]  m_b_resp,
    input  logic        m_b_valid,
    output logic        m_b_ready
);

    /* verilator lint_off UNUSEDSIGNAL */
    logic [1:0] resp_r_unused, resp_b_unused;
    /* verilator lint_on UNUSEDSIGNAL */
    assign resp_r_unused = m_r_resp;
    assign resp_b_unused = m_b_resp;

    typedef enum logic [2:0] {
        IDLE,
        RD_ADDR,    // present AR
        RD_DATA,    // wait for R
        WR_ADDR,    // present AW + W
        WR_DATA,    // wait for W accept
        WR_RESP,    // wait for B
        DONE_ST
    } state_t;
    state_t state;

    logic [31:0] cur_src, cur_dst;
    logic [31:0] words_rem;   // words remaining
    logic [31:0] rd_data_r;   // latched read data

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            done       <= 1'b0;
            cur_src    <= '0;
            cur_dst    <= '0;
            words_rem  <= '0;
            rd_data_r  <= '0;
            m_ar_addr  <= '0;
            m_ar_valid <= 1'b0;
            m_r_ready  <= 1'b0;
            m_aw_addr  <= '0;
            m_aw_valid <= 1'b0;
            m_w_data   <= '0;
            m_w_strb   <= 4'hF;
            m_w_valid  <= 1'b0;
            m_b_ready  <= 1'b1;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        cur_src   <= src_addr;
                        cur_dst   <= dst_addr;
                        words_rem <= byte_len >> 2;
                        state     <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (words_rem == 32'd0) begin
                        state <= DONE_ST;
                    end else begin
                        m_ar_addr  <= cur_src;
                        m_ar_valid <= 1'b1;
                        m_r_ready  <= 1'b0;
                        state      <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_ar_ready) begin
                        m_ar_valid <= 1'b0;
                        m_r_ready  <= 1'b1;
                    end
                    if (m_r_valid && m_r_ready) begin
                        rd_data_r <= m_r_data;
                        m_r_ready <= 1'b0;
                        cur_src   <= cur_src + 32'd4;
                        state     <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    m_aw_addr  <= cur_dst;
                    m_aw_valid <= 1'b1;
                    m_w_data   <= rd_data_r;
                    m_w_strb   <= 4'hF;
                    m_w_valid  <= 1'b1;
                    state      <= WR_DATA;
                end

                WR_DATA: begin
                    if (m_aw_ready) m_aw_valid <= 1'b0;
                    if (m_w_ready)  m_w_valid  <= 1'b0;
                    // Advance when both channels are either already idle or being accepted now.
                    // Uses current (pre-NBA) values: "valid AND NOT being accepted" means still pending.
                    if ((!m_aw_valid || m_aw_ready) && (!m_w_valid || m_w_ready)) begin
                        state <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (m_b_valid) begin
                        cur_dst   <= cur_dst + 32'd4;
                        words_rem <= words_rem - 32'd1;
                        state     <= RD_ADDR;
                    end
                end

                DONE_ST: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
