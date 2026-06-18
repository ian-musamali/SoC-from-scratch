# Fixed-Point Arithmetic: Q16.16

## Format

Q16.16 stores a signed real number in a 32-bit two's-complement integer:
- Bits [31:16]: signed integer part (−32768 to +32767)
- Bits [15:0]: fractional part (resolution = 1/65536 ≈ 0.0000153)

Value = raw_integer / 65536.0

## Why Q16.16

| Criterion | Rationale |
|-----------|-----------|
| Register width | Fits exactly in one 32-bit register — matches PicoRV32 ALU width and AXI data bus |
| Map precision | 64×64 map with sub-cell resolution of 1/65536; error < 0.02% of one map cell |
| Distance range | Integer part covers 0–32767 map units; DDA never exceeds this on a 64×64 map |
| Multiply hardware | 32×32 → 64-bit product in one DSP48/flop cycle; common in Artix-7 |

## Range and Precision

- Maximum positive: 32767 + (65535/65536) ≈ 32767.99998
- Minimum (most negative): −32768.0
- Resolution: 1/65536 ≈ 1.526 × 10⁻⁵

For the DDA raycaster operating on a 64×64 map, all coordinates, ray directions (magnitude ≤ 1.0), and wall distances (≤ 90.5 for diagonal) fit within the Q16.16 range without saturation.

## Overflow Cases

The integer part is 16 bits: overflow occurs when |value| ≥ 32768. This is **impossible** for the DDA raycaster because:
- Map dimensions are 64×64 (coordinates ≤ 64)
- Ray direction components are always in [−1.0, +1.0]
- Perpendicular distances are bounded by sqrt(64² + 64²) ≈ 90.5 << 32767

The fpdiv result could overflow if denominator ≈ 0 (very grazing ray). The DDA algorithm avoids this by clamping delta_dist when ray_dir ≈ 0 (map-aligned rays hit a wall after at most 64 steps).

## Multiply Implementation

```
product_full[63:0] = $signed(a) * $signed(b)   // 64-bit signed product
result[31:0]       = product_full[47:16]         // extract Q16.16 bits
```

- Bits [63:48]: sign extension / overflow — discarded (correct for inputs within range)
- Bits [47:16]: the Q16.16 result
- Bits [15:0]: sub-fractional bits — discarded (rounds toward zero)

Latency: 1 clock cycle (registered multiply). Vivado maps to DSP48E1.

## Divide Implementation

```
dividend_extended = abs_num << 16          // 48-bit unsigned
quotient = dividend_extended / abs_den     // 32-bit unsigned via restoring division
```

The 48-cycle restoring division processes all 48 bits of the extended dividend, building the 32-bit quotient from MSB to LSB. The 32-bit `quotient_r` register naturally captures the correct bits because it truncates the 48-bit quotient to its lower 32 bits (the valid Q16.16 range).

Sign: computed separately from input signs, applied to result on completion.

Latency: 50 clock cycles (2 overhead + 48 division steps).

## Simulation Results

| Test | Expected | Got | Status |
|------|----------|-----|--------|
| fpmul: 1.0×1.0 | 1.0 | 1.0 | PASS |
| fpmul: 1.5×2.0 | 3.0 | 3.0 | PASS |
| fpmul: −1.0×1.0 | −1.0 | −1.0 | PASS |
| fpmul: 0×3.14 | 0.0 | 0.0 | PASS |
| fpmul: 100×100 | 10000 | 10000 | PASS |
| fpmul: 0.5×0.5 | 0.25 | 0.25 | PASS |
| fpdiv: 4.0/2.0 | 2.0 | 2.0 | PASS |
| fpdiv: 1.0/4.0 | 0.25 | 0.25 | PASS |
| fpdiv: −3.0/1.0 | −3.0 | −3.0 | PASS |
| fpdiv: −6.0/−2.0 | 3.0 | 3.0 | PASS |
| fpdiv: 3.0/4.0 | 0.75 | 0.75 | PASS |
| fpdiv: div_by_zero | flag | flag | PASS |
