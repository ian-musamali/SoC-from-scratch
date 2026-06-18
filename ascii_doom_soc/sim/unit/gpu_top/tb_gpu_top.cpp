// Integration testbench for gpu_top.
// Uses a simple always-ready AXI slave model for the collector's master port.
#include "Vgpu_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static const char MAP[64][65] = {
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
static uint8_t map_mem[64*64];
static uint8_t vga_fb[4096];

static Vgpu_top* dut;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

// -----------------------------------------------------------------------
// Minimal AXI4-Lite slave model for the collector's master port.
// Always-ready: awready=1, wready=1, bready=1.
// Sends bvalid one cycle after wready fires.
// -----------------------------------------------------------------------
// AXI4-Lite slave state
static uint32_t ax_latched_addr  = 0;
static bool     ax_aw_seen       = false;  // AW address latched
static bool     ax_bvalid_hold   = false;  // driving bvalid for one cycle
static int      writes_received  = 0;

// Call BEFORE each tick(). Drives m_awready, m_wready, m_bvalid based on DUT outputs.
// Two-phase:
//   1. Latch AW address when awvalid fires.
//   2. Capture data and schedule bvalid when wvalid && wready fires.
//   3. Hold bvalid for exactly one cycle after wvalid fires (so DUT sees it in W_RESP).
static void axi_master_slave_pre_tick() {
    dut->m_awready = 1;
    dut->m_wready  = 1;
    dut->m_bready  = 1;

    // Latch AW address
    if (dut->m_awvalid) {
        ax_latched_addr = dut->m_awaddr;
        ax_aw_seen      = true;
    }

    // After wvalid fires AND bvalid was held last cycle → clear bvalid
    // Drive bvalid from the PREVIOUS cycle's "schedule" (ax_bvalid_hold set by LAST call)
    dut->m_bvalid = ax_bvalid_hold ? 1 : 0;
    dut->m_bresp  = 0;
    ax_bvalid_hold = false;  // will be re-set below if wvalid fires this cycle

    // Accept write data
    if (dut->m_wvalid) {
        if (ax_aw_seen) {
            uint32_t offset = ax_latched_addr - 0x20000000u;
            if (offset < sizeof(vga_fb)) {
                vga_fb[offset] = (uint8_t)(dut->m_wdata & 0xFF);
                writes_received++;
            }
            ax_aw_seen = false;
        }
        // Schedule bvalid for NEXT cycle (so DUT is in W_RESP when it sees it)
        ax_bvalid_hold = true;
    }
}

// -----------------------------------------------------------------------
// AXI4-Lite write to GPU MMIO slave (s_* ports)
// -----------------------------------------------------------------------
static void mmio_write(uint32_t addr, uint32_t data) {
    // Keep both AW and W valid; MMIO accepts them together.
    // Keep bready=1 so the bvalid handshake clears immediately.
    dut->s_awaddr  = addr;
    dut->s_awvalid = 1;
    dut->s_wdata   = data;
    dut->s_wstrb   = 0xF;
    dut->s_wvalid  = 1;
    dut->s_bready  = 1;

    for (int t = 0; t < 10; t++) {
        for (int c = 0; c < 4; c++) {
            uint32_t ma = dut->map_read_addr[c];
            dut->map_read_data[c] = (dut->map_read_req[c] && ma < 64*64u) ? map_mem[ma] : 0u;
        }
        axi_master_slave_pre_tick();
        tick();
        // AW+W accepted in same cycle → awready/wready drop next cycle → bvalid asserts
        // Stay in loop until both s_awvalid and s_wvalid have been accepted
        if (dut->s_awready && dut->s_awvalid) { dut->s_awvalid = 0; dut->s_wvalid = 0; }
        if (!dut->s_bvalid && !dut->s_awvalid) break;  // transaction complete
    }
    dut->s_bready  = 0;
    dut->s_awvalid = 0;
    dut->s_wvalid  = 0;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 64; x++)
            map_mem[y*64+x] = (MAP[y][x] == '1') ? 1 : 0;
    memset(vga_fb, 0x20, sizeof(vga_fb));

    dut = new Vgpu_top;

    // Reset
    dut->rst_n = 0;
    dut->clk   = 0;
    dut->s_awvalid = 0; dut->s_wvalid = 0; dut->s_arvalid = 0;
    dut->s_bready  = 0; dut->s_rready = 1;
    dut->m_awready = 0; dut->m_wready = 0;
    dut->m_bvalid  = 0; dut->m_bresp  = 0; dut->m_bready = 0;
    for (int c = 0; c < 4; c++) dut->map_read_data[c] = 0;
    for (int i = 0; i < 5; i++) { axi_master_slave_pre_tick(); tick(); }
    dut->rst_n = 1;
    for (int i = 0; i < 3; i++) { axi_master_slave_pre_tick(); tick(); }

    // Write player state and trigger frame
    mmio_write(0x30000008, (uint32_t)(int32_t)(2.5 * 65536.0)); // PLAYER_X
    mmio_write(0x3000000C, (uint32_t)(int32_t)(2.5 * 65536.0)); // PLAYER_Y
    mmio_write(0x30000010, 0);                                    // PLAYER_ANG = 0
    mmio_write(0x30000000, 1);                                    // GPU_CTRL.frame_start

    // Run until 80 writes received or timeout
    for (int cyc = 0; cyc < 30000 && writes_received < 80; cyc++) {
        // Feed map data for each core independently
        for (int c = 0; c < 4; c++) {
            uint32_t maddr = dut->map_read_addr[c];
            dut->map_read_data[c] = (dut->map_read_req[c] && maddr < 64*64u)
                                    ? map_mem[maddr] : 0u;
        }
        axi_master_slave_pre_tick();
        tick();
    }

    // Drain any remaining
    for (int i = 0; i < 20; i++) {
        for (int c = 0; c < 4; c++) {
            uint32_t ma = dut->map_read_addr[c];
            dut->map_read_data[c] = (dut->map_read_req[c] && ma < 64*64u) ? map_mem[ma] : 0u;
        }
        axi_master_slave_pre_tick();
        tick();
    }

    const char* ref = "****++++++++++++++========----::::.................::::::---------============++";
    char rtl[81];
    for (int i = 0; i < 80; i++) rtl[i] = (char)vga_fb[i];
    rtl[80] = '\0';

    printf("REF: %s\n", ref);
    printf("RTL: %s\n", rtl);
    printf("Writes received: %d/80\n", writes_received);

    int match = (strcmp(rtl, ref) == 0);
    if (!match) {
        for (int i = 0; i < 80; i++)
            if (rtl[i] != ref[i])
                printf("MISMATCH col %d: RTL='%c' REF='%c'\n", i, rtl[i], ref[i]);
        int cnt = 0;
        for (int i = 0; i < 80; i++) if (rtl[i] == ref[i]) cnt++;
        printf("FAIL: %d/80 match\n", cnt);
    } else {
        printf("PASS: gpu_top 80/80 columns match Python reference\n");
    }
    printf("\ngpu_top: %d PASS, %d FAIL\n", match, 1-match);

    delete dut;
    return match ? 0 : 1;
}
