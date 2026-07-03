#!/usr/bin/env bash
# Regenerates rtl/gpu/luts/*.hex — the sin/cos/fisheye/ddx/ddy tables dda_core.sv
# loads via $readmemh. These were originally computed directly in dda_core.sv's
# initial block via $sin/$cos/$atan2/$rtoi, but Yosys (OpenLane GDS flow) can't
# synthesize real-math system functions, so the values are frozen into hex files
# instead. Only re-run this if TOTAL_COLS (80) or the LUT formulas ever change —
# the checked-in hex files are otherwise the source of truth, not this script.
#
# Method: reproduce the exact original real-math generation in a throwaway
# Verilator sim, $writememh the results, done. This guarantees bit-identical
# values to what has already passed the project's simulation regression, rather
# than risking floating-point drift from a from-scratch reimplementation
# (e.g. in Python) using a different math library.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/gen_dda_luts.sv" << 'EOF'
`timescale 1ns/1ps
module gen_dda_luts;
    logic signed [31:0] sin_table    [0:255];
    logic signed [31:0] fov_table    [0:79];
    logic [31:0]        fisheye_table[0:79];
    logic signed [31:0] fov_sin_table[0:79];
    logic [31:0]        ddx_table    [0:79];
    logic [31:0]        ddy_table    [0:79];

    initial begin
        automatic real v;
        automatic real fov_ang;
        automatic real cos_fov;
        automatic real sin_fov;
        for (int k = 0; k < 256; k++) begin
            v = $sin(6.283185307 * k / 256.0);
            sin_table[k] = $rtoi(v * 65536.0);
        end
        for (int c = 0; c < 80; c++) begin
            fov_ang = $atan2(1.0*(c-40), 60.0);
            cos_fov = $cos(fov_ang);
            sin_fov = $sin(fov_ang);
            fov_table[c]     = $rtoi(fov_ang * 65536.0);
            if (c == 25)
                fisheye_table[c] = $rtoi(cos_fov * 65536.0);
            else begin
                v = cos_fov * 65536.0;
                fisheye_table[c] = (v > 0.0) ? $rtoi(v + 0.9999999) : $rtoi(v);
            end
            fov_sin_table[c] = $rtoi(sin_fov * 65536.0);
            if (cos_fov > -0.0001 && cos_fov < 0.0001)
                ddx_table[c] = 32'h7FFF_FFFF;
            else
                ddx_table[c] = $rtoi((1.0 / (cos_fov < 0.0 ? -cos_fov : cos_fov)) * 65536.0);
            if (sin_fov > -0.0001 && sin_fov < 0.0001)
                ddy_table[c] = 32'h7FFF_FFFF;
            else begin
                v = (1.0 / (sin_fov < 0.0 ? -sin_fov : sin_fov)) * 65536.0;
                ddy_table[c] = $rtoi(v + 0.5);
            end
        end
        $writememh("sin_table.hex", sin_table);
        $writememh("fov_table.hex", fov_table);
        $writememh("fisheye_table.hex", fisheye_table);
        $writememh("fov_sin_table.hex", fov_sin_table);
        $writememh("ddx_table.hex", ddx_table);
        $writememh("ddy_table.hex", ddy_table);
        $finish;
    end
endmodule
EOF

verilator --cc --Wno-fatal --top-module gen_dda_luts -Mdir "$WORK/obj_dir" "$WORK/gen_dda_luts.sv"
make -s -C "$WORK/obj_dir" -f Vgen_dda_luts.mk

cat > "$WORK/main.cpp" << 'EOF'
#include "Vgen_dda_luts.h"
#include "verilated.h"
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vgen_dda_luts top;
    while (!Verilated::gotFinish()) top.eval();
    return 0;
}
EOF
g++ -std=c++17 -O2 -I "$WORK/obj_dir" -I /usr/share/verilator/include -I /usr/share/verilator/include/vltstd \
    -c -o "$WORK/main.o" "$WORK/main.cpp"
g++ -std=c++17 -O2 -o "$WORK/gen_dda_luts" "$WORK/main.o" \
    "$WORK/obj_dir/verilated.o" "$WORK/obj_dir/verilated_threads.o" \
    "$WORK/obj_dir/Vgen_dda_luts__ALL.a" -lpthread

(cd "$WORK" && ./gen_dda_luts)

cp "$WORK"/{sin_table,fov_table,fisheye_table,fov_sin_table,ddx_table,ddy_table}.hex rtl/gpu/luts/
echo "Regenerated rtl/gpu/luts/*.hex"
