#!/usr/bin/env python3
"""Emit conv_engine and npu_core test cases (Phase 4-6).

Layout (under --outdir, default ../vectors):

conv/<case>/            one conv_engine start (one output channel)
  cfg.txt               single line: img_w img_h in_ch stride pad out_shift
                        ifm_base ofm_base wgt_base (decimal) acc_init (8-hex)
  ifm.memh, wgt.memh    $readmemh images (with @base offsets; loader zeroes
                        the memory first)
  mac_trace.txt         expected MAC request + golden response per pass, in
                        order, in the Phase-3 131-field format
                        (64 act, 64 wgt, acc_in, acc_out, sat)
  ofm_trace.txt         expected int8 output writes in order: addr(4hex) data(2hex)
conv/<suite>_manifest.txt   case dir names, one per line

npu/<case>/             one npu_core start (a whole layer program)
  descs.txt             line 1: num_layers (decimal); then one packed 67-bit
                        descriptor per layer (17 hex chars, layer 0 first)
  fm_init.memh          initial unified fm buffer contents (@base regions)
  wgt.memh              weight memory (@base regions)
  write_trace.txt       every expected fm write in order: addr(4hex) data(2hex)
  fm_final.memh         full expected fm buffer (all 2**FM_ADDR_W entries)
npu/<suite>_manifest.txt
"""

import argparse
import os
import random

from golden_mac_model import DATA_W, ACC_W
from golden_conv_model import (K, FM_ADDR_W, WGT_ADDR_W, out_dim, pack_desc,
                               run_conv_channel, run_program)

DMIN, DMAX = -(1 << (DATA_W - 1)), (1 << (DATA_W - 1)) - 1


def h8(v):
    return format(v & 0xFF, "02x")


def h32(v):
    return format(v & 0xFFFFFFFF, "08x")


def write_memh(path, regions):
    """regions: list of (base, values)."""
    with open(path, "w") as f:
        for base, vals in regions:
            f.write(f"@{base:x}\n")
            f.write("\n".join(h8(v) for v in vals) + "\n")


def write_full_memh(path, mem):
    with open(path, "w") as f:
        f.write("@0\n")
        f.write("\n".join(h8(v) for v in mem) + "\n")


def write_trace_file(path, header, rows):
    with open(path, "w") as f:
        f.write(f"# {header}\n")
        for addr, val in rows:
            f.write(f"{addr:04x} {h8(val)}\n")


def write_mac_trace(path, passes):
    with open(path, "w") as f:
        f.write("# fields: act[0..63] wgt[0..63] acc_in acc_out sat (hex)\n")
        for a, w, acc_in, acc_out, sat in passes:
            fields = [h8(x) for x in a] + [h8(x) for x in w]
            fields += [h32(acc_in), h32(acc_out), str(sat)]
            f.write(" ".join(fields) + "\n")


def emit_conv_case(outdir, name, cfg, ifm_vals, wgt_vals):
    """ifm_vals sits at cfg['ifm_base'] in fm space; wgt_vals at cfg['wgt_base']."""
    case = os.path.join(outdir, "conv", name)
    os.makedirs(case, exist_ok=True)

    fm = [0] * (1 << FM_ADDR_W)
    fm[cfg["ifm_base"]:cfg["ifm_base"] + len(ifm_vals)] = ifm_vals
    wm = [0] * (1 << WGT_ADDR_W)
    wm[cfg["wgt_base"]:cfg["wgt_base"] + len(wgt_vals)] = wgt_vals

    mac_trace, ofm_writes, _sat = run_conv_channel(fm, wm, cfg)

    with open(os.path.join(case, "cfg.txt"), "w") as f:
        f.write(f"{cfg['img_w']} {cfg['img_h']} {cfg['in_ch']} {cfg['stride']} "
                f"{cfg['pad']} {cfg['out_shift']} {cfg['ifm_base']} "
                f"{cfg['ofm_base']} {cfg['wgt_base']} {h32(cfg['acc_init'])}\n")
    write_memh(os.path.join(case, "ifm.memh"), [(cfg["ifm_base"], ifm_vals)])
    write_memh(os.path.join(case, "wgt.memh"), [(cfg["wgt_base"], wgt_vals)])
    write_mac_trace(os.path.join(case, "mac_trace.txt"), mac_trace)
    write_trace_file(os.path.join(case, "ofm_trace.txt"),
                     "expected ofm writes: addr data", ofm_writes)
    return name


