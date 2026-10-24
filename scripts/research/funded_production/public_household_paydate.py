"""Explicit current-quarter bridge for the exact HouseholdLiquidityBook.

Preparation quotes original bases, principal and early nonhousehold income,
NOT actual post-payroll household credit approval. Actual owned wallets and
current secured-credit conditions decide at the new sole-journal boundary.
No paid-book migration, future controller, economic recovery or native claim.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F

from . import macro as m, ledger as l, public_paydate as strict
from . import public_funding as funding, public_income as income, early_liquidity
from . import checkpoint, public_scenarios as scenarios


PublicStep = strict.PublicStep
FundingFailure = strict.FundingFailure
ConditionalBudget = strict.ConditionalBudget


@dataclass(frozen=True)
class PublicPrefix:
    """Conditional boundary observations, NOT another owned monetary book."""
    projected_opening: funding.FundingOpening
    batch: funding.FundingBatch
    principal_prefix: funding.FundingProjection
    income_prefix: l.PaydateSnapshot
    observations: tuple[income.CouponLine, ...]
    early_bank_earnings: tuple[F, F]
    principal_snapshot: l.PaydateSnapshot
    early_plan: early_liquidity.EarlyPlan
    credit_prefix: l.PaydateSnapshot
    household_liquidity_status: str = 'conditional_at_actual_payroll'


@dataclass(frozen=True)
class Prepared:
    opening: m.Envelope
    policy: m.Policy
    step: PublicStep
    news: m.News
    source: m.Prepared
    orders: l.ProductionOrders
    projected_opening: funding.FundingOpening
    batch: funding.FundingBatch
    principal_prefix: funding.FundingProjection
    income_prefix: l.PaydateSnapshot
    observations: tuple[income.CouponLine, ...]
    early_bank_earnings: tuple[F, F]
    forecast_residual: F
    forecast_services: F
    forecast_payroll: tuple[F, F]
    household_budgets: tuple[ConditionalBudget, ConditionalBudget]
    previous_income: tuple[F, F]
    forecast_income: tuple[F, F]
    private_planner_status: str
    input_digest: str
    principal_snapshot: l.PaydateSnapshot
    early_plan: early_liquidity.EarlyPlan
    credit_prefix: l.PaydateSnapshot
    household_liquidity_status: str = 'conditional_at_actual_payroll'


# Fixed trusted schemas. New preparations are deliberately NOT checkpoint tags.
_OWN_RECORDS = (PublicPrefix, Prepared)
_RECORDS = (*strict._RECORDS, *_OWN_RECORDS)


def _check_sources():
    checkpoint._check_sources()
    # Do not quietly run an unbound new adapter while parent integration waits.
    if 'public_household_paydate' not in checkpoint._SOURCES:
        raise ValueError('Current household-paydate bridge source is not registered.')


def _canonical_value(value):
    """Admit the entire closed tree BEFORE constructors/equality/normalization."""
    funding.validate_records(value, _RECORDS)
    def signature(item):
        cls = type(item)
        if cls is tuple:
            return cls, tuple(signature(child) for child in item)
        if any(cls is record for record in _OWN_RECORDS):
            return cls, tuple((field.name, signature(object.__getattribute__(item, field.name)))
                              for field in fields(cls))
        return strict._canonical_value(item)
    return signature(value)


def quote_prefix(opening, step):
    """Zero executors/transactions: original bases, principal, credit, coupons.

    Actual predecessor history is validated before new IORB in the shared
    closed input helper. Conditional early equity/collateral exclude future
    private claims and coupon earnings. Gross room is not net reserve cash.
    """
    _check_sources()
    snapshot, batch, principal, pure, observations = strict._quote_prefix_inputs(opening, step, early=True, household=True)
    sector = opening.sector
    for loan in sector.cb_loans:
        if loan.start >= snapshot.quarter or loan.maturity != snapshot.quarter:
            raise FundingFailure('Early novation requires original due CB cohorts.')
    _, equities, capacities = l._early_conditions(pure, sector.loans)
    try:
        plan = early_liquidity.plan(scale=sector.scale,
            reserves=pure.reserves, old_faces=pure.cb_faces, equities=equities,
            capacities=capacities, facility_limits=step.facility_limits,
            cb_rates_pct=pure.terms.cb_rates_pct, tga=pure.tga, observations=observations)
    except early_liquidity.PlanFailure as error:
        if error.status == 'unsupported_public_income':
            raise scenarios.MissingCoverage(str(error)) from error
        if error.status == 'funding_failure':
            raise FundingFailure(str(error)) from error
        raise
    credit = replace(pure, reserves=plan.credit_reserves, cb_faces=plan.replacement_faces)
    try:
        quoted_income = l._paydate_income_snapshot(credit, l._paydate_ordered_lines(observations))
    except ValueError as error:
        raise FundingFailure(str(error)) from error
    return PublicPrefix(snapshot, batch, principal, quoted_income, observations,
        strict._early_bank_earnings(observations), pure, plan, credit)


def prepare(opening, policy, step, news=m.News(), *, project_units=0):
    """Pure conditional hiring and finance inputs, never a paid quarter."""
    _check_sources()
    strict._prepare_inputs(opening, policy, step, news)
    prefix = quote_prefix(opening, step)
    source, orders, cr, services, payroll, budgets, previous, forecast, units, digest = strict._quote_prepared(
        opening, policy, step, news, project_units, prefix)
    return Prepared(opening, policy, step, news, source, orders,
        prefix.projected_opening, prefix.batch, prefix.principal_prefix,
        prefix.income_prefix, prefix.observations, prefix.early_bank_earnings,
        cr, services, payroll, budgets, previous, forecast,
        'supplied_research_project' if units else 'unqualified_no_project', digest,
        prefix.principal_snapshot, prefix.early_plan, prefix.credit_prefix)


def _validated(prepared):
    _check_sources()
    if type(prepared) is not Prepared:
        raise ValueError('Stale or inconsistent current-household-paydate preparation.')
    supplied = _canonical_value(prepared)
    if type(prepared.orders) is not l.ProductionOrders:
        raise ValueError('Require exact prepared ProductionOrders.')
    expected = prepare(prepared.opening, prepared.policy, prepared.step,
                       prepared.news, project_units=prepared.orders.investment_units)
    if supplied != _canonical_value(expected):
        raise ValueError('Stale or inconsistent current-household-paydate preparation.')


def controls(prepared):
    """Conditional private offers; actual underwriting and collateral decide."""
    _validated(prepared)
    return strict._quote_controls(prepared.opening, prepared.source, prepared.orders,
                                  prepared.step, prepared.early_bank_earnings)


def execute(prepared, finance):
    """One actual atomic attempt; close only strictly positive actual paid GDP.

    Public command/IORB/limits bind before the journal. Missing terms needed by
    later actual credit retain unsupported status, including optional staged
    project cancellation; no unknown contract is silently changed to zero.
    """
    _validated(prepared)
    return strict._execute_current(prepared.opening, prepared.source, prepared.orders, prepared.step, finance)
