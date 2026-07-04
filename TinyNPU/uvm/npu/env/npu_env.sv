// -----------------------------------------------------------------------------
// Full-system environment: one active agent, scoreboard, coverage.
// -----------------------------------------------------------------------------
class npu_env extends uvm_env;

  `uvm_component_utils(npu_env)

  npu_agent      agent;
  npu_scoreboard sb;
  npu_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = npu_agent::type_id::create("agent", this);
    sb    = npu_scoreboard::type_id::create("sb", this);
    cov   = npu_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap_write.connect(sb.imp_write);
    agent.mon.ap_done.connect(sb.imp_done);
    agent.mon.ap_start.connect(cov.imp_start);
    agent.mon.ap_done.connect(cov.imp_done);
  endfunction

endclass : npu_env
