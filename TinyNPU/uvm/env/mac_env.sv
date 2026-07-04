// -----------------------------------------------------------------------------
// MAC array unit environment: one active agent, scoreboard, coverage.
// Monitor analysis ports fan out to both subscribers.
// -----------------------------------------------------------------------------
class mac_env extends uvm_env;

  `uvm_component_utils(mac_env)

  mac_agent      agent;
  mac_scoreboard sb;
  mac_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = mac_agent::type_id::create("agent", this);
    sb    = mac_scoreboard::type_id::create("sb", this);
    cov   = mac_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap_in.connect(sb.imp_in);
    agent.mon.ap_in.connect(cov.imp_in);
    agent.mon.ap_out.connect(sb.imp_out);
    agent.mon.ap_out.connect(cov.imp_out);
    agent.mon.ap_reset.connect(sb.imp_rst);
    agent.mon.ap_reset.connect(cov.imp_rst);
  endfunction

endclass : mac_env
