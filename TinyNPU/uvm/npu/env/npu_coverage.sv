// -----------------------------------------------------------------------------
// Full-system functional coverage: program shape (layer count), per-layer
// descriptor fields (stride x pad cross, channel counts, requant shift), and
// end-of-program saturation. Layer descriptors are unpacked from the packed
// 67-bit words the monitor sampled, so coverage sees exactly what the DUT saw.
// -----------------------------------------------------------------------------

`uvm_analysis_imp_decl(_npu_cov_start)
`uvm_analysis_imp_decl(_npu_cov_done)

class npu_coverage extends uvm_component;

  `uvm_component_utils(npu_coverage)

  uvm_analysis_imp_npu_cov_start #(npu_txn, npu_coverage) imp_start;
  uvm_analysis_imp_npu_cov_done  #(bit,     npu_coverage) imp_done;

  // Sampling state
  int unsigned cov_num_layers;
  bit          cov_stride2, cov_pad;
  int unsigned cov_in_ch, cov_out_ch, cov_shift;
  bit          cov_sat;

  covergroup cg_program;
    option.per_instance = 1;
    cp_num_layers: coverpoint cov_num_layers {
      bins one   = {1};
      bins two   = {2};
      bins three = {3};
      bins deep  = {[4:6]};
    }
  endgroup

  covergroup cg_layer;
    option.per_instance = 1;
    cp_stride: coverpoint cov_stride2 { bins s1 = {0}; bins s2 = {1}; }
    cp_pad:    coverpoint cov_pad     { bins none = {0}; bins pad1 = {1}; }
    x_stride_pad: cross cp_stride, cp_pad;
    cp_in_ch: coverpoint cov_in_ch {
      bins single = {1};
      bins few    = {[2:4]};
      bins many   = {[5:8]};  // > 64 taps -> multi-pass MAC chaining
    }
    cp_out_ch: coverpoint cov_out_ch {
      bins single = {1};
      bins few    = {[2:4]};
      bins many   = {[5:8]};
    }
    cp_shift: coverpoint cov_shift {
      bins none     = {0};
      bins shift_lo = {[1:4]};
      bins shift_hi = {[5:31]};
    }
  endgroup

  covergroup cg_done;
    option.per_instance = 1;
    cp_sat: coverpoint cov_sat { bins clean = {0}; bins saturated = {1}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp_start  = new("imp_start", this);
    imp_done   = new("imp_done", this);
    cg_program = new();
    cg_layer   = new();
    cg_done    = new();
  endfunction

  function void write_npu_cov_start(npu_txn t);
    tinynpu_pkg::layer_desc_t d;
    cov_num_layers = t.num_layers;
    cg_program.sample();
    for (int unsigned i = 0; i < t.num_layers; i++) begin
      d = tinynpu_pkg::layer_desc_t'(t.descs[i]);
      cov_stride2 = d.stride2;
      cov_pad     = d.pad;
      cov_in_ch   = d.in_ch;
      cov_out_ch  = d.out_ch;
      cov_shift   = d.out_shift;
      cg_layer.sample();
    end
  endfunction

  function void write_npu_cov_done(bit sat);
    cov_sat = sat;
    cg_done.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("NPU_COV", $sformatf(
      "coverage: program=%.1f%% layer=%.1f%% done=%.1f%%",
      cg_program.get_inst_coverage(), cg_layer.get_inst_coverage(),
      cg_done.get_inst_coverage()), UVM_LOW)
  endfunction

endclass : npu_coverage
