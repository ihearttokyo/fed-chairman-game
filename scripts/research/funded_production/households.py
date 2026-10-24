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
