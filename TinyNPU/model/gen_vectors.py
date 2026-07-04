#!/usr/bin/env python3
"""Emit MAC array test vectors (inputs + golden expected outputs) for UVM.

Vector file format (read by the UVM sequences and scoreboard with $fscanf):
  - lines starting with '#' are comments
  - each transaction is one line of 131 whitespace-separated lowercase hex
    fields, two's complement, fixed width:
      fields [0..63]    act lane 0..63   (2 hex digits, signed int8)
      fields [64..127]  wgt lane 0..63   (2 hex digits, signed int8)
      field  [128]      acc_in           (8 hex digits, signed int32)
      field  [129]      expected acc_out (8 hex digits, signed int32)
      field  [130]      expected sat_flag (1 digit, 0/1)

Files produced (in --outdir):
  smoke.txt    directed known-answer cases
  overflow.txt directed saturation and exact-boundary cases
  random.txt   constrained-random transactions (--random-count, default 500)
  reset.txt    random transactions for the reset-during-active test
"""

import argparse
import random

from golden_mac_model import mac_golden, NUM_LANES, DATA_W, ACC_W

DMIN, DMAX = -(1 << (DATA_W - 1)), (1 << (DATA_W - 1)) - 1
AMIN, AMAX = -(1 << (ACC_W - 1)), (1 << (ACC_W - 1)) - 1


def h8(v):
    return format(v & 0xFF, "02x")


def h32(v):
    return format(v & 0xFFFFFFFF, "08x")


def line(act, wgt, acc_in):
    acc_out, sat = mac_golden(act, wgt, acc_in)
    fields = [h8(a) for a in act] + [h8(w) for w in wgt]
    fields += [h32(acc_in), h32(acc_out), str(sat)]
    return " ".join(fields)


def directed_smoke():
    z = [0] * NUM_LANES
    ones = [1] * NUM_LANES
    cases = [
        (z, z, 0),                                    # all zero
        (z, z, 1234567),                              # acc_in passthrough
        (z, z, -1234567),                             # negative passthrough
        (ones, ones, 0),                              # dot = 64
        (ones, [-1] * NUM_LANES, 0),                  # dot = -64
        ([2] * NUM_LANES, [3] * NUM_LANES, 100),      # dot = 384 + 100
        ([DMAX] * NUM_LANES, [DMAX] * NUM_LANES, 0),  # 127*127*64
        ([DMIN] * NUM_LANES, [DMIN] * NUM_LANES, 0),  # (-128)^2*64 = 2^20
        ([DMIN] * NUM_LANES, [DMAX] * NUM_LANES, 0),  # most negative dot
        (list(range(-32, 32)), list(range(64)), -500),  # ramp patterns
        ([5] + z[1:], [7] + z[1:], 0),                # single active lane
        (z[:-1] + [DMIN], z[:-1] + [DMAX], AMIN + (1 << 16)),  # last lane only
    ]
    return [line(a, w, c) for a, w, c in cases]


def directed_overflow():
    z = [0] * NUM_LANES
    ones = [1] * NUM_LANES
    neg = [-1] * NUM_LANES
    maxdot = [DMIN] * NUM_LANES  # paired with itself: dot = +2^20
    cases = [
        (ones, ones, AMAX),            # positive saturation
        (maxdot, maxdot, AMAX),        # deep positive saturation
        (ones, ones, AMAX - 64),       # exact boundary, no saturation
        (ones, ones, AMAX - 63),       # boundary + 1, saturates
        (ones, neg, AMIN),             # negative saturation
        ([DMIN] * NUM_LANES, [DMAX] * NUM_LANES, AMIN),  # deep negative saturation
        (ones, neg, AMIN + 64),        # exact boundary, no saturation
        (ones, neg, AMIN + 63),        # boundary - 1, saturates
        (z, z, AMAX),                  # extremes without saturation
        (z, z, AMIN),
        ([1] + z[1:], [1] + z[1:], AMAX - 1),  # dot=1 onto AMAX-1: lands on AMAX, no sat
        ([1] + z[1:], [1] + z[1:], AMAX),      # dot=1 onto AMAX: saturates by 1
        ([-1] + z[1:], [1] + z[1:], AMIN + 1),
        ([-1] + z[1:], [1] + z[1:], AMIN),
    ]
    return [line(a, w, c) for a, w, c in cases]


def rand_lane_vec(rng, profile):
    if profile == "uniform":
        return [rng.randint(DMIN, DMAX) for _ in range(NUM_LANES)]
    if profile == "small":
        return [rng.randint(-4, 4) for _ in range(NUM_LANES)]
    if profile == "sparse":
        return [rng.randint(DMIN, DMAX) if rng.random() < 0.15 else 0
                for _ in range(NUM_LANES)]
    # extremes
    return [rng.choice([DMIN, DMAX, -1, 0, 1]) for _ in range(NUM_LANES)]


def rand_acc_in(rng, profile):
    if profile == "zero":
        return 0
    if profile == "uniform":
        return rng.randint(AMIN, AMAX)
    if profile == "near_max":  # dot product can push past AMAX
        return AMAX - rng.randint(0, 1 << 21)
    if profile == "near_min":
        return AMIN + rng.randint(0, 1 << 21)
    return rng.randint(-(1 << 16), 1 << 16)  # moderate


def random_vectors(rng, count):
    lane_profiles = ["uniform", "small", "sparse", "extremes"]
    acc_profiles = ["zero", "uniform", "near_max", "near_min", "moderate"]
    out = []
    for _ in range(count):
        act = rand_lane_vec(rng, rng.choice(lane_profiles))
        wgt = rand_lane_vec(rng, rng.choice(lane_profiles))
        acc = rand_acc_in(rng, rng.choice(acc_profiles))
        out.append(line(act, wgt, acc))
    return out


def write(path, header, lines):
    with open(path, "w") as f:
        f.write(f"# {header}\n")
        f.write("# fields: act[0..63] wgt[0..63] acc_in exp_acc_out exp_sat (hex)\n")
        f.write("\n".join(lines) + "\n")
    print(f"wrote {path} ({len(lines)} transactions)")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--outdir", default="../vectors")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--random-count", type=int, default=500)
    p.add_argument("--reset-count", type=int, default=40)
    args = p.parse_args()

    rng = random.Random(args.seed)
    write(f"{args.outdir}/smoke.txt", "directed smoke vectors", directed_smoke())
    write(f"{args.outdir}/overflow.txt", "directed saturation/boundary vectors",
          directed_overflow())
    write(f"{args.outdir}/random.txt",
          f"constrained-random vectors (seed={args.seed})",
          random_vectors(rng, args.random_count))
    write(f"{args.outdir}/reset.txt",
          f"vectors for reset-during-active test (seed={args.seed})",
          random_vectors(rng, args.reset_count))


if __name__ == "__main__":
    main()
