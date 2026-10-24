"""Explicit new-calendar programs; no latent/future information in WAIT keys.

This is authored conditional coverage, not an auction, forecast or adopted
career. Every date requires bounded market-funding terms, even when all new
issue limits are explicitly zero. Existing full-roll scenarios are unchanged.
"""
from dataclasses import dataclass,fields

from . import macro as m, episodes as e
from . import public_market as market, public_scenarios as old
from . import public_funding as funding

MissingCoverage = old.MissingCoverage


def _date(value):
    if type(value) is not market.MarketFundingDate:
        raise TypeError('Require an exact bounded MarketFundingDate or missing coverage None.')
    market._check_shapes(value)
    return market.MarketFundingDate(**{field.name:getattr(value,field.name)
                                      for field in fields(market.MarketFundingDate)})


@dataclass(frozen=True)
class ScenarioCell:
    demand_sign: int
    fulfilled: bool
    dates: tuple[market.MarketFundingDate | None,...]

    def __post_init__(self):
        funding.validate_records(self,(ScenarioCell,market.MarketFundingDate,
            m.Policy,m.News,e.PolicyRule,old.PolicyIORB))
        if type(self.demand_sign) is not int or self.demand_sign not in (-1,1):
            raise ValueError('Demand signal must be the plain integer -1 or +1.')
        if type(self.fulfilled) is not bool:
            raise TypeError('Promise fulfillment must be an exact Boolean.')
        if type(self.dates) is not tuple or len(self.dates)!=19:
            raise TypeError('Require nineteen immutable authored dates.')
        object.__setattr__(self,'dates',tuple(None if value is None else _date(value)
                                             for value in self.dates))


def validated_cells(cells):
    if type(cells) is not tuple or len(cells)!=4:
        raise TypeError('Require an immutable four-cell tuple.')
    checked=[]
    for cell in cells:
        if type(cell) is not ScenarioCell:
            raise TypeError('Require exact paydate ScenarioCell records.')
        funding.validate_records(cell,(ScenarioCell,market.MarketFundingDate,
            m.Policy,m.News,e.PolicyRule,old.PolicyIORB))
        checked.append(ScenarioCell(cell.demand_sign,cell.fulfilled,cell.dates))
    if {(cell.demand_sign,cell.fulfilled) for cell in checked}!={
            (-1,False),(-1,True),(1,False),(1,True)}:
        raise ValueError('Require each demand-sign/promise pair exactly once.')
    return tuple(checked)


def resolve_date(opening,descriptor):
    return market.resolve_paydate_date(opening,descriptor)


def wait_observation(opening,resolved):
    return old.wait_paydate_observation(opening,resolved)
