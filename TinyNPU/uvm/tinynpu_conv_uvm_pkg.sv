// -----------------------------------------------------------------------------
// TinyNPU conv_engine isolated UVM package. Imports tinynpu_uvm_pkg to reuse
// mac_txn (the 131-field golden trace parser). Compiled after tinynpu_pkg,
// conv_engine, mac_if, tinynpu_uvm_pkg, mem_if and the conv interfaces,
// before conv_tb_top (see sim/conv_tb.f). +incdir+../uvm on the compile line.
// -----------------------------------------------------------------------------
package tinynpu_conv_uvm_pkg;

  import uvm_pkg::*;
  import tinynpu_pkg::*;
  import tinynpu_uvm_pkg::*;   // mac_txn reuse

  `include "uvm_macros.svh"

  // Agent layer (conv_txn also provides read_manifest/parse_cfg)
  `include "conv/agents/conv_txn.sv"
  `include "conv/agents/conv_write_txn.sv"
  `include "conv/agents/conv_sequencer.sv"
  `include "conv/agents/conv_driver.sv"
  `include "conv/agents/conv_monitor.sv"
  `include "conv/agents/conv_agent.sv"

  // Environment layer
  `include "conv/env/conv_mac_responder.sv"
  `include "conv/env/conv_scoreboard.sv"
  `include "conv/env/conv_coverage.sv"
  `include "conv/env/conv_env.sv"

  // Sequences
  `include "conv/seq/conv_manifest_seq.sv"

  // Tests
  `include "conv/tests/conv_base_test.sv"
  `include "conv/tests/conv_unit_smoke_test.sv"
  `include "conv/tests/conv_unit_stride_pad_test.sv"
  `include "conv/tests/conv_unit_multichannel_test.sv"
  `include "conv/tests/conv_unit_random_test.sv"

endpackage : tinynpu_conv_uvm_pkg
