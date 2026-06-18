#include "Vvga_sync.h"
#include "verilated.h"
#include <cstdio>

static void tick(Vvga_sync* dut) {
    dut->pix_clk = 0; dut->eval();
    dut->pix_clk = 1; dut->eval();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vvga_sync* dut = new Vvga_sync;

    dut->rst_n = 0;
    for (int i = 0; i < 3; i++) tick(dut);
    dut->rst_n = 1;

    // Run 2 full frames (800*525*2 = 840000 ticks)
    int hsync_pulses = 0, vsync_pulses = 0;
    int hsync_prev = 1, vsync_prev = 1;
    int hsync_width_ticks = 0, vsync_width_lines = 0;
    int measuring_h = 0, h_width = 0;
    int measuring_v = 0, v_width = 0;
    int line_count = 0;

    for (int frame = 0; frame < 2; frame++) {
        for (int line = 0; line < 525; line++) {
            for (int px = 0; px < 800; px++) {
                tick(dut);
                if (!dut->hsync && hsync_prev) { measuring_h = 1; h_width = 0; }
                if (dut->hsync && !hsync_prev && measuring_h) {
                    hsync_width_ticks = h_width;
                    hsync_pulses++;
                    measuring_h = 0;
                }
                if (measuring_h) h_width++;
                hsync_prev = dut->hsync;
            }
            if (!dut->vsync && vsync_prev) { measuring_v = 1; v_width = 0; }
            if (dut->vsync && !vsync_prev && measuring_v) {
                vsync_width_lines = v_width;
                vsync_pulses++;
                measuring_v = 0;
            }
            if (measuring_v) v_width++;
            vsync_prev = dut->vsync;
        }
    }

    int pass = 0, fail = 0;

    // hsync: 96 ticks wide (active low pulse)
    if (hsync_width_ticks == 96) { printf("PASS: hsync pulse = %d ticks (expected 96)\n", hsync_width_ticks); pass++; }
    else { printf("FAIL: hsync pulse = %d ticks (expected 96)\n", hsync_width_ticks); fail++; }

    // vsync: 2 lines wide
    if (vsync_width_lines == 2) { printf("PASS: vsync pulse = %d lines (expected 2)\n", vsync_width_lines); pass++; }
    else { printf("FAIL: vsync pulse = %d lines (expected 2)\n", vsync_width_lines); fail++; }

    // 525 hsync per vsync: check 1050 total hsync pulses in 2 frames
    if (hsync_pulses == 1050) { printf("PASS: hsync pulses per 2 frames = %d (expected 1050)\n", hsync_pulses); pass++; }
    else { printf("FAIL: hsync pulses per 2 frames = %d (expected 1050)\n", hsync_pulses); fail++; }

    printf("\nvga_sync: %d PASS, %d FAIL\n", pass, fail);
    delete dut;
    return fail ? 1 : 0;
}
