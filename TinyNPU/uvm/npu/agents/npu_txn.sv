// -----------------------------------------------------------------------------
// npu_txn: one npu_core run (a whole layer program). All golden data comes
// from the Python model's case files; nothing is recomputed in SV.
//
// Also hosts npu_parse_manifest(), the shared manifest-file parser used by
// the scoreboard, the manifest sequence and the base test (single source of
// truth for the '# comment / one case-dir name per line' format).
// -----------------------------------------------------------------------------

// Parse a manifest file (one case dir name per line, '#' comments, blank
// lines allowed) into names[]. Returns 0 if the file cannot be opened.
function automatic bit npu_parse_manifest(string path, ref string names[$]);
  int    fd;
  int    code;
  string line;
  string name;
  names.delete();
  fd = $fopen(path, "r");
  if (fd == 0)
    return 0;
  while (!$feof(fd)) begin
    line = "";
    code = $fgets(line, fd);
    if (code == 0)
      continue;
    name = "";
    code = $sscanf(line, " %s", name);
    if (code != 1)
      continue;
    if (name.len() == 0)
      continue;
    if (name.substr(0, 0) == "#")
      continue;
    names.push_back(name);
  end
  $fclose(fd);
  return 1;
endfunction : npu_parse_manifest

class npu_txn extends uvm_sequence_item;

  `uvm_object_utils(npu_txn)

  int unsigned num_layers;                          // 1..MAX_LAYERS
  logic [66:0] descs [tinynpu_pkg::MAX_LAYERS];     // packed layer descriptors
  string       case_dir;                            // full case directory path

  function new(string name = "npu_txn");
    super.new(name);
    num_layers = 0;
    case_dir   = "";
    foreach (descs[i]) descs[i] = '0;
  endfunction

  // Parse an already-opened descs.txt: first line num_layers (decimal), then
  // num_layers lines each a 17-hex-char packed 67-bit descriptor. Returns 0
  // on any parse failure. Static context: report calls MUST stay qualified.
  static function bit parse_descs(int fd, npu_txn t);
    int          code;
    int unsigned nl;
    logic [66:0] d;
    code = $fscanf(fd, " %d", nl);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("NPU_TXN", "descs.txt: failed to read num_layers",
                                uvm_pkg::UVM_NONE);
      return 0;
    end
    if (nl < 1 || nl > tinynpu_pkg::MAX_LAYERS) begin
      uvm_pkg::uvm_report_error("NPU_TXN",
        $sformatf("descs.txt: num_layers %0d out of range 1..%0d",
                  nl, tinynpu_pkg::MAX_LAYERS),
        uvm_pkg::UVM_NONE);
      return 0;
    end
    t.num_layers = nl;
    foreach (t.descs[i]) t.descs[i] = '0;
    for (int unsigned i = 0; i < nl; i++) begin
      code = $fscanf(fd, " %h", d);
      if (code != 1) begin
        uvm_pkg::uvm_report_error("NPU_TXN",
          $sformatf("descs.txt: failed to read descriptor %0d of %0d", i, nl),
          uvm_pkg::UVM_NONE);
        return 0;
      end
      t.descs[i] = d;
    end
    return 1;
  endfunction : parse_descs

  virtual function string convert2string();
    string s;
    s = $sformatf("npu_txn case_dir=%s num_layers=%0d", case_dir, num_layers);
    foreach (descs[i]) begin
      if (i < num_layers)
        s = {s, $sformatf("\n  layer[%0d] desc=%017h", i, descs[i])};
    end
    return s;
  endfunction

endclass : npu_txn
