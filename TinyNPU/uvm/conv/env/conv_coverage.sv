// -----------------------------------------------------------------------------
// conv_engine functional coverage: configuration space (stride x pad cross,
// channel count incl. the multi-pass >64-tap bin, requant shift, acc_init
// sign, image size classes), end-of-case saturation, and MAC-port
// backpressure sampled straight off the interface.
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_conv_cov_start)
`uvm_analysis_imp_decl(_conv_cov_done)

class conv_coverage extends uvm_component;

  `uvm_component_utils(conv_coverage)

  uvm_analysis_imp_conv_cov_start #(conv_txn, conv_coverage) imp_start;
  uvm_analysis_imp_conv_cov_done  #(bit,      conv_coverage) imp_done;

  virtual conv_mac_if mac_vif;

  // Sampling state
  bit          cov_stride2, cov_pad;
  int unsigned cov_in_ch, cov_shift, cov_img_w, cov_img_h;
  int          cov_acc_sign;   // -1 / 0 / +1
  bit          cov_sat;
  bit          cov_req_bp;

  covergroup cg_cfg;
    option.per_instance = 1;
    cp_stride: coverpoint cov_stride2 { bins s1 = {0}; bins s2 = {1}; }
    cp_pad:    coverpoint cov_pad     { bins none = {0}; bins pad1 = {1}; }
    x_stride_pad: cross cp_stride, cp_pad;
    cp_in_ch: coverpoint cov_in_ch {
      bins single    = {1};
      bins few       = {[2:4]};
      bins multipass = {8};      // 72 taps -> 2 chained MAC passes
    }
    cp_shift: coverpoint cov_shift {
      bins none     = {0};
      bins shift_lo = {[1:4]};
      bins shift_hi = {[5:31]};
    }
    cp_acc_sign: coverpoint cov_acc_sign {
      bins negative = {-1};
      bins zero     = {0};
      bins positive = {1};
    }
    cp_img_w: coverpoint cov_img_w {
      bins tiny  = {[1:4]};
      bins mid   = {[5:16]};
      bins wide  = {[17:32]};
    }
    cp_img_h: coverpoint cov_img_h {
      bins tiny  = {[1:4]};
      bins mid   = {[5:16]};
      bins tall  = {[17:32]};
    }
  endgroup

  covergroup cg_done;
    option.per_instance = 1;
    cp_sat: coverpoint cov_sat { bins clean = {0}; bins saturated = {1}; }
  endgroup

  covergroup cg_mac;
    option.per_instance = 1;
    cp_req_backpressure: coverpoint cov_req_bp { bins stalled = {1}; bins flowing = {0}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_start = new("imp_start", this);
    imp_done  = new("imp_done", this);
    cg_cfg    = new();
    cg_done   = new();
    cg_mac    = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual conv_mac_if)::get(this, "", "mac_vif", mac_vif))
      `uvm_fatal("NOVIF", "conv_coverage: virtual conv_mac_if not found under key 'mac_vif'")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge mac_vif.clk);
      if (mac_vif.rst_n === 1'b1 && mac_vif.mac_valid === 1'b1) begin
        cov_req_bp = (mac_vif.mac_ready !== 1'b1);
        cg_mac.sample();
      end
    end
  endtask

  function void write_conv_cov_start(conv_txn t);
    cov_stride2  = t.stride2;
    cov_pad      = t.pad;
    cov_in_ch    = t.in_ch;
    cov_shift    = t.out_shift;
    cov_img_w    = t.img_w;
    cov_img_h    = t.img_h;
    cov_acc_sign = (t.acc_init == 0) ? 0 : ((t.acc_init > 0) ? 1 : -1);
    cg_cfg.sample();
  endfunction

  function void write_conv_cov_done(bit sat);
    cov_sat = sat;
    cg_done.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("CONV_COV", $sformatf(
      "coverage: cfg=%.1f%% done=%.1f%% mac=%.1f%%",
      cg_cfg.get_inst_coverage(), cg_done.get_inst_coverage(),
      cg_mac.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : conv_coverage
