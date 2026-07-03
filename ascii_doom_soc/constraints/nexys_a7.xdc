## Nexys A7-100T constraints for ASCII Doom SoC
## Top module: fpga_top

## ============================================================
## System Clock (100 MHz onboard oscillator)
## ============================================================
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports { sys_clk_in }]
create_clock -name sys_clk_pin -period 10.000 [get_ports { sys_clk_in }]

## ============================================================
## Reset — CPU_RESET push-button, active-low
## ============================================================
set_property -dict { PACKAGE_PIN C12  IOSTANDARD LVCMOS33 } [get_ports { cpu_resetn }]

## ============================================================
## VGA connector
## ============================================================
set_property -dict { PACKAGE_PIN A3   IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }]
set_property -dict { PACKAGE_PIN B4   IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }]
set_property -dict { PACKAGE_PIN C5   IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }]
set_property -dict { PACKAGE_PIN A4   IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }]

set_property -dict { PACKAGE_PIN C6   IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }]
set_property -dict { PACKAGE_PIN A5   IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }]
set_property -dict { PACKAGE_PIN B6   IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }]
set_property -dict { PACKAGE_PIN A6   IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }]

set_property -dict { PACKAGE_PIN B7   IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }]
set_property -dict { PACKAGE_PIN C7   IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }]
set_property -dict { PACKAGE_PIN D7   IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }]
set_property -dict { PACKAGE_PIN D8   IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }]

set_property -dict { PACKAGE_PIN B11  IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }]
set_property -dict { PACKAGE_PIN B12  IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }]

## ============================================================
## UART (USB-UART bridge via FT2232)
## uart_txd_in  = FPGA receives (our uart_rx)
## uart_rxd_out = FPGA transmits (our uart_tx)
## ============================================================
set_property -dict { PACKAGE_PIN C4   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]
set_property -dict { PACKAGE_PIN D4   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]

## ============================================================
## Push-buttons (player input) — active-high
## Pin numbers from Digilent Nexys-A7-100T-Master.xdc
## ============================================================
set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33 } [get_ports { btnu }]
set_property -dict { PACKAGE_PIN P18  IOSTANDARD LVCMOS33 } [get_ports { btnd }]
set_property -dict { PACKAGE_PIN P17  IOSTANDARD LVCMOS33 } [get_ports { btnl }]
set_property -dict { PACKAGE_PIN M17  IOSTANDARD LVCMOS33 } [get_ports { btnr }]
set_property -dict { PACKAGE_PIN N17  IOSTANDARD LVCMOS33 } [get_ports { btnc }]

## ============================================================
## Bitstream / configuration
## ============================================================
set_property BITSTREAM.GENERAL.COMPRESS  TRUE  [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN  PULLDOWN [current_design]
