# Vivado synthesis script for ASCII Doom SoC — Nexys A7-100T
# Usage: vivado -mode batch -source synth/synth_nexys_a7.tcl
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
# Reports
# -----------------------------------------------------------------------
report_utilization -file $outdir/utilization.rpt
report_timing_summary -file $outdir/timing_summary.rpt -max_paths 10
report_clock_interaction -file $outdir/clock_interaction.rpt

puts "\n=== Synthesis complete. Reports in $outdir/ ==="
