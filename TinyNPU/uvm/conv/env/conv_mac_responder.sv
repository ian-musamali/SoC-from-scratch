// -----------------------------------------------------------------------------
// Reactive golden MAC responder — the heart of the isolated conv env.
//
// The conv engine's MAC request stream is fully deterministic given config +
// memories, so the Python model pre-computed the exact request AND response
// of every MAC pass into <case_dir>/mac_trace.txt (Phase-3 131-field format,
// parsed with the existing mac_txn::read_record). This component:
//  - CHECKS every request (act/wgt lane buses + acc_in) against the trace —
//    this is where windowing / padding / stride / lane-packing bugs surface;
//  - RESPONDS with the golden accumulator + sat flag (never computed in SV),
//    with randomized 0..2-cycle delays on both accept and response to shake
//    the DUT's handshake robustness;
//  - on each done pulse verifies the case's trace is exhausted and advances
//    to the next manifest case.
// -----------------------------------------------------------------------------
class conv_mac_responder extends uvm_component;

  `uvm_component_utils(conv_mac_responder)

  virtual conv_mac_if  mac_vif;
  virtual conv_ctrl_if ctrl_vif;

  mac_txn      traces [][$];    // per case, in manifest order
  string       case_dirs [$];
  int unsigned case_idx;
  int unsigned trace_pos;       // consumed entries within the current case
  int unsigned num_served;      // total responses driven (public, test checks >0)
  int unsigned num_req_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual conv_mac_if)::get(this, "", "mac_vif", mac_vif))
      `uvm_fatal("NOVIF", "conv_mac_responder: virtual conv_mac_if not found under key 'mac_vif'")
    if (!uvm_config_db#(virtual conv_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
      `uvm_fatal("NOVIF", "conv_mac_responder: virtual conv_ctrl_if not found under key 'ctrl_vif'")

    conv_txn::read_manifest(case_dirs);
    traces = new [case_dirs.size()];
    foreach (case_dirs[i]) begin
      int    fd;
      string path;
      path = {case_dirs[i], "/mac_trace.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        `uvm_fatal("MAC_RSP", {"cannot open ", path})
      forever begin
        mac_txn t = mac_txn::type_id::create($sformatf("trace_%0d_%0d", i, traces[i].size()));
        if (!mac_txn::read_record(fd, t)) break;
        traces[i].push_back(t);
      end
      $fclose(fd);
      `uvm_info("MAC_RSP", $sformatf("case %0d (%s): %0d expected MAC transactions",
                                     i, case_dirs[i], traces[i].size()), UVM_LOW)
    end
  endfunction

  task run_phase(uvm_phase phase);
    mac_vif.mac_ready     <= 1'b0;
    mac_vif.mac_res_valid <= 1'b0;
    mac_vif.mac_res_acc   <= '0;
    mac_vif.mac_res_sat   <= 1'b0;

    fork
      watch_done();
    join_none

    forever begin
      @(posedge mac_vif.clk);
      if (mac_vif.rst_n !== 1'b1)
        continue;

      if (mac_vif.mac_valid === 1'b1) begin
        mac_txn rec;

        // Random accept delay (DUT must hold valid + stable buses)
        repeat ($urandom_range(2)) @(posedge mac_vif.clk);
        mac_vif.mac_ready <= 1'b1;
        @(posedge mac_vif.clk);      // accept edge: request sampled here
        mac_vif.mac_ready <= 1'b0;

        rec = next_record();
        if (rec != null)
          check_request(rec);

        // Random response delay, then drive the golden response
        repeat ($urandom_range(2)) @(posedge mac_vif.clk);
        mac_vif.mac_res_valid <= 1'b1;
        if (rec != null) begin
          mac_vif.mac_res_acc <= rec.exp_acc_out;
          mac_vif.mac_res_sat <= rec.exp_sat;
        end
        else begin
          mac_vif.mac_res_acc <= '0;
          mac_vif.mac_res_sat <= 1'b0;
        end
        forever begin
          @(posedge mac_vif.clk);
          if (mac_vif.mac_res_ready === 1'b1) break;
        end
        mac_vif.mac_res_valid <= 1'b0;
        num_served++;
      end
    end
  endtask

  // Pop the next expected record for the current case (null + error if the
  // DUT issued more MAC transactions than the golden model predicted).
  protected function mac_txn next_record();
    if (case_idx >= traces.size() || trace_pos >= traces[case_idx].size()) begin
      num_req_errors++;
      `uvm_error("MAC_RSP", $sformatf(
        "case %0d: unexpected extra MAC request (trace exhausted at %0d entries)",
        case_idx, trace_pos))
      return null;
    end
    trace_pos++;
    return traces[case_idx][trace_pos - 1];
  endfunction

  // Compare the sampled request buses against the golden record, lane by lane.
  protected function void check_request(mac_txn rec);
    logic [tinynpu_pkg::NUM_LANES*tinynpu_pkg::DATA_W-1:0] exp_act, exp_wgt;
    foreach (rec.act[i]) begin
      exp_act[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W] = rec.act[i];
      exp_wgt[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W] = rec.wgt[i];
    end

    if (mac_vif.mac_act !== exp_act) begin
      num_req_errors++;
      for (int i = 0; i < tinynpu_pkg::NUM_LANES; i++) begin
        if (mac_vif.mac_act[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W]
            !== exp_act[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W]) begin
          `uvm_error("MAC_RSP", $sformatf(
            "case %0d pass %0d: act lane %0d mismatch got=0x%02h exp=0x%02h",
            case_idx, trace_pos - 1, i,
            mac_vif.mac_act[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W],
            exp_act[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W]))
          break;  // first offending lane is enough
        end
      end
    end
    if (mac_vif.mac_wgt !== exp_wgt) begin
      num_req_errors++;
      for (int i = 0; i < tinynpu_pkg::NUM_LANES; i++) begin
        if (mac_vif.mac_wgt[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W]
            !== exp_wgt[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W]) begin
          `uvm_error("MAC_RSP", $sformatf(
            "case %0d pass %0d: wgt lane %0d mismatch got=0x%02h exp=0x%02h",
            case_idx, trace_pos - 1, i,
            mac_vif.mac_wgt[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W],
            exp_wgt[i*tinynpu_pkg::DATA_W +: tinynpu_pkg::DATA_W]))
          break;
        end
      end
    end
    if ($signed(mac_vif.mac_acc_in) !== rec.acc_in) begin
      num_req_errors++;
      `uvm_error("MAC_RSP", $sformatf(
        "case %0d pass %0d: acc_in mismatch got=0x%08h exp=0x%08h",
        case_idx, trace_pos - 1, mac_vif.mac_acc_in, rec.acc_in))
    end
  endfunction

  // Advance to the next case's trace on each done pulse.
  protected task watch_done();
    forever begin
      @(posedge ctrl_vif.clk);
      if (ctrl_vif.rst_n === 1'b1 && ctrl_vif.done === 1'b1) begin
        if (case_idx < traces.size() && trace_pos != traces[case_idx].size())
          `uvm_error("MAC_RSP", $sformatf(
            "case %0d done but only %0d of %0d expected MAC transactions occurred",
            case_idx, trace_pos, traces[case_idx].size()))
        case_idx++;
        trace_pos = 0;
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MAC_RSP", $sformatf(
      "responder summary: served=%0d request_errors=%0d cases=%0d/%0d",
      num_served, num_req_errors, case_idx, case_dirs.size()), UVM_LOW)
  endfunction

endclass : conv_mac_responder
