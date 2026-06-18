// Full SoC integration testbench.
// Instantiates soc_top with SIMULATION=1 (CPU AXI bypass + map backdoor).
// 1. Loads map data via sim_map_* backdoor port.
// 2. Writes player state to GPU MMIO via CPU AXI bypass.
// 3. Triggers frame_start, polls frame_done.
// 4. Reads char_framebuffer contents via Verilator internal-signal access.
// 5. Verifies output against Python raycaster reference.
#include "Vsoc_top.h"
#include "Vsoc_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static Vsoc_top* dut;

static void sys_tick() {
    dut->sys_clk = 0; dut->eval();
    dut->sys_clk = 1; dut->eval();
}

// 64×64 map
static const char MAP_STR[64][65] = {
    "1111111111111111111111111111111111111111111111111111111111111111",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000011111111111111111111100001111111111111111111110000000000001",
    "1000010000000000000000000100001000000000000000000010000000000001",
    "1000010000000000000000000100001000000000000000000010000000000001",
    "1000010000000000000000000100001000000000000111110010000000000001",
    "1000010000000000000000000100001000000000000010100010000000000001",
    "1000010000000000000000000000000000000000000010100000000000000001",
    "1000010000000000000000000100001000000000000010100010000000000001",
    "1000010000000000000000000100001000000000000010100010000000000001",
    "1000010000000000000000000100001000000000000010100010000000000001",
    "1000010000000000000000000100001000000000000010100010000000000001",
    "1000011111111111111111111100001111111111111111111110000000000001",
    "1000000000000000000000000000000000000000000010100000000000000001",
    "1000000000000000000000000000000000000000000010100000000000000001",
    "1000000000000000000000000000000000000000111110111111111111111001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000100000000000000000001001",
    "1000000000000000000000000000000000000000111111111111111111111001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1000000000000000000000000000000000000000000000000000000000000001",
    "1111111111111111111111111111111111111111111111111111111111111111",
};

// -----------------------------------------------------------------------
// Write a 32-bit word through the CPU AXI bypass → fabric → slave.
//
// Timing: the fabric takes ONE clock to transition from W_IDLE → W_M0,
// then combinatorially forwards AW/W to the slave.  The slave sees
// valid+ready on the SECOND tick.  We must hold awvalid/wvalid HIGH
// until the slave produces bvalid — deasserting early (when awready
// first rises) skips the cycle where the slave actually latches the data.
// -----------------------------------------------------------------------
static void cpu_write(uint32_t addr, uint32_t data) {
    dut->sim_cpu_awaddr  = addr;
    dut->sim_cpu_awvalid = 1;
    dut->sim_cpu_wdata   = data;
    dut->sim_cpu_wstrb   = 0xF;
    dut->sim_cpu_wvalid  = 1;
    dut->sim_cpu_bready  = 1;

    for (int t = 0; t < 40; t++) {
        sys_tick();
        // Hold awvalid/wvalid until slave drives bvalid.
        // Only deassert after bvalid fires so the slave has a full clock
        // edge with valid=1 AND ready=1.
        if (dut->sim_cpu_bvalid) {
            dut->sim_cpu_awvalid = 0;
            dut->sim_cpu_wvalid  = 0;
            dut->sim_cpu_bready  = 0;
            sys_tick();
            return;
        }
    }
    fprintf(stderr, "TIMEOUT: cpu_write(0x%08x)\n", addr);
    dut->sim_cpu_awvalid = 0;
    dut->sim_cpu_wvalid  = 0;
    dut->sim_cpu_bready  = 0;
}

// Read a 32-bit word through the CPU AXI bypass → fabric → slave.
// Same principle: hold arvalid until rvalid fires.
static uint32_t cpu_read(uint32_t addr) {
    dut->sim_cpu_araddr  = addr;
    dut->sim_cpu_arvalid = 1;
    dut->sim_cpu_rready  = 1;

    for (int t = 0; t < 40; t++) {
        sys_tick();
        if (dut->sim_cpu_rvalid) {
            uint32_t d = dut->sim_cpu_rdata;
            dut->sim_cpu_arvalid = 0;
            dut->sim_cpu_rready  = 0;
            sys_tick();
            return d;
        }
    }
    fprintf(stderr, "TIMEOUT: cpu_read(0x%08x)\n", addr);
    dut->sim_cpu_arvalid = 0;
    dut->sim_cpu_rready  = 0;
    return 0xDEADBEEF;
}

