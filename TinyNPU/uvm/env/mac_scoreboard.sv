// -----------------------------------------------------------------------------
// MAC array scoreboard. Expected values come ONLY from the +VEC_FILE golden
// vector file (never recomputed in SV):
//  - build_phase reads every record into exp_q in file order;
//  - each accepted input (ap_in) pops the next file expectation onto
//    pending_q;
//  - each completed output (ap_out) pops the pending front and compares
//    acc_out / sat_flag bit-exactly;
//  - a reset notification (ap_reset) flushes pending_q, so transactions
//    killed in flight are not falsely flagged.
// check_phase errors on unflushed pending entries always, and on unconsumed
// file expectations unless allow_unconsumed_expected is set (reset test).
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_sb_in)
`uvm_analysis_imp_decl(_sb_out)
`uvm_analysis_imp_decl(_sb_rst)

class mac_scoreboard extends uvm_component;

  `uvm_component_utils(mac_scoreboard)

  uvm_analysis_imp_sb_in  #(mac_txn, mac_scoreboard) imp_in;
  uvm_analysis_imp_sb_out #(mac_txn, mac_scoreboard) imp_out;
  uvm_analysis_imp_sb_rst #(bit,     mac_scoreboard) imp_rst;

  typedef struct {
    mac_txn      ftxn;   // parsed file record (carries exp_acc_out/exp_sat)
    int unsigned index;  // 0-based record index within the vector file
  } exp_rec_t;

  exp_rec_t exp_q     [$];  // file expectations not yet consumed by an input
  exp_rec_t pending_q [$];  // accepted inputs awaiting a completed output

  bit          allow_unconsumed_expected;
  int unsigned num_compared;
  int unsigned num_matched;
  int unsigned num_flushed;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_in  = new("imp_in", this);
    imp_out = new("imp_out", this);
    imp_rst = new("imp_rst", this);
  endfunction

  function void build_phase(uvm_phase phase);
    int    fd;
    string vec_file;
    super.build_phase(phase);

    if (!uvm_config_db#(bit)::get(this, "", "allow_unconsumed_expected",
                                  allow_unconsumed_expected))
      allow_unconsumed_expected = 1'b0;

    if (!$value$plusargs("VEC_FILE=%s", vec_file))
      `uvm_fatal("VEC_FILE", "+VEC_FILE=<path> plusarg is required")
    fd = $fopen(vec_file, "r");
    if (fd == 0)
      `uvm_fatal("VEC_FILE", $sformatf("cannot open vector file '%s'", vec_file))

    forever begin
      mac_txn t = mac_txn::type_id::create($sformatf("vec_%0d", exp_q.size()));
      if (!mac_txn::read_record(fd, t)) break;
      exp_q.push_back('{ftxn: t, index: exp_q.size()});
    end
    $fclose(fd);

    if (exp_q.size() == 0)
      `uvm_error("VEC_FILE", $sformatf("no records parsed from '%s'", vec_file))
    else
      `uvm_info("SB", $sformatf("loaded %0d expected records from '%s'",
                                exp_q.size(), vec_file), UVM_LOW)
  endfunction

  // Input accepted: consume the next file expectation in order
  function void write_sb_in(mac_txn t);
    exp_rec_t rec;
    if (exp_q.size() == 0) begin
      `uvm_error("SB", {"input accepted but the vector file has no more ",
                        "expectations — DUT accepted more transactions than driven?"})
      return;
    end
    rec = exp_q.pop_front();
    pending_q.push_back(rec);
    `uvm_info("SB", $sformatf("input accepted -> pending expectation #%0d (exp_acc_out=0x%08h exp_sat=%0b)",
                              rec.index, rec.ftxn.exp_acc_out, rec.ftxn.exp_sat), UVM_HIGH)
  endfunction

  // Output completed: compare against the oldest pending expectation
  function void write_sb_out(mac_txn t);
    exp_rec_t rec;
    if (pending_q.size() == 0) begin
      `uvm_error("SB", $sformatf("output completed (acc_out=0x%08h sat=%0b) with no pending input",
                                 t.acc_out, t.sat_flag))
      return;
    end
    rec = pending_q.pop_front();
    num_compared++;
    if (t.acc_out === rec.ftxn.exp_acc_out && t.sat_flag === rec.ftxn.exp_sat) begin
      num_matched++;
      `uvm_info("SB", $sformatf("txn #%0d MATCH: acc_out=0x%08h sat=%0b",
                                rec.index, t.acc_out, t.sat_flag), UVM_HIGH)
    end
    else begin
      `uvm_error("SB", $sformatf(
        "txn #%0d MISMATCH: acc_out exp=0x%08h got=0x%08h, sat_flag exp=%0b got=%0b\n  file record: %s",
        rec.index, rec.ftxn.exp_acc_out, t.acc_out, rec.ftxn.exp_sat, t.sat_flag,
        rec.ftxn.convert2string()))
    end
  endfunction

  // Reset: flush everything in flight
  function void write_sb_rst(bit t);
    if (pending_q.size() > 0)
      `uvm_info("SB", $sformatf("reset: flushing %0d pending expectation(s)",
                                pending_q.size()), UVM_LOW)
    num_flushed += pending_q.size();
    pending_q.delete();
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (pending_q.size() != 0)
      `uvm_error("SB", $sformatf(
        "%0d accepted transaction(s) still pending at end of test (no output, no flushing reset)",
        pending_q.size()))
    if (exp_q.size() != 0 && !allow_unconsumed_expected)
      `uvm_error("SB", $sformatf(
        "%0d vector file record(s) were never consumed by an accepted input",
        exp_q.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SB", $sformatf(
      "scoreboard summary: compared=%0d matched=%0d mismatched=%0d flushed_on_reset=%0d unconsumed=%0d",
      num_compared, num_matched, num_compared - num_matched, num_flushed, exp_q.size()),
      UVM_LOW)
  endfunction

endclass : mac_scoreboard
