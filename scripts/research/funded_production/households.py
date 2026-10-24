"""Authored household cash-budget choices, not an estimated consumption model."""
from dataclasses import dataclass
from fractions import Fraction
from .numerics import amount

@dataclass(frozen=True)
class Preferences:
    residual: Fraction = Fraction(19)
    services: Fraction = Fraction(1)
    cash: Fraction = Fraction(3)

    def __post_init__(self):
        for name in self.__dataclass_fields__:
            object.__setattr__(self,name,amount(getattr(self,name)))
        if not self.residual+self.services+self.cash:
            raise ValueError('At least one preference weight must be positive.')


@dataclass(frozen=True)
class Allocation:
    residual: Fraction
    services: Fraction
    saving: Fraction


@dataclass(frozen=True)
class CashStockBudget:
    """An intention and funded ceiling, NOT actual purchases or closing saving.

    Unfilled goods orders can leave more owned cash than ``unspent_wallet``.
    Closing distributions, if actually paid, add cash only at their legal date.
    """

    desired: Fraction
    wallet: Fraction
    funded: Fraction
    unspent_wallet: Fraction


def cash_stock_budget(*, opening_cash, paid_wages, previous_income,
                      forecast_income, cash_ratio, adjustment=Fraction(1, 4)):
    """Pure proposed closing-dividend budget; not wired into any ledger mode.

    All inputs are current nominal amounts except dimensionless cash_ratio and
    adjustment. Forecast income is a disclosed intention input, never cash.
    Previous income must be actual paid income, not its previous forecast.
    The target-growth deduction funds desired liquid-balance growth rather than
    spending expected income AND assuming the growing target is already saved.
    These are authored behavioral conventions, not estimated household behavior.
    """
    cash, wages, prior, forecast, ratio, speed = map(amount, (
        opening_cash, paid_wages, previous_income, forecast_income,
        cash_ratio, adjustment))
    if speed > 1:
        raise ValueError('Cash-target adjustment must be in [0, 1].')
    desired = max(Fraction(0), forecast - ratio * (forecast - prior)
                  + speed * (cash - ratio * prior))
    wallet = cash + wages
    funded = min(wallet, desired)
    return CashStockBudget(desired, wallet, funded, wallet - funded)


def _mode(mode):
    if mode not in ('wallet','liquidity'):
        raise ValueError('Choose wallet control or liquidity-saving mode.')


def allocate(budget,expected_dividend,prefs=Preferences(),mode='liquidity'):
    _mode(mode)
    if not isinstance(prefs,Preferences):
        raise TypeError('Allocation requires explicit preference weights.')
    budget,dividend=amount(budget),amount(expected_dividend)
    goods=prefs.residual+prefs.services
    if not goods:
        return Allocation(Fraction(0),Fraction(0),budget)
    spend=budget if mode=='wallet' else min(budget,goods*(budget+dividend)/(goods+prefs.cash))
    return Allocation(spend*prefs.residual/goods,spend*prefs.services/goods,budget-spend)
