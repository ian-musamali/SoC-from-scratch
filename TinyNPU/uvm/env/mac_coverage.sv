// -----------------------------------------------------------------------------
// Functional coverage per docs/verification_plan.md:
//  - per-input lane-value classes (min/max/zero/pos/neg present across the 64
//    lanes, act and wgt separately) and acc_in rail/range bins;
//  - per-output sat_flag, crossed with the sign of the paired acc_in (tracked
//    with a small pending-sign queue mirroring the scoreboard pairing rule);
//  - reset-during-active (reset notification while work was pending);
//  - handshake stall/backpressure, sampled from the virtual interface in a
//    clocked process.
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_cov_in)
`uvm_analysis_imp_decl(_cov_out)
`uvm_analysis_imp_decl(_cov_rst)

class mac_coverage extends uvm_component;

  `uvm_component_utils(mac_coverage)

  uvm_analysis_imp_cov_in  #(mac_txn, mac_coverage) imp_in;
  uvm_analysis_imp_cov_out #(mac_txn, mac_coverage) imp_out;
  uvm_analysis_imp_cov_rst #(bit,     mac_coverage) imp_rst;

  virtual mac_if vif;

  // Sampling state for cg_input
  bit act_has_min, act_has_max, act_has_zero, act_has_pos, act_has_neg;
  bit wgt_has_min, wgt_has_max, wgt_has_zero, wgt_has_pos, wgt_has_neg;
  int cov_acc_in;

  // Sampling state for cg_output (acc_in sign paired with its output)
  bit cov_sat;
  bit cov_acc_in_neg;
  bit pend_sign_q [$];

  // Sampling state for cg_reset / cg_handshake
  bit cov_reset_active;
  bit cov_in_stall;
  bit cov_out_bp;

  covergroup cg_input;
    option.per_instance = 1;
    cp_act_has_min:  coverpoint act_has_min  { bins present = {1}; }
    cp_act_has_max:  coverpoint act_has_max  { bins present = {1}; }
    cp_act_has_zero: coverpoint act_has_zero { bins present = {1}; }
    cp_act_has_pos:  coverpoint act_has_pos  { bins present = {1}; }
    cp_act_has_neg:  coverpoint act_has_neg  { bins present = {1}; }
    cp_wgt_has_min:  coverpoint wgt_has_min  { bins present = {1}; }
    cp_wgt_has_max:  coverpoint wgt_has_max  { bins present = {1}; }
    cp_wgt_has_zero: coverpoint wgt_has_zero { bins present = {1}; }
    cp_wgt_has_pos:  coverpoint wgt_has_pos  { bins present = {1}; }
    cp_wgt_has_neg:  coverpoint wgt_has_neg  { bins present = {1}; }
    cp_acc_in: coverpoint cov_acc_in {
      bins min_rail  = {32'sh8000_0000};
      bins large_neg = {[32'sh8000_0001 : 32'shC000_0000]};
      bins zero      = {0};
      bins moderate  = {[32'shC000_0001 : -1], [1 : 32'sh3FFF_FFFF]};
      bins large_pos = {[32'sh4000_0000 : 32'sh7FFF_FFFE]};
      bins max_rail  = {32'sh7FFF_FFFF};
    }
  endgroup

  covergroup cg_output;
    option.per_instance = 1;
    cp_sat: coverpoint cov_sat {
      bins no_sat = {0};
      bins sat    = {1};
    }
    cp_acc_in_sign: coverpoint cov_acc_in_neg {
      bins non_negative = {0};
      bins negative     = {1};
    }
    x_sat_acc_sign: cross cp_sat, cp_acc_in_sign;
  endgroup

  covergroup cg_reset;
    option.per_instance = 1;
    cp_reset_during_active: coverpoint cov_reset_active {
      bins while_active = {1};
      bins while_idle   = {0};
    }
  endgroup

  covergroup cg_handshake;
    option.per_instance = 1;
    cp_in_stall: coverpoint cov_in_stall { bins stall        = {1}; }
    cp_out_bp:   coverpoint cov_out_bp   { bins backpressure = {1}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_in       = new("imp_in", this);
    imp_out      = new("imp_out", this);
    imp_rst      = new("imp_rst", this);
    cg_input     = new();
    cg_output    = new();
    cg_reset     = new();
    cg_handshake = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "mac_coverage: virtual mac_if not found in config db under key 'vif'")
  endfunction

  // Clocked handshake sampling straight off the interface
  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n === 1'b1) begin
        cov_in_stall = (vif.in_valid  === 1'b1 && vif.in_ready  === 1'b0);
        cov_out_bp   = (vif.out_valid === 1'b1 && vif.out_ready === 1'b0);
        cg_handshake.sample();
      end
    end
  endtask

  function void write_cov_in(mac_txn t);
    act_has_min = 0; act_has_max = 0; act_has_zero = 0; act_has_pos = 0; act_has_neg = 0;
    wgt_has_min = 0; wgt_has_max = 0; wgt_has_zero = 0; wgt_has_pos = 0; wgt_has_neg = 0;
    foreach (t.act[i]) begin
      if (t.act[i] == -(2 ** (DATA_W - 1)))    act_has_min  = 1;
      if (t.act[i] == (2 ** (DATA_W - 1)) - 1) act_has_max  = 1;
      if (t.act[i] == 0)                       act_has_zero = 1;
      if (t.act[i] > 0)                        act_has_pos  = 1;
      if (t.act[i] < 0)                        act_has_neg  = 1;
    end
    foreach (t.wgt[i]) begin
      if (t.wgt[i] == -(2 ** (DATA_W - 1)))    wgt_has_min  = 1;
      if (t.wgt[i] == (2 ** (DATA_W - 1)) - 1) wgt_has_max  = 1;
      if (t.wgt[i] == 0)                       wgt_has_zero = 1;
      if (t.wgt[i] > 0)                        wgt_has_pos  = 1;
      if (t.wgt[i] < 0)                        wgt_has_neg  = 1;
    end
    cov_acc_in = t.acc_in;
    cg_input.sample();
    pend_sign_q.push_back(t.acc_in < 0);
  endfunction

  function void write_cov_out(mac_txn t);
    cov_sat        = t.sat_flag;
    cov_acc_in_neg = (pend_sign_q.size() > 0) ? pend_sign_q.pop_front() : 1'b0;
    cg_output.sample();
  endfunction

  function void write_cov_rst(bit t);
    cov_reset_active = (pend_sign_q.size() > 0);
    cg_reset.sample();
    pend_sign_q.delete();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf(
      "coverage: input=%.1f%% output=%.1f%% reset=%.1f%% handshake=%.1f%%",
      cg_input.get_inst_coverage(), cg_output.get_inst_coverage(),
      cg_reset.get_inst_coverage(), cg_handshake.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : mac_coverage
