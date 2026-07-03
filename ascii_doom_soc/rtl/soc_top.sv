`timescale 1ns/1ps
// ASCII Doom SoC — top-level integration
//
// Architecture:
//   CPU (PicoRV32 AXI) ─── M0 ─┐
//                                ├─ AXI4-Lite fabric ─── S0 BRAM 256 KB
//   DMA             ─────── M1 ─┘                    ─── S1 UART
//                                                      ─── S2 stub (VGA FB via CPU – unused in game loop)
//                                                      ─── S3 GPU MMIO
//
//   GPU collector (m_*) ──────────────────────────────────→ char_framebuffer (direct, no fabric)
//
//   char_framebuffer ─── vga_addr/vga_data ──────────────→ vga_top → VGA pins
//   font_rom         ─── font_addr/font_data ────────────→ vga_top
//
// The GPU collector always writes to VGA_FB_BASE (0x2000_0000+col).
// It bypasses the fabric to avoid needing a third fabric master port.
// The fabric's S2 slot is wired to a dummy always-ready slave; CPU does not
// write to VGA FB in the normal game loop.
//
// Map BRAMs: each DDA core has its own 4 KB read-only map BRAM.
// The CPU initialises all four by writing to 0x0004_0000–0x0004_0FFF via BRAM S0
// (the top 4 KB of BRAM is logically aliased to the four map BRAMs via soc_top wiring).

/* verilator lint_off UNUSEDPARAM */
module soc_top #(
    parameter int  NUM_GPU_CORES = 4,
    parameter int  MAP_SIZE      = 64,
    parameter int  BRAM_WORDS    = 65536,  // 256 KB / 4
    parameter bit  SIMULATION    = 0       // 1 = expose CPU AXI ports for testbench
) (
    input  logic        sys_clk,
    input  logic        pix_clk,    // 25.175 MHz — drive from MMCM in XDC
    input  logic        rst_n,

    // VGA outputs
    output logic        vga_hsync,
    output logic        vga_vsync,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,

    // UART (debug)
    output logic        uart_tx,
    input  logic        uart_rx,

    // Player input — already synchronized to sys_clk by fpga_top; bit order
    // {btnc, btnr, btnl, btnd, btnu}, active-high
    input  logic [4:0]  buttons,

    // CPU AXI master bypass — only active when SIMULATION=1
    // In synthesis (SIMULATION=0), these are ignored; picorv32_axi drives the bus.
    input  logic [31:0] sim_cpu_awaddr,
    input  logic        sim_cpu_awvalid,
    output logic        sim_cpu_awready,
    input  logic [31:0] sim_cpu_wdata,
    input  logic [3:0]  sim_cpu_wstrb,
    input  logic        sim_cpu_wvalid,
    output logic        sim_cpu_wready,
    output logic [1:0]  sim_cpu_bresp,
    output logic        sim_cpu_bvalid,
    input  logic        sim_cpu_bready,
    input  logic [31:0] sim_cpu_araddr,
    input  logic        sim_cpu_arvalid,
    output logic        sim_cpu_arready,
    output logic [31:0] sim_cpu_rdata,
    output logic [1:0]  sim_cpu_rresp,
    output logic        sim_cpu_rvalid,
    input  logic        sim_cpu_rready,
    // Map data backdoor for simulation — write to per-core map BRAMs
    input  logic [11:0] sim_map_addr,
    input  logic [7:0]  sim_map_wdata,
    input  logic        sim_map_wen,
    input  logic [1:0]  sim_map_core
);
/* verilator lint_on UNUSEDPARAM */

    // =========================================================================
    // CPU AXI4-Lite master bus
    // =========================================================================
    logic [31:0] cpu_awaddr;  logic cpu_awvalid; logic cpu_awready;
    logic [31:0] cpu_wdata;   logic [3:0] cpu_wstrb;
    logic        cpu_wvalid;  logic cpu_wready;
    logic [1:0]  cpu_bresp;   logic cpu_bvalid;  logic cpu_bready;
    logic [31:0] cpu_araddr;  logic cpu_arvalid; logic cpu_arready;
    logic [31:0] cpu_rdata;   logic [1:0] cpu_rresp;
    logic        cpu_rvalid;  logic cpu_rready;

    // =========================================================================
    // DMA AXI4-Lite master bus
    // =========================================================================
    logic [31:0] dma_awaddr;  logic dma_awvalid; logic dma_awready;
    logic [31:0] dma_wdata;   logic [3:0] dma_wstrb;
    logic        dma_wvalid;  logic dma_wready;
    logic [1:0]  dma_bresp;   logic dma_bvalid;  logic dma_bready;
    logic [31:0] dma_araddr;  logic dma_arvalid; logic dma_arready;
    logic [31:0] dma_rdata;   logic [1:0] dma_rresp;
    logic        dma_rvalid;  logic dma_rready;

    // =========================================================================
    // Fabric slave buses
    // =========================================================================
    // S0: BRAM
    logic [31:0] bram_awaddr;  logic bram_awvalid; logic bram_awready;
    logic [31:0] bram_wdata;   logic [3:0] bram_wstrb;
    logic        bram_wvalid;  logic bram_wready;
    logic [1:0]  bram_bresp;   logic bram_bvalid;  logic bram_bready;
    logic [31:0] bram_araddr;  logic bram_arvalid; logic bram_arready;
    logic [31:0] bram_rdata;   logic [1:0] bram_rresp;
    logic        bram_rvalid;  logic bram_rready;

    // S1: UART
    logic [31:0] uart_awaddr;  logic uart_awvalid; logic uart_awready;
    logic [31:0] uart_wdata;   logic [3:0] uart_wstrb;
    logic        uart_wvalid;  logic uart_wready;
    logic [1:0]  uart_bresp;   logic uart_bvalid;  logic uart_bready;
    logic [31:0] uart_araddr;  logic uart_arvalid; logic uart_arready;
    logic [31:0] uart_rdata;   logic [1:0] uart_rresp;
    logic        uart_rvalid;  logic uart_rready;

    // S2: VGA FB stub (CPU path, not used in game loop)
    logic [31:0] vfb_awaddr;  logic vfb_awvalid; logic vfb_awready;
    logic [31:0] vfb_wdata;   logic [3:0] vfb_wstrb;
    logic        vfb_wvalid;  logic vfb_wready;
    logic [1:0]  vfb_bresp;   logic vfb_bvalid;  logic vfb_bready;
    logic [31:0] vfb_araddr;  logic vfb_arvalid; logic vfb_arready;
    logic [31:0] vfb_rdata;   logic [1:0] vfb_rresp;
    logic        vfb_rvalid;  logic vfb_rready;

    // S3: GPU MMIO
    logic [31:0] gpu_s_awaddr;  logic gpu_s_awvalid; logic gpu_s_awready;
    logic [31:0] gpu_s_wdata;   logic [3:0] gpu_s_wstrb;
    logic        gpu_s_wvalid;  logic gpu_s_wready;
    logic [1:0]  gpu_s_bresp;   logic gpu_s_bvalid;  logic gpu_s_bready;
    logic [31:0] gpu_s_araddr;  logic gpu_s_arvalid; logic gpu_s_arready;
    logic [31:0] gpu_s_rdata;   logic [1:0] gpu_s_rresp;
    logic        gpu_s_rvalid;  logic gpu_s_rready;

    // =========================================================================
    // GPU collector AXI master → char_framebuffer (direct path)
    // =========================================================================
    logic [31:0] gcoll_awaddr;  logic gcoll_awvalid; logic gcoll_awready;
    logic [31:0] gcoll_wdata;   logic [3:0] gcoll_wstrb;
    logic        gcoll_wvalid;  logic gcoll_wready;
    logic [1:0]  gcoll_bresp;   logic gcoll_bvalid;  logic gcoll_bready;

    // =========================================================================
    // char_framebuffer AXI connections (write = GPU collector; read = fabric S2)
    // =========================================================================
    // Write port: GPU collector (higher priority in game loop, CPU stub never writes)
    // Read port:  fabric S2 (CPU debug reads)
    logic [11:0] cfb_awaddr_w;

    assign cfb_awaddr_w = gcoll_awaddr[11:0];

    // =========================================================================
    // VGA framebuffer read/write to/from vga_top
    // =========================================================================
    logic [11:0] vga_fb_addr;
    logic [7:0]  vga_fb_data;

    // =========================================================================
    // Font ROM
    // =========================================================================
    logic [9:0]  font_addr;
    logic [7:0]  font_data;

    // =========================================================================
    // Map BRAMs — per-core replicated read-only maps
    // (CPU initialises via BRAM S0 aliased top 4KB; simplified here as inferred BRAM)
    // =========================================================================
    logic [11:0]              map_addr [0:NUM_GPU_CORES-1];
    logic [7:0]                map_data [0:NUM_GPU_CORES-1];
    logic [NUM_GPU_CORES-1:0] map_req; // 1 bit/core: packed vector, not an unpacked array

    // gpu_top's map_read_addr/data ports are packed flat buses (Yosys can't
    // synthesize unpacked-array ports — see gpu_dispatcher.sv), while the
    // per-core BRAMs below want a plain per-core array. Shim between the two.
    logic [NUM_GPU_CORES*12-1:0] map_addr_flat;
    logic [NUM_GPU_CORES*8-1:0]  map_data_flat;

    // Per-core map BRAMs — separate 1D arrays so Vivado infers one BRAM18 per core.
    // (2D arrays infer as "3D-RAM" and may dissolve into registers.)
    // CPU loads map data via game_loop.c at startup; testbench uses sim backdoor.
    genvar mc;
    generate
        for (mc = 0; mc < NUM_GPU_CORES; mc++) begin : gen_map
            // Unpack/pack this core's slice of gpu_top's flat map ports
            assign map_addr[mc] = map_addr_flat[mc*12 +: 12];
            assign map_data_flat[mc*8 +: 8] = map_data[mc];

            (* ram_style = "block" *)
            logic [7:0] map_bram [0:MAP_SIZE*MAP_SIZE-1];

            /* verilator lint_off INITIALDLY */
            initial $readmemh("software/firmware/map.hex", map_bram);
            /* verilator lint_on INITIALDLY */

            // Simulation backdoor — constant-false in synthesis (sim_map_wen tied 0)
            always_ff @(posedge sys_clk) begin
                if (sim_map_wen && (sim_map_core == 2'(mc)))
                    map_bram[sim_map_addr] <= sim_map_wdata;
            end

            // Registered read (BRAM output register, no reset)
            always_ff @(posedge sys_clk) begin
                if (map_req[mc])
                    map_data[mc] <= map_bram[map_addr[mc]];
            end
        end
    endgenerate

    // =========================================================================
    // CPU — PicoRV32 AXI wrapper (or simulation bypass)
    // =========================================================================
    generate
        if (SIMULATION) begin : gen_sim_cpu
            // Testbench drives the CPU AXI master directly
            assign cpu_awaddr  = sim_cpu_awaddr;
            assign cpu_awvalid = sim_cpu_awvalid;
            assign cpu_wdata   = sim_cpu_wdata;
            assign cpu_wstrb   = sim_cpu_wstrb;
            assign cpu_wvalid  = sim_cpu_wvalid;
            assign cpu_bready  = sim_cpu_bready;
            assign cpu_araddr  = sim_cpu_araddr;
            assign cpu_arvalid = sim_cpu_arvalid;
            assign cpu_rready  = sim_cpu_rready;
            // Fabric M0 ready/response outputs back to testbench
            assign sim_cpu_awready = cpu_awready;
            assign sim_cpu_wready  = cpu_wready;
            assign sim_cpu_bresp   = cpu_bresp;
            assign sim_cpu_bvalid  = cpu_bvalid;
            assign sim_cpu_arready = cpu_arready;
            assign sim_cpu_rdata   = cpu_rdata;
            assign sim_cpu_rresp   = cpu_rresp;
            assign sim_cpu_rvalid  = cpu_rvalid;
        end else begin : gen_real_cpu
            /* verilator lint_off PINCONNECTEMPTY */
            picorv32_axi #(
                .ENABLE_MUL    (1),
                .ENABLE_FAST_MUL(1),
                .ENABLE_DIV    (1),
                .STACKADDR     (32'h0003_FFF0),  // top of 256 KB BRAM
                .PROGADDR_RESET(32'h0000_0000)
            ) u_cpu (
                .clk            (sys_clk),
                .resetn         (rst_n),
                .mem_axi_awaddr (cpu_awaddr),
                .mem_axi_awvalid(cpu_awvalid),
                .mem_axi_awready(cpu_awready),
                .mem_axi_awprot (),
                .mem_axi_wdata  (cpu_wdata),
                .mem_axi_wstrb  (cpu_wstrb),
                .mem_axi_wvalid (cpu_wvalid),
                .mem_axi_wready (cpu_wready),
                .mem_axi_bvalid (cpu_bvalid),
                .mem_axi_bready (cpu_bready),
                .mem_axi_araddr (cpu_araddr),
                .mem_axi_arvalid(cpu_arvalid),
                .mem_axi_arready(cpu_arready),
                .mem_axi_arprot (),
                .mem_axi_rdata  (cpu_rdata),
                .mem_axi_rvalid (cpu_rvalid),
                .mem_axi_rready (cpu_rready),
                .trap           (),
                .irq            (32'b0),
                .eoi            ()
            );
            /* verilator lint_on PINCONNECTEMPTY */
            // Unused sim bypass ports
            assign sim_cpu_awready = 1'b0;
            assign sim_cpu_wready  = 1'b0;
            assign sim_cpu_bresp   = 2'b0;
            assign sim_cpu_bvalid  = 1'b0;
            assign sim_cpu_arready = 1'b0;
            assign sim_cpu_rdata   = 32'b0;
            assign sim_cpu_rresp   = 2'b0;
            assign sim_cpu_rvalid  = 1'b0;
        end
    endgenerate

    // =========================================================================
    // AXI4-Lite DMA controller (Master 1)
    // =========================================================================
    logic        dma_start;
    logic [31:0] dma_src, dma_dst, dma_len;
    logic        dma_done;

    axi_dma u_dma (
        .clk      (sys_clk),
        .rst_n    (rst_n),
        .start    (dma_start),
        .src_addr (dma_src),
        .dst_addr (dma_dst),
        .byte_len (dma_len),
        .done     (dma_done),
        .m_ar_addr (dma_araddr),  .m_ar_valid(dma_arvalid), .m_ar_ready(dma_arready),
        .m_r_data  (dma_rdata),   .m_r_resp  (dma_rresp),   .m_r_valid (dma_rvalid),
        .m_r_ready (dma_rready),
        .m_aw_addr (dma_awaddr),  .m_aw_valid(dma_awvalid), .m_aw_ready(dma_awready),
        .m_w_data  (dma_wdata),   .m_w_strb  (dma_wstrb),   .m_w_valid (dma_wvalid),
        .m_w_ready (dma_wready),
        .m_b_resp  (dma_bresp),   .m_b_valid (dma_bvalid),  .m_b_ready (dma_bready)
    );

    // DMA control comes from GPU MMIO DMA_CTRL register (wired below via gpu_top outputs)
    // For now, tie off (GPU MMIO DMA registers not yet wired through gpu_top interface)
    assign dma_start = 1'b0;
    assign dma_src   = '0;
    assign dma_dst   = '0;
    assign dma_len   = '0;

    // =========================================================================
    // AXI4-Lite fabric: 2 masters × 4 slaves
    // =========================================================================
    axi4lite_fabric u_fabric (
        .clk   (sys_clk),
        .rst_n (rst_n),
        // M0 — CPU
        .m0_awaddr(cpu_awaddr),   .m0_awvalid(cpu_awvalid), .m0_awready(cpu_awready),
        .m0_wdata (cpu_wdata),    .m0_wstrb  (cpu_wstrb),
        .m0_wvalid(cpu_wvalid),   .m0_wready (cpu_wready),
        .m0_bresp (cpu_bresp),    .m0_bvalid (cpu_bvalid),  .m0_bready(cpu_bready),
        .m0_araddr(cpu_araddr),   .m0_arvalid(cpu_arvalid), .m0_arready(cpu_arready),
        .m0_rdata (cpu_rdata),    .m0_rresp  (cpu_rresp),
        .m0_rvalid(cpu_rvalid),   .m0_rready (cpu_rready),
        // M1 — DMA
        .m1_awaddr(dma_awaddr),   .m1_awvalid(dma_awvalid), .m1_awready(dma_awready),
        .m1_wdata (dma_wdata),    .m1_wstrb  (dma_wstrb),
        .m1_wvalid(dma_wvalid),   .m1_wready (dma_wready),
        .m1_bresp (dma_bresp),    .m1_bvalid (dma_bvalid),  .m1_bready(dma_bready),
        .m1_araddr(dma_araddr),   .m1_arvalid(dma_arvalid), .m1_arready(dma_arready),
        .m1_rdata (dma_rdata),    .m1_rresp  (dma_rresp),
        .m1_rvalid(dma_rvalid),   .m1_rready (dma_rready),
        // S0 — BRAM
        .s0_awaddr(bram_awaddr),  .s0_awvalid(bram_awvalid), .s0_awready(bram_awready),
        .s0_wdata (bram_wdata),   .s0_wstrb  (bram_wstrb),
        .s0_wvalid(bram_wvalid),  .s0_wready (bram_wready),
        .s0_bresp (bram_bresp),   .s0_bvalid (bram_bvalid),  .s0_bready(bram_bready),
        .s0_araddr(bram_araddr),  .s0_arvalid(bram_arvalid), .s0_arready(bram_arready),
        .s0_rdata (bram_rdata),   .s0_rresp  (bram_rresp),
        .s0_rvalid(bram_rvalid),  .s0_rready (bram_rready),
        // S1 — UART
        .s1_awaddr(uart_awaddr),  .s1_awvalid(uart_awvalid), .s1_awready(uart_awready),
        .s1_wdata (uart_wdata),   .s1_wstrb  (uart_wstrb),
        .s1_wvalid(uart_wvalid),  .s1_wready (uart_wready),
        .s1_bresp (uart_bresp),   .s1_bvalid (uart_bvalid),  .s1_bready(uart_bready),
        .s1_araddr(uart_araddr),  .s1_arvalid(uart_arvalid), .s1_arready(uart_arready),
        .s1_rdata (uart_rdata),   .s1_rresp  (uart_rresp),
        .s1_rvalid(uart_rvalid),  .s1_rready (uart_rready),
        // S2 — VGA FB stub (CPU debug path; GPU collector writes directly)
        .s2_awaddr(vfb_awaddr),   .s2_awvalid(vfb_awvalid),  .s2_awready(vfb_awready),
        .s2_wdata (vfb_wdata),    .s2_wstrb  (vfb_wstrb),
        .s2_wvalid(vfb_wvalid),   .s2_wready (vfb_wready),
        .s2_bresp (vfb_bresp),    .s2_bvalid (vfb_bvalid),   .s2_bready(vfb_bready),
        .s2_araddr(vfb_araddr),   .s2_arvalid(vfb_arvalid),  .s2_arready(vfb_arready),
        .s2_rdata (vfb_rdata),    .s2_rresp  (vfb_rresp),
        .s2_rvalid(vfb_rvalid),   .s2_rready (vfb_rready),
        // S3 — GPU MMIO
        .s3_awaddr(gpu_s_awaddr), .s3_awvalid(gpu_s_awvalid), .s3_awready(gpu_s_awready),
        .s3_wdata (gpu_s_wdata),  .s3_wstrb  (gpu_s_wstrb),
        .s3_wvalid(gpu_s_wvalid), .s3_wready (gpu_s_wready),
        .s3_bresp (gpu_s_bresp),  .s3_bvalid (gpu_s_bvalid),  .s3_bready(gpu_s_bready),
        .s3_araddr(gpu_s_araddr), .s3_arvalid(gpu_s_arvalid), .s3_arready(gpu_s_arready),
        .s3_rdata (gpu_s_rdata),  .s3_rresp  (gpu_s_rresp),
        .s3_rvalid(gpu_s_rvalid), .s3_rready (gpu_s_rready)
    );

    // =========================================================================
    // BRAM — 256 KB, inferred as Xilinx block RAM tiles
    // Port A: AXI4-Lite (CPU/DMA via fabric)
    // =========================================================================
    (* ram_style = "block" *)
    logic [31:0] bram [0:BRAM_WORDS-1];

    logic [31:0] bram_aw_r;
    logic        bram_aw_pend;

    // AXI control signals — async reset supported here
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_awready <= 1'b1;
            bram_wready  <= 1'b1;
            bram_bvalid  <= 1'b0;
            bram_bresp   <= 2'b00;
            bram_arready <= 1'b1;
            bram_rvalid  <= 1'b0;
            bram_rresp   <= 2'b00;
            bram_aw_r    <= '0;
            bram_aw_pend <= 1'b0;
        end else begin
            if (bram_awvalid && bram_awready) begin
                bram_aw_r    <= bram_awaddr;
                bram_aw_pend <= 1'b1;
                bram_awready <= 1'b0;
            end
            if (bram_wvalid && bram_wready && bram_aw_pend) begin
                bram_aw_pend <= 1'b0;
                bram_bvalid  <= 1'b1;
                bram_awready <= 1'b1;
                bram_wready  <= 1'b1;
            end
            if (bram_bvalid && bram_bready) bram_bvalid <= 1'b0;
            if (bram_arvalid && bram_arready) begin
                bram_rvalid  <= 1'b1;
                bram_arready <= 1'b0;
            end
            if (bram_rvalid && bram_rready) begin
                bram_rvalid  <= 1'b0;
                bram_arready <= 1'b1;
            end
        end
    end

    // BRAM data — no reset (Xilinx BRAM inference).  Read uses enable so that
    // bram_rdata is only updated on the AXI handshake cycle; the address is
    // valid at that point and rvalid is asserted one clock later.
    /* verilator lint_off INITIALDLY */
    initial $readmemh("software/firmware/firmware.hex", bram);
    /* verilator lint_on INITIALDLY */
    always_ff @(posedge sys_clk) begin
        if (bram_wvalid && bram_wready && bram_aw_pend) begin
            if (bram_wstrb[0]) bram[bram_aw_r[17:2]][7:0]   <= bram_wdata[7:0];
            if (bram_wstrb[1]) bram[bram_aw_r[17:2]][15:8]  <= bram_wdata[15:8];
            if (bram_wstrb[2]) bram[bram_aw_r[17:2]][23:16] <= bram_wdata[23:16];
            if (bram_wstrb[3]) bram[bram_aw_r[17:2]][31:24] <= bram_wdata[31:24];
        end
        if (bram_arvalid && bram_arready)
            bram_rdata <= bram[bram_araddr[17:2]];
    end

    // =========================================================================
    // UART
    // =========================================================================
    uart_lite u_uart (
        .clk(sys_clk), .rst_n(rst_n),
        .s_awaddr(uart_awaddr),  .s_awvalid(uart_awvalid), .s_awready(uart_awready),
        .s_wdata (uart_wdata),   .s_wstrb  (uart_wstrb),
        .s_wvalid(uart_wvalid),  .s_wready (uart_wready),
        .s_bresp (uart_bresp),   .s_bvalid (uart_bvalid),  .s_bready(uart_bready),
        .s_araddr(uart_araddr),  .s_arvalid(uart_arvalid), .s_arready(uart_arready),
        .s_rdata (uart_rdata),   .s_rresp  (uart_rresp),
        .s_rvalid(uart_rvalid),  .s_rready (uart_rready),
        .tx(uart_tx), .rx(uart_rx)
    );

    // =========================================================================
    // VGA FB stub — always-ready slave for fabric S2 (read returns 0)
    // =========================================================================
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            vfb_awready <= 1'b1;
            vfb_wready  <= 1'b1;
            vfb_bvalid  <= 1'b0;
            vfb_bresp   <= 2'b00;
            vfb_arready <= 1'b1;
            vfb_rvalid  <= 1'b0;
            vfb_rdata   <= '0;
            vfb_rresp   <= 2'b00;
        end else begin
            if (vfb_awvalid && vfb_awready && vfb_wvalid && vfb_wready)
                vfb_bvalid <= 1'b1;
            if (vfb_bvalid && vfb_bready) vfb_bvalid <= 1'b0;
            if (vfb_arvalid && vfb_arready) begin
                vfb_rdata   <= '0;
                vfb_rvalid  <= 1'b1;
                vfb_arready <= 1'b0;
            end
            if (vfb_rvalid && vfb_rready) begin
                vfb_rvalid  <= 1'b0;
                vfb_arready <= 1'b1;
            end
        end
    end

    // =========================================================================
    // GPU top (MMIO slave + collector master)
    // =========================================================================
    gpu_top #(
        .NUM_CORES (NUM_GPU_CORES),
        .TOTAL_COLS(80),
        .MAP_SIZE  (MAP_SIZE)
    ) u_gpu (
        .clk     (sys_clk),
        .rst_n   (rst_n),
        .buttons (buttons),
        // MMIO slave (from fabric S3)
        .s_awaddr (gpu_s_awaddr),  .s_awvalid(gpu_s_awvalid), .s_awready(gpu_s_awready),
        .s_wdata  (gpu_s_wdata),   .s_wstrb  (gpu_s_wstrb),
        .s_wvalid (gpu_s_wvalid),  .s_wready (gpu_s_wready),
        .s_bresp  (gpu_s_bresp),   .s_bvalid (gpu_s_bvalid),  .s_bready(gpu_s_bready),
        .s_araddr (gpu_s_araddr),  .s_arvalid(gpu_s_arvalid), .s_arready(gpu_s_arready),
        .s_rdata  (gpu_s_rdata),   .s_rresp  (gpu_s_rresp),
        .s_rvalid (gpu_s_rvalid),  .s_rready (gpu_s_rready),
        // Collector master → char_framebuffer (direct, not through fabric)
        .m_awaddr (gcoll_awaddr),  .m_awvalid(gcoll_awvalid), .m_awready(gcoll_awready),
        .m_wdata  (gcoll_wdata),   .m_wstrb  (gcoll_wstrb),
        .m_wvalid (gcoll_wvalid),  .m_wready (gcoll_wready),
        .m_bresp  (gcoll_bresp),   .m_bvalid (gcoll_bvalid),  .m_bready(gcoll_bready),
        // Per-core map ports
        .map_read_addr_flat(map_addr_flat),
        .map_read_data_flat(map_data_flat),
        .map_read_req      (map_req)
    );

    // =========================================================================
    // char_framebuffer (write from GPU collector, read for VGA)
    // =========================================================================
    // Unused read-port outputs (CPU reads go to the vfb stub, not here)
    /* verilator lint_off PINCONNECTEMPTY */
    char_framebuffer u_cfb (
        .clk       (sys_clk),
        .pix_clk   (pix_clk),
        .rst_n     (rst_n),
        // Write port: GPU collector
        .axi_awaddr (cfb_awaddr_w),
        .axi_awvalid(gcoll_awvalid),
        .axi_awready(gcoll_awready),
        .axi_wdata  (gcoll_wdata),
        .axi_wstrb  (gcoll_wstrb),
        .axi_wvalid (gcoll_wvalid),
        .axi_wready (gcoll_wready),
        .axi_bresp  (gcoll_bresp),
        .axi_bvalid (gcoll_bvalid),
        .axi_bready (gcoll_bready),
        // Read port: not connected (CPU reads go to vfb stub; VGA reads via vga_data)
        .axi_araddr (12'b0),
        .axi_arvalid(1'b0),
        .axi_arready(),
        .axi_rdata  (),
        .axi_rresp  (),
        .axi_rvalid (),
        .axi_rready (1'b0),
        // VGA read port (pixel clock domain — sys_clk used here; MMCM isolates domains)
        .vga_addr   (vga_fb_addr),
        .vga_data   (vga_fb_data)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // font_rom
    // =========================================================================
    font_rom u_font (
        .clk     (pix_clk),
        .addr    (font_addr),
        .data_out(font_data)
    );

    // =========================================================================
    // VGA top
    // =========================================================================
    vga_top u_vga (
        .pix_clk  (pix_clk),
        .rst_n    (rst_n),
        .fb_addr  (vga_fb_addr),
        .fb_data  (vga_fb_data),
        .font_addr(font_addr),
        .font_data(font_data),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b)
    );

endmodule
