"""Research-only CURRENT-quarter funded-public/sales-driven bridge.

This is a vertical acceptance slice, not future scenario coverage, investment
optimization, recovery qualification or a native/private-planner adoption path.
Preparation projects the canonical public prefix without a ledger transition;
execution attempts exactly one actual journal and closes only actual paid GDP.
Fixed coupons are contractual. Explicit IORB is independent of the policy curve.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F
import hashlib
import math

from . import macro as m, ledger as l, coupled as c
from . import public_funding as funding, public_income as income
from . import households
from .checkpoint import _paid_economy, _TAGS


def _fiscal(value):
    """Exact immutable command boundary, including every unsupported route.

    Do not admit numeric proxies/callbacks through the older permissive scalar
    constructors. Reconstruct the validated command without changing its schema.
    """
    if type(value) is not l.FundedPublicInstructions:
        raise TypeError('Require exact immutable FundedPublicInstructions.')
    data = {}
    for name, size, signed, optional in (
        ('currency_to_deposits', 2, True, False),
        ('mortgage_repayments', 2, False, False),
        ('treasury_subscriptions', 2, False, False),
        ('treasury_rolls', 3, False, False),
        ('rrp_offers', 2, False, False),
        ('subscription_coupon_mass', 2, True, True)):
        data[name] = funding._vector(getattr(value, name), size, name,
                                    signed=signed, optional=optional)
    for name in ('treasury_issue_authorization', 'treasury_redemption',
                 'rrp_request', 'replacement_maturity'):
        data[name] = funding._number(getattr(value, name))
    return l.FundedPublicInstructions(**data)


@dataclass(frozen=True)
class PublicStep:
    iorb_rate_pct: F
    fiscal: l.FundedPublicInstructions
    facility_limits: tuple[F, F]

    def __post_init__(self):
        object.__setattr__(self, 'iorb_rate_pct',
                           funding._number(self.iorb_rate_pct, signed=True))
        object.__setattr__(self, 'fiscal', _fiscal(self.fiscal))
        object.__setattr__(self, 'facility_limits',
                           funding._vector(self.facility_limits, 2, 'Facility limits'))


class FundingFailure(ValueError):
    """A KNOWN current-prefix shortfall, never missing future coverage."""
    status = 'funding_failure'


@dataclass(frozen=True)
class PublicPrefix:
    projected_opening: funding.FundingOpening
    batch: funding.FundingBatch
    principal_prefix: funding.FundingProjection
    income_prefix: funding.FundingPrefix
    observations: tuple[income.CouponLine, ...]


def quote_prefix(opening, step):
    """Pure original-stock quotation, after validating actual paid history.

    No private credit, future CB remittance or expected dividend bridges a
    public shortfall. RRP return/principal precede coupons, while all coupons
    (including IORB) retain their ORIGINAL opening bases.
    """
    if type(opening) is not m.Envelope or type(step) is not PublicStep:
        raise TypeError('Require an immutable Envelope and explicit PublicStep.')
    _canonical_value(opening)
    _canonical_value(step)
    if type(opening.sector.public_book) is not l.FundedPublicBook:
        raise NotImplementedError('Current public bridge requires the exact funded public book.')
    # Validate the predecessor BEFORE quoting new terms. Never rewrite its
    # already-paid IORB, snapshot, receipts or fixed contractual coupon rights.
    _paid_economy(opening)
    s = opening.sector; book = s.public_book
    l.validate_funded_public(book, s.scale, s.quarter,
                            None if s.last is None else s.last.payments)
    checked = PublicStep(step.iorb_rate_pct, step.fiscal, step.facility_limits)
    if checked != step:
        raise ValueError('Inconsistent public step.')
    fiscal = checked.fiscal
    if (any(fiscal.currency_to_deposits) or fiscal.rrp_request
            or any(fiscal.rrp_offers) or fiscal.treasury_redemption):
        raise NotImplementedError('Current bridge does not support currency, new RRP or direct redemption.')
    for limit in checked.facility_limits:
        l._money(limit, s.scale)
    snapshot = funding.FundingOpening(quarter=s.quarter + 1, scale=s.scale,
        terms=replace(book.terms, iorb_rate_pct=checked.iorb_rate_pct),
        treasuries=(book.treasuries, *book.private_treasuries), mortgages=book.mortgages,
        reserves=tuple(bank.reserves for bank in s.banks),
        household_deposits=tuple(s.deposit(owner) for owner in ('HA', 'HB')),
        cb_faces=tuple(s.cb_debt(bank) for bank in l.BANKS),
        rrp_faces=tuple(s.rrp_face(bank) for bank in l.BANKS),
        tga=book.tga, deferred=book.deferred_asset)
    batch = funding.FundingBatch(rolls=fiscal.treasury_rolls,
        subscriptions=fiscal.treasury_subscriptions,
        subscription_coupon_mass=fiscal.subscription_coupon_mass,
        authorization=fiscal.treasury_issue_authorization,
        maturity=fiscal.replacement_maturity,
        mortgage_repayments=fiscal.mortgage_repayments)
    observations = income.quote(snapshot.terms, treasuries=snapshot.treasuries,
        mortgages=snapshot.mortgages, reserves=snapshot.reserves,
        cb_faces=snapshot.cb_faces, rrp_faces=snapshot.rrp_faces, scale=snapshot.scale)
    try:
        principal = funding.project_batch(snapshot, batch)
        prefix = funding.project_income(snapshot, principal, observations)
    except ValueError as error:
        raise FundingFailure(str(error)) from error
    return PublicPrefix(snapshot, batch, principal, prefix, observations)


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
    income_prefix: funding.FundingPrefix
    observations: tuple[income.CouponLine, ...]
    forecast_residual: F
    forecast_services: F
    forecast_payroll: tuple[F, F]
    household_budgets: tuple[households.CashStockBudget, households.CashStockBudget]
    previous_income: tuple[F, F]
    forecast_income: tuple[F, F]
    private_planner_status: str
    input_digest: str


def prepare(opening, policy, step, news=m.News(), *, project_units=0):
    """Quote only this explicit current program; never call guarded macro.prepare.

    Last paid wages/jobs and firm/bank dividends are adaptive expectations. Q0
    uses the unchanged authored income/jobs seeds. Mortgage income enters the
    signed income intention once; its cash is ALREADY in the projected wallet.
    """
    if (type(opening) is not m.Envelope or type(policy) is not m.Policy
            or type(news) is not m.News or type(step) is not PublicStep):
        raise TypeError('Require exact immutable current-information inputs.')
    _canonical_value(policy)
    _canonical_value(news)
    prefix = quote_prefix(opening, step)
    a = opening.macro
    if a.consumption_state_pct or a.deferred_consumption_units:
        raise ValueError('Legacy demand/backlog migration is not implemented; do not delete stocks.')
    units = funding._number(project_units)
    if units % l.QUANTUM:
        raise ValueError('Project input must be on the physical order grid.')
    source = m._quote_source(opening, policy, news)
    current_public = tuple(-z.settled for z in prefix.observations[3:5])
    quote = c._quote_orders(opening, source, units,
        household_cash=prefix.income_prefix.household_deposits,
        current_public=current_public, net_income=True)
    source = replace(source, orders=quote.orders)
    # A content binding catches command-only edits (e.g. unused facility room)
    # as well as stale openings. This is consistency, NOT authentication/custody.
    digest = hashlib.sha256(repr((opening, policy, step, news, units)).encode()).hexdigest()
    return Prepared(opening, policy, step, news, source, quote.orders,
        prefix.projected_opening, prefix.batch, prefix.principal_prefix,
        prefix.income_prefix, prefix.observations, quote.residual, quote.services,
        quote.payroll, quote.budgets, quote.previous_income, quote.forecast_income,
        'supplied_research_project' if units else 'unqualified_no_project', digest)


def _canonical_value(value):
    """Compare known immutable values without user-overloaded equality.

    Source Prepared has no normalizing constructor. Its exact outer class alone
    does not exclude equality-spoofing scalar subclasses or nested proxies.
    This is an in-memory consistency boundary, not a new checkpoint format.
    """
    cls = type(value)
    if cls is type(None) or cls is str or cls is bool or cls is int:
        return cls, value
    if cls is float:
        if not math.isfinite(value):
            raise ValueError('Prepared values must be finite.')
        return cls, value
    if cls is F:
        funding._number(value, signed=True)
        return cls, value.numerator, value.denominator
    if cls is tuple:
        return cls, tuple(_canonical_value(x) for x in value)
    records = (*_TAGS, Prepared, PublicStep, PublicPrefix, m.Prepared,
               l.ProductionOrders, households.Preferences, households.CashStockBudget,
               funding.FundingProjection, funding.FundingPrefix)
    if any(cls is allowed for allowed in records):
        schema = fields(cls)
        attributes = object.__getattribute__(value, '__dict__')
        if (type(attributes) is not dict
                or any(type(key) is not str for key in attributes)
                or set(attributes) != {field.name for field in schema}):
            raise ValueError('Canonical records require their class-defined instance fields.')
        return cls, tuple((field.name, _canonical_value(getattr(value, field.name)))
                          for field in schema)
    raise ValueError('Prepared inputs require exact canonical records and scalars.')


def _validated(prepared):
    if type(prepared) is not Prepared or type(prepared.orders) is not l.ProductionOrders:
        raise ValueError('Stale or inconsistent current-public preparation.')
    supplied = _canonical_value(prepared)
    expected = prepare(prepared.opening, prepared.policy, prepared.step,
                       prepared.news, project_units=prepared.orders.investment_units)
    if supplied != _canonical_value(expected):
        raise ValueError('Stale or inconsistent current-public preparation.')


def controls(prepared):
    """Authored coupled credit quotes with explicit public terms and limits.

    Current public bank earnings inform conditional capital room, not household
    cash or guaranteed credit. Existing CB terms are retained; no zero-coupon
    CB contract/refinance term is invented when contract coverage is absent.
    """
    _validated(prepared)
    offers, renewals, commitment = c._quote_finance(prepared.opening.sector,
        prepared.source, prepared.orders, equity_earnings=prepared.income_prefix.earnings)
    return l.PublicIncomeControls(iorb_rate_pct=prepared.step.iorb_rate_pct,
        public_instructions=prepared.step.fiscal, facility_limits=prepared.step.facility_limits,
        household_mode='cash_stock_close_v1', new_loans=offers, renewals=renewals,
        project_commitment=commitment)


def execute(prepared, finance):
    """One actual adoption attempt; raw refusal preserves the exact predecessor.

    Revalidate every prepared result and bind public command/IORB/facilities
    before the actual call. Private lending remains explicitly supplied and
    subject to actual underwriting, collateral, cash and payout constraints.
    """
    _validated(prepared)
    if type(finance) is not l.PublicIncomeControls:
        raise ValueError('Current public closure requires explicit PublicIncomeControls and closing budgets.')
    _canonical_value(finance)
    if finance.household_mode != 'cash_stock_close_v1':
        raise ValueError('Current public closure requires closing budgets.')
    fiscal = _fiscal(finance.public_instructions)
    rate = funding._number(finance.iorb_rate_pct, signed=True)
    limits = funding._vector(finance.facility_limits, 2, 'Facility limits')
    if (fiscal != prepared.step.fiscal or rate != prepared.step.iorb_rate_pct
            or limits != prepared.step.facility_limits):
        raise ValueError('Submitted public command, IORB or facility limits differ from preparation.')
    request = funding._number(finance.asset_purchase_request)
    offers = funding._vector(finance.asset_offers, 2, 'Asset offers')
    if request or any(offers) or finance.security_bids is not None:
        raise NotImplementedError('Current public bridge does not support QE or explicit security bids.')
    out = l.advance_given_orders(prepared.opening.sector, prepared.orders, finance)
    if not out.ok:
        return m.Transition(False, prepared.opening, out.status, out.reason)
    return m._close_paid(prepared.source, out.state, closing_households=True)
