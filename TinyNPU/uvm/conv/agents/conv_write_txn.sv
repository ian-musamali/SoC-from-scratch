// -----------------------------------------------------------------------------
// One observed OFM write ({addr, data}), published by conv_monitor on
// ap_write and consumed by conv_scoreboard. Included before conv_monitor.
// -----------------------------------------------------------------------------
class conv_write_txn extends uvm_object;

  bit [FM_ADDR_W-1:0] addr;
  bit [DATA_W-1:0]    data;

  `uvm_object_utils(conv_write_txn)

  function new(string name = "conv_write_txn");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("ofm write addr=0x%04h data=0x%02h", addr, data);
  endfunction

endclass : conv_write_txn
