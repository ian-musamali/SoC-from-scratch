// -----------------------------------------------------------------------------
// Drives exactly one npu case (one whole layer program). The base test loops
// this sequence over the manifest so it can run the end-of-case full-memory
// compare between cases.
// -----------------------------------------------------------------------------
class npu_case_seq extends uvm_sequence #(npu_txn);

  `uvm_object_utils(npu_case_seq)

  string case_dir;  // set by the test before start()

  function new(string name = "npu_case_seq");
    super.new(name);
  endfunction

  virtual task body();
    npu_txn t;
    int     fd;

    if (case_dir.len() == 0)
      `uvm_fatal("NPU_SEQ", "case_dir not set before start()")

    fd = $fopen({case_dir, "/descs.txt"}, "r");
    if (fd == 0)
      `uvm_fatal("NPU_SEQ", {"cannot open ", case_dir, "/descs.txt"})

    t = npu_txn::type_id::create("t");
    if (!npu_txn::parse_descs(fd, t))
      `uvm_fatal("NPU_SEQ", {"descriptor parse failed for ", case_dir})
    $fclose(fd);
    t.case_dir = case_dir;

    start_item(t);
    finish_item(t);
    `uvm_info("NPU_SEQ", $sformatf("case driven: %s", t.convert2string()), UVM_LOW)
  endtask

endclass : npu_case_seq
