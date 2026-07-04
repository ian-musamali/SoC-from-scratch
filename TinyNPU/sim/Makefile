# -----------------------------------------------------------------------------
# TinyNPU regression — Synopsys VCS
#
#   make vectors            regenerate all golden vectors + FPGA demo memories
#   make compile_mac | compile_conv | compile_npu | compile_top
#   make <testname>         run one test (see suite lists below)
#   make regress_mac | regress_conv | regress_npu | regress_top
#   make regress            everything + pass/fail summary
#   make clean
# -----------------------------------------------------------------------------
SHELL := /bin/bash

VCS       := vcs
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM

VCS_COMMON := -full64 -sverilog -timescale=1ns/1ps \
              -debug_access+all \
              -licqueue

VCS_UVM := $(VCS_COMMON) -ntb_opts uvm-1.2 +incdir+../uvm

TESTS_MAC  := mac_unit_smoke_test mac_unit_random_test mac_unit_overflow_test mac_unit_reset_test
TESTS_CONV := conv_unit_smoke_test conv_unit_stride_pad_test conv_unit_multichannel_test conv_unit_random_test
TESTS_NPU  := npu_smoke_test npu_multilayer_test npu_random_test
TESTS_TOP  := top_smoke_test
TESTS      := $(TESTS_MAC) $(TESTS_CONV) $(TESTS_NPU) $(TESTS_TOP)

# Per-test plusargs
ARGS_mac_unit_smoke_test        := +VEC_FILE=../vectors/smoke.txt
ARGS_mac_unit_random_test       := +VEC_FILE=../vectors/random.txt
ARGS_mac_unit_overflow_test     := +VEC_FILE=../vectors/overflow.txt
ARGS_mac_unit_reset_test        := +VEC_FILE=../vectors/reset.txt
ARGS_conv_unit_smoke_test       := +CONV_DIR=../vectors/conv +CONV_MANIFEST=../vectors/conv/smoke_manifest.txt
ARGS_conv_unit_stride_pad_test  := +CONV_DIR=../vectors/conv +CONV_MANIFEST=../vectors/conv/stride_pad_manifest.txt
ARGS_conv_unit_multichannel_test:= +CONV_DIR=../vectors/conv +CONV_MANIFEST=../vectors/conv/multichannel_manifest.txt
ARGS_conv_unit_random_test      := +CONV_DIR=../vectors/conv +CONV_MANIFEST=../vectors/conv/random_manifest.txt
ARGS_npu_smoke_test             := +NPU_DIR=../vectors/npu +NPU_MANIFEST=../vectors/npu/smoke_manifest.txt
ARGS_npu_multilayer_test        := +NPU_DIR=../vectors/npu +NPU_MANIFEST=../vectors/npu/multilayer_manifest.txt
ARGS_npu_random_test            := +NPU_DIR=../vectors/npu +NPU_MANIFEST=../vectors/npu/random_manifest.txt
ARGS_top_smoke_test              = +EXP_CLASS=$(shell head -1 ../fpga/mem/expected.txt)

# UVM tests need +UVM_TESTNAME; the plain-SV top smoke does not
UVMARGS_mac  := +UVM_VERBOSITY=$(VERBOSITY) +ntb_random_seed=$(SEED)
UVM_TESTS    := $(TESTS_MAC) $(TESTS_CONV) $(TESTS_NPU)

# Test -> simv binary / compile target
$(foreach t,$(TESTS_MAC), $(eval SIMV_$(t) := ./simv_mac)  $(eval COMPILE_$(t) := compile_mac))
$(foreach t,$(TESTS_CONV),$(eval SIMV_$(t) := ./simv_conv) $(eval COMPILE_$(t) := compile_conv))
$(foreach t,$(TESTS_NPU), $(eval SIMV_$(t) := ./simv_npu)  $(eval COMPILE_$(t) := compile_npu))
$(foreach t,$(TESTS_TOP), $(eval SIMV_$(t) := ./simv_top)  $(eval COMPILE_$(t) := compile_top))

.PHONY: all vectors compile_mac compile_conv compile_npu compile_top \
        regress regress_mac regress_conv regress_npu regress_top \
        summary clean $(TESTS)

all: regress

vectors:
	python3 ../model/gen_vectors.py --outdir ../vectors --seed $(SEED)
	python3 ../model/gen_conv_vectors.py --outdir ../vectors --seed $(SEED)
	cd ../model && python3 gen_fpga_mem.py --outdir ../fpga/mem

logs:
	mkdir -p logs

compile_mac: | logs
	$(VCS) $(VCS_UVM) -f mac_tb.f  -o simv_mac  -l logs/compile_mac.log

compile_conv: | logs
	$(VCS) $(VCS_UVM) -f conv_tb.f -o simv_conv -l logs/compile_conv.log

compile_npu: | logs
	$(VCS) $(VCS_UVM) -f npu_tb.f  -o simv_npu  -l logs/compile_npu.log

compile_top: | logs
	$(VCS) $(VCS_COMMON) -f top_tb.f -o simv_top -l logs/compile_top.log

.SECONDEXPANSION:
$(UVM_TESTS): $$(COMPILE_$$@) vectors
	$(SIMV_$@) +UVM_TESTNAME=$@ $(ARGS_$@) $(UVMARGS_mac) -l logs/$@.log

$(TESTS_TOP): $$(COMPILE_$$@) vectors
	$(SIMV_$@) $(ARGS_$@) -l logs/$@.log

regress_mac: $(TESTS_MAC)
	@$(MAKE) --no-print-directory summary SUMMARY_TESTS="$(TESTS_MAC)"

regress_conv: $(TESTS_CONV)
	@$(MAKE) --no-print-directory summary SUMMARY_TESTS="$(TESTS_CONV)"

regress_npu: $(TESTS_NPU)
	@$(MAKE) --no-print-directory summary SUMMARY_TESTS="$(TESTS_NPU)"

regress_top: $(TESTS_TOP)
	@$(MAKE) --no-print-directory summary SUMMARY_TESTS="$(TESTS_TOP)"

regress: $(TESTS)
	@$(MAKE) --no-print-directory summary SUMMARY_TESTS="$(TESTS)"

SUMMARY_TESTS ?= $(TESTS)
summary:
	@echo "==================== TinyNPU REGRESSION SUMMARY ===================="
	@pass=0; fail=0; \
	for t in $(SUMMARY_TESTS); do \
	  if grep -q "TINYNPU TEST PASSED" logs/$$t.log 2>/dev/null; then \
	    echo "  PASS  $$t"; pass=$$((pass+1)); \
	  else \
	    echo "  FAIL  $$t"; fail=$$((fail+1)); \
	  fi; \
	done; \
	echo "---------------------------------------------------------------------"; \
	echo "  Total: $$((pass+fail))   Pass: $$pass   Fail: $$fail"; \
	echo "====================================================================="; \
	test $$fail -eq 0

clean:
	rm -rf simv_mac simv_conv simv_npu simv_top *.daidir csrc logs *.log \
	       ucli.key vc_hdrs.h DVEfiles verdiLog novas.* *.fsdb
