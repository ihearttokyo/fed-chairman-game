"""Pure authored public-date coverage and conservative WAIT information.

These are conditional research declarations, not a public-debt auction model,
paid journal, career adoption or empirical information-availability claim. Each
full-roll declaration consents to rolling its OWN branch's actual holder dues.
The existing funding arithmetic carries their fixed coupon mass at pooled par;
neither fresh subscriptions nor a future CB contract is invented here.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F

from . import episodes as e, macro as m, ledger as l
from . import public_forecast as p, public_funding as funding


def _policy(value):
    if type(value) is not m.Policy:
        raise TypeError('Require an exact immutable Policy.')
    # Old constructors accept some scalar subclasses. Check every old leaf
    # BEFORE reconstruction, arithmetic, equality or truthiness can see it.
    p._canonical_value(value)
    return m.Policy(**{field.name: getattr(value, field.name) for field in fields(m.Policy)})


def _news(value):
    if type(value) is not m.News:
        raise TypeError('Require explicit exact immutable News, including zero news.')
    p._canonical_value(value)
    return m.News(**{field.name: getattr(value, field.name) for field in fields(m.News)})


def _policy_descriptor(value):
    if type(value) is m.Policy:
        return _policy(value)
    if type(value) is not e.PolicyRule:
        raise TypeError('Require an exact Policy or authored PolicyRule, not a callback.')
    # PolicyRule is NOT registered with public_forecast._canonical_value.
    # Validate its explicit kind and its known leaf record instead.
    if type(value.kind) is not str or value.kind not in ('fixed', 'staff', 'promise'):
        raise ValueError('Unknown immutable policy rule.')
    if value.kind == 'fixed':
        return e.PolicyRule('fixed', _policy(value.fixed))
    if value.fixed is not None:
        raise ValueError('Only the fixed rule carries an explicit Policy.')
    return e.PolicyRule(value.kind)


def _step(value):
    if type(value) is not p.PublicStep:
        raise TypeError('Require an exact immutable PublicStep.')
    p._canonical_value(value)
    return p.PublicStep(value.iorb_rate_pct, value.fiscal, value.facility_limits)


@dataclass(frozen=True)
class PolicyIORB:
    """Explicit authored nominal-policy identity, not an estimated Fed spread.

    Resolution uses that branch's policy quote, never its nonlinear effective
    borrowing-rate transform. A fixed-rate declaration remains independent.
    """


@dataclass(frozen=True)
class FullRollDate:
    """Explicit full holder-roll/issuer authorization, without cash additions.

    IORB is required independently of the nominal/effective policy rate.
    Facilities are declared cash limits; their branch-scale grid is checked
    only when resolving against a current opening. Maturity is in quarters.
    """
    policy: m.Policy | e.PolicyRule
    news: m.News
    iorb_rate_pct: F | PolicyIORB
    facility_limits: tuple[F, F]
    replacement_maturity: F = F(118, 5)

    def __post_init__(self):
        object.__setattr__(self, 'policy', _policy_descriptor(self.policy))
        object.__setattr__(self, 'news', _news(self.news))
        rate = (PolicyIORB() if type(self.iorb_rate_pct) is PolicyIORB
                else funding._number(self.iorb_rate_pct, signed=True))
        object.__setattr__(self, 'iorb_rate_pct', rate)
        object.__setattr__(self, 'facility_limits',
                           funding._vector(self.facility_limits, 2, 'Facility limits'))
        maturity = funding._number(self.replacement_maturity)
        if not 1 <= maturity <= 120:
            raise ValueError('Replacement Treasury maturity must lie in 1..120 quarters.')
        object.__setattr__(self, 'replacement_maturity', maturity)


def _date(value):
    if type(value) is not FullRollDate:
        raise TypeError('Require an exact FullRollDate or missing coverage None.')
    return FullRollDate(value.policy, value.news, value.iorb_rate_pct,
                        value.facility_limits, value.replacement_maturity)


@dataclass(frozen=True)
class ScenarioCell:
    demand_sign: int
    fulfilled: bool
    dates: tuple[FullRollDate | None, ...]

    def __post_init__(self):
        if type(self.demand_sign) is not int or self.demand_sign not in (-1, 1):
            raise ValueError('Demand signal must be the plain integer -1 or +1.')
        if type(self.fulfilled) is not bool:
            raise TypeError('Promise fulfillment must be an exact Boolean.')
        if type(self.dates) is not tuple or len(self.dates) != 19:
            raise TypeError('Require exactly nineteen immutable date descriptors.')
        object.__setattr__(self, 'dates', tuple(None if item is None else _date(item)
                                               for item in self.dates))


def validated_cells(cells) -> tuple[ScenarioCell, ...]:
    """Reconstruct four unique Cartesian cells, preserving their supplied order.

    Missing descriptors remain missing, never implicit zero policies/news.
    No cell name, callback or caller-defined observation function is accepted.
    """
    if type(cells) is not tuple or len(cells) != 4:
        raise TypeError('Require an immutable four-cell tuple.')
    checked = []
    for cell in cells:
        if type(cell) is not ScenarioCell:
            raise TypeError('Require exact immutable ScenarioCell records.')
        checked.append(ScenarioCell(cell.demand_sign, cell.fulfilled, cell.dates))
    if {(cell.demand_sign, cell.fulfilled) for cell in checked} != {
            (-1, False), (-1, True), (1, False), (1, True)}:
        raise ValueError('Require each demand-sign/promise-fulfillment pair exactly once.')
    return tuple(checked)


class MissingCoverage(ValueError):
    """Unknown authored coverage; distinct from a known funding/credit refusal."""
    status = 'unknown'


@dataclass(frozen=True)
class ResolvedDate:
    policy: m.Policy
    news: m.News
    step: p.PublicStep

    def __post_init__(self):
        object.__setattr__(self, 'policy', _policy(self.policy))
        object.__setattr__(self, 'news', _news(self.news))
        object.__setattr__(self, 'step', _step(self.step))


def _opening(value):
    if type(value) is not m.Envelope:
        raise TypeError('Require the exact current branch Envelope.')
    p._canonical_value(value)
    replace(value)  # Recheck the wrapper version and component clock contract.
    if type(value.macro) is not m.Macro or type(value.sector) is not l.SectorState:
        raise TypeError('Require exact macro and sector records.')
    sector = value.sector
    if type(sector.public_book) is not l.FundedPublicBook:
        raise NotImplementedError('Require the exact funded public book.')
    scale = funding._number(sector.scale)
    if not scale:
        raise ValueError('Current branch nominal scale must be positive.')
    # Actual paid-history/book validation remains the caller's obligation.
    # The deep canonical check above is essential even for fields omitted from
    # the coarse key, but is not a custody or paid-history proof.
    return value


def resolve_date(opening, descriptor) -> ResolvedDate:
    """Resolve one date against its own current branch, without a projection.

    Read closing holdings, not an old opening snapshot or another branch's
    already resolved rolls. This module neither prepares nor executes a quarter.
    Missing applicable CB coupon coverage is left for the actual ledger to
    refuse; it never becomes a fabricated zero-rate contract here.
    """
    opening = _opening(opening)
    if descriptor is None:
        raise MissingCoverage('No authored public program covers this date.')
    descriptor = _date(descriptor)
    policy = descriptor.policy
    if type(policy) is e.PolicyRule:
        if policy.kind == 'promise':
            if type(opening.macro.guidance_active) is not bool:
                raise TypeError('Prior promise activity must be an exact Boolean.')
            if not opening.macro.guidance_active:
                raise MissingCoverage('No active prior conditional promise covers this date.')
        policy = e.PolicyRule.resolve(policy, opening)
    book = opening.sector.public_book
    rows = funding._treasuries((book.treasuries, *book.private_treasuries))
    rolls = tuple(row[0] for row in rows)
    for limit in descriptor.facility_limits:
        l._money(limit, opening.sector.scale)
    for roll in rolls:
        l._money(roll, opening.sector.scale)
    fiscal = l.FundedPublicInstructions(treasury_rolls=rolls,
        treasury_issue_authorization=sum(rolls, F(0)),
        replacement_maturity=descriptor.replacement_maturity)
    rate = (m.rational(policy.rate_pct) if type(descriptor.iorb_rate_pct) is PolicyIORB
            else descriptor.iorb_rate_pct)
    return ResolvedDate(policy, descriptor.news,
                        p.PublicStep(rate, fiscal, descriptor.facility_limits))


# Deliberately not the entire Macro record: private/latent expectations, r-star,
# credibility, hardship memory and financing state cannot separate WAIT groups.
_PUBLIC_MACRO_FIELDS = (
    'quarter', 'price_index', 'annualized_quarterly_inflation_pct',
    'four_quarter_inflation_pct', 'public_support', 'unemployment_rate_pct',
    'actual_output_index', 'output_gap_pct', 'annualized_actual_growth_pct',
)
_LOAN_KINDS = {l.Loan: 'loan', l.OperatingLoan: 'operating', l.ProjectLoan: 'project'}


def wait_observation(opening, resolved) -> tuple:
    """Return a typed, immutable, hashable COARSE pre-date-1 observation.

    V1 includes only the listed already-realized public macro indicators; F's
    nominal cash; sorted own (age, units, basis) vintages and (units, basis) WIP;
    and sorted own-loan (legal kind, lender, face, coupon rate, start, maturity,
    last paid coupon date) terms. Claim IDs, allowances, other borrowers, other
    wallets, bank books and arbitrary latent IDs/digests never enter the key.
    The current resolved published Policy, News and explicit IORB also enter;
    facility limits and Treasury calendars do not enter this coarse v1 key.

    No cell or future date vector is an argument. Current date-1 announcements
    are legitimate declared observations; future date-2+ news is not. This
    conservative grouping is not perfect-information optimality and its typed
    content binding is not empirical proof of public observability.
    """
    opening = _opening(opening)
    if type(resolved) is not ResolvedDate:
        raise TypeError('Require an exact current ResolvedDate.')
    resolved = ResolvedDate(resolved.policy, resolved.news, resolved.step)
    sector = opening.sector
    own_loans = []
    for loan in sector.loans:
        if type(loan) not in _LOAN_KINDS:
            raise TypeError('Require known exact loan contract types.')
        if loan.borrower == 'F':
            own_loans.append((_LOAN_KINDS[type(loan)], loan.lender, loan.face,
                loan.rate_pct, loan.start, loan.maturity, loan.last_coupon_paid))
    key = (
        'public_wait_observation_v1',
        ('public_macro', tuple((name, getattr(opening.macro, name))
                               for name in _PUBLIC_MACRO_FIELDS)),
        ('focal_cash', sector.deposit('F')),
        ('focal_vintages', tuple(sorted((v.age, v.units, v.basis) for v in sector.vintages))),
        ('focal_wip', (sector.wip_units, sector.wip_basis)),
        ('focal_loans', tuple(sorted(own_loans))),
        ('policy', resolved.policy), ('news', resolved.news),
        ('iorb_rate_pct', resolved.step.iorb_rate_pct),
    )
    # Exact old-record/scalar checks above precede sorting and this signature;
    # typed signatures also distinguish e.g. bool/int or float/Fraction leaves.
    return p._canonical_value(key)
