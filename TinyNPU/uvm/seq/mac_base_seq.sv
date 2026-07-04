// -----------------------------------------------------------------------------
// Base sequence: file-reading and send utilities shared by all sequences.
// Data (act/wgt/acc_in and expected results) always comes from the +VEC_FILE
// golden vector file; only protocol timing (idle_cycles) is randomized in SV.
//  - randomize_idle == 0: directed timing, idle_cycles forced to 0
//  - randomize_idle == 1: idle_cycles randomized 0..5 via the txn constraint
// -----------------------------------------------------------------------------
class mac_base_seq extends uvm_sequence #(mac_txn);

  `uvm_object_utils(mac_base_seq)

  bit randomize_idle = 0;

  function new(string name = "mac_base_seq");
    super.new(name);
  endfunction

  // Open +VEC_FILE and parse every record (comments skipped) into q, in file
  // order. Fatals if the plusarg is missing, the file cannot be opened, or it
  // contains no records.
  protected function void load_vectors(ref mac_txn q[$]);
    int    fd;
    string vec_file;
    if (!$value$plusargs("VEC_FILE=%s", vec_file))
      `uvm_fatal("VEC_FILE", "+VEC_FILE=<path> plusarg is required")
    fd = $fopen(vec_file, "r");
    if (fd == 0)
      `uvm_fatal("VEC_FILE", $sformatf("cannot open vector file '%s'", vec_file))
    forever begin
      mac_txn t = mac_txn::type_id::create($sformatf("file_txn_%0d", q.size()));
      if (!mac_txn::read_record(fd, t)) break;
      q.push_back(t);
    end
    $fclose(fd);
    if (q.size() == 0)
      `uvm_fatal("VEC_FILE", $sformatf("no transactions parsed from '%s'", vec_file))
    `uvm_info("SEQ", $sformatf("loaded %0d transactions from '%s'",
                               q.size(), vec_file), UVM_LOW)
  endfunction

  // Apply the idle-gap policy (data fields are untouched — golden-model
  // coupling) and send the item to the driver.
  protected task send_txn(mac_txn t);
    if (randomize_idle) begin
      if (!t.randomize(idle_cycles))
        `uvm_error("SEQ", "randomization of idle_cycles failed")
    end
    else begin
      t.idle_cycles = 0;
    end
    start_item(t);
    finish_item(t);
  endtask

endclass : mac_base_seq
