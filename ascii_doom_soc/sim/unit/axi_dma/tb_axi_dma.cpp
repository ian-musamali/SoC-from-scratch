// Testbench for axi_dma.sv
// Tests: 4-word transfer, zero-length transfer, single-word transfer.
#include "Vaxi_dma.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static Vaxi_dma* dut;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

// 4KB simulated memory (word-addressed, 1024 words)
static uint32_t mem[1024];

// Run one complete DMA transfer.
// AXI slave model: accepts beats one at a time; bvalid fires ONE cycle after W acceptance.
// Returns 1 if done asserts within timeout, 0 on timeout.
static int run_transfer(int timeout = 2000) {
    bool     ar_accepted = false;
    bool     r_sent      = false;
    bool     aw_accepted = false;
    bool     w_accepted  = false;
    bool     b_hold      = false;   // bvalid pending for next cycle
    uint32_t rd_addr     = 0;
    uint32_t wr_addr     = 0;

    for (int t = 0; t < timeout; t++) {

        // ---- AR channel ------------------------------------------------
        if (dut->m_ar_valid && !ar_accepted) {
            dut->m_ar_ready = 1;
            rd_addr         = dut->m_ar_addr >> 2;
            ar_accepted     = true;
        } else {
            dut->m_ar_ready = 0;
        }

        // ---- R channel: hold valid until DMA latches (m_r_ready drops) --
        if (ar_accepted && !r_sent) {
            dut->m_r_data  = (rd_addr < 1024) ? mem[rd_addr] : 0u;
            dut->m_r_valid = 1;
            dut->m_r_resp  = 0;
        } else {
            dut->m_r_valid = 0;
        }

        // ---- AW channel ------------------------------------------------
        if (dut->m_aw_valid && !aw_accepted) {
            dut->m_aw_ready = 1;
            wr_addr         = dut->m_aw_addr >> 2;
            aw_accepted     = true;
        } else {
            dut->m_aw_ready = 0;
        }

        // ---- W channel -------------------------------------------------
        bool w_fired = false;
        if (dut->m_w_valid && !w_accepted) {
            dut->m_w_ready = 1;
            if (wr_addr < 1024) mem[wr_addr] = dut->m_w_data;
            w_accepted     = true;
            w_fired        = true;
        } else {
            dut->m_w_ready = 0;
        }

        // ---- B channel: delayed one cycle after W acceptance -----------
        // The DMA transitions WR_DATA→WR_RESP in the SAME cycle W fires,
        // so bvalid must appear in the NEXT cycle (when DMA is in WR_RESP).
        bool b_this       = b_hold;
        dut->m_b_valid    = b_this ? 1 : 0;
        dut->m_b_resp     = 0;
        if (w_fired)       b_hold = true;
        else if (b_this)   b_hold = false;

        tick();

        // ---- Post-tick bookkeeping ------------------------------------
        // R: DMA deasserts m_r_ready after latching data
        if (ar_accepted && !r_sent && !dut->m_r_ready)
            r_sent = true;

        // B: handshake completes (m_b_ready always 1 in DMA) → reset beat
        if (b_this && dut->m_b_ready) {
            ar_accepted = false;
            r_sent      = false;
            aw_accepted = false;
            w_accepted  = false;
        }

        if (dut->done)
            return 1;
    }
    return 0;
}

static int pass_cnt = 0, fail_cnt = 0;

static void check(const char* name, int cond) {
    if (cond) { printf("PASS: %s\n", name); pass_cnt++; }
    else       { printf("FAIL: %s\n", name); fail_cnt++; }
}

static void reset_dut() {
    dut->rst_n      = 0;
    dut->start      = 0;
    dut->src_addr   = 0;
    dut->dst_addr   = 0;
    dut->byte_len   = 0;
    dut->m_ar_ready = 0;
    dut->m_r_data   = 0;
    dut->m_r_resp   = 0;
    dut->m_r_valid  = 0;
    dut->m_aw_ready = 0;
    dut->m_w_ready  = 0;
    dut->m_b_resp   = 0;
    dut->m_b_valid  = 0;
    for (int i = 0; i < 4; i++) tick();
    dut->rst_n = 1;
    tick();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vaxi_dma;

    // ----------------------------------------------------------------
    // Test 1: 4-word (16-byte) transfer
    // ----------------------------------------------------------------
    memset(mem, 0, sizeof(mem));
    mem[0] = 0xDEADBEEF;
    mem[1] = 0xCAFEBABE;
    mem[2] = 0x12345678;
    mem[3] = 0x9ABCDEF0;
    reset_dut();

    dut->src_addr = 0x0000;
    dut->dst_addr = 0x0010;   // offset 16 bytes = word 4
    dut->byte_len = 16;
    dut->start    = 1;
    tick();
    dut->start = 0;

    int ok1 = run_transfer();
    check("Test1: done fires",     ok1);
    check("Test1: word0 copied",   mem[4] == 0xDEADBEEF);
    check("Test1: word1 copied",   mem[5] == 0xCAFEBABE);
    check("Test1: word2 copied",   mem[6] == 0x12345678);
    check("Test1: word3 copied",   mem[7] == 0x9ABCDEF0);

    // ----------------------------------------------------------------
    // Test 2: zero-length (done fires immediately)
    // ----------------------------------------------------------------
    reset_dut();
    dut->src_addr = 0x0100;
    dut->dst_addr = 0x0200;
    dut->byte_len = 0;
    dut->start    = 1;
    tick();
    dut->start = 0;

    int ok2 = run_transfer(20);
    check("Test2: zero-length done fires", ok2);

    // ----------------------------------------------------------------
    // Test 3: single-word transfer
    // ----------------------------------------------------------------
    reset_dut();
    mem[16] = 0xABCD1234;
    dut->src_addr = 0x0040;   // word 16
    dut->dst_addr = 0x0080;   // word 32
    dut->byte_len = 4;
    dut->start    = 1;
    tick();
    dut->start = 0;

    int ok3 = run_transfer();
    check("Test3: single-word done fires", ok3);
    check("Test3: word copied",            mem[32] == 0xABCD1234);

    printf("\naxi_dma: %d PASS, %d FAIL\n", pass_cnt, fail_cnt);
    delete dut;
    return fail_cnt ? 1 : 0;
}
