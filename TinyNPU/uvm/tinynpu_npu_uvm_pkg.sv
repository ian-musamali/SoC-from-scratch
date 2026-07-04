// -----------------------------------------------------------------------------
// TinyNPU full-system (npu_core) UVM package. Compiled after tinynpu_pkg,
// the RTL, mem_if.sv and npu_ctrl_if.sv, before npu_tb_top (see
// sim/npu_tb.f). +incdir+../uvm is on the compile line.
// -----------------------------------------------------------------------------
package tinynpu_npu_uvm_pkg;

  import uvm_pkg::*;
  import tinynpu_pkg::*;

  `include "uvm_macros.svh"

  // Agent layer (npu_txn also provides npu_parse_manifest)
  `include "npu/agents/npu_txn.sv"
  `include "npu/agents/npu_sequencer.sv"
  `include "npu/agents/npu_driver.sv"
  `include "npu/agents/npu_monitor.sv"
  `include "npu/agents/npu_agent.sv"

  // Environment layer
  `include "npu/env/npu_scoreboard.sv"
  `include "npu/env/npu_coverage.sv"
  `include "npu/env/npu_env.sv"

  // Sequences
  `include "npu/seq/npu_case_seq.sv"

  // Tests
  `include "npu/tests/npu_base_test.sv"
  `include "npu/tests/npu_smoke_test.sv"
  `include "npu/tests/npu_multilayer_test.sv"
  `include "npu/tests/npu_random_test.sv"

endpackage : tinynpu_npu_uvm_pkg