def emit_npu_case(outdir, name, descs, fm_regions, wgt_regions):
    """descs: list of dicts (with 'stride' 1/2). fm_regions/wgt_regions: (base, vals)."""
    case = os.path.join(outdir, "npu", name)
    os.makedirs(case, exist_ok=True)

    fm = [0] * (1 << FM_ADDR_W)
    for base, vals in fm_regions:
        fm[base:base + len(vals)] = vals
    wm = [0] * (1 << WGT_ADDR_W)
    for base, vals in wgt_regions:
        wm[base:base + len(vals)] = vals

    write_memh(os.path.join(case, "fm_init.memh"), fm_regions)
    write_memh(os.path.join(case, "wgt.memh"), wgt_regions)

    trace, _sat = run_program(fm, wm, descs)  # mutates fm to final state

    with open(os.path.join(case, "descs.txt"), "w") as f:
        f.write(f"{len(descs)}\n")
        for d in descs:
            f.write(format(pack_desc(d), "017x") + "\n")
    write_trace_file(os.path.join(case, "write_trace.txt"),
                     "expected fm writes: addr data", trace)
    write_full_memh(os.path.join(case, "fm_final.memh"), fm)
    return name


def write_manifest(outdir, kind, suite, names):
    path = os.path.join(outdir, kind, f"{suite}_manifest.txt")
    with open(path, "w") as f:
        f.write(f"# {kind} suite: {suite}\n")
        f.write("\n".join(names) + "\n")
    print(f"wrote {path} ({len(names)} case(s))")


def rand_bytes(rng, n, extremes=False):
    if extremes:
        return [rng.choice([DMIN, DMAX, -1, 0, 1]) for _ in range(n)]
    return [rng.randint(DMIN, DMAX) for _ in range(n)]


# ----------------------------------------------------------------------------
# conv_engine suites
# ----------------------------------------------------------------------------

def conv_suites(outdir, rng):
    names = []
    # smoke: 4x4 single channel, identity-ish kernel, easy to eyeball
    cfg = dict(img_w=4, img_h=4, in_ch=1, stride=1, pad=1, out_shift=0,
               ifm_base=0, ofm_base=64, wgt_base=0, acc_init=0)
    wgt = [0] * 9
    wgt[4] = 1  # center tap
    names.append(emit_conv_case(outdir, "smoke_4x4_identity", cfg,
                                list(range(-8, 8)), wgt))
    write_manifest(outdir, "conv", "smoke", names)

    # stride/pad corner cases (all four stride x pad combos + minimum dims)
    names = []
    cases = [
        ("sp_5x5_s1_p0", dict(img_w=5, img_h=5, in_ch=1, stride=1, pad=0)),
        ("sp_5x5_s2_p1", dict(img_w=5, img_h=5, in_ch=1, stride=2, pad=1)),
        ("sp_4x4_s2_p0", dict(img_w=4, img_h=4, in_ch=1, stride=2, pad=0)),
        ("sp_1x1_s1_p1", dict(img_w=1, img_h=1, in_ch=1, stride=1, pad=1)),
        ("sp_32x6_s2_p1", dict(img_w=32, img_h=6, in_ch=1, stride=2, pad=1)),
    ]
    for name, c in cases:
        c.update(out_shift=0, ifm_base=rng.choice([0, 512]),
                 ofm_base=4096, wgt_base=rng.choice([0, 64]), acc_init=0)
        n = c["img_w"] * c["img_h"]
        names.append(emit_conv_case(outdir, name, c,
                                    rand_bytes(rng, n), rand_bytes(rng, 9)))
    write_manifest(outdir, "conv", "stride_pad", names)

    # multichannel + multi-pass + saturation
    names = []
    c3 = dict(img_w=6, img_h=6, in_ch=3, stride=1, pad=1, out_shift=2,
              ifm_base=0, ofm_base=256, wgt_base=0, acc_init=0)
    names.append(emit_conv_case(outdir, "mc_6x6_ch3", c3,
                                rand_bytes(rng, 3 * 36), rand_bytes(rng, 27)))
    c8 = dict(img_w=4, img_h=4, in_ch=8, stride=1, pad=1, out_shift=0,
              ifm_base=128, ofm_base=1024, wgt_base=32, acc_init=0)
    names.append(emit_conv_case(outdir, "mc_4x4_ch8_multipass", c8,
                                rand_bytes(rng, 8 * 16), rand_bytes(rng, 72)))
    csat = dict(img_w=3, img_h=3, in_ch=8, stride=1, pad=0, out_shift=0,
                ifm_base=0, ofm_base=512, wgt_base=0,
                acc_init=(1 << (ACC_W - 1)) - 1 - (1 << 10))  # near +rail
    names.append(emit_conv_case(outdir, "mc_3x3_ch8_saturate", csat,
                                rand_bytes(rng, 8 * 9, extremes=True),
                                rand_bytes(rng, 72, extremes=True)))
    write_manifest(outdir, "conv", "multichannel", names)

    # constrained-random
    names = []
    for i in range(8):
        stride = rng.choice([1, 2])
        pad = rng.choice([0, 1])
        while True:
            w, h = rng.randint(3, 12), rng.randint(3, 12)
            if out_dim(w, pad, stride) >= 1 and out_dim(h, pad, stride) >= 1:
                break
        in_ch = rng.choice([1, 2, 3, 4, 8])
        c = dict(img_w=w, img_h=h, in_ch=in_ch, stride=stride, pad=pad,
                 out_shift=rng.randint(0, 7),
                 ifm_base=rng.choice([0, 1024, 4096]),
                 ofm_base=rng.choice([8192, 12288]),
                 wgt_base=rng.choice([0, 128, 1000]),
                 acc_init=rng.choice([0, 0, rng.randint(-(1 << 16), 1 << 16)]))
        names.append(emit_conv_case(outdir, f"rand_{i}", c,
                                    rand_bytes(rng, in_ch * w * h, extremes=(i % 3 == 0)),
                                    rand_bytes(rng, in_ch * 9)))
    write_manifest(outdir, "conv", "random", names)


