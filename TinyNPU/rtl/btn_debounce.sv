// -----------------------------------------------------------------------------
// Button debouncer: 2-flop synchronizer, then the synchronized level must be
// stable for 2^CNT_W cycles before it is accepted. `pressed` is a 1-cycle
// pulse on each accepted rising edge (Phase 7). CNT_W=16 at 100 MHz gives a
// ~0.66 ms stability window; simulation overrides it small.
// -----------------------------------------------------------------------------
module btn_debounce #(
  parameter int CNT_W = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic btn_in,    // raw, asynchronous, active-high
  output logic pressed    // 1-cycle pulse on debounced rising edge
);

  logic             sync0, sync1;
  logic             stable_q, stable_d1;
  logic [CNT_W-1:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync0     <= 1'b0;
      sync1     <= 1'b0;
      stable_q  <= 1'b0;
      stable_d1 <= 1'b0;
      cnt       <= '0;
      pressed   <= 1'b0;
    end else begin
      sync0 <= btn_in;
      sync1 <= sync0;

      if (sync1 == stable_q) begin
        cnt <= '0;
      end else begin
        cnt <= cnt + 1'b1;
        if (&cnt) begin
          stable_q <= sync1;
          cnt      <= '0;
        end
      end

      stable_d1 <= stable_q;
      pressed   <= stable_q & ~stable_d1;
    end
  end

endmodule : btn_debounce
