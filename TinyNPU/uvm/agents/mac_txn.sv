// -----------------------------------------------------------------------------
// MAC array transaction. Data (act/wgt/acc_in) and the expected results always
// come from the golden vector files; only idle_cycles is randomized in SV.
// The static read_record() parser is the single point of truth for the
// 131-field hex line format, shared by the sequences and the scoreboard.
// -----------------------------------------------------------------------------
class mac_txn extends uvm_sequence_item;

  // Stimulus (loaded from the vector file; rand so protocol sequences could
  // constrain them later, but this env never randomizes data)
  rand bit signed [DATA_W-1:0] act [NUM_LANES];
  rand bit signed [DATA_W-1:0] wgt [NUM_LANES];
  rand bit signed [ACC_W-1:0]  acc_in;

  // Protocol timing: idle cycles inserted by the driver before in_valid
  rand int unsigned idle_cycles;

  // Expected results (from the vector file)
  bit signed [ACC_W-1:0] exp_acc_out;
  bit                    exp_sat;

  // Actual results (filled in by the monitor on output completion)
  bit signed [ACC_W-1:0] acc_out;
  bit                    sat_flag;

  constraint c_idle { idle_cycles inside {[0:5]}; }

  `uvm_object_utils(mac_txn)

  function new(string name = "mac_txn");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    mac_txn rt;
    if (!$cast(rt, rhs)) begin
      `uvm_fatal("MAC_TXN", "do_copy: rhs is not a mac_txn")
    end
    super.do_copy(rhs);
    act         = rt.act;
    wgt         = rt.wgt;
    acc_in      = rt.acc_in;
    idle_cycles = rt.idle_cycles;
    exp_acc_out = rt.exp_acc_out;
    exp_sat     = rt.exp_sat;
    acc_out     = rt.acc_out;
    sat_flag    = rt.sat_flag;
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    mac_txn rt;
    if (!$cast(rt, rhs)) return 0;
    return super.do_compare(rhs, comparer) &&
           (act         == rt.act)         &&
           (wgt         == rt.wgt)         &&
           (acc_in      == rt.acc_in)      &&
           (exp_acc_out == rt.exp_acc_out) &&
           (exp_sat     == rt.exp_sat)     &&
           (acc_out     == rt.acc_out)     &&
           (sat_flag    == rt.sat_flag);
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("idle=%0d acc_in=0x%08h exp_acc_out=0x%08h exp_sat=%0b acc_out=0x%08h sat_flag=%0b",
                  idle_cycles, acc_in, exp_acc_out, exp_sat, acc_out, sat_flag);
    s = {s, "\n  act:"};
    foreach (act[i]) s = {s, $sformatf(" %02h", act[i])};
    s = {s, "\n  wgt:"};
    foreach (wgt[i]) s = {s, $sformatf(" %02h", wgt[i])};
    return s;
  endfunction

  // ---------------------------------------------------------------------------
  // Parse one vector-file record into t. Skips '#' comment lines and blank
  // lines. Returns 1 on success, 0 on clean EOF; fatals on a malformed line.
  // Field order: 64x act (2 hex), 64x wgt (2 hex), acc_in (8 hex),
  // exp_acc_out (8 hex), exp_sat (1 hex digit).
  // ---------------------------------------------------------------------------
  static function bit read_record(int fd, mac_txn t);
    int                c;
    int                code;
    string             line;
    logic [DATA_W-1:0] v_lane;
    logic [ACC_W-1:0]  v_acc;
    logic [3:0]        v_sat;

    // Skip whitespace and comment lines until the first data character
    forever begin
      c = $fgetc(fd);
      if (c == -1) return 0;                       // clean EOF
      if (c == "#") begin
        void'($fgets(line, fd));                   // discard rest of comment
      end
      else if (c == 32 || c == 9 || c == 10 || c == 13) begin
        ;                                          // space/tab/LF/CR: skip
      end
      else begin
        void'($ungetc(c, fd));
        break;
      end
    end

    foreach (t.act[i]) begin
      code = $fscanf(fd, "%h", v_lane);
      if (code != 1) begin
        uvm_pkg::uvm_report_fatal("VEC_PARSE", $sformatf("malformed vector line: act[%0d] missing", i));
        return 0;
      end
      t.act[i] = $signed(v_lane);
    end
    foreach (t.wgt[i]) begin
      code = $fscanf(fd, "%h", v_lane);
      if (code != 1) begin
        uvm_pkg::uvm_report_fatal("VEC_PARSE", $sformatf("malformed vector line: wgt[%0d] missing", i));
        return 0;
      end
      t.wgt[i] = $signed(v_lane);
    end
    code = $fscanf(fd, "%h", v_acc);
    if (code != 1) begin
      uvm_pkg::uvm_report_fatal("VEC_PARSE", "malformed vector line: acc_in missing");
      return 0;
    end
    t.acc_in = $signed(v_acc);
    code = $fscanf(fd, "%h", v_acc);
    if (code != 1) begin
      uvm_pkg::uvm_report_fatal("VEC_PARSE", "malformed vector line: exp_acc_out missing");
      return 0;
    end
    t.exp_acc_out = $signed(v_acc);
    code = $fscanf(fd, "%h", v_sat);
    if (code != 1) begin
      uvm_pkg::uvm_report_fatal("VEC_PARSE", "malformed vector line: exp_sat missing");
      return 0;
    end
    t.exp_sat = v_sat[0];
    return 1;
  endfunction

endclass : mac_txn
