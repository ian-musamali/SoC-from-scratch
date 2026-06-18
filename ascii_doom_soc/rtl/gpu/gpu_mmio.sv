// GPU MMIO register block — AXI4-Lite slave.
// Implements all GPU_MMIO registers per the address map in CLAUDE.md.
module gpu_mmio (
    input  logic        clk,
    input  logic        rst_n,
    // AXI4-Lite slave
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] s_awaddr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_wdata,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [3:0]  s_wstrb,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        s_wvalid,
    output logic        s_wready,
    output logic [1:0]  s_bresp,
    output logic        s_bvalid,
    input  logic        s_bready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] s_araddr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        s_arvalid,
    output logic        s_arready,
    output logic [31:0] s_rdata,
    output logic [1:0]  s_rresp,
    output logic        s_rvalid,
    input  logic        s_rready,
    // GPU control signals
    output logic        frame_start,
    input  logic        frame_done,
    output logic [31:0] player_x,
    output logic [31:0] player_y,
    output logic [31:0] player_angle,
    input  logic [3:0]  core_busy,
    input  logic [31:0] gpu_cycles,
    input  logic [3:0]  core_util
);

    // Register file (word-addressed by bits [4:2])
    logic [31:0] reg_ctrl;      // 0x00: bit0=frame_start(w), bit1=frame_done(r)
    logic [31:0] reg_status;    // 0x04: bits[3:0]=per-core busy
    logic [31:0] reg_px;        // 0x08
    logic [31:0] reg_py;        // 0x0C
    logic [31:0] reg_pang;      // 0x10
    logic [31:0] reg_cycles;    // 0x14 read-only
    logic [31:0] reg_util;      // 0x18 read-only

    assign player_x     = reg_px;
    assign player_y     = reg_py;
    assign player_angle = reg_pang;

    // Write path
    // Write FSM: accept AW and W together in one cycle (standard AXI4-Lite shortcut)
    // s_awready and s_wready deasserted together to block re-entry until B completes.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_awready   <= 1'b1;
            s_wready    <= 1'b1;
            s_bvalid    <= 1'b0;
            s_bresp     <= 2'b00;
            frame_start <= 1'b0;
            reg_ctrl    <= '0;
            reg_px      <= 32'h0002_8000; // 2.5 default
            reg_py      <= 32'h0002_8000;
            reg_pang    <= '0;
        end else begin
            frame_start <= 1'b0;

            // Accept AW+W simultaneously: both must be valid and ready
            if (s_awvalid && s_awready && s_wvalid && s_wready) begin
                case (s_awaddr[4:0])
                    5'h00: begin
                        reg_ctrl    <= s_wdata;
                        frame_start <= s_wdata[0];
                    end
                    5'h08: reg_px   <= s_wdata;
                    5'h0C: reg_py   <= s_wdata;
                    5'h10: reg_pang <= s_wdata;
                    default: ;
                endcase
                s_awready <= 1'b0;
                s_wready  <= 1'b0;
                s_bvalid  <= 1'b1;
                s_bresp   <= 2'b00;
            end

            if (s_bvalid && s_bready) begin
                s_bvalid  <= 1'b0;
                s_awready <= 1'b1;
                s_wready  <= 1'b1;
            end
        end
    end

    // Read path
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_arready <= 1'b1;
            s_rvalid  <= 1'b0;
            s_rdata   <= '0;
            s_rresp   <= 2'b00;
            reg_status <= '0;
            reg_cycles <= '0;
            reg_util   <= '0;
        end else begin
            // Update read-only mirrors from GPU inputs
            reg_status <= {28'b0, core_busy};
            reg_cycles <= gpu_cycles;
            reg_util   <= {28'b0, core_util};

            if (s_arvalid && s_arready) begin
                s_arready <= 1'b0;
                s_rvalid  <= 1'b1;
                s_rresp   <= 2'b00;
                case (s_araddr[4:0])
                    // bit1 is live frame_done status — not stored in reg_ctrl to avoid multi-driver
                    5'h00: s_rdata <= {reg_ctrl[31:2], frame_done, reg_ctrl[0]};
                    5'h04: s_rdata <= reg_status;
                    5'h08: s_rdata <= reg_px;
                    5'h0C: s_rdata <= reg_py;
                    5'h10: s_rdata <= reg_pang;
                    5'h14: s_rdata <= reg_cycles;
                    5'h18: s_rdata <= reg_util;
                    default: s_rdata <= '0;
                endcase
            end

            if (s_rvalid && s_rready) begin
                s_rvalid  <= 1'b0;
                s_arready <= 1'b1;
            end
        end
    end

endmodule
