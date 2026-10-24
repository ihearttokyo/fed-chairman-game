"""Current-date bridge for the exact opt-in paid-payroll public calendar.

Pure early observations never fund wages, household coupons or CB remittance.
Adaptive hiring uses conditional spending intentions, NOT another owned wallet.
Only the actual ledger decides credit, collateral, wages and mandatory payments;
execution makes one atomic attempt and closes strictly positive actual paid GDP.
No future-program, recovery, native or autonomous-investment claim is made here.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F
import hashlib
import math

from . import macro as m, ledger as l, coupled as c, households as h
from . import checkpoint, public_forecast as p, public_scenarios as scenarios
from . import public_funding as funding, public_income as income, paydate_households
from .numerics import ration


# Preserve exact existing command/failure identities for generic bridge callers.
PublicStep = p.PublicStep
FundingFailure = p.FundingFailure


@dataclass(frozen=True)
class ConditionalBudget:
    """A signed prediction, never paid income or spendable owned cash."""
    desired: F
    conditional_wallet: F
    predicted_shortfall: F
    spending_intention: F


def _conditional_budget(*, opening_cash, wage_intention, settled_income,
                        previous_income, forecast_income, cash_ratio,
                        adjustment=F(1, 4), demand_multiplier=1):
    cash, wage, ratio, speed, impulse = map(funding._number, (
        opening_cash, wage_intention, cash_ratio, adjustment, demand_multiplier))
    signed, prior, forecast = (funding._number(value, signed=True) for value in (
        settled_income, previous_income, forecast_income))
    if speed > 1:
        raise ValueError('Cash-target adjustment must be in [0, 1].')
    wallet = cash + wage + signed
    desired = paydate_households._desired(cash, signed, prior, forecast, ratio, speed, impulse)
    return ConditionalBudget(desired, wallet, max(F(0), -wallet),
                             min(max(F(0), wallet), desired))


@dataclass(frozen=True)
class PublicPrefix:
    """Closed read-only quote of original bases, principal and early coupons."""
    projected_opening: funding.FundingOpening
    batch: funding.FundingBatch
    principal_prefix: funding.FundingProjection
    income_prefix: l.PaydateSnapshot
    observations: tuple[income.CouponLine, ...]
    early_bank_earnings: tuple[F, F]


@dataclass(frozen=True)
class Prepared:
    opening: m.Envelope
    policy: m.Policy
    step: p.PublicStep
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


# Fixed code-owned schemas, never class names or schemas supplied by a record.
_OWN_RECORDS = (ConditionalBudget, PublicPrefix, Prepared)
_RECORDS = (*checkpoint._TAGS, p.PublicStep, m.Prepared, l.ProductionOrders,
            h.Preferences, h.CashStockBudget, funding.FundingProjection,
            funding.FundingPrefix, *_OWN_RECORDS)


def _canonical_value(value):
    """Structural admission precedes constructors, equality and normalization."""
    funding.validate_records(value, _RECORDS)
    def signature(item):
        cls = type(item)
        if cls is tuple:
            return cls, tuple(signature(child) for child in item)
        if any(cls is record for record in _OWN_RECORDS):
            return cls, tuple((field.name, signature(object.__getattribute__(item, field.name)))
                              for field in fields(cls))
        return p._canonical_value(item)
    return signature(value)


def _coverage(sector):
    """Missing applicable contract terms are unknown, not invented zero rates."""
    book = sector.public_book
    for kind, faces, rates in (
        ('cb_loan', tuple(sector.cb_debt(b) for b in l.BANKS), book.terms.cb_rates_pct),
        ('rrp', tuple(sector.rrp_face(b) for b in l.BANKS), book.terms.rrp_rates_pct)):
        for owner, face, rate in zip(l.BANKS, faces, rates):
            if face and rate is None:
                raise scenarios.MissingCoverage('Missing contractual ' + kind + ' coupon terms for ' + owner)


def quote_prefix(opening, step):
    """Zero transactions: original eleven bases, principal, non-HH coupons.

    Prior actual payments AND trace validate before quoting new IORB. The
    read-only PaydateSnapshot retains all four actual wallets and prior income
    history; only its current terms receive the new administered-rate quote.
    """
    checkpoint._check_sources()
    if type(opening) is not m.Envelope or type(step) is not p.PublicStep:
        raise TypeError('Require an exact Envelope and explicit PublicStep.')
    _canonical_value((opening, step))
    replace(opening)  # Exact components/version/clock, after structural admission.
    sector = opening.sector
    if type(sector.public_book) is not l.PaydatePublicBook:
        raise NotImplementedError('Current paydate bridge requires the exact PaydatePublicBook.')
    # Recheck individual legal balances/contracts too: aggregate SectorState
    # identities alone do not prove each firm's or household's wallet is valid.
    # No constructor is reached before the closed-tree admission above.
    for name, allowed in (
        ('banks', (l.Bank,)), ('loans', (l.Loan, l.OperatingLoan, l.ProjectLoan)),
        ('cb_loans', (l.CBLoan,)), ('vintages', (l.Vintage,))):
        values = getattr(sector, name)
        if type(values) is not tuple:
            raise TypeError('Require exact immutable current sector collections.')
        for record in values:
            if not any(type(record) is cls for cls in allowed):
                raise TypeError('Require exact current sector record types.')
            if type(record) is l.CBLoan:
                for pledge in record.collateral:
                    if type(pledge) is not l.Collateral:
                        raise TypeError('Require exact identified collateral.')
                    replace(pledge)
            replace(record)
    book = sector.public_book
    if type(book.terms) is not income.PublicIncomeTerms:
        raise TypeError('Require exact immutable public income terms.')
    replace(book.terms)
    for claim in book.rrp_claims:
        if type(claim) is not l.RRPClaim:
            raise TypeError('Require exact RRP contract records.')
        replace(claim)
    replace(book)
    replace(opening.macro)
    checkpoint._paid_economy(opening)
    _coverage(sector)
    # Validate actual asset/right/CB-reserve identities and the full paid witness.
    replace(sector)
    checked = p.PublicStep(step.iorb_rate_pct, step.fiscal, step.facility_limits)
    if _canonical_value(checked) != _canonical_value(step):
        raise ValueError('Inconsistent current paydate step.')
    fiscal = checked.fiscal
    if (any(fiscal.currency_to_deposits) or fiscal.rrp_request
            or any(fiscal.rrp_offers) or fiscal.treasury_redemption):
        raise NotImplementedError('Current paydate bridge does not support currency, new RRP or direct redemption.')
    for limit in checked.facility_limits:
        l._money(limit, sector.scale)
    book, last = sector.public_book, sector.last
    snapshot = funding.FundingOpening(quarter=sector.quarter + 1, scale=sector.scale,
        terms=replace(book.terms, iorb_rate_pct=checked.iorb_rate_pct),
        treasuries=(book.treasuries, *book.private_treasuries), mortgages=book.mortgages,
        reserves=tuple(b.reserves for b in sector.banks),
        household_deposits=tuple(sector.deposit(owner) for owner in ('HA', 'HB')),
        cb_faces=tuple(sector.cb_debt(b) for b in l.BANKS),
        rrp_faces=tuple(sector.rrp_face(b) for b in l.BANKS),
        tga=book.tga, deferred=book.deferred_asset)
    batch = funding.FundingBatch(rolls=fiscal.treasury_rolls,
        subscriptions=fiscal.treasury_subscriptions,
        subscription_coupon_mass=fiscal.subscription_coupon_mass,
        authorization=fiscal.treasury_issue_authorization,
        maturity=fiscal.replacement_maturity, mortgage_repayments=fiscal.mortgage_repayments)
    observations = income.quote(snapshot.terms, treasuries=snapshot.treasuries,
        mortgages=snapshot.mortgages, reserves=snapshot.reserves,
        cb_faces=snapshot.cb_faces, rrp_faces=snapshot.rrp_faces, scale=snapshot.scale)
    previous = ((20*sector.scale, F(63,20)*sector.scale) if last is None else
                tuple(last.disposable_income(owner) for owner in ('HA', 'HB')))
    dividends = ((None, None) if last is None else (
        last.dividend_residual + last.bank_dividend_to('HA'),
        last.dividend_focal + last.bank_dividend_to('HB')))
    try:
        principal = funding.project_batch(snapshot, batch)
        pure = l.PaydateSnapshot(reserves=principal.reserves,
            wallets=(*(sector.deposit(a) for a in ('R', 'F')), *principal.household_deposits),
            cb_faces=snapshot.cb_faces, treasuries=principal.treasuries, terms=principal.terms,
            mortgages=principal.mortgages, rrp_faces=(F(0), F(0)), currency=book.currency,
            capital_other=book.capital_other, tga=principal.tga, deferred=snapshot.deferred,
            previous_income=previous, previous_dividends=dividends)
        early = l._paydate_ordered_lines(observations)
        pure = l._paydate_income_snapshot(pure, early)
    except ValueError as error:
        raise p.FundingFailure(str(error)) from error
    earnings = tuple(sum((z.settled * (-1 if z.kind == 'cb_loan' else 1)
                          for z in early if z.owner == bank), F(0)) for bank in l.BANKS)
    return PublicPrefix(snapshot, batch, principal, pure, observations, earnings)


def _quote_orders(opening, source, units, prefix):
    """Preserve coupled._quote_orders' observed-job hiring and technology.

    Only its budget record changes: D is post-principal actual owned cash, I is
    the original signed HH coupon, and wages are intentions from observed jobs.
    A negative conditional wallet yields zero spending, not an actual refusal.
    """
    a, s = opening.macro, opening.sector
    try:
        multiplier = m.rational(math.exp(source.news.demand_shock_pct / 100))
    except (OverflowError, ValueError) as error:
        raise ValueError('Demand preference impulse is not representable.') from error
    price, trend = m.rational(source.price_index / 100), m.rational(source.trend)
    unit = s.scale * price
    wage = unit * trend
    previous = prefix.income_prefix.previous_income
    divs = ((3*s.scale, F(3,20)*s.scale) if s.last is None else
            prefix.income_prefix.previous_dividends)
    old_workers = ((F(17), F(3)) if s.last is None else
                   (s.last.paid_residual_workers, s.last.paid_focal_workers))
    payroll = tuple(jobs * wage for jobs in old_workers)
    signed = tuple(-z.settled for z in prefix.observations[3:5])
    forecast = tuple(pay + div + public for pay, div, public in zip(payroll, divs, signed))
    quotes = tuple(_conditional_budget(opening_cash=cash, wage_intention=pay,
        settled_income=public, previous_income=prior, forecast_income=expected,
        cash_ratio=ratio, demand_multiplier=multiplier)
        for cash, pay, public, prior, expected, ratio in zip(
            prefix.principal_prefix.household_deposits, payroll, signed, previous,
            forecast, (F(3,20), F(1,21))))
    budgets = tuple(z.spending_intention for z in quotes)
    cr = budgets[0] * F(363,400) / unit
    services = (budgets[0] * F(37,400) + budgets[1]) / unit
    ar, af, v, chi = F(20,17)*trend, F(5,3)*trend, F(5,16), F(37,20)
    requested_r = (cr + chi*units) / ar
    current_capital = sum((z.units for z in s.vintages if z.age < 15), F(0)) + s.wip_units
    requested_f = min(services, current_capital*v) / af
    lr, lf = ration(m.rational(a.workforce), requested_r, requested_f, quantum=l.QUANTUM)
    orders = replace(l.depth_orders(), market_clearing=True, price_factor=price,
        real_wage=trend, residual_workers=lr, focal_workers=lf,
        available_workers=m.rational(a.workforce), residual_productivity=ar,
        service_productivity=af, investment_units=units, residual_consumption=cr,
        service_a=budgets[0]*F(37,400)/unit, service_b=budgets[1]/unit,
        cash_floor_r=lr*trend, cash_floor_f=lf*trend,
        expected_dividends_nominal=divs, demand_multiplier=multiplier)
    return orders, cr, services, payroll, quotes, previous, forecast


def prepare(opening, policy, step, news=m.News(), *, project_units=0):
    """Pure current command and conditional intentions; zero paid quarters."""
    checkpoint._check_sources()
    if (type(opening) is not m.Envelope or type(policy) is not m.Policy
            or type(step) is not p.PublicStep or type(news) is not m.News):
        raise TypeError('Require exact immutable current-information inputs.')
    _canonical_value((opening, policy, step, news))
    # Recheck policy grids/ranges and news without permissive proxy inputs.
    if (_canonical_value(replace(policy)) != _canonical_value(policy)
            or _canonical_value(replace(news)) != _canonical_value(news)):
        raise ValueError('Inconsistent current policy or news.')
    prefix = quote_prefix(opening, step)
    if opening.macro.consumption_state_pct or opening.macro.deferred_consumption_units:
        raise ValueError('Legacy demand/backlog migration is not implemented; do not delete stocks.')
    units = funding._number(project_units)
    if units % l.QUANTUM:
        raise ValueError('Project input must be on the physical order grid.')
    source = m._quote_source(opening, policy, news)
    orders, cr, services, payroll, budgets, previous, forecast = _quote_orders(
        opening, source, units, prefix)
    source = replace(source, orders=orders)
    # Consistency binding only, NOT authentication or custody. No adopted command
    # codec or serializable career is supplied for this Prepared quote.
    digest = hashlib.sha256(repr((opening, policy, step, news, units)).encode()).hexdigest()
    return Prepared(opening, policy, step, news, source, orders,
        prefix.projected_opening, prefix.batch, prefix.principal_prefix,
        prefix.income_prefix, prefix.observations, prefix.early_bank_earnings,
        cr, services, payroll, budgets, previous, forecast,
        'supplied_research_project' if units else 'unqualified_no_project', digest)


def _validated(prepared):
    checkpoint._check_sources()
    if type(prepared) is not Prepared:
        raise ValueError('Stale or inconsistent current-paydate preparation.')
    supplied = _canonical_value(prepared)
    if type(prepared.orders) is not l.ProductionOrders:
        raise ValueError('Require exact prepared ProductionOrders.')
    expected = prepare(prepared.opening, prepared.policy, prepared.step,
                       prepared.news, project_units=prepared.orders.investment_units)
    if supplied != _canonical_value(expected):
        raise ValueError('Stale or inconsistent current-paydate preparation.')


def controls(prepared):
    """Conditional private quotes; actual underwriting/collateral still decide."""
    _validated(prepared)
    offers, renewals, commitment = c._quote_finance(prepared.opening.sector,
        prepared.source, prepared.orders, equity_earnings=prepared.early_bank_earnings)
    return l.PublicIncomeControls(iorb_rate_pct=prepared.step.iorb_rate_pct,
        public_instructions=prepared.step.fiscal, facility_limits=prepared.step.facility_limits,
        household_mode='cash_stock_close_v1', new_loans=offers, renewals=renewals,
        project_commitment=commitment)


def execute(prepared, finance):
    """Exactly one raw journal attempt after binding public current controls.

    Raw unsupported/missing NEW CB-credit contracts stay unsupported, not an
    invented zero term or a known funding failure. Refusal keeps the predecessor.
    """
    _validated(prepared)
    if type(finance) is not l.PublicIncomeControls:
        raise ValueError('Current paydate closure requires explicit PublicIncomeControls.')
    _canonical_value(finance)
    if finance.household_mode != 'cash_stock_close_v1':
        raise ValueError('Current paydate closure requires closing cash-stock budgets.')
    fiscal = p._fiscal(finance.public_instructions)
    rate = funding._number(finance.iorb_rate_pct, signed=True)
    limits = funding._vector(finance.facility_limits, 2, 'Facility limits')
    if (fiscal != prepared.step.fiscal or rate != prepared.step.iorb_rate_pct
            or limits != prepared.step.facility_limits):
        raise ValueError('Submitted public command, IORB or facility limits differ from preparation.')
    request = funding._number(finance.asset_purchase_request)
    offers = funding._vector(finance.asset_offers, 2, 'Asset offers')
    if request or any(offers) or finance.security_bids is not None:
        raise NotImplementedError('Current paydate bridge does not support QE or explicit security bids.')
    out = l.advance_given_orders(prepared.opening.sector, prepared.orders, finance)
    if not out.ok:
        return m.Transition(False, prepared.opening, out.status, out.reason)
    if out.state.last.real_output <= 0:
        return m.Transition(False, prepared.opening, 'terminal_crisis',
                            'Zero paid GDP; economic crisis successor remains required.')
    return m._close_paid(prepared.source, out.state, closing_households=True)
