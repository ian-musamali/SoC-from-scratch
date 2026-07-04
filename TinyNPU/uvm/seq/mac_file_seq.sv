// -----------------------------------------------------------------------------
// Drives every transaction of +VEC_FILE in file order. The inherited
// randomize_idle knob selects directed (zero-gap) vs randomized idle gaps.
// -----------------------------------------------------------------------------
class mac_file_seq extends mac_base_seq;

  `uvm_object_utils(mac_file_seq)

  function new(string name = "mac_file_seq");
    super.new(name);
  endfunction

  virtual task body();
    mac_txn q[$];
    load_vectors(q);
    foreach (q[i])
      send_txn(q[i]);
    `uvm_info("SEQ", $sformatf("mac_file_seq done: %0d transactions sent", q.size()), UVM_LOW)
  endtask

endclass : mac_file_seq
