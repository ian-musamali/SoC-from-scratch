#!/usr/bin/env python3
"""TinyNPU golden reference model for the MAC array (Phase 2).

Implements the exact integer math mac_array.sv performs, bit-for-bit:

    dot     = sum(act[i] * wgt[i] for i in range(num_lanes))   # exact integers
    full    = dot + acc_in                                     # exact integers
    acc_out = clamp(full, -2**(acc_w-1), 2**(acc_w-1) - 1)
    sat     = (full != acc_out)

All values are signed two's complement: act/wgt are data_w-bit, acc_in and
acc_out are acc_w-bit. Python's unbounded ints make the intermediate math
exact, which matches the RTL because the RTL computes dot and full in
max(2*data_w + clog2(num_lanes), acc_w) + 1 bits before saturating -- wide
enough that nothing wraps pre-saturation. No floating point anywhere.
"""

NUM_LANES = 64
DATA_W = 8
ACC_W = 32


def mac_golden(act, wgt, acc_in, num_lanes=NUM_LANES, data_w=DATA_W, acc_w=ACC_W):
    """Return (acc_out, sat_flag) for one MAC array transaction.

    act, wgt: sequences of num_lanes signed ints in [-2**(data_w-1), 2**(data_w-1)-1]
    acc_in:   signed int in [-2**(acc_w-1), 2**(acc_w-1)-1]
    """
    assert len(act) == num_lanes and len(wgt) == num_lanes
    dmin, dmax = -(1 << (data_w - 1)), (1 << (data_w - 1)) - 1
    amin, amax = -(1 << (acc_w - 1)), (1 << (acc_w - 1)) - 1
    assert all(dmin <= v <= dmax for v in act), "activation out of range"
    assert all(dmin <= v <= dmax for v in wgt), "weight out of range"
    assert amin <= acc_in <= amax, "acc_in out of range"

    dot = sum(a * w for a, w in zip(act, wgt))
    full = dot + acc_in

    if full > amax:
        return amax, 1
    if full < amin:
        return amin, 1
    return full, 0


def _self_test():
    amax = (1 << (ACC_W - 1)) - 1
    amin = -(1 << (ACC_W - 1))
    z = [0] * NUM_LANES
    ones = [1] * NUM_LANES

    # acc_in passthrough with zero dot product
    assert mac_golden(z, z, 0) == (0, 0)
    assert mac_golden(z, z, -12345) == (-12345, 0)
    # simple dot products
    assert mac_golden(ones, ones, 0) == (64, 0)
    assert mac_golden(ones, [-1] * NUM_LANES, 10) == (-54, 0)
    # extreme lane values: (-128 * -128) * 64 = 1048576
    assert mac_golden([-128] * NUM_LANES, [-128] * NUM_LANES, 0) == (1 << 20, 0)
    # positive saturation and exact non-saturating boundary
    assert mac_golden(ones, ones, amax) == (amax, 1)
    assert mac_golden(ones, ones, amax - 64) == (amax, 0)
    assert mac_golden(ones, ones, amax - 63) == (amax, 1)
    # negative saturation and exact non-saturating boundary
    assert mac_golden(ones, [-1] * NUM_LANES, amin) == (amin, 1)
    assert mac_golden(ones, [-1] * NUM_LANES, amin + 64) == (amin, 0)
    assert mac_golden(ones, [-1] * NUM_LANES, amin + 63) == (amin, 1)
    print("golden_mac_model self-test: all checks passed")


if __name__ == "__main__":
    _self_test()
