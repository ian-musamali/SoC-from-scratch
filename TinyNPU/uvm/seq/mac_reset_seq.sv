// -----------------------------------------------------------------------------
// Reset-recovery sequence. Drives the first half of +VEC_FILE, then triggers
// the global "tinynpu_reset_half_done" event and blocks on
// "tinynpu_reset_resume". The reset TEST orchestrates the actual reset pulse
// in between (via the "tinynpu_reset_req" event that tb_top listens on) and
// then triggers the resume event, after which this sequence drives the
// remaining transactions.
// -----------------------------------------------------------------------------
class mac_reset_seq extends mac_base_seq;

  `uvm_object_utils(mac_reset_seq)

  function new(string name = "mac_reset_seq");
    super.new(name);
  endfunction

  virtual task body();
    mac_txn      q[$];
    int unsigned half;
    uvm_event    ev_half   = uvm_event_pool::get_global("tinynpu_reset_half_done");
    uvm_event    ev_resume = uvm_event_pool::get_global("tinynpu_reset_resume");

    load_vectors(q);
    half = q.size() / 2;

    for (int unsigned i = 0; i < half; i++)
      send_txn(q[i]);

    `uvm_info("SEQ", $sformatf("first %0d/%0d transactions sent; pausing for mid-stream reset",
                               half, q.size()), UVM_LOW)
    ev_half.trigger();
    ev_resume.wait_trigger();
    `uvm_info("SEQ", "resuming after reset", UVM_LOW)

    for (int unsigned i = half; i < q.size(); i++)
      send_txn(q[i]);

    `uvm_info("SEQ", $sformatf("mac_reset_seq done: %0d transactions sent", q.size()), UVM_LOW)
  endtask

endclass : mac_reset_seq
