"""Authored post-payroll cash intention, not paid income or a second wallet.

The journal supplies actual opening cash, paid wages and signed settled public
income. Forecast income changes desired spending, never spendable cash. This
pure formula establishes neither wage funding nor successful coupon settlement.
"""
from fractions import Fraction as F

from .households import CashStockBudget
from .public_funding import _number


def cash_stock_budget(*, opening_cash, paid_wages, settled_income, previous_income,
                      forecast_income, cash_ratio, adjustment=F(1, 4),
                      demand_multiplier=1):
    """Keep owned cash distinct from a potentially negative adjustment base.

    All cash/income amounts are current nominal. Ratio, speed and demand impulse
    are dimensionless. The caller's disposable-income forecast ALREADY includes
    signed public income; it is not added again. Nonnegative pre-payroll cash
    after settlement gives exact parity with the older net cash-stock formula.
    These behavioral conventions are authored, not empirically estimated.
    """
    cash, wages, ratio, speed, impulse = map(_number, (
        opening_cash, paid_wages, cash_ratio, adjustment, demand_multiplier))
    income, prior, forecast = (
        _number(value, signed=True)
        for value in (settled_income, previous_income, forecast_income))
    if speed > 1:
        raise ValueError('Cash-target adjustment must be in [0, 1].')
    wallet = cash + wages + income
    if wallet < 0:
        raise ValueError('Mandatory settled income exceeds actual owned cash and paid wages.')
    old_target = max(F(0), ratio * prior)
    new_target = max(F(0), ratio * forecast)
    # cash + income is a signed wealth-adjustment base, NOT owned opening cash.
    desired = impulse * max(F(0), forecast - (new_target - old_target)
                            + speed * (cash + income - old_target))
    funded = min(wallet, desired)
    return CashStockBudget(desired, wallet, funded, wallet - funded)
