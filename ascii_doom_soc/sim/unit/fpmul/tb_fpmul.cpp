#include "Vfpmul.h"
#include "verilated.h"
#include <cstdint>
#include <cmath>
#include <cstdio>
#include <cassert>

// Convert float to Q16.16 (signed 32-bit)
static int32_t to_q1616(double f) {
    return (int32_t)(f * 65536.0 + (f >= 0 ? 0.5 : -0.5));
}

// Convert Q16.16 bits to float
static double from_q1616(uint32_t bits) {
    int32_t s = (int32_t)bits;
    return (double)s / 65536.0;
}

static vluint64_t sim_time = 0;

static void tick(Vfpmul* dut) {
    dut->clk = 0; dut->eval(); sim_time++;
    dut->clk = 1; dut->eval(); sim_time++;
}

static void reset(Vfpmul* dut) {
    dut->rst_n = 0;
    dut->valid_in = 0;
    dut->a = 0;
    dut->b = 0;
    for (int i = 0; i < 3; i++) tick(dut);
    dut->rst_n = 1;
    tick(dut);
}

// Returns result as float, asserts if valid_out never fires
static double multiply(Vfpmul* dut, double a_f, double b_f) {
    dut->a = (uint32_t)to_q1616(a_f);
    dut->b = (uint32_t)to_q1616(b_f);
    dut->valid_in = 1;
    tick(dut);               // posedge: product latched, valid_out <= valid_in
    dut->valid_in = 0;
    if (dut->valid_out) return from_q1616(dut->result); // 1-cycle latency
    for (int i = 0; i < 5; i++) {
        tick(dut);
        if (dut->valid_out) return from_q1616(dut->result);
    }
    printf("FAIL: valid_out never asserted for %.4f × %.4f\n", a_f, b_f);
    exit(1);
}

struct TestCase {
    double a, b, expected;
    const char* name;
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vfpmul* dut = new Vfpmul;

    reset(dut);

    TestCase cases[] = {
        {1.0,    1.0,   1.0,   "1.0 × 1.0"},
        {1.5,    2.0,   3.0,   "1.5 × 2.0"},
        {-1.0,   1.0,  -1.0,  "-1.0 × 1.0"},
        {0.0,    3.14,  0.0,   "0 × 3.14"},
        {100.0, 100.0, 10000.0,"100 × 100"},
        {0.5,    0.5,   0.25,  "0.5 × 0.5"},
    };

    double tol = 2.0 / 65536.0;  // 2 LSB tolerance
    int pass = 0, fail = 0;

    for (auto& tc : cases) {
        double res = multiply(dut, tc.a, tc.b);
        if (fabs(res - tc.expected) <= tol) {
            printf("PASS: %s = %.6f (expected %.6f)\n", tc.name, res, tc.expected);
            pass++;
        } else {
            printf("FAIL: %s = %.6f (expected %.6f, err=%.8f)\n",
                   tc.name, res, tc.expected, fabs(res - tc.expected));
            fail++;
        }
    }

    printf("\nfpmul: %d PASS, %d FAIL\n", pass, fail);
    delete dut;
    return fail ? 1 : 0;
}
