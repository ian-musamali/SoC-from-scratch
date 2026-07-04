// -----------------------------------------------------------------------------
// Display stub (Phase 7): latches the classification result and drives simple
// LED indicators. This is the seam where a real display controller (7-seg,
// HDMI, ...) plugs in later without touching tinynpu_top:
//   led_class - one-hot latched class (cat/truck/plane/ship), clear on reset
//   led_busy  - live NPU-running indicator
//   led_sat   - latched "saturation occurred during the last run"
// -----------------------------------------------------------------------------
module display_stub (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       result_valid,  // 1-cycle pulse
  input  logic [1:0] class_idx,     // valid with result_valid
  input  logic       busy,
  input  logic       sat,           // valid with result_valid
  output logic [3:0] led_class,
  output logic       led_busy,
  output logic       led_sat
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      led_class <= '0;
      led_sat   <= 1'b0;
    end else if (result_valid) begin
      led_class <= 4'b0001 << class_idx;
      led_sat   <= sat;
    end
  end

  assign led_busy = busy;

endmodule : display_stub
