SIM        = verilator
TOPLEVEL_LANG = verilog
TOPLEVEL   = fpdiv
MODULE     = test_fpdiv
VERILOG_SOURCES = $(shell pwd)/../../../rtl/lib/fpdiv.sv
EXTRA_ARGS = --language 1800-2012

include $(shell cocotb-config --makefiles)/Makefile.sim
