"""Exact promised positive cashflow legs on a supplied full forward curve."""
from fractions import Fraction
from .numerics import amount

def price_cashflows(cashflows, forward_gross):
    """Exact present value; each quarter's positive gross forward factor matters.

    Gross factors below one support negative yields. This prices fixed,
    nonnegative promised cashflows, not swaps, credit defaults or policy curves.
    """
    if not isinstance(cashflows, (list, tuple)) or not isinstance(forward_gross, (list, tuple)):
        raise TypeError('Cashflows and forward factors require ordered list/tuple vectors.')
    flows, curve = tuple(map(amount, cashflows)), tuple(map(amount, forward_gross))
    if not flows or len(flows) != len(curve) or any(x == 0 for x in curve):
        raise ValueError('Require a positive gross forward factor for every cashflow period.')
    discount_denominator, value = Fraction(1), Fraction(0)
    for cash, gross in zip(flows, curve):
        discount_denominator *= gross
        value += cash / discount_denominator
    return value
