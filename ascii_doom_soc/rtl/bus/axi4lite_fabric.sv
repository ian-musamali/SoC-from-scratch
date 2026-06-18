// AXI4-Lite 2-master × 4-slave crossbar.
// Masters: M0=CPU, M1=DMA. Round-robin arbitration; M1 wins ties.
// Address decode on bits[31:28]:
//   0x0... → S0 BRAM   0x00000000 – 0x0003FFFF
//   0x1... → S1 UART   0x10000000 – 0x10000FFF
//   0x2... → S2 VGA FB 0x20000000 – 0x20000FFF
//   0x3... → S3 GPU    0x30000000 – 0x3000001F
module axi4lite_fabric #(
    /* verilator lint_off UNUSEDPARAM */
    parameter int N_MASTERS = 2,
    parameter int N_SLAVES  = 4
    /* verilator lint_on UNUSEDPARAM */
) (
    input  logic clk,
    input  logic rst_n,

    // --- Master 0 (CPU) ---
    input  logic [31:0] m0_awaddr,  input  logic m0_awvalid, output logic m0_awready,
    input  logic [31:0] m0_wdata,   input  logic [3:0] m0_wstrb,
    input  logic        m0_wvalid,  output logic m0_wready,
    output logic [1:0]  m0_bresp,   output logic m0_bvalid,  input  logic m0_bready,
    input  logic [31:0] m0_araddr,  input  logic m0_arvalid, output logic m0_arready,
    output logic [31:0] m0_rdata,   output logic [1:0] m0_rresp,
    output logic        m0_rvalid,  input  logic m0_rready,

    // --- Master 1 (DMA) ---
    input  logic [31:0] m1_awaddr,  input  logic m1_awvalid, output logic m1_awready,
    input  logic [31:0] m1_wdata,   input  logic [3:0] m1_wstrb,
    input  logic        m1_wvalid,  output logic m1_wready,
    output logic [1:0]  m1_bresp,   output logic m1_bvalid,  input  logic m1_bready,
    input  logic [31:0] m1_araddr,  input  logic m1_arvalid, output logic m1_arready,
    output logic [31:0] m1_rdata,   output logic [1:0] m1_rresp,
    output logic        m1_rvalid,  input  logic m1_rready,

    // --- Slave 0 (BRAM) ---
    output logic [31:0] s0_awaddr,  output logic s0_awvalid, input  logic s0_awready,
    output logic [31:0] s0_wdata,   output logic [3:0] s0_wstrb,
    output logic        s0_wvalid,  input  logic s0_wready,
    input  logic [1:0]  s0_bresp,   input  logic s0_bvalid,  output logic s0_bready,
    output logic [31:0] s0_araddr,  output logic s0_arvalid, input  logic s0_arready,
    input  logic [31:0] s0_rdata,   input  logic [1:0] s0_rresp,
    input  logic        s0_rvalid,  output logic s0_rready,

    // --- Slave 1 (UART) ---
    output logic [31:0] s1_awaddr,  output logic s1_awvalid, input  logic s1_awready,
    output logic [31:0] s1_wdata,   output logic [3:0] s1_wstrb,
    output logic        s1_wvalid,  input  logic s1_wready,
    input  logic [1:0]  s1_bresp,   input  logic s1_bvalid,  output logic s1_bready,
    output logic [31:0] s1_araddr,  output logic s1_arvalid, input  logic s1_arready,
    input  logic [31:0] s1_rdata,   input  logic [1:0] s1_rresp,
    input  logic        s1_rvalid,  output logic s1_rready,

    // --- Slave 2 (VGA FB) ---
    output logic [31:0] s2_awaddr,  output logic s2_awvalid, input  logic s2_awready,
    output logic [31:0] s2_wdata,   output logic [3:0] s2_wstrb,
    output logic        s2_wvalid,  input  logic s2_wready,
    input  logic [1:0]  s2_bresp,   input  logic s2_bvalid,  output logic s2_bready,
    output logic [31:0] s2_araddr,  output logic s2_arvalid, input  logic s2_arready,
    input  logic [31:0] s2_rdata,   input  logic [1:0] s2_rresp,
    input  logic        s2_rvalid,  output logic s2_rready,

    // --- Slave 3 (GPU MMIO) ---
    output logic [31:0] s3_awaddr,  output logic s3_awvalid, input  logic s3_awready,
    output logic [31:0] s3_wdata,   output logic [3:0] s3_wstrb,
    output logic        s3_wvalid,  input  logic s3_wready,
    input  logic [1:0]  s3_bresp,   input  logic s3_bvalid,  output logic s3_bready,
    output logic [31:0] s3_araddr,  output logic s3_arvalid, input  logic s3_arready,
    input  logic [31:0] s3_rdata,   input  logic [1:0] s3_rresp,
    input  logic        s3_rvalid,  output logic s3_rready
);

    // -----------------------------------------------------------------------
    // Address decode: bits [31:28]
    // -----------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [1:0] decode_slave(input logic [31:0] addr);
    /* verilator lint_on UNUSEDSIGNAL */
        case (addr[31:28])
            4'h0:    return 2'd0; // BRAM
            4'h1:    return 2'd1; // UART
            4'h2:    return 2'd2; // VGA FB
            4'h3:    return 2'd3; // GPU MMIO
            default: return 2'd0;
        endcase
    endfunction

    // -----------------------------------------------------------------------
    // Write channel arbitration (AW+W+B) — registered state
    // -----------------------------------------------------------------------
    // Grant: 0=none, 1=M0, 2=M1
    typedef enum logic [1:0] {W_IDLE, W_M0, W_M1} w_state_t;
    w_state_t w_state;
    logic [1:0] w_slave;       // locked slave for current write transaction
    logic       w_last_grant;  // 0=M0 was last, 1=M1 was last (round-robin)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state      <= W_IDLE;
            w_slave      <= '0;
            w_last_grant <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (m1_awvalid && (!m0_awvalid || w_last_grant == 1'b0)) begin
                        // M1 wins (DMA priority on tie, or M0 was last)
                        w_slave      <= decode_slave(m1_awaddr);
                        w_state      <= W_M1;
                        w_last_grant <= 1'b1;
                    end else if (m0_awvalid) begin
                        w_slave      <= decode_slave(m0_awaddr);
                        w_state      <= W_M0;
                        w_last_grant <= 1'b0;
                    end
                end
                W_M0: begin
                    // Release when B channel handshake completes
                    if (m0_bvalid && m0_bready) w_state <= W_IDLE;
                end
                W_M1: begin
                    if (m1_bvalid && m1_bready) w_state <= W_IDLE;
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Read channel arbitration (AR+R) — registered state
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {R_IDLE, R_M0, R_M1} r_state_t;
    r_state_t r_state;
    logic [1:0] r_slave;
    logic       r_last_grant;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state      <= R_IDLE;
            r_slave      <= '0;
            r_last_grant <= 1'b0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (m1_arvalid && (!m0_arvalid || r_last_grant == 1'b0)) begin
                        r_slave      <= decode_slave(m1_araddr);
                        r_state      <= R_M1;
                        r_last_grant <= 1'b1;
                    end else if (m0_arvalid) begin
                        r_slave      <= decode_slave(m0_araddr);
                        r_state      <= R_M0;
                        r_last_grant <= 1'b0;
                    end
                end
                R_M0: begin
                    if (m0_rvalid && m0_rready) r_state <= R_IDLE;
                end
                R_M1: begin
                    if (m1_rvalid && m1_rready) r_state <= R_IDLE;
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Write address channel routing
    // -----------------------------------------------------------------------
    assign s0_awaddr  = (w_state == W_M0) ? m0_awaddr  : m1_awaddr;
    assign s1_awaddr  = s0_awaddr;
    assign s2_awaddr  = s0_awaddr;
    assign s3_awaddr  = s0_awaddr;

    assign s0_awvalid = ((w_state == W_M0 && m0_awvalid && w_slave == 2'd0) ||
                         (w_state == W_M1 && m1_awvalid && w_slave == 2'd0));
    assign s1_awvalid = ((w_state == W_M0 && m0_awvalid && w_slave == 2'd1) ||
                         (w_state == W_M1 && m1_awvalid && w_slave == 2'd1));
    assign s2_awvalid = ((w_state == W_M0 && m0_awvalid && w_slave == 2'd2) ||
                         (w_state == W_M1 && m1_awvalid && w_slave == 2'd2));
    assign s3_awvalid = ((w_state == W_M0 && m0_awvalid && w_slave == 2'd3) ||
                         (w_state == W_M1 && m1_awvalid && w_slave == 2'd3));

    // awready back to master
    wire slave_awready = (w_slave == 2'd0) ? s0_awready :
                         (w_slave == 2'd1) ? s1_awready :
                         (w_slave == 2'd2) ? s2_awready : s3_awready;

    assign m0_awready = (w_state == W_M0) ? slave_awready : 1'b0;
    assign m1_awready = (w_state == W_M1) ? slave_awready : 1'b0;

    // -----------------------------------------------------------------------
    // Write data channel routing
    // -----------------------------------------------------------------------
    assign s0_wdata  = (w_state == W_M0) ? m0_wdata  : m1_wdata;
    assign s0_wstrb  = (w_state == W_M0) ? m0_wstrb  : m1_wstrb;
    assign s1_wdata  = s0_wdata; assign s1_wstrb = s0_wstrb;
    assign s2_wdata  = s0_wdata; assign s2_wstrb = s0_wstrb;
    assign s3_wdata  = s0_wdata; assign s3_wstrb = s0_wstrb;

    assign s0_wvalid = ((w_state == W_M0 && m0_wvalid && w_slave == 2'd0) ||
                        (w_state == W_M1 && m1_wvalid && w_slave == 2'd0));
    assign s1_wvalid = ((w_state == W_M0 && m0_wvalid && w_slave == 2'd1) ||
                        (w_state == W_M1 && m1_wvalid && w_slave == 2'd1));
    assign s2_wvalid = ((w_state == W_M0 && m0_wvalid && w_slave == 2'd2) ||
                        (w_state == W_M1 && m1_wvalid && w_slave == 2'd2));
    assign s3_wvalid = ((w_state == W_M0 && m0_wvalid && w_slave == 2'd3) ||
                        (w_state == W_M1 && m1_wvalid && w_slave == 2'd3));

    wire slave_wready = (w_slave == 2'd0) ? s0_wready :
                        (w_slave == 2'd1) ? s1_wready :
                        (w_slave == 2'd2) ? s2_wready : s3_wready;

    assign m0_wready = (w_state == W_M0) ? slave_wready : 1'b0;
    assign m1_wready = (w_state == W_M1) ? slave_wready : 1'b0;

    // -----------------------------------------------------------------------
    // Write response channel routing
    // -----------------------------------------------------------------------
    wire [1:0] slave_bresp  = (w_slave == 2'd0) ? s0_bresp  :
                              (w_slave == 2'd1) ? s1_bresp  :
                              (w_slave == 2'd2) ? s2_bresp  : s3_bresp;
    wire       slave_bvalid = (w_slave == 2'd0) ? s0_bvalid :
                              (w_slave == 2'd1) ? s1_bvalid :
                              (w_slave == 2'd2) ? s2_bvalid : s3_bvalid;

    assign m0_bresp  = slave_bresp;
    assign m0_bvalid = (w_state == W_M0) ? slave_bvalid : 1'b0;
    assign m1_bresp  = slave_bresp;
    assign m1_bvalid = (w_state == W_M1) ? slave_bvalid : 1'b0;

    assign s0_bready = (w_slave == 2'd0) ? ((w_state == W_M0) ? m0_bready : m1_bready) : 1'b0;
    assign s1_bready = (w_slave == 2'd1) ? ((w_state == W_M0) ? m0_bready : m1_bready) : 1'b0;
    assign s2_bready = (w_slave == 2'd2) ? ((w_state == W_M0) ? m0_bready : m1_bready) : 1'b0;
    assign s3_bready = (w_slave == 2'd3) ? ((w_state == W_M0) ? m0_bready : m1_bready) : 1'b0;

    // -----------------------------------------------------------------------
    // Read address channel routing
    // -----------------------------------------------------------------------
    assign s0_araddr  = (r_state == R_M0) ? m0_araddr : m1_araddr;
    assign s1_araddr  = s0_araddr;
    assign s2_araddr  = s0_araddr;
    assign s3_araddr  = s0_araddr;

    assign s0_arvalid = ((r_state == R_M0 && m0_arvalid && r_slave == 2'd0) ||
                         (r_state == R_M1 && m1_arvalid && r_slave == 2'd0));
    assign s1_arvalid = ((r_state == R_M0 && m0_arvalid && r_slave == 2'd1) ||
                         (r_state == R_M1 && m1_arvalid && r_slave == 2'd1));
    assign s2_arvalid = ((r_state == R_M0 && m0_arvalid && r_slave == 2'd2) ||
                         (r_state == R_M1 && m1_arvalid && r_slave == 2'd2));
    assign s3_arvalid = ((r_state == R_M0 && m0_arvalid && r_slave == 2'd3) ||
                         (r_state == R_M1 && m1_arvalid && r_slave == 2'd3));

    wire slave_arready = (r_slave == 2'd0) ? s0_arready :
                         (r_slave == 2'd1) ? s1_arready :
                         (r_slave == 2'd2) ? s2_arready : s3_arready;

    assign m0_arready = (r_state == R_M0) ? slave_arready : 1'b0;
    assign m1_arready = (r_state == R_M1) ? slave_arready : 1'b0;

    // -----------------------------------------------------------------------
    // Read data channel routing
    // -----------------------------------------------------------------------
    wire [31:0] slave_rdata  = (r_slave == 2'd0) ? s0_rdata  :
                               (r_slave == 2'd1) ? s1_rdata  :
                               (r_slave == 2'd2) ? s2_rdata  : s3_rdata;
    wire [1:0]  slave_rresp  = (r_slave == 2'd0) ? s0_rresp  :
                               (r_slave == 2'd1) ? s1_rresp  :
                               (r_slave == 2'd2) ? s2_rresp  : s3_rresp;
    wire        slave_rvalid = (r_slave == 2'd0) ? s0_rvalid :
                               (r_slave == 2'd1) ? s1_rvalid :
                               (r_slave == 2'd2) ? s2_rvalid : s3_rvalid;

    assign m0_rdata  = slave_rdata;
    assign m0_rresp  = slave_rresp;
    assign m0_rvalid = (r_state == R_M0) ? slave_rvalid : 1'b0;
    assign m1_rdata  = slave_rdata;
    assign m1_rresp  = slave_rresp;
    assign m1_rvalid = (r_state == R_M1) ? slave_rvalid : 1'b0;

    assign s0_rready = (r_slave == 2'd0) ? ((r_state == R_M0) ? m0_rready : m1_rready) : 1'b0;
    assign s1_rready = (r_slave == 2'd1) ? ((r_state == R_M0) ? m0_rready : m1_rready) : 1'b0;
    assign s2_rready = (r_slave == 2'd2) ? ((r_state == R_M0) ? m0_rready : m1_rready) : 1'b0;
    assign s3_rready = (r_slave == 2'd3) ? ((r_state == R_M0) ? m0_rready : m1_rready) : 1'b0;

endmodule
