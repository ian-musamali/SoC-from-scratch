// -----------------------------------------------------------------------------
// Convolution engine configuration transaction. One conv_txn = one conv case
// = one start pulse. All fields are loaded from <case_dir>/cfg.txt via the
// static parse_cfg() helper; nothing is randomized in this environment (the
// only randomness is the responder's protocol delays).
//
// This file is also the home of the two static file helpers shared by every
// component that walks the vector suite:
//   read_manifest() - resolves +CONV_DIR / +CONV_MANIFEST into a queue of
//                     absolute-ish case directory paths ({dir, "/", name})
//   parse_cfg()     - parses cfg.txt's single line:
//                     "%d %d %d %d %d %d %d %d %d %h" =
//                     img_w img_h in_ch stride(1|2) pad out_shift
//                     ifm_base ofm_base wgt_base acc_init(8-hex, two's compl.)
// -----------------------------------------------------------------------------
class conv_txn extends uvm_sequence_item;

  // Configuration fields, types matching the conv_engine ports
  bit [5:0]              img_w;
  bit [5:0]              img_h;
  bit [3:0]              in_ch;
  bit                    stride2;
  bit                    pad;
  bit [SHIFT_W-1:0]      out_shift;
  bit [FM_ADDR_W-1:0]    ifm_base;
  bit [FM_ADDR_W-1:0]    ofm_base;
  bit [WGT_ADDR_W-1:0]   wgt_base;
  bit signed [ACC_W-1:0] acc_init;

  // Which vector directory this case came from
  string case_dir;

  `uvm_object_utils(conv_txn)

  function new(string name = "conv_txn");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    conv_txn rt;
    if (!$cast(rt, rhs)) begin
      `uvm_fatal("CONV_TXN", "do_copy: rhs is not a conv_txn")
    end
    super.do_copy(rhs);
    img_w     = rt.img_w;
    img_h     = rt.img_h;
    in_ch     = rt.in_ch;
    stride2   = rt.stride2;
    pad       = rt.pad;
    out_shift = rt.out_shift;
    ifm_base  = rt.ifm_base;
    ofm_base  = rt.ofm_base;
    wgt_base  = rt.wgt_base;
    acc_init  = rt.acc_init;
    case_dir  = rt.case_dir;
  endfunction

  virtual function string convert2string();
    return $sformatf({"case_dir=%s img_w=%0d img_h=%0d in_ch=%0d stride2=%0b ",
                      "pad=%0b out_shift=%0d ifm_base=0x%04h ofm_base=0x%04h ",
                      "wgt_base=0x%03h acc_init=0x%08h"},
                     case_dir, img_w, img_h, in_ch, stride2,
                     pad, out_shift, ifm_base, ofm_base,
                     wgt_base, acc_init);
  endfunction

  // ---------------------------------------------------------------------------
  // Strip leading/trailing whitespace and anything after a '#'.
  // ---------------------------------------------------------------------------
  static function string trim_line(string s);
    int l;
    int r;
    int hash;
    hash = -1;
    for (int i = 0; i < s.len(); i++) begin
      if (s.getc(i) == "#") begin
        hash = i;
        break;
      end
    end
    if (hash == 0) return "";
    if (hash > 0) s = s.substr(0, hash - 1);
    l = 0;
    r = s.len() - 1;
    while (l <= r && (s.getc(l) == 32 || s.getc(l) == 9 ||
                      s.getc(l) == 10 || s.getc(l) == 13)) l++;
    while (r >= l && (s.getc(r) == 32 || s.getc(r) == 9 ||
                      s.getc(r) == 10 || s.getc(r) == 13)) r--;
    if (l > r) return "";
    return s.substr(l, r);
  endfunction

  // ---------------------------------------------------------------------------
  // Resolve +CONV_DIR / +CONV_MANIFEST (both required) and return the case
  // directory paths in manifest order. '#' comments and blank lines skipped.
  // Fatals (qualified, this is a static function) if a plusarg is missing or
  // the manifest cannot be opened.
  // ---------------------------------------------------------------------------
  static function void read_manifest(output string case_dirs[$]);
    string dir;
    string mfile;
    string path;
    string line;
    string name;
    int    fd;

    if (!$value$plusargs("CONV_DIR=%s", dir)) begin
      uvm_pkg::uvm_report_fatal("CONV_MANIFEST",
        "+CONV_DIR=<vector dir> plusarg is required");
      return;
    end
    if (!$value$plusargs("CONV_MANIFEST=%s", mfile)) begin
      uvm_pkg::uvm_report_fatal("CONV_MANIFEST",
        "+CONV_MANIFEST=<manifest file> plusarg is required");
      return;
    end

    path = mfile;  // +CONV_MANIFEST is a standalone path; +CONV_DIR prefixes case names
    fd   = $fopen(path, "r");
    if (fd == 0) begin
      uvm_pkg::uvm_report_fatal("CONV_MANIFEST",
        {"cannot open manifest file: ", path});
      return;
    end
    while ($fgets(line, fd) > 0) begin
      name = trim_line(line);
      if (name.len() == 0) continue;
      case_dirs.push_back({dir, "/", name});
    end
    $fclose(fd);
  endfunction

  // ---------------------------------------------------------------------------
  // Parse one cfg.txt line into t (case_dir is NOT set here). Field-by-field
  // $fscanf per repo portability rules. Returns 1 on success, 0 on any
  // malformed/missing field (reported as a qualified error).
  // ---------------------------------------------------------------------------
  static function bit parse_cfg(int fd, conv_txn t);
    int               v;
    int               code;
    logic [ACC_W-1:0] v_acc;

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: img_w missing");
      return 0;
    end
    t.img_w = v[5:0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: img_h missing");
      return 0;
    end
    t.img_h = v[5:0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: in_ch missing");
      return 0;
    end
    t.in_ch = v[3:0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: stride missing");
      return 0;
    end
    if (v != 1 && v != 2) begin
      uvm_pkg::uvm_report_error("CFG_PARSE",
        $sformatf("cfg.txt: stride must be 1 or 2, got %0d", v));
      return 0;
    end
    t.stride2 = (v == 2);

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: pad missing");
      return 0;
    end
    t.pad = v[0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: out_shift missing");
      return 0;
    end
    t.out_shift = v[SHIFT_W-1:0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: ifm_base missing");
      return 0;
    end
    t.ifm_base = v[FM_ADDR_W-1:0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: ofm_base missing");
      return 0;
    end
    t.ofm_base = v[FM_ADDR_W-1:0];

    code = $fscanf(fd, "%d", v);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: wgt_base missing");
      return 0;
    end
    t.wgt_base = v[WGT_ADDR_W-1:0];

    code = $fscanf(fd, " %h", v_acc);
    if (code != 1) begin
      uvm_pkg::uvm_report_error("CFG_PARSE", "cfg.txt: acc_init missing");
      return 0;
    end
    t.acc_init = $signed(v_acc);

    return 1;
  endfunction

endclass : conv_txn
