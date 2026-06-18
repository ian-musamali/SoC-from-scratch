// Verilator C++ testbench for axi4lite_fabric.sv
// Tests 7 scenarios listed in the task brief.

#include "Vaxi4lite_fabric.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>

// -----------------------------------------------------------------------
// helpers
// -----------------------------------------------------------------------
static int pass_count = 0;
static int fail_count = 0;

static void check(const char* test_name, bool cond)
{
    if (cond) {
        printf("  PASS: %s\n", test_name);
        ++pass_count;
    } else {
        printf("  FAIL: %s\n", test_name);
        ++fail_count;
    }
}

// -----------------------------------------------------------------------
// DUT wrapper — all signals accessed through dut.*
// -----------------------------------------------------------------------
struct Dut {
    Vaxi4lite_fabric dut;

    // Posedge clock
    void tick()
    {
        dut.clk = 0; dut.eval();
        dut.clk = 1; dut.eval();
    }

    // ---------- slave stubs: always ready, drive responses ----------
    void tie_slaves_ready()
    {
        dut.s0_awready = 1; dut.s1_awready = 1;
        dut.s2_awready = 1; dut.s3_awready = 1;
        dut.s0_wready  = 1; dut.s1_wready  = 1;
        dut.s2_wready  = 1; dut.s3_wready  = 1;
        dut.s0_bresp = 0; dut.s0_bvalid = 1;
        dut.s1_bresp = 0; dut.s1_bvalid = 1;
        dut.s2_bresp = 0; dut.s2_bvalid = 1;
        dut.s3_bresp = 0; dut.s3_bvalid = 1;
        dut.s0_arready = 1; dut.s1_arready = 1;
        dut.s2_arready = 1; dut.s3_arready = 1;
        dut.s0_rdata = 0xDEADBEEF; dut.s0_rresp = 0; dut.s0_rvalid = 1;
        dut.s1_rdata = 0xDEADBEEF; dut.s1_rresp = 0; dut.s1_rvalid = 1;
        dut.s2_rdata = 0xDEADBEEF; dut.s2_rresp = 0; dut.s2_rvalid = 1;
        dut.s3_rdata = 0xDEADBEEF; dut.s3_rresp = 0; dut.s3_rvalid = 1;
    }

    void clear_masters()
    {
        dut.m0_awaddr  = 0; dut.m0_awvalid = 0;
        dut.m0_wdata   = 0; dut.m0_wstrb   = 0; dut.m0_wvalid  = 0;
        dut.m0_bready  = 1;
        dut.m0_araddr  = 0; dut.m0_arvalid = 0;
        dut.m0_rready  = 1;

        dut.m1_awaddr  = 0; dut.m1_awvalid = 0;
        dut.m1_wdata   = 0; dut.m1_wstrb   = 0; dut.m1_wvalid  = 0;
        dut.m1_bready  = 1;
        dut.m1_araddr  = 0; dut.m1_arvalid = 0;
        dut.m1_rready  = 1;
    }

    void reset()
    {
        dut.clk   = 0;
        dut.rst_n = 0;
        clear_masters();
        tie_slaves_ready();
        dut.eval();
        tick(); tick();
        dut.rst_n = 1;
        dut.eval();
    }

    // Wait until fabric write channels are idle (both master bvalid low), timeout cycles
    void drain_write(int timeout = 20)
    {
        for (int i = 0; i < timeout; ++i) {
            if (!dut.m0_bvalid && !dut.m1_bvalid) break;
            tick();
        }
        tick(); // extra settle
    }

    void drain_read(int timeout = 20)
    {
        for (int i = 0; i < timeout; ++i) {
            if (!dut.m0_rvalid && !dut.m1_rvalid) break;
            tick();
        }
        tick();
    }
};

// -----------------------------------------------------------------------
// Convenience: sample slave awvalid outputs
// -----------------------------------------------------------------------
struct SlaveAW { uint8_t s0, s1, s2, s3; };
struct SlaveAR { uint8_t s0, s1, s2, s3; };

// Drive m0 write, tick so FSM latches grant, then read slave awvalid outputs.
SlaveAW m0_write_sample(Dut& d, uint32_t addr, uint32_t data)
{
    d.clear_masters();
    d.dut.m0_awaddr  = addr;
    d.dut.m0_awvalid = 1;
    d.dut.m0_wdata   = data;
    d.dut.m0_wstrb   = 0xF;
    d.dut.m0_wvalid  = 1;
    d.dut.m0_bready  = 1;
    d.dut.eval();
    d.tick();       // FSM transitions to W_M0
    d.dut.eval();   // combinational outputs settle
    SlaveAW r;
    r.s0 = d.dut.s0_awvalid;
    r.s1 = d.dut.s1_awvalid;
    r.s2 = d.dut.s2_awvalid;
    r.s3 = d.dut.s3_awvalid;
    d.drain_write();
    d.clear_masters();
    return r;
}

