"""Cocotb unit test for fpmul.sv — Q16.16 fixed-point multiplier."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def to_q1616(f):
    """Convert Python float to Q16.16 32-bit signed integer."""
    v = int(round(f * 65536.0))
    if v < 0:
        v = v & 0xFFFF_FFFF
    return v & 0xFFFF_FFFF


def from_q1616(bits):
    """Convert Q16.16 bits to Python float."""
    signed = bits if bits < 0x8000_0000 else bits - 0x1_0000_0000
    return signed / 65536.0


def q1616_mul_ref(a_f, b_f):
    """Reference Q16.16 multiply: round to nearest Q16.16."""
    product = a_f * b_f
    return round(product * 65536) / 65536


async def reset(dut):
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.a.value = 0
    dut.b.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def multiply(dut, a_f, b_f):
    """Drive one multiply and return result float."""
    dut.a.value = to_q1616(a_f)
    dut.b.value = to_q1616(b_f)
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    # wait for valid_out
    for _ in range(5):
        await RisingEdge(dut.clk)
        if dut.valid_out.value == 1:
            return from_q1616(int(dut.result.value))
    raise AssertionError("valid_out never asserted")


@cocotb.test()
async def test_one_times_one(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res = await multiply(dut, 1.0, 1.0)
    assert abs(res - 1.0) < 2/65536, f"1.0×1.0 expected 1.0, got {res}"
    dut._log.info(f"PASS 1.0×1.0 = {res}")


@cocotb.test()
async def test_one_point_five_times_two(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res = await multiply(dut, 1.5, 2.0)
    assert abs(res - 3.0) < 2/65536, f"1.5×2.0 expected 3.0, got {res}"
    dut._log.info(f"PASS 1.5×2.0 = {res}")


@cocotb.test()
async def test_neg_one_times_one(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res = await multiply(dut, -1.0, 1.0)
    assert abs(res - (-1.0)) < 2/65536, f"-1.0×1.0 expected -1.0, got {res}"
    dut._log.info(f"PASS -1.0×1.0 = {res}")


@cocotb.test()
async def test_zero_times_anything(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res = await multiply(dut, 0.0, 3.14159)
    assert abs(res) < 2/65536, f"0×3.14 expected 0, got {res}"
    dut._log.info(f"PASS 0×anything = {res}")


@cocotb.test()
async def test_near_overflow(dut):
    """Q16.16 max positive is ~32767.99998. Test 100×100=10000 (well within range)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res = await multiply(dut, 100.0, 100.0)
    assert abs(res - 10000.0) < 1.0, f"100×100 expected 10000, got {res}"
    dut._log.info(f"PASS 100×100 = {res}")


@cocotb.test()
async def test_fractional(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res = await multiply(dut, 0.5, 0.5)
    assert abs(res - 0.25) < 2/65536, f"0.5×0.5 expected 0.25, got {res}"
    dut._log.info(f"PASS 0.5×0.5 = {res}")
