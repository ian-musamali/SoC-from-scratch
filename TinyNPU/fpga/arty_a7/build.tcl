# -----------------------------------------------------------------------------
# Vivado non-project build for TinyNPU on the Arty A7-35T (Phase 7).
# Run from the repo's TinyNPU/ directory:
#   vivado -mode batch -source fpga/arty_a7/build.tcl
# Outputs land in fpga/arty_a7/build/.
# -----------------------------------------------------------------------------
set outdir fpga/arty_a7/build
file mkdir $outdir

# Memory init images must be regenerated first if the model changed:
#   cd model && python3 gen_fpga_mem.py --outdir ../fpga/mem
read_mem fpga/mem/img_rom.memh
read_mem fpga/mem/wgt_rom.memh

read_verilog -sv {
  rtl/tinynpu_pkg.sv
  rtl/mac_array.sv
  rtl/conv_engine.sv
  rtl/npu_core.sv
  rtl/byte_rom.sv
  rtl/fm_buffer.sv
  rtl/btn_debounce.sv
  rtl/display_stub.sv
  rtl/tinynpu_top.sv
  fpga/arty_a7/arty_a7_top.sv
}
set_property include_dirs fpga/mem [current_fileset]

read_xdc fpga/arty_a7/arty_a7.xdc

synth_design -top arty_a7_top -part xc7a35ticsg324-1L
report_utilization -file $outdir/utilization_synth.rpt

opt_design
place_design
route_design

report_utilization -file $outdir/utilization.rpt
report_timing_summary -file $outdir/timing.rpt

write_bitstream -force $outdir/tinynpu_arty_a7.bit
puts "TinyNPU bitstream: $outdir/tinynpu_arty_a7.bit"
