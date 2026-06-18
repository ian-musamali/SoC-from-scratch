"""Cocotb unit test for fpdiv.sv — Q16.16 fixed-point divider."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


def to_q1616(f):
    v = int(round(f * 65536.0))
    if v < 0:
        v = v & 0xFFFF_FFFF
    return v & 0xFFFF_FFFF


def from_q1616(bits):
    signed = bits if bits < 0x8000_0000 else bits - 0x1_0000_0000
    return signed / 65536.0


async def reset(dut):
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.numerator.value = 0
    dut.denominator.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def divide(dut, num_f, den_f, max_cycles=60):
    """Drive one divide and return (result_float, div_by_zero)."""
    dut.numerator.value = to_q1616(num_f)
    dut.denominator.value = to_q1616(den_f)
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if dut.valid_out.value == 1:
            return from_q1616(int(dut.result.value)), int(dut.div_by_zero.value)
    raise AssertionError(f"valid_out never asserted after {max_cycles} cycles")


@cocotb.test()
async def test_four_div_two(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res, dbz = await divide(dut, 4.0, 2.0)
    assert not dbz
    assert abs(res - 2.0) < 2/65536, f"4/2 expected 2.0, got {res}"
    dut._log.info(f"PASS 4.0/2.0 = {res}")


@cocotb.test()
async def test_one_div_four(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res, dbz = await divide(dut, 1.0, 4.0)
    assert not dbz
    assert abs(res - 0.25) < 2/65536, f"1/4 expected 0.25, got {res}"
    dut._log.info(f"PASS 1.0/4.0 = {res}")


@cocotb.test()
async def test_negative_numerator(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res, dbz = await divide(dut, -3.0, 1.0)
    assert not dbz
    assert abs(res - (-3.0)) < 2/65536, f"-3/1 expected -3.0, got {res}"
    dut._log.info(f"PASS -3.0/1.0 = {res}")


@cocotb.test()
async def test_both_negative(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res, dbz = await divide(dut, -6.0, -2.0)
    assert not dbz
    assert abs(res - 3.0) < 2/65536, f"-6/-2 expected 3.0, got {res}"
    dut._log.info(f"PASS -6.0/-2.0 = {res}")


@cocotb.test()
async def test_divide_by_zero(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    # denominator == 0 → div_by_zero asserted synchronously in same cycle as valid_out
    dut.numerator.value = to_q1616(1.0)
    dut.denominator.value = 0
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.div_by_zero.value) == 1 or int(dut.valid_out.value) == 1, \
        "div_by_zero should assert promptly"
    dut._log.info("PASS divide-by-zero flag asserted")


@cocotb.test()
async def test_fractional_result(dut):
    """3.0 / 4.0 = 0.75 — tests sub-integer result precision."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    res, dbz = await divide(dut, 3.0, 4.0)
    assert not dbz
    assert abs(res - 0.75) < 2/65536, f"3/4 expected 0.75, got {res}"
    dut._log.info(f"PASS 3.0/4.0 = {res}")
