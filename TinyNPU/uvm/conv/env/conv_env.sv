// -----------------------------------------------------------------------------
// Isolated conv_engine environment: active agent, golden MAC responder,
// output scoreboard, coverage.
// -----------------------------------------------------------------------------
class conv_env extends uvm_env;

  `uvm_component_utils(conv_env)

  conv_agent         agent;
  conv_mac_responder responder;
  conv_scoreboard    sb;
  conv_coverage      cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent     = conv_agent::type_id::create("agent", this);
    responder = conv_mac_responder::type_id::create("responder", this);
    sb        = conv_scoreboard::type_id::create("sb", this);
    cov       = conv_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap_write.connect(sb.imp_write);
    agent.mon.ap_done.connect(sb.imp_done);
    agent.mon.ap_start.connect(cov.imp_start);
    agent.mon.ap_done.connect(cov.imp_done);
  endfunction

endclass : conv_env
