#!/usr/bin/env python3
"""TinyNPU golden reference for the convolution engine and NPU core (Phase 4-6).

Bit-exact contract shared with conv_engine.sv / npu_core.sv:

One conv_engine `start` computes ONE output channel:
  out_w = (img_w + 2*pad - K) // s + 1   (s = 1 or 2, K = 3), same for out_h
  for each output pixel (or_, oc_) in row-major order:
    taps t = 0 .. in_ch*K*K - 1 ordered t = (ch*K + ky)*K + kx
      r = or_*s + ky - pad ; c = oc_*s + kx - pad
      act[t] = 0 if r/c outside the image else ifm[ifm_base + (ch*img_h + r)*img_w + c]
      wgt[t] = wgt_mem[wgt_base + t]
    taps are packed lane-major into NUM_LANES-wide MAC transactions
    (pass p = t // NUM_LANES, lane = t % NUM_LANES, unused lanes 0/0);
    passes are chained through acc_in: pass 0 uses acc_init, pass p uses the
    saturated result of pass p-1 (exact mac_golden math).
    final = last pass result; shifted = final >> out_shift (arithmetic);
    q = clamp(shifted, -2**(DATA_W-1), 2**(DATA_W-1)-1)  -> written to
    ofm_addr = ofm_base + or_*out_w + oc_
  sat_seen = OR of every MAC sat flag and every int8 clamp event.

npu_core runs a descriptor program: for each layer, for each output channel
oc, one conv pass with wgt_base = layer.wgt_base + oc*in_ch*K*K and
ofm_base = layer.ofm_base + oc*out_w*out_h, acc_init = 0. All reads/writes
target one unified int8 feature-map buffer.
"""

from golden_mac_model import mac_golden, NUM_LANES, DATA_W, ACC_W

K = 3
DMIN, DMAX = -(1 << (DATA_W - 1)), (1 << (DATA_W - 1)) - 1

# Descriptor packing (must match layer_desc_t in tinynpu_pkg.sv, MSB..LSB):
# img_w[6] img_h[6] in_ch[4] out_ch[4] stride2[1] pad[1] out_shift[5]
# ifm_base[14] ofm_base[14] wgt_base[12]  -> 67 bits
FM_ADDR_W = 14
WGT_ADDR_W = 12
LAYER_DESC_W = 67


def out_dim(dim, pad, stride):
    return (dim + 2 * pad - K) // stride + 1


def pack_desc(d):
    """d: dict with img_w img_h in_ch out_ch stride pad out_shift
    ifm_base ofm_base wgt_base. Returns 67-bit int."""
    v = 0
    for val, width in [(d["img_w"], 6), (d["img_h"], 6), (d["in_ch"], 4),
                       (d["out_ch"], 4), (1 if d["stride"] == 2 else 0, 1),
                       (d["pad"], 1), (d["out_shift"], 5),
                       (d["ifm_base"], FM_ADDR_W), (d["ofm_base"], FM_ADDR_W),
                       (d["wgt_base"], WGT_ADDR_W)]:
        assert 0 <= val < (1 << width), f"descriptor field overflow: {val} in {width} bits"
        v = (v << width) | val
    return v


def gather_window(fm, ifm_base, img_w, img_h, in_ch, pad, stride, or_, oc_):
    """Return the act tap list for output pixel (or_, oc_)."""
    acts = []
    for ch in range(in_ch):
        for ky in range(K):
            for kx in range(K):
                r = or_ * stride + ky - pad
                c = oc_ * stride + kx - pad
                if 0 <= r < img_h and 0 <= c < img_w:
                    acts.append(fm[ifm_base + (ch * img_h + r) * img_w + c])
                else:
                    acts.append(0)
    return acts


