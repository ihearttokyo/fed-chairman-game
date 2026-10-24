"""Pure bounded par Treasury funding declarations, not an auction or journal.

Resolve against the OWN current branch: consenting actual principal rolls plus
only enough explicitly authorized/bid-funded bank subscriptions for the signed
Treasury coupon prefix. No CB primary purchase, future income, payroll, facility
draw or remittance supplies subscription cash. New fixed coupon rights do not
enter today's original-opening coupon bases. This neither adopts a quarter nor
certifies other public/private obligations, legal authority, custody or solvency.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F

from . import episodes as e, macro as m, ledger as l
from . import public_scenarios as s, public_forecast as p
from . import public_funding as funding, public_income as income
from . import checkpoint


@dataclass(frozen=True)
class MarketFundingDate:
    """Authored limits, not implicit funding or orders to fill the entire bid.

    All fields are required, including zero limits/rates and exact Boolean roll
    consent. ``new_issue_authorization`` is the TOTAL additional face authorized
    beyond actual consenting rolls, not a per-bank allowance. Limits and face
    are in branch nominal money units; rates are signed annual percentages and
    replacement maturity is in quarters. Priority must explicitly be A/B or B/A.
    PolicyIORB is the existing explicit nominal-policy identity, not an estimate.
    """
    policy: m.Policy | e.PolicyRule
    news: m.News
    iorb_rate_pct: F | s.PolicyIORB
    facility_limits: tuple[F, F]
    full_roll: bool
    new_issue_authorization: F
    subscription_limits: tuple[F, F]
    subscription_rates_pct: tuple[F, F]
    replacement_maturity: F
    allocation_priority: tuple[str, str]

    def __post_init__(self):
        for field in fields(MarketFundingDate):
            _check_shapes(object.__getattribute__(self, field.name))
        object.__setattr__(self, 'policy', s._policy_descriptor(self.policy))
        object.__setattr__(self, 'news', s._news(self.news))
        rate = (s.PolicyIORB() if type(self.iorb_rate_pct) is s.PolicyIORB
                else funding._number(self.iorb_rate_pct, signed=True))
        object.__setattr__(self, 'iorb_rate_pct', rate)
        object.__setattr__(self, 'facility_limits',
                           funding._vector(self.facility_limits, 2, 'Facility limits'))
        if type(self.full_roll) is not bool:
            raise TypeError('Full-roll consent must be an exact Boolean.')
        object.__setattr__(self, 'new_issue_authorization',
                           funding._number(self.new_issue_authorization))
        object.__setattr__(self, 'subscription_limits',
                           funding._vector(self.subscription_limits, 2, 'Subscription limits'))
        object.__setattr__(self, 'subscription_rates_pct', funding._vector(
            self.subscription_rates_pct, 2, 'New annual coupon rates', signed=True))
        maturity = funding._number(self.replacement_maturity)
        if not 1 <= maturity <= 120:
            raise ValueError('Replacement Treasury maturity must lie in 1..120 quarters.')
        object.__setattr__(self, 'replacement_maturity', maturity)
        priority = self.allocation_priority
        if (type(priority) is not tuple or len(priority) != 2
                or any(type(bank) is not str for bank in priority)):
            raise TypeError('Allocation priority requires an immutable pair of plain bank names.')
        if priority not in (('A', 'B'), ('B', 'A')):
            raise ValueError('Allocation priority must be A/B or B/A, without a CB bid.')


def _check_shapes(value):
    """Reject instance-supplied schemas before the older canonical walker.

    These exact frozen records have ordinary instance dictionaries. Class
    fields are the schema; an instance's replacement metadata is not authority
    to omit version checks or run a mapping callback during traversal.
    """
    cls = type(value)
    if any(cls is scalar for scalar in (type(None), str, bool, int, float, F)):
        return
    if cls is tuple:
        for item in value:
            _check_shapes(item)
        return
    if not any(cls is record for record in
               (*checkpoint._TAGS, e.PolicyRule, s.PolicyIORB, MarketFundingDate)):
        raise TypeError('Require exact immutable records with class-defined fields.')
    schema = fields(cls)
    attributes = object.__getattribute__(value, '__dict__')
    if (type(attributes) is not dict
            or any(type(key) is not str for key in attributes)
            or set(attributes) != {field.name for field in schema}):
        raise TypeError('Record fields cannot be replaced or supplemented by instance metadata.')
    for field in schema:
        _check_shapes(object.__getattribute__(value, field.name))


def _reconstruct(value):
    """Recheck old constructors ONLY after the entire root is canonical.

    Exact outer records alone do not validate constructor-bypassed numeric
    leaves, versions or cross-component accounting. No caller-defined type is
    invoked: the preceding deep canonical pass restricts this tree to the
    existing closed registry and built-in immutable scalars/tuples.
    """
    if type(value) is tuple:
        return tuple(_reconstruct(item) for item in value)
    if type(value) in (type(None), str, bool, int, float, F):
        return value
    return type(value)(**{field.name: _reconstruct(getattr(value, field.name))
                          for field in fields(type(value))})


def _opening(value, book_type=l.FundedPublicBook):
    if (book_type is not l.FundedPublicBook and book_type is not l.PaydatePublicBook
            and book_type is not l.EarlyPaydateBook):
        raise TypeError('Require an explicitly supported public-book convention.')
    if type(value) is not m.Envelope:
        raise TypeError('Require the exact current branch Envelope.')
    _check_shapes(value)
    p._canonical_value(value)  # Reject ALL hostile leaves before any constructor.
    if type(value.macro) is not m.Macro or type(value.sector) is not l.SectorState:
        raise TypeError('Require exact macro and sector records.')
    if type(value.sector.public_book) is not book_type:
        raise TypeError('Require the exact selected public-book convention.')
    checked = _reconstruct(value)
    # Validate the predecessor, not a rewritten paid IORB or prior snapshot.
    p._paid_economy(checked)
    sector = checked.sector
    if book_type is l.EarlyPaydateBook:
        l.validate_early_paydate_public(sector.public_book, sector.scale, sector.quarter,
            None if sector.last is None else sector.last.payments,
            None if sector.last is None else sector.last.trace)
    elif book_type is l.PaydatePublicBook:
        l.validate_paydate_public(sector.public_book, sector.scale, sector.quarter,
            None if sector.last is None else sector.last.payments,
            None if sector.last is None else sector.last.trace)
    else:
        l.validate_funded_public(sector.public_book, sector.scale, sector.quarter,
                                None if sector.last is None else sector.last.payments)
    return checked


def resolve_date(opening, descriptor) -> s.ResolvedDate:
    """The original funded-book route; it does not admit the paydate subtype."""
    return _resolve_date(opening, descriptor, l.FundedPublicBook)


def resolve_paydate_date(opening, descriptor) -> s.ResolvedDate:
    """Explicit paydate-book route, sharing the same bounded fiscal arithmetic.

    This neither settles nor certifies household coupons after wages. The new
    current/future adapter owns that separate conditional and actual closure.
    """
    return _resolve_date(opening, descriptor, l.PaydatePublicBook)


def resolve_early_paydate_date(opening, descriptor) -> s.ResolvedDate:
    """Exact early-book route through the SAME bounded Treasury arithmetic.

    Prior paid payments AND trace validate before quoting changed IORB. This
    neither draws early credit nor expands Treasury subscription funding; the
    separate current bridge and sole journal own early-credit qualification.
    """
    return _resolve_date(opening, descriptor, l.EarlyPaydateBook)


def _resolve_date(opening, descriptor, book_type) -> s.ResolvedDate:
    """Quote one immutable bounded command; zero preparation/executor calls.

    RRP return and unrolled PRIVATE due principal are available at subscription
    settlement. CB returned principal reduces TGA, never private reserves. All
    eleven coupons are quoted on original stocks, but ONLY Treasury affordability
    is checked here. In particular, a later household mortgage failure is not
    converted into a Treasury coupon-funding failure by a whole-income preflight.
    Historical paid-book validation retains its existing full-prefix checks.
    """
    checkpoint._check_sources()
    opening = _opening(opening, book_type)
    if descriptor is None:
        raise s.MissingCoverage('No authored market-funding program covers this date.')
    if type(descriptor) is not MarketFundingDate:
        raise TypeError('Require an exact MarketFundingDate or missing coverage None.')
    _check_shapes(descriptor)
    descriptor = MarketFundingDate(**{field.name: getattr(descriptor, field.name)
                                     for field in fields(MarketFundingDate)})
    sector = opening.sector; book = sector.public_book
    for value in (*descriptor.facility_limits, descriptor.new_issue_authorization,
                  *descriptor.subscription_limits):
        l._money(value, sector.scale)
    rows = funding._treasuries((book.treasuries, *book.private_treasuries))
    due = tuple(row[0] for row in rows)
    rolls = due if descriptor.full_roll else (F(0), F(0), F(0))
    for roll in rolls:
        l._money(roll, sector.scale)

    policy = descriptor.policy
    if type(policy) is e.PolicyRule:
        if policy.kind == 'promise' and not opening.macro.guidance_active:
            raise s.MissingCoverage('No active prior conditional promise covers this date.')
        policy = e.PolicyRule.resolve(policy, opening)
    rate = (m.rational(policy.rate_pct) if type(descriptor.iorb_rate_pct) is s.PolicyIORB
            else descriptor.iorb_rate_pct)
    source = funding.FundingOpening(quarter=sector.quarter + 1, scale=sector.scale,
        terms=replace(book.terms, iorb_rate_pct=rate), treasuries=rows,
        mortgages=book.mortgages, reserves=tuple(bank.reserves for bank in sector.banks),
        household_deposits=tuple(sector.deposit(owner) for owner in ('HA', 'HB')),
        cb_faces=tuple(sector.cb_debt(bank) for bank in l.BANKS),
        rrp_faces=tuple(sector.rrp_face(bank) for bank in l.BANKS),
        tga=book.tga, deferred=book.deferred_asset)
    observations = income.quote(source.terms, treasuries=source.treasuries,
        mortgages=source.mortgages, reserves=source.reserves, cb_faces=source.cb_faces,
        rrp_faces=source.rrp_faces, scale=source.scale)
    c_cb, c_a, c_b = (line.settled for line in observations[:3])
    prefix = max(F(0), c_cb, c_cb + c_a, c_cb + c_a + c_b)
    unrolled = tuple(face - roll for face, roll in zip(due, rolls))
    quantum = source.scale * funding.QUANTUM
    shortage = max(F(0), sum(unrolled, F(0)) + prefix - source.tga)
    need = -(-shortage // quantum) * quantum
    if need > descriptor.new_issue_authorization:
        raise p.FundingFailure('Required new Treasury cash exceeds explicit additional authorization.')

    # Floor each owned reserve capacity; inherited off-grid dust is not a bid.
    available = tuple(((reserve + returned + redeemed) // quantum) * quantum
        for reserve, returned, redeemed in zip(source.reserves, source.rrp_faces, unrolled[1:]))
    subscribed = [F(0), F(0)]
    left = need
    for bank in descriptor.allocation_priority:
        index = l.BANKS.index(bank)
        take = min(left, descriptor.subscription_limits[index], available[index])
        subscribed[index] = take
        left -= take
    if left:
        raise p.FundingFailure('Declared bank bids or actual subscription reserves cannot fund Treasury cash.')
    subscriptions = tuple(subscribed)
    masses = tuple(face * coupon_rate / 100
                   for face, coupon_rate in zip(subscriptions, descriptor.subscription_rates_pct))
    batch = funding.FundingBatch(rolls=rolls, subscriptions=subscriptions,
        subscription_coupon_mass=masses,
        authorization=sum(rolls, F(0)) + descriptor.new_issue_authorization,
        maturity=descriptor.replacement_maturity)
    try:
        principal = funding.project_batch(source, batch)
    except ValueError as error:
        raise p.FundingFailure(str(error)) from error
    # Signed private Treasury coupons still need their own holder's reserves.
    # Check ONLY this early Treasury phase; no IORB/remittance netting or loans.
    tga = principal.tga
    reserves = list(principal.reserves)
    for index, line in enumerate(observations[:3]):
        tga -= line.settled
        if tga < 0:
            raise p.FundingFailure('Treasury coupon exceeds actual TGA funding.')
        if index:
            reserves[index - 1] += line.settled
            if reserves[index - 1] < 0:
                raise p.FundingFailure('Treasury coupon exceeds bank-owned reserves.')
    fiscal = l.FundedPublicInstructions(treasury_rolls=batch.rolls,
        treasury_subscriptions=batch.subscriptions,
        subscription_coupon_mass=batch.subscription_coupon_mass,
        treasury_issue_authorization=batch.authorization,
        replacement_maturity=batch.maturity)
    return s.ResolvedDate(policy, descriptor.news,
                          p.PublicStep(rate, fiscal, descriptor.facility_limits))
