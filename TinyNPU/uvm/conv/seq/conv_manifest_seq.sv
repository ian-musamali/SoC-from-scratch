// -----------------------------------------------------------------------------
// Drives every case of the +CONV_MANIFEST suite in order. All configuration
// and data come from the case files (golden-model coupling); the only
// randomness in this env is the responder's protocol delays.
// -----------------------------------------------------------------------------
class conv_manifest_seq extends uvm_sequence #(conv_txn);

  `uvm_object_utils(conv_manifest_seq)

  function new(string name = "conv_manifest_seq");
    super.new(name);
  endfunction

  virtual task body();
    string case_dirs[$];

    conv_txn::read_manifest(case_dirs);
    if (case_dirs.size() == 0)
      `uvm_fatal("CONV_SEQ", "manifest resolved to zero cases")

    foreach (case_dirs[i]) begin
      conv_txn t;
      int      fd;

      fd = $fopen({case_dirs[i], "/cfg.txt"}, "r");
      if (fd == 0)
        `uvm_fatal("CONV_SEQ", {"cannot open ", case_dirs[i], "/cfg.txt"})

      t = conv_txn::type_id::create($sformatf("case_%0d", i));
      if (!conv_txn::parse_cfg(fd, t))
        `uvm_fatal("CONV_SEQ", {"cfg parse failed for ", case_dirs[i]})
      $fclose(fd);
      t.case_dir = case_dirs[i];

      start_item(t);
      finish_item(t);
    end

    `uvm_info("CONV_SEQ", $sformatf("all %0d cases driven", case_dirs.size()), UVM_LOW)
  endtask

endclass : conv_manifest_seq
