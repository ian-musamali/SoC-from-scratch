// -----------------------------------------------------------------------------
// Reset test: drive half of vectors/reset.txt, then pulse rst_n mid-flight
// (while the last accepted transaction's result is still outstanding), resume
// with the remaining vectors, and end clean. Orchestration via global
// uvm_events:
//   sequence --half_done--> test --reset_req--> tb_top (pulses rst_n)
//   tb_top --reset_done--> test --resume--> sequence
// The scoreboard flushes its pending queue on the reset notification;
// allow_unconsumed_expected is set so a file record consumed by an
// accepted-then-flushed (or reset-killed) input cannot fail check_phase.
// The base test verdict still requires num_compared > 0 and zero errors.
// -----------------------------------------------------------------------------
class mac_unit_reset_test extends mac_base_test;

  `uvm_component_utils(mac_unit_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "env.sb", "allow_unconsumed_expected", 1'b1);
  endfunction

  task run_phase(uvm_phase phase);
    mac_reset_seq seq;
    uvm_event ev_half   = uvm_event_pool::get_global("tinynpu_reset_half_done");
    uvm_event ev_req    = uvm_event_pool::get_global("tinynpu_reset_req");
    uvm_event ev_done   = uvm_event_pool::get_global("tinynpu_reset_done");
    uvm_event ev_resume = uvm_event_pool::get_global("tinynpu_reset_resume");

    phase.raise_objection(this, "mac_unit_reset_test main sequence");
    wait_reset_release();

    seq = mac_reset_seq::type_id::create("seq");
    seq.randomize_idle = 0;

    fork
      seq.start(env.agent.sqr);
    join_none

    ev_half.wait_trigger();
    `uvm_info("RESET_TEST", "half of the vector stream sent; requesting mid-stream reset", UVM_LOW)
    ev_req.trigger();
    ev_done.wait_trigger();
    `uvm_info("RESET_TEST", "reset released; resuming the sequence", UVM_LOW)
    ev_resume.trigger();

    wait fork;
    drain();
    phase.drop_objection(this, "mac_unit_reset_test main sequence");
  endtask

endclass : mac_unit_reset_test
