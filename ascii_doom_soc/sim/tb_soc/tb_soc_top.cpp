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

    // Drain extra cycles: the collector now drains NUM_ROWS (45) AXI writes
    // per column instead of one, and frame_done only guarantees the last
    // column was *accepted* (backpressure), not that its ~45-row write has
    // finished draining yet. Give it generous margin.
    for (int i = 0; i < 400; i++) sys_tick();

    // Read the full 80x45 char_framebuffer via Verilator internal signal access.
    // Layout is row*80+col (see vga_top.sv), rows 0..44.
    static const int NUM_ROWS = 45;
    static const int NUM_COLS = 80;
    uint8_t grid[NUM_ROWS][NUM_COLS];
    for (int r = 0; r < NUM_ROWS; r++)
        for (int c = 0; c < NUM_COLS; c++)
            grid[r][c] = (uint8_t)(dut->rootp->soc_top__DOT__u_cfb__DOT__mem[r * NUM_COLS + c] & 0xFF);

    // The wall-shading character choice (dist_to_ascii in dda_core.sv) is
    // completely unchanged by the wall-height feature — still bit-exact
    // matchable against the original golden reference. What's new is WHICH
    // rows it's drawn into; extract it by finding the (uniform) non-space
    // band in each column.
    const char* ref = "****++++++++++++++========----::::.................::::::---------============++";
    char rtl_char[NUM_COLS + 1];
    int  wall_top[NUM_COLS], wall_height[NUM_COLS];
    for (int c = 0; c < NUM_COLS; c++) {
        int first = -1, count = 0;
        char ch = ' ';
        for (int r = 0; r < NUM_ROWS; r++) {
            if (grid[r][c] != 0x20) {
                if (first < 0) { first = r; ch = (char)grid[r][c]; }
                count++;
            }
        }
        rtl_char[c]    = ch;
        wall_top[c]    = first < 0 ? 0 : first;
        wall_height[c] = count;
    }
    rtl_char[NUM_COLS] = '\0';

    printf("REF: %s\n", ref);
    printf("RTL: %s\n", rtl_char);

    int char_match_cnt = 0;
    for (int c = 0; c < NUM_COLS; c++) {
        if (rtl_char[c] != ref[c])
            printf("CHAR MISMATCH col %2d: RTL='%c'(0x%02x) REF='%c'\n",
                   c, rtl_char[c], (unsigned char)rtl_char[c], ref[c]);
        else
            char_match_cnt++;
    }
    bool chars_ok = (char_match_cnt == NUM_COLS);
    printf(chars_ok ? "PASS: %d/80 wall characters match Python reference\n"
                     : "FAIL: %d/80 wall characters match Python reference\n",
           char_match_cnt);

    // Wall-height sanity: h = NUM_ROWS / perp_dist (rows), clamped to
    // [1, NUM_ROWS]. Bucket ranges below are floor(45/d) over each
    // dist_to_ascii threshold band, widened by a few rows to absorb the
    // Q16.16/LUT quantization noise inherent in perp_corrected (the same
    // noise the existing fisheye_table ceil/floor tweaks work around for
    // the character brackets) — this checks the divide+clamp is in the
    // right ballpark per column, not a bit-exact height match.
    struct Range { char ch; int lo, hi; };
    static const Range kRanges[] = {
        {'#', 40, 45}, {'%', 27, 45}, {'*', 15, 32},
        {'+', 9, 20},  {'=', 5, 13},  {'-', 3, 9},
        {':', 1, 7},   {'.', 1, 5},
    };
    int height_ok_cnt = 0;
    for (int c = 0; c < NUM_COLS; c++) {
        int lo = 1, hi = 45;
        for (const auto& rg : kRanges) {
            if (ref[c] == rg.ch) { lo = rg.lo; hi = rg.hi; break; }
        }
        bool ok = (wall_height[c] >= lo && wall_height[c] <= hi);
        if (ok) height_ok_cnt++;
        else printf("HEIGHT OUT OF RANGE col %2d: char='%c' height=%d top=%d expected [%d,%d]\n",
                     c, rtl_char[c], wall_height[c], wall_top[c], lo, hi);
    }
    bool heights_ok = (height_ok_cnt == NUM_COLS);
    printf(heights_ok ? "PASS: %d/80 wall heights within expected range\n"
                       : "FAIL: %d/80 wall heights within expected range\n",
           height_ok_cnt);

    bool match = chars_ok && heights_ok;
    printf("\nsoc_top: %d PASS, %d FAIL\n", match ? 1 : 0, match ? 0 : 1);
    delete dut;
    return match ? 0 : 1;
}
