// -----------------------------------------------------------------------------
// conv_engine output scoreboard. Expected int8 OFM writes come ONLY from each
// case's golden ofm_trace.txt (addr + data, in order). A done pulse checks
// the current case's trace is exhausted and advances to the next case.
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_conv_write)
`uvm_analysis_imp_decl(_conv_done)

class conv_scoreboard extends uvm_component;

  `uvm_component_utils(conv_scoreboard)

  uvm_analysis_imp_conv_write #(conv_write_txn, conv_scoreboard) imp_write;
  uvm_analysis_imp_conv_done  #(bit,            conv_scoreboard) imp_done;

  typedef struct {
    bit [FM_ADDR_W-1:0] addr;
    bit [DATA_W-1:0]    data;
  } wr_t;

  wr_t         traces [][$];
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
    super.build_phase(phase);

    conv_txn::read_manifest(case_dirs);
    if (case_dirs.size() == 0)
      `uvm_fatal("CONV_SB", "manifest resolved to zero cases")

    traces = new [case_dirs.size()];
    foreach (case_dirs[i]) begin
      int    fd, code;
      string path, ln;
      bit [FM_ADDR_W-1:0] a;
      bit [DATA_W-1:0]    d;
      path = {case_dirs[i], "/ofm_trace.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        `uvm_fatal("CONV_SB", {"cannot open ", path})
      void'($fgets(ln, fd));  // '#' header line
      forever begin
        code = $fscanf(fd, " %h %h", a, d);
        if (code != 2) break;
        traces[i].push_back('{addr: a, data: d});
      end
      $fclose(fd);
      `uvm_info("CONV_SB", $sformatf("case %0d (%s): %0d expected writes",
                                     i, case_dirs[i], traces[i].size()), UVM_LOW)
    end
  endfunction

  function void write_conv_write(conv_write_txn t);
    wr_t exp;
    if (case_idx >= traces.size()) begin
      `uvm_error("CONV_SB", {"write after all cases done: ", t.convert2string()})
      return;
    end
    if (traces[case_idx].size() == 0) begin
      `uvm_error("CONV_SB", $sformatf("case %0d: unexpected extra write %s",
                                      case_idx, t.convert2string()))
      return;
    end
    exp = traces[case_idx].pop_front();
    num_compared++;
    if (t.addr === exp.addr && t.data === exp.data)
      num_matched++;
    else
      `uvm_error("CONV_SB", $sformatf(
        "case %0d write #%0d MISMATCH: addr got=0x%04h exp=0x%04h, data got=0x%02h exp=0x%02h",
        case_idx, num_compared - 1, t.addr, exp.addr, t.data, exp.data))
  endfunction

  function void write_conv_done(bit sat);
    if (case_idx >= traces.size()) begin
      `uvm_error("CONV_SB", "done pulse after all cases completed")
      return;
    end
    if (traces[case_idx].size() != 0)
      `uvm_error("CONV_SB", $sformatf(
        "case %0d done but %0d expected write(s) never happened",
        case_idx, traces[case_idx].size()))
    else
      `uvm_info("CONV_SB", $sformatf("case %0d complete (sat_seen=%0b)",
                                     case_idx, sat), UVM_LOW)
    cases_done++;
    case_idx++;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (cases_done != case_dirs.size())
      `uvm_error("CONV_SB", $sformatf("only %0d of %0d cases completed",
                                      cases_done, case_dirs.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("CONV_SB", $sformatf(
      "scoreboard summary: cases=%0d/%0d compared=%0d matched=%0d mismatched=%0d",
      cases_done, case_dirs.size(), num_compared, num_matched,
      num_compared - num_matched), UVM_LOW)
  endfunction

endclass : conv_scoreboard
