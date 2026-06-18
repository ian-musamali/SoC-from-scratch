SIM        = verilator
TOPLEVEL_LANG = verilog
TOPLEVEL   = fpmul
MODULE     = test_fpmul
VERILOG_SOURCES = $(shell pwd)/../../../rtl/lib/fpmul.sv
EXTRA_ARGS = --language 1800-2012

include $(shell cocotb-config --makefiles)/Makefile.sim
