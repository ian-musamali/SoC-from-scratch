# Creates a Vivado GUI project for ASCII Doom SoC
# Usage (Vivado Tcl Console):
#   cd /home/ian/SoC-from-scratch/ascii_doom_soc
#   source synth/create_project.tcl

set root [pwd]
set proj_dir $root/vivado_proj

create_project ascii_doom_soc $proj_dir -part xc7a100tcsg324-1 -force

set_property target_language SystemVerilog [current_project]
set_property default_lib work [current_project]

# Add all RTL sources
add_files -norecurse [glob $root/rtl/lib/*.sv]
add_files -norecurse [glob $root/rtl/bus/*.sv]
add_files -norecurse [glob $root/rtl/vga/*.sv]
add_files -norecurse [glob $root/rtl/gpu/*.sv]
add_files -norecurse [glob $root/rtl/dma/*.sv]
add_files -norecurse [glob $root/rtl/core/*.sv]
add_files -norecurse $root/rtl/soc_top.sv
add_files -norecurse $root/rtl/fpga_top.sv

# Add constraints
add_files -fileset constrs_1 $root/constraints/nexys_a7.xdc

set_property top fpga_top [current_fileset]

update_compile_order -fileset sources_1

puts "\n=== Project created at $proj_dir ==="
puts "=== You can now run Synthesis and Implementation from the Flow Navigator ==="
