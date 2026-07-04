// -----------------------------------------------------------------------------
// TinyNPU UVM package. Compiled after tinynpu_pkg / mac_array / mac_if and
// before tb_top (see sim/mac_tb.f). All class files are `include-d here in
// dependency order; +incdir+../uvm is on the VCS compile line.
// -----------------------------------------------------------------------------
package tinynpu_uvm_pkg;

  import uvm_pkg::*;
  import tinynpu_pkg::*;

  `include "uvm_macros.svh"

  // Agent layer
  `include "agents/mac_txn.sv"
  `include "agents/mac_sequencer.sv"
  `include "agents/mac_driver.sv"
  `include "agents/mac_monitor.sv"
  `include "agents/mac_agent.sv"

  // Environment layer
  `include "env/mac_scoreboard.sv"
  `include "env/mac_coverage.sv"
  `include "env/mac_env.sv"

  // Sequences
  `include "seq/mac_base_seq.sv"
  `include "seq/mac_file_seq.sv"
  `include "seq/mac_reset_seq.sv"

  // Tests
  `include "tests/mac_base_test.sv"
  `include "tests/mac_unit_smoke_test.sv"
  `include "tests/mac_unit_random_test.sv"
  `include "tests/mac_unit_overflow_test.sv"
  `include "tests/mac_unit_reset_test.sv"

endpackage : tinynpu_uvm_pkg
