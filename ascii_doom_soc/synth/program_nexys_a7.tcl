# Program Nexys A7 via Vivado hw_server
# Usage: vivado -mode batch -source synth/program_nexys_a7.tcl
# Run from project root

set bit synth/out/ascii_doom_soc.bit

open_hw_manager
connect_hw_server -quiet
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
refresh_hw_device -update_hw_probes false [current_hw_device]
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_target
puts "\n=== Nexys A7 programmed: $bit ==="