SlaveAW m1_write_sample(Dut& d, uint32_t addr, uint32_t data)
{
    d.clear_masters();
    d.dut.m1_awaddr  = addr;
    d.dut.m1_awvalid = 1;
    d.dut.m1_wdata   = data;
    d.dut.m1_wstrb   = 0xF;
    d.dut.m1_wvalid  = 1;
    d.dut.m1_bready  = 1;
    d.dut.eval();
    d.tick();
    d.dut.eval();
    SlaveAW r;
    r.s0 = d.dut.s0_awvalid;
    r.s1 = d.dut.s1_awvalid;
    r.s2 = d.dut.s2_awvalid;
    r.s3 = d.dut.s3_awvalid;
    d.drain_write();
    d.clear_masters();
    return r;
}

// -----------------------------------------------------------------------
// Test 1: M0 write to S0 (0x00001000) — addr[31:28]=0 → slave 0
// -----------------------------------------------------------------------
void test1_m0_to_s0(Dut& d)
{
    printf("\n[Test 1] M0 write to S0 (addr=0x00001000)\n");
    SlaveAW r = m0_write_sample(d, 0x00001000, 0xAABBCCDD);
    check("S0 awvalid=1", r.s0 == 1);
    check("S1 awvalid=0", r.s1 == 0);
    check("S2 awvalid=0", r.s2 == 0);
    check("S3 awvalid=0", r.s3 == 0);
}

// -----------------------------------------------------------------------
// Test 2: M0 write to S1 (0x10000000) — addr[31:28]=1 → slave 1
// -----------------------------------------------------------------------
void test2_m0_to_s1(Dut& d)
{
    printf("\n[Test 2] M0 write to S1 (addr=0x10000000)\n");
    SlaveAW r = m0_write_sample(d, 0x10000000, 0x12345678);
    check("S0 awvalid=0", r.s0 == 0);
    check("S1 awvalid=1", r.s1 == 1);
    check("S2 awvalid=0", r.s2 == 0);
    check("S3 awvalid=0", r.s3 == 0);
}

// -----------------------------------------------------------------------
// Test 3: M0 write to S2 (0x20000000) — addr[31:28]=2 → slave 2
// -----------------------------------------------------------------------
void test3_m0_to_s2(Dut& d)
{
    printf("\n[Test 3] M0 write to S2 (addr=0x20000000)\n");
    SlaveAW r = m0_write_sample(d, 0x20000000, 0xCAFEBABE);
    check("S0 awvalid=0", r.s0 == 0);
    check("S1 awvalid=0", r.s1 == 0);
    check("S2 awvalid=1", r.s2 == 1);
    check("S3 awvalid=0", r.s3 == 0);
}

// -----------------------------------------------------------------------
// Test 4: M0 write to S3 (0x30000000) — addr[31:28]=3 → slave 3
// -----------------------------------------------------------------------
void test4_m0_to_s3(Dut& d)
{
    printf("\n[Test 4] M0 write to S3 (addr=0x30000000)\n");
    SlaveAW r = m0_write_sample(d, 0x30000000, 0xDEAD0001);
    check("S0 awvalid=0", r.s0 == 0);
    check("S1 awvalid=0", r.s1 == 0);
    check("S2 awvalid=0", r.s2 == 0);
    check("S3 awvalid=1", r.s3 == 1);
}

// -----------------------------------------------------------------------
// Test 5: M1 write to S0 (0x00002000)
// -----------------------------------------------------------------------
void test5_m1_to_s0(Dut& d)
{
    printf("\n[Test 5] M1 write to S0 (addr=0x00002000)\n");
    SlaveAW r = m1_write_sample(d, 0x00002000, 0x11223344);
    check("S0 awvalid=1", r.s0 == 1);
    check("S1 awvalid=0", r.s1 == 0);
    check("S2 awvalid=0", r.s2 == 0);
    check("S3 awvalid=0", r.s3 == 0);
}

