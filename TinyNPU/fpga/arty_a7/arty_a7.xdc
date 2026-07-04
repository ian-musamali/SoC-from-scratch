# -----------------------------------------------------------------------------
# Digilent Arty A7-35T pin constraints for TinyNPU (Phase 7).
# Pin sites follow the Digilent Arty A7 master XDC; re-verify against your
# board revision's master file before building.
# -----------------------------------------------------------------------------

# 100 MHz system clock
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]

# Push buttons (BTN0 = reset, BTN1 = classify)
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN B8 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

# Green LEDs LD4..LD7 (one-hot class)
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# RGB LED LD0: green = busy, red = saturation
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports led0_g]
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports led0_r]

# Buttons are asynchronous by nature; they are synchronized/debounced inside.
set_false_path -from [get_ports {btn[*]}]
