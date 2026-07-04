// -----------------------------------------------------------------------------
// npu_core full-system scoreboard. Expected fm writes come ONLY from the
// golden write_trace.txt of each case (never recomputed in SV):
//  - build_phase loads every case's trace into per-case queues (manifest order)
//  - each observed fm write pops the current case's front and compares
//    address AND data bit-exactly
//  - a done pulse checks the current case's trace is exhausted and advances
// The complementary end-of-case full-memory compare lives in npu_base_test
// (task context is needed for fm_mem_if.compare_against()).
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_npu_write)
`uvm_analysis_imp_decl(_npu_done)

class npu_scoreboard extends uvm_component;

  `uvm_component_utils(npu_scoreboard)

  uvm_analysis_imp_npu_write #(npu_write_txn, npu_scoreboard) imp_write;
  uvm_analysis_imp_npu_done  #(bit,           npu_scoreboard) imp_done;

  typedef struct {
    bit [tinynpu_pkg::FM_ADDR_W-1:0] addr;
    bit [tinynpu_pkg::DATA_W-1:0]    data;
  } wr_t;

  wr_t         traces [][$];   // per case, in manifest order
  string       case_dirs [$];
  int unsigned case_idx;
  int unsigned num_compared;
  int unsigned num_matched;
  int unsigned cases_done;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_write = new("imp_write", this);
    imp_done  = new("imp_done", this);
  endfunction

  function void build_phase(uvm_phase phase);
    string dir, mfile, names[$];
    super.build_phase(phase);

    if (!$value$plusargs("NPU_DIR=%s", dir))
      `uvm_fatal("NPU_SB", "+NPU_DIR=<vector dir> plusarg is required")
    if (!$value$plusargs("NPU_MANIFEST=%s", mfile))
      `uvm_fatal("NPU_SB", "+NPU_MANIFEST=<manifest file> plusarg is required")
    if (!npu_parse_manifest(mfile, names))
      `uvm_fatal("NPU_SB", {"cannot open manifest: ", mfile})
    if (names.size() == 0)
      `uvm_fatal("NPU_SB", {"empty manifest: ", mfile})

    foreach (names[i]) case_dirs.push_back({dir, "/", names[i]});

    traces = new [case_dirs.size()];
    foreach (case_dirs[i]) begin
      int    fd, code;
      string path, ln;
      bit [tinynpu_pkg::FM_ADDR_W-1:0] a;
      bit [tinynpu_pkg::DATA_W-1:0]    d;
      path = {case_dirs[i], "/write_trace.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        `uvm_fatal("NPU_SB", {"cannot open ", path})
      void'($fgets(ln, fd));  // '#' header line
      forever begin
        code = $fscanf(fd, " %h %h", a, d);
        if (code != 2) break;
        traces[i].push_back('{addr: a, data: d});
      end
      $fclose(fd);
      `uvm_info("NPU_SB", $sformatf("case %0d (%s): %0d expected writes",
                                    i, case_dirs[i], traces[i].size()), UVM_LOW)
    end
  endfunction

  function void write_npu_write(npu_write_txn t);
    wr_t exp;
    if (case_idx >= traces.size()) begin
      `uvm_error("NPU_SB", $sformatf("write observed after all cases done: %s",
                                     t.convert2string()))
      return;
    end
    if (traces[case_idx].size() == 0) begin
      `uvm_error("NPU_SB", $sformatf("case %0d: unexpected extra write %s",
                                     case_idx, t.convert2string()))
      return;
    end
    exp = traces[case_idx].pop_front();
    num_compared++;
    if (t.addr === exp.addr && t.data === exp.data)
      num_matched++;
    else
      `uvm_error("NPU_SB", $sformatf(
        "case %0d write #%0d MISMATCH: addr got=0x%04h exp=0x%04h, data got=0x%02h exp=0x%02h",
        case_idx, num_compared - 1, t.addr, exp.addr, t.data, exp.data))
  endfunction

  function void write_npu_done(bit sat);
    if (case_idx >= traces.size()) begin
      `uvm_error("NPU_SB", "done pulse after all cases completed")
      return;
    end
    if (traces[case_idx].size() != 0)
      `uvm_error("NPU_SB", $sformatf(
        "case %0d done but %0d expected write(s) never happened",
        case_idx, traces[case_idx].size()))
    else
      `uvm_info("NPU_SB", $sformatf("case %0d complete (sat_seen=%0b)",
                                    case_idx, sat), UVM_LOW)
    cases_done++;
    case_idx++;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (cases_done != case_dirs.size())
      `uvm_error("NPU_SB", $sformatf("only %0d of %0d cases completed",
                                     cases_done, case_dirs.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("NPU_SB", $sformatf(
      "scoreboard summary: cases=%0d/%0d compared=%0d matched=%0d mismatched=%0d",
      cases_done, case_dirs.size(), num_compared, num_matched,
      num_compared - num_matched), UVM_LOW)
  endfunction

endclass : npu_scoreboard
