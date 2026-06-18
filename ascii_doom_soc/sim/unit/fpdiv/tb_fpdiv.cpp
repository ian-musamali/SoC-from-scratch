#include "Vfpdiv.h"
#include "verilated.h"
#include <cstdint>
#include <cmath>
#include <cstdio>

static int32_t to_q1616(double f) {
    return (int32_t)(f * 65536.0 + (f >= 0 ? 0.5 : -0.5));
}

static double from_q1616(uint32_t bits) {
    int32_t s = (int32_t)bits;
    return (double)s / 65536.0;
}

static void tick(Vfpdiv* dut) {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

static void reset(Vfpdiv* dut) {
    dut->rst_n = 0;
    dut->valid_in = 0;
    dut->numerator = 0;
    dut->denominator = 0;
    for (int i = 0; i < 3; i++) tick(dut);
    dut->rst_n = 1;
    tick(dut);
}

static double do_divide(Vfpdiv* dut, double num, double den, int* dbz_out) {
    dut->numerator   = (uint32_t)to_q1616(num);
    dut->denominator = (uint32_t)to_q1616(den);
    dut->valid_in    = 1;
    tick(dut);
    dut->valid_in    = 0;
    for (int i = 0; i < 80; i++) {
        tick(dut);
        if (dut->valid_out) {
            *dbz_out = dut->div_by_zero;
            return from_q1616(dut->result);
        }
        if (dut->div_by_zero) {
            *dbz_out = 1;
            return 0.0;
        }
    }
    printf("FAIL: valid_out never asserted for %.4f / %.4f\n", num, den);
    exit(1);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vfpdiv* dut = new Vfpdiv;

    reset(dut);

    double tol = 2.0 / 65536.0;
    int pass = 0, fail = 0;

    // Normal cases
    struct TC { double num, den, exp; const char* name; };
    TC cases[] = {
        {4.0,  2.0,  2.0,  "4/2"},
        {1.0,  4.0,  0.25, "1/4"},
        {-3.0, 1.0, -3.0, "-3/1"},
        {-6.0,-2.0,  3.0, "-6/-2"},
        {3.0,  4.0,  0.75, "3/4"},
    };

    for (auto& tc : cases) {
        int dbz = 0;
        double res = do_divide(dut, tc.num, tc.den, &dbz);
        if (!dbz && fabs(res - tc.exp) <= tol) {
            printf("PASS: %s = %.6f\n", tc.name, res);
            pass++;
        } else {
            printf("FAIL: %s = %.6f (expected %.6f, dbz=%d)\n", tc.name, res, tc.exp, dbz);
            fail++;
        }
    }

    // Divide-by-zero test
    {
        dut->numerator   = (uint32_t)to_q1616(1.0);
        dut->denominator = 0;
        dut->valid_in    = 1;
        tick(dut);              // posedge: div_by_zero and valid_out registered here
        dut->valid_in = 0;
        int fired = (dut->div_by_zero || dut->valid_out);
        for (int i = 0; i < 5 && !fired; i++) {
            tick(dut);
            fired = (dut->div_by_zero || dut->valid_out);
        }
        if (fired) {
            printf("PASS: div_by_zero flag asserted\n");
            pass++;
        } else {
            printf("FAIL: div_by_zero never asserted\n");
            fail++;
        }
    }

    printf("\nfpdiv: %d PASS, %d FAIL\n", pass, fail);
    delete dut;
    return fail ? 1 : 0;
}