# ----------------------------------------------------------------------------
# npu_core suites
# ----------------------------------------------------------------------------

def npu_suites(outdir, rng):
    # smoke: 1 layer, 4x4x1 -> out_ch 2
    names = []
    d0 = dict(img_w=4, img_h=4, in_ch=1, out_ch=2, stride=1, pad=1,
              out_shift=1, ifm_base=0, ofm_base=8192, wgt_base=0)
    names.append(emit_npu_case(outdir, "smoke_1layer", [d0],
                               [(0, rand_bytes(rng, 16))],
                               [(0, rand_bytes(rng, 2 * 9))]))
    write_manifest(outdir, "npu", "smoke", names)

    # multilayer: directed 3-layer ping-pong + CIFAR-shaped 5-layer program
    names = []
    ml = [dict(img_w=8, img_h=8, in_ch=3, out_ch=4, stride=2, pad=1,
               out_shift=4, ifm_base=0, ofm_base=8192, wgt_base=0),
          dict(img_w=4, img_h=4, in_ch=4, out_ch=4, stride=1, pad=1,
               out_shift=4, ifm_base=8192, ofm_base=0, wgt_base=108),
          dict(img_w=4, img_h=4, in_ch=4, out_ch=4, stride=2, pad=0,
               out_shift=3, ifm_base=0, ofm_base=8192, wgt_base=252)]
    wtotal = 108 + 144 + 144
    names.append(emit_npu_case(outdir, "ml_3layer_pingpong", ml,
                               [(0, rand_bytes(rng, 3 * 64))],
                               [(0, rand_bytes(rng, wtotal))]))

    cifar = []
    dims, ch = 32, 3
    bases = [0, 8192]
    wb = 0
    chans = [8, 8, 8, 8, 4]  # -> 16,8,4,2,1 spatial; final 1x1x4 = 4 classes
    for li, oc in enumerate(chans):
        cifar.append(dict(img_w=dims, img_h=dims, in_ch=ch, out_ch=oc,
                          stride=2, pad=1, out_shift=5,
                          ifm_base=bases[li % 2], ofm_base=bases[(li + 1) % 2],
                          wgt_base=wb))
        wb += oc * ch * K * K
        dims = out_dim(dims, 1, 2)
        ch = oc
    names.append(emit_npu_case(outdir, "ml_cifar_shape_32x32", cifar,
                               [(0, rand_bytes(rng, 3 * 32 * 32))],
                               [(0, rand_bytes(rng, wb))]))
    write_manifest(outdir, "npu", "multilayer", names)

    # random programs
    names = []
    for i in range(4):
        nl = rng.randint(1, 3)
        w = rng.randint(4, 10)
        h = rng.randint(4, 10)
        ch = rng.randint(1, 3)
        wb = 0
        descs = []
        for li in range(nl):
            while True:
                stride = rng.choice([1, 2])
                pad = rng.choice([0, 1])
                ow, oh = out_dim(w, pad, stride), out_dim(h, pad, stride)
                if ow >= 1 and oh >= 1:
                    break
            oc = rng.randint(1, 4)
            descs.append(dict(img_w=w, img_h=h, in_ch=ch, out_ch=oc,
                              stride=stride, pad=pad,
                              out_shift=rng.randint(0, 5),
                              ifm_base=8192 * (li % 2),
                              ofm_base=8192 * ((li + 1) % 2),
                              wgt_base=wb))
            wb += oc * ch * K * K
            w, h, ch = ow, oh, oc
        names.append(emit_npu_case(outdir, f"rand_prog_{i}", descs,
                                   [(descs[0]["ifm_base"],
                                     rand_bytes(rng, descs[0]["in_ch"] *
                                                descs[0]["img_w"] * descs[0]["img_h"]))],
                                   [(0, rand_bytes(rng, wb))]))
    write_manifest(outdir, "npu", "random", names)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--outdir", default="../vectors")
    p.add_argument("--seed", type=int, default=1)
    args = p.parse_args()
    rng = random.Random(args.seed)
    conv_suites(args.outdir, rng)
    npu_suites(args.outdir, rng)


if __name__ == "__main__":
    main()
