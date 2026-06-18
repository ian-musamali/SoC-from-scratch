# Vivado implementation + bitstream script for ASCII Doom SoC — Nexys A7-100T
# Usage: vivado -mode batch -source synth/impl_nexys_a7.tcl
# Run from project root: /home/ian/SoC-from-scratch/ascii_doom_soc

set part xc7a100tcsg324-1
set top  fpga_top
set outdir synth/out

file mkdir $outdir

# -----------------------------------------------------------------------
# Read all RTL
# -----------------------------------------------------------------------
read_verilog -sv [glob rtl/lib/*.sv]
read_verilog -sv [glob rtl/bus/*.sv]
read_verilog -sv [glob rtl/vga/*.sv]
read_verilog -sv [glob rtl/gpu/*.sv]
read_verilog -sv [glob rtl/dma/*.sv]
# picorv32_axi.sv is a simulation stub — skip it; the real CPU comes from picorv32.v
read_verilog -sv rtl/core/uart_lite.sv
read_verilog    rtl/core/picorv32.v
read_verilog -sv rtl/soc_top.sv
read_verilog -sv rtl/fpga_top.sv

read_xdc constraints/nexys_a7.xdc

# -----------------------------------------------------------------------
# Synthesize
# -----------------------------------------------------------------------
synth_design -top $top -part $part -flatten_hierarchy rebuilt

# -----------------------------------------------------------------------
# Implement
# -----------------------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design

# -----------------------------------------------------------------------
# Reports
# -----------------------------------------------------------------------
report_utilization        -file $outdir/utilization_impl.rpt
report_timing_summary     -file $outdir/timing_summary_impl.rpt -max_paths 10 -warn_on_violation
report_clock_interaction  -file $outdir/clock_interaction_impl.rpt
report_power              -file $outdir/power_impl.rpt

# -----------------------------------------------------------------------
# Bitstream
# -----------------------------------------------------------------------
write_bitstream -force $outdir/ascii_doom_soc.bit

puts "\n=== Implementation complete. Bitstream: $outdir/ascii_doom_soc.bit ==="