// Load map data to all 4 core BRAMs via backdoor.
static void load_map() {
    for (int c = 0; c < 4; c++) {
        dut->sim_map_core = (uint8_t)c;
        for (int y = 0; y < 64; y++) {
            for (int x = 0; x < 64; x++) {
                dut->sim_map_addr  = (uint16_t)(y * 64 + x);
                dut->sim_map_wdata = (MAP_STR[y][x] == '1') ? 1u : 0u;
                dut->sim_map_wen   = 1;
                sys_tick();
            }
        }
    }
    dut->sim_map_wen = 0;
    sys_tick();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vsoc_top;

    // Reset
    dut->sys_clk = 0;
    dut->pix_clk = 0;
    dut->rst_n   = 0;
    dut->uart_rx = 1;
    dut->sim_cpu_awaddr  = 0; dut->sim_cpu_awvalid = 0;
    dut->sim_cpu_wdata   = 0; dut->sim_cpu_wstrb   = 0;
    dut->sim_cpu_wvalid  = 0; dut->sim_cpu_bready  = 0;
    dut->sim_cpu_araddr  = 0; dut->sim_cpu_arvalid = 0;
    dut->sim_cpu_rready  = 0;
    dut->sim_map_addr    = 0; dut->sim_map_wdata   = 0;
    dut->sim_map_wen     = 0; dut->sim_map_core    = 0;
    for (int i = 0; i < 8; i++) sys_tick();
    dut->rst_n = 1;
    for (int i = 0; i < 4; i++) sys_tick();

    printf("Loading map...\n");
    load_map();

    // Write player state and trigger frame
    const uint32_t PX   = (uint32_t)(int32_t)(2.5 * 65536.0);
    const uint32_t PY   = (uint32_t)(int32_t)(2.5 * 65536.0);
    const uint32_t PANG = 0;

    printf("Writing player state...\n");
    cpu_write(0x30000008, PX);
    cpu_write(0x3000000C, PY);
    cpu_write(0x30000010, PANG);

    printf("Triggering frame...\n");
    cpu_write(0x30000000, 1);  // GPU_CTRL.frame_start

    // Wait for frame_done via direct internal signal (avoids AXI polling overhead)
    int frame_cyc = 0;
    for (int t = 0; t < 200000; t++) {
        sys_tick();
        frame_cyc++;
        if (dut->rootp->soc_top__DOT__u_gpu__DOT__frame_done)
            break;
    }
    printf("Frame completed in %d cycles\n", frame_cyc);

    // Drain extra cycles for last collector AXI writes to complete
    for (int i = 0; i < 200; i++) sys_tick();

    // Read char_framebuffer via Verilator internal signal access
    const char* ref = "****++++++++++++++========----::::.................::::::---------============++";
    char rtl[81];
    for (int i = 0; i < 80; i++) {
        // Access: soc_top -> u_cfb -> mem[i]
        // Verilator public-flat-rw exposes as rootp->soc_top__DOT__u_cfb__DOT__mem
        rtl[i] = (char)(dut->rootp->soc_top__DOT__u_cfb__DOT__mem[i] & 0xFF);
    }
    rtl[80] = '\0';

    printf("REF: %s\n", ref);
    printf("RTL: %s\n", rtl);

    int match = (strcmp(rtl, ref) == 0);
    if (!match) {
        int cnt = 0;
        for (int i = 0; i < 80; i++) {
            if (rtl[i] != ref[i])
                printf("MISMATCH col %2d: RTL='%c'(0x%02x) REF='%c'\n",
                       i, rtl[i], (unsigned char)rtl[i], ref[i]);
            else cnt++;
        }
        printf("FAIL: %d/80 match\n", cnt);
    } else {
        printf("PASS: soc_top 80/80 columns match Python reference\n");
    }

    printf("\nsoc_top: %d PASS, %d FAIL\n", match, 1 - match);
    delete dut;
    return match ? 0 : 1;
}