// -----------------------------------------------------------------------
// Test 6: M0+M1 simultaneous write — M1 wins (DMA priority on tie)
//
// After reset: w_last_grant=0.
// Arbitration condition for M1:
//   m1_awvalid && (!m0_awvalid || w_last_grant == 0) → TRUE when both valid
// So M1 is granted on the first cycle both assert awvalid.
// M0 -> S0 (0x00001000), M1 -> S1 (0x10000000)
// Expected after tick: FSM in W_M1, w_slave=1 → s1_awvalid=1, m1_awready=1
// -----------------------------------------------------------------------
void test6_simultaneous_m1_wins(Dut& d)
{
    printf("\n[Test 6] M0+M1 simultaneous write — M1 wins\n");

    d.clear_masters();
    d.dut.m0_awaddr  = 0x00001000; d.dut.m0_awvalid = 1;
    d.dut.m0_wdata   = 0xAA; d.dut.m0_wstrb = 0xF; d.dut.m0_wvalid = 1;
    d.dut.m0_bready  = 1;
    d.dut.m1_awaddr  = 0x10000000; d.dut.m1_awvalid = 1;
    d.dut.m1_wdata   = 0xBB; d.dut.m1_wstrb = 0xF; d.dut.m1_wvalid = 1;
    d.dut.m1_bready  = 1;
    d.dut.eval();
    d.tick();   // FSM latches: should pick M1
    d.dut.eval();

    uint8_t m1_ready = d.dut.m1_awready;
    uint8_t m0_ready = d.dut.m0_awready;
    uint8_t s0_aw    = d.dut.s0_awvalid;
    uint8_t s1_aw    = d.dut.s1_awvalid;
    uint8_t s2_aw    = d.dut.s2_awvalid;
    uint8_t s3_aw    = d.dut.s3_awvalid;

    check("M1 gets awready (granted)", m1_ready == 1);
    check("M0 does NOT get awready (stalled)", m0_ready == 0);
    check("S1 awvalid=1 (M1->S1)", s1_aw == 1);
    check("S0 awvalid=0 (M0 blocked)", s0_aw == 0);
    check("S2 awvalid=0", s2_aw == 0);
    check("S3 awvalid=0", s3_aw == 0);

    // Finish M1 transaction, then let M0 proceed
    d.dut.m1_awvalid = 0; d.dut.m1_wvalid = 0;
    d.drain_write();
    d.drain_write(); // M0 gets its turn
    d.clear_masters();
}

// -----------------------------------------------------------------------
// Test 7: M0 read from S0 (0x00001000)
// -----------------------------------------------------------------------
void test7_m0_read_s0(Dut& d)
{
    printf("\n[Test 7] M0 read from S0 (addr=0x00001000)\n");

    d.clear_masters();
    d.dut.m0_araddr  = 0x00001000;
    d.dut.m0_arvalid = 1;
    d.dut.m0_rready  = 1;
    d.dut.eval();
    d.tick();   // FSM transitions to R_M0, r_slave=0
    d.dut.eval();

    uint8_t  s0_ar     = d.dut.s0_arvalid;
    uint8_t  s1_ar     = d.dut.s1_arvalid;
    uint8_t  s2_ar     = d.dut.s2_arvalid;
    uint8_t  s3_ar     = d.dut.s3_arvalid;
    uint8_t  ar_ready  = d.dut.m0_arready;
    uint8_t  rvalid    = d.dut.m0_rvalid;
    uint32_t rdata     = d.dut.m0_rdata;

    check("S0 arvalid=1", s0_ar == 1);
    check("S1 arvalid=0", s1_ar == 0);
    check("S2 arvalid=0", s2_ar == 0);
    check("S3 arvalid=0", s3_ar == 0);
    check("m0_arready=1 (S0 arready passed through)", ar_ready == 1);
    check("m0_rvalid=1 (S0 rvalid passed through)", rvalid == 1);
    check("m0_rdata=0xDEADBEEF", rdata == 0xDEADBEEFU);

    d.drain_read();
    d.clear_masters();
}

// -----------------------------------------------------------------------
// main
// -----------------------------------------------------------------------
int main(int argc, char** argv)
{
    VerilatedContext ctx;
    ctx.commandArgs(argc, argv);

    printf("=== AXI4-Lite Fabric Testbench ===\n");

    Dut d;
    d.reset();

    test1_m0_to_s0(d);
    d.reset();

    test2_m0_to_s1(d);
    d.reset();

    test3_m0_to_s2(d);
    d.reset();

    test4_m0_to_s3(d);
    d.reset();

    test5_m1_to_s0(d);
    d.reset();

    test6_simultaneous_m1_wins(d);
    d.reset();

    test7_m0_read_s0(d);

    printf("\n=== Results: %d passed, %d failed ===\n", pass_count, fail_count);

    d.dut.final();
    return (fail_count == 0) ? 0 : 1;
}
