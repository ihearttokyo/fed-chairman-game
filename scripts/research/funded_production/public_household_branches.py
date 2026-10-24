"""Exact household-liquidity futures: authored programs, never adoption.

Both finite runners use the SAME current household adapter and actual journal.
Post-payroll secured liquidity remains conditional at every date. Construction
backgrounds/discount factors/cell weights are authored, not empirical forecasts,
endogenous investment, Fed approvals or economic-recovery qualification.
"""
from __future__ import annotations

from dataclasses import dataclass, fields
from fractions import Fraction as F

from . import macro as m, ledger as l, episodes as e, checkpoint
from . import public_funding as funding, public_market as market, public_scenarios as old
from . import public_household_paydate as current
from . import public_branches as core, public_recurring_branches as recurring

ProgramDate = market.MarketFundingDate
MissingCoverage = old.MissingCoverage
Quotation = core.Quotation
RecurringQuotation = recurring.Quotation


def _check_sources():
    checkpoint._check_sources()
    if 'public_household_branches' not in checkpoint._SOURCES:
        raise ValueError('Household future source is not registered.')


def _admit(value):
    # Exact code-owned classes and their CLASS schemas before any comparison,
    # constructor, sorting or hashing. No instance metadata selects traversal.
    funding.validate_records(value, _RECORDS)


def _date(value):
    if type(value) is not ProgramDate:
        raise TypeError('Require an exact MarketFundingDate or missing coverage None.')
    _admit(value)
    return ProgramDate(**{field.name: object.__getattribute__(value, field.name)
                          for field in fields(ProgramDate)})


@dataclass(frozen=True)
class ScenarioCell:
    demand_sign: int
    fulfilled: bool
    dates: tuple[ProgramDate | None, ...]

    def __post_init__(self):
        _admit(self)
        if type(self.demand_sign) is not int or self.demand_sign not in (-1, 1):
            raise ValueError('Demand signal must be the plain integer -1 or +1.')
        if type(self.fulfilled) is not bool:
            raise TypeError('Promise label must be an exact Boolean.')
        if type(self.dates) is not tuple or len(self.dates) != 19:
            raise TypeError('Require nineteen immutable authored dates.')
        object.__setattr__(self, 'dates', tuple(None if value is None else _date(value)
                                               for value in self.dates))


_RECORDS = (*checkpoint._TAGS, ScenarioCell, ProgramDate, e.PolicyRule,
            old.PolicyIORB, old.ResolvedDate, current.PublicStep)


def validated_cells(cells):
    _check_sources()
    _admit(cells)
    if type(cells) is not tuple or len(cells) != 4:
        raise TypeError('Require an immutable four-cell tuple.')
    checked = []
    for cell in cells:
        if type(cell) is not ScenarioCell:
            raise TypeError('Require exact household ScenarioCell records.')
        checked.append(ScenarioCell(cell.demand_sign, cell.fulfilled, cell.dates))
    if {(cell.demand_sign, cell.fulfilled) for cell in checked} != {
            (-1, False), (-1, True), (1, False), (1, True)}:
        raise ValueError('Require each demand-sign/promise pair exactly once.')
    return tuple(checked)


def resolve_date(opening, descriptor):
    """Zero preparation/execution; exact full prior witness before new IORB."""
    _check_sources()
    return market.resolve_household_paydate_date(opening, descriptor)


def _tokens(value):
    """Fixed primitive type tags, NOT an executable schema or object codec."""
    cls = type(value)
    if cls is tuple:
        return 'tuple', tuple(_tokens(child) for child in value)
    if value is None:
        return ('none',)
    if cls is str:
        return 'str', value
    if cls is bool:
        return 'bool', value
    if cls is int:
        return 'int', value
    if cls is float:
        funding._number(value, signed=True)
        # WAIT observes numeric quantities, not an IEEE signed-zero bit that
        # could encode a hidden cell. Preserve the type tag and every nonzero
        # bit; do not round genuinely different published facts together.
        canonical = 0.0 if value == 0.0 else value
        return 'float', canonical.hex()
    if cls is F:
        funding._number(value, signed=True)
        return 'fraction', value.numerator, value.denominator
    raise TypeError('WAIT facts require only exact immutable primitive scalars.')


def wait_observation(opening, resolved):
    """Coarse REALIZED public/own-F facts and CURRENT published declarations.

    No cell/future descriptors are parameters. Hidden macro/financial states,
    bank books, claim IDs and source digests cannot distinguish WAIT groups.
    Primitive tagged tuples retain scalar types without exporting live classes.
    This declared information convention is not empirical observability proof.
    """
    _check_sources()
    _admit((opening, resolved))
    checked = market._opening(opening, l.HouseholdLiquidityBook)
    if type(resolved) is not old.ResolvedDate:
        raise TypeError('Require the exact current ResolvedDate.')
    validated = old.ResolvedDate(resolved.policy, resolved.news, resolved.step)
    if current._canonical_value((resolved.policy, resolved.news, resolved.step)) != current._canonical_value(
            (validated.policy, validated.news, validated.step)):
        raise ValueError('Noncanonical current published declaration.')
    sector = checked.sector
    own = []
    for loan in sector.loans:
        if type(loan) is l.Loan:
            kind = 'loan'
        elif type(loan) is l.OperatingLoan:
            kind = 'operating'
        elif type(loan) is l.ProjectLoan:
            kind = 'project'
        else:
            raise TypeError('Require exact legal private claim types.')
        if loan.borrower == 'F':
            own.append((kind, loan.lender, loan.face, loan.rate_pct,
                        loan.start, loan.maturity, loan.last_coupon_paid))
    policy_names = ('rate_pct', 'guidance_pct', 'inflation_sensitivity', 'gap_sensitivity')
    news_names = ('demand_shock_pct', 'supply_innovation_pct', 'r_star_change_pct',
                  'r_star_reference_change_pct', 'structural_unemployment_change_pct')
    facts = ('public_household_wait_observation_v1',
        ('public_macro', tuple((name, getattr(checked.macro, name)) for name in old._PUBLIC_MACRO_FIELDS)),
        ('focal_cash', sector.deposit('F')),
        ('focal_vintages', tuple(sorted((v.age, v.units, v.basis) for v in sector.vintages))),
        ('focal_wip', (sector.wip_units, sector.wip_basis)),
        ('focal_loans', tuple(sorted(own))),
        ('policy', tuple((name, getattr(validated.policy, name)) for name in policy_names)),
        ('news', tuple((name, getattr(validated.news, name)) for name in news_names)),
        ('iorb_rate_pct', validated.step.iorb_rate_pct))
    result = _tokens(facts)
    _check_sources()
    return result


def evaluate(opening, cells, *, units, forward_gross, tolerance=1e-6) -> Quotation:
    """One extra NOW0/WAIT1 tranche; at most228 simulated raw attempts."""
    _check_sources()
    return core._evaluate(opening, cells, units=units, forward_gross=forward_gross,
                          tolerance=tolerance, paydate=True, household=True)


def evaluate_recurring(opening, cells, *, units, background_units,
                       forward_gross, tolerance=1e-6) -> RecurringQuotation:
    """Extra investment against SAME authored background; at most228 attempts.

    Joint invoices/debt are never split into a fictional candidate fraction.
    Later background principal is explicitly right-censored. Unknown coverage
    cannot become zero cash or an investment recommendation. No successor,
    preparation or finance command is exported/adopted by this quotation.
    """
    _check_sources()
    return recurring._evaluate(opening, cells, units=units, background_units=background_units,
        forward_gross=forward_gross, tolerance=tolerance, household=True)
