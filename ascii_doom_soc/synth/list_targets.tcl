open_hw_manager
connect_hw_server -quiet
set targets [get_hw_targets]
puts "Targets: $targets"
foreach t $targets {
    puts "  target: $t"
    open_hw_target $t
    puts "  devices: [get_hw_devices]"
    close_hw_target
}