def conv_pixel(acts, wgts, acc_init, out_shift):
    """Multi-pass MAC chaining + requantization for one output pixel.
    Returns (q, mac_passes, sat_seen) where mac_passes is a list of
    (act64, wgt64, acc_in, acc_out, sat) tuples (already lane-padded)."""
    assert len(acts) == len(wgts)
    acc = acc_init
    passes = []
    sat_seen = 0
    for p in range(0, len(acts), NUM_LANES):
        a = acts[p:p + NUM_LANES]
        w = wgts[p:p + NUM_LANES]
        a += [0] * (NUM_LANES - len(a))
        w += [0] * (NUM_LANES - len(w))
        acc_out, sat = mac_golden(a, w, acc)
        passes.append((a, w, acc, acc_out, sat))
        sat_seen |= sat
        acc = acc_out
    shifted = acc >> out_shift  # Python >> on ints is arithmetic/floor: matches SV >>>
    q = max(DMIN, min(DMAX, shifted))
    if q != shifted:
        sat_seen = 1
    return q, passes, sat_seen


def run_conv_channel(fm, wgt_mem, cfg):
    """One conv_engine start (one output channel).
    cfg: img_w img_h in_ch stride pad out_shift ifm_base ofm_base wgt_base acc_init
    Returns (mac_trace, ofm_writes, sat_seen); ofm_writes applied to nothing --
    caller decides whether to commit them to fm."""
    ow = out_dim(cfg["img_w"], cfg["pad"], cfg["stride"])
    oh = out_dim(cfg["img_h"], cfg["pad"], cfg["stride"])
    assert ow >= 1 and oh >= 1, "config yields empty output"
    taps = cfg["in_ch"] * K * K
    wgts = [wgt_mem[cfg["wgt_base"] + t] for t in range(taps)]
    mac_trace = []
    ofm_writes = []
    sat_seen = 0
    for or_ in range(oh):
        for oc_ in range(ow):
            acts = gather_window(fm, cfg["ifm_base"], cfg["img_w"], cfg["img_h"],
                                 cfg["in_ch"], cfg["pad"], cfg["stride"], or_, oc_)
            q, passes, sat = conv_pixel(acts, wgts, cfg["acc_init"], cfg["out_shift"])
            mac_trace.extend(passes)
            ofm_writes.append((cfg["ofm_base"] + or_ * ow + oc_, q))
            sat_seen |= sat
    return mac_trace, ofm_writes, sat_seen


def run_program(fm, wgt_mem, descs):
    """npu_core golden: execute layer descriptors in order against the unified
    fm buffer (mutates fm). Returns (write_trace, sat_seen)."""
    write_trace = []
    sat_seen = 0
    for d in descs:
        ow = out_dim(d["img_w"], d["pad"], d["stride"])
        oh = out_dim(d["img_h"], d["pad"], d["stride"])
        taps = d["in_ch"] * K * K
        for oc in range(d["out_ch"]):
            cfg = dict(d)
            cfg["wgt_base"] = d["wgt_base"] + oc * taps
            cfg["ofm_base"] = d["ofm_base"] + oc * ow * oh
            cfg["acc_init"] = 0
            _, writes, sat = run_conv_channel(fm, wgt_mem, cfg)
            for addr, val in writes:
                fm[addr] = val
                write_trace.append((addr, val))
            sat_seen |= sat
    return write_trace, sat_seen


def _self_test():
    # 3x3 single-channel image, identity kernel (center tap = 1), stride 1,
    # pad 1, shift 0 -> output reproduces the image exactly.
    img = [10, -20, 30, -40, 50, -60, 70, -80, 127]
    fm = list(img) + [0] * 100
    wgt = [0] * 9
    wgt[(0 * K + 1) * K + 1] = 1  # ch0, ky=1, kx=1
    cfg = dict(img_w=3, img_h=3, in_ch=1, stride=1, pad=1, out_shift=0,
               ifm_base=0, ofm_base=50, wgt_base=0, acc_init=0)
    _, writes, sat = run_conv_channel(fm, wgt, cfg)
    assert [v for _, v in writes] == img and sat == 0
    assert [a for a, _ in writes] == list(range(50, 59))

    # 2x2, no pad, stride 1 -> single output = full 2x2..3x3 window sum;
    # all-ones 3x3 kernel over 2x2 image without pad is invalid (out_dim 0),
    # so use 3x3 image no pad: out 1x1 = sum of all 9 pixels.
    fm2 = list(range(1, 10)) + [0] * 20
    _, w2, _ = run_conv_channel(fm2, [1] * 9,
                                dict(img_w=3, img_h=3, in_ch=1, stride=1, pad=0,
                                     out_shift=0, ifm_base=0, ofm_base=0,
                                     wgt_base=0, acc_init=0))
    assert w2 == [(0, 45)]

    # shift + int8 clamp: acc 45 with shift 1 -> 22; acc_init pushes clamp
    _, w3, sat3 = run_conv_channel(fm2, [1] * 9,
                                   dict(img_w=3, img_h=3, in_ch=1, stride=1, pad=0,
                                        out_shift=1, ifm_base=0, ofm_base=0,
                                        wgt_base=0, acc_init=1))
    assert w3 == [(0, 23)] and sat3 == 0  # (45+1)>>1
    _, w4, sat4 = run_conv_channel(fm2, [1] * 9,
                                   dict(img_w=3, img_h=3, in_ch=1, stride=1, pad=0,
                                        out_shift=0, ifm_base=0, ofm_base=0,
                                        wgt_base=0, acc_init=1000))
    assert w4 == [(0, 127)] and sat4 == 1  # int8 clamp

    # stride 2 dims: 5x5 pad1 stride2 -> 3x3 output
    assert out_dim(5, 1, 2) == 3 and out_dim(4, 0, 2) == 1 and out_dim(32, 1, 2) == 16

    # multi-pass chaining: in_ch=8 -> 72 taps -> 2 MAC passes per pixel
    fm5 = [1] * (8 * 3 * 3) + [0] * 10
    wgt5 = [1] * 72
    cfg5 = dict(img_w=3, img_h=3, in_ch=8, stride=1, pad=0, out_shift=0,
                ifm_base=0, ofm_base=0, wgt_base=0, acc_init=0)
    trace5, w5, _ = run_conv_channel(fm5, wgt5, cfg5)
    assert len(trace5) == 2 and w5 == [(0, 72)]
    assert trace5[1][2] == trace5[0][3]  # pass 1 acc_in == pass 0 acc_out

    # program executor: two chained 1-layer identity convs move the image
    fmbuf = [0] * (1 << FM_ADDR_W)
    fmbuf[0:9] = img
    wm = [0] * (1 << WGT_ADDR_W)
    wm[4] = 1                    # layer 0 identity kernel (oc 0)
    wm[9 + 4] = 1                # layer 1 identity kernel reads from base 9
    descs = [dict(img_w=3, img_h=3, in_ch=1, out_ch=1, stride=1, pad=1,
                  out_shift=0, ifm_base=0, ofm_base=100, wgt_base=0),
             dict(img_w=3, img_h=3, in_ch=1, out_ch=1, stride=1, pad=1,
                  out_shift=0, ifm_base=100, ofm_base=200, wgt_base=9)]
    for d in descs:
        d["stride"] = d.pop("stride")  # keep key name 'stride'
    tr, sat = run_program(fmbuf, wm, descs)
    assert fmbuf[100:109] == img and fmbuf[200:209] == img and sat == 0
    assert len(tr) == 18

    # descriptor packing spot-check
    v = pack_desc(dict(img_w=32, img_h=32, in_ch=3, out_ch=8, stride=2, pad=1,
                       out_shift=4, ifm_base=0, ofm_base=4096, wgt_base=0))
    assert v >> (LAYER_DESC_W - 6) == 32           # img_w in top 6 bits
    assert (v >> 12) & 0x3FFF == 4096              # ofm_base
    assert (v >> 40) & 0x1F == 4                   # out_shift
    print("golden_conv_model self-test: all checks passed")


if __name__ == "__main__":
    _self_test()
