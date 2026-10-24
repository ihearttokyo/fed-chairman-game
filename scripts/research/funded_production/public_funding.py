"""Pure, immutable public-funding arithmetic, not a second monetary ledger.

Inputs are asserted snapshots; these checks establish neither their custody nor
paid/future qualification. Principal and coupon projections use the declared
source order, not an intraday solvency theorem. Transfers move exact contractual
cash rights at explicit par only; no market pricing or empirical fit is implied.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from fractions import Fraction as F
import math

from . import public_income
from .numerics import amount, _signed, distribute
from .public_income import CouponLine, PublicIncomeTerms


ZERO = F(0)
QUANTUM = F(1, 10**6)
OWNERS = ('CB', 'A', 'B')
BANKS = ('A', 'B')
FacePair = tuple[F, F]
FaceTriple = tuple[F, F, F]
FaceRow = tuple[F, ...]  # Exactly 120 immutable dated buckets at the boundary.
Treasuries = tuple[FaceRow, FaceRow, FaceRow]
OptionalMassPair = tuple[F | None, F | None]
CashReceipt = tuple[str, str, F, str, str | None]
Payments = tuple[CashReceipt, ...]


def _number(value: F, *, signed: bool = False) -> F:
    # Built-in scalar types only: no Boolean, callback or numeric proxy.
    if type(value) is not int and type(value) is not float and type(value) is not F:
        raise TypeError('Require a finite numeric scalar, not Boolean or callback.')
    # Fraction(int-subclass) can retain callback-bearing numerator/denominator
    # objects even though its outer type is exactly Fraction.
    if type(value) is F and (type(value.numerator) is not int
                            or type(value.denominator) is not int):
        raise TypeError('Fraction components must be plain integers.')
    if type(value) is F and (value.denominator <= 0
                            or math.gcd(value.numerator, value.denominator) != 1):
        raise ValueError('Fraction components must be reduced with positive denominator.')
    return _signed(value) if signed else amount(value)


def _vector(values: tuple, size: int, name: str, *, signed: bool = False,
            optional: bool = False) -> tuple:
    if type(values) is not tuple or len(values) != size:
        raise TypeError(f'{name} requires an immutable {size}-scalar tuple.')
    return tuple(None if optional and x is None else _number(x, signed=signed)
                 for x in values)


def _treasuries(values: Treasuries) -> Treasuries:
    if type(values) is not tuple or len(values) != 3:
        raise TypeError('Require immutable CB/A/B Treasury pools.')
    return tuple(_vector(row, 120, 'Treasury pool') for row in values)


def _owned_terms(treasuries: Treasuries, terms: PublicIncomeTerms) -> None:
    if type(terms) is not PublicIncomeTerms:
        raise TypeError('Require explicit immutable PublicIncomeTerms.')
    for row in terms.annual_treasury:
        _vector(row, 120, 'Treasury coupon masses', signed=True)
    for rates in (terms.mortgage_rates_pct, terms.cb_rates_pct, terms.rrp_rates_pct):
        _vector(rates, 2, 'Coupon rates', signed=True, optional=True)
    _number(terms.iorb_rate_pct, signed=True)
    if any(not face and mass
           for faces, masses in zip(treasuries, terms.annual_treasury)
           for face, mass in zip(faces, masses)):
        raise ValueError('A Treasury coupon mass requires actual owned principal.')


def _receipts(values: Payments) -> Payments:
    if type(values) is not tuple:
        raise TypeError('Require immutable scalar cash receipts.')
    result = []
    for receipt in values:
        if type(receipt) is not tuple or len(receipt) != 5:
            raise TypeError('Each cash receipt requires five immutable scalars.')
        payer, payee, value, kind, claim = receipt
        if any(type(x) is not str or not x for x in (payer, payee, kind)):
            raise TypeError('Receipt routes and kind require explicit text.')
        if claim is not None and type(claim) is not str:
            raise TypeError('Receipt claim must be text or None.')
        value = _number(value)
        if not value:
            raise ValueError('Zero cash receipts must be omitted.')
        result.append((payer, payee, value, kind, claim))
    return tuple(result)


def _cash_fields(record: object) -> None:
    for name in ('reserves', 'household_deposits'):
        object.__setattr__(record, name, _vector(getattr(record, name), 2, name))
    object.__setattr__(record, 'tga', _number(record.tga))


@dataclass(frozen=True)
class FundingOpening:
    quarter: int
    scale: F
    terms: PublicIncomeTerms
    treasuries: Treasuries
    mortgages: FacePair = (ZERO, ZERO)
    reserves: FacePair = (ZERO, ZERO)
    household_deposits: FacePair = (ZERO, ZERO)
    cb_faces: FacePair = (ZERO, ZERO)
    rrp_faces: FacePair = (ZERO, ZERO)
    tga: F = ZERO
    deferred: F = ZERO

    def __post_init__(self) -> None:
        if type(self.quarter) is not int:
            raise TypeError('Funding quarter must be an integer, not Boolean.')
        if self.quarter < 1:
            raise ValueError('Funding quarter must be at least one.')
        object.__setattr__(self, 'scale', _number(self.scale))
        if not self.scale:
            raise ValueError('Nominal scale must be positive.')
        object.__setattr__(self, 'treasuries', _treasuries(self.treasuries))
        _owned_terms(self.treasuries, self.terms)
        for name in ('mortgages', 'cb_faces', 'rrp_faces'):
            object.__setattr__(self, name, _vector(getattr(self, name), 2, name))
        _cash_fields(self)
        object.__setattr__(self, 'deferred', _number(self.deferred))


@dataclass(frozen=True)
class FundingBatch:
    rolls: FaceTriple = (ZERO, ZERO, ZERO)
    subscriptions: FacePair = (ZERO, ZERO)
    subscription_coupon_mass: OptionalMassPair = (None, None)
    authorization: F = ZERO
    maturity: F = F(120)
    mortgage_repayments: FacePair = (ZERO, ZERO)

    def __post_init__(self) -> None:
        object.__setattr__(self, 'rolls', _vector(self.rolls, 3, 'Treasury rolls'))
        for name in ('subscriptions', 'mortgage_repayments'):
            object.__setattr__(self, name, _vector(getattr(self, name), 2, name))
        object.__setattr__(self, 'subscription_coupon_mass', _vector(
            self.subscription_coupon_mass, 2, 'Subscription coupon masses',
            signed=True, optional=True))
        for face, mass in zip(self.subscriptions, self.subscription_coupon_mass):
            if face and mass is None:
                raise ValueError('Positive subscription requires explicit coupon mass.')
            if not face and mass not in (None, ZERO):
                raise ValueError('Zero subscription cannot carry coupon mass.')
        object.__setattr__(self, 'authorization', _number(self.authorization))
        object.__setattr__(self, 'maturity', _number(self.maturity))
        if not 1 <= self.maturity <= 120:
            raise ValueError('Treasury maturity must lie in 1..120 quarters.')


@dataclass(frozen=True)
class FundingProjection:
    treasuries: Treasuries
    terms: PublicIncomeTerms
    mortgages: FacePair
    reserves: FacePair
    household_deposits: FacePair
    tga: F
    payments: Payments = ()

    def __post_init__(self) -> None:
        object.__setattr__(self, 'treasuries', _treasuries(self.treasuries))
        _owned_terms(self.treasuries, self.terms)
        object.__setattr__(self, 'mortgages', _vector(self.mortgages, 2, 'Mortgages'))
        _cash_fields(self)
        object.__setattr__(self, 'payments', _receipts(self.payments))


@dataclass(frozen=True)
class FundingPrefix:
    reserves: FacePair
    household_deposits: FacePair
    tga: F
    deferred: F
    earnings: FacePair
    payments: Payments = ()

    def __post_init__(self) -> None:
        _cash_fields(self)
        object.__setattr__(self, 'deferred', _number(self.deferred))
        object.__setattr__(self, 'earnings', _vector(
            self.earnings, 2, 'Bank earnings', signed=True))
        object.__setattr__(self, 'payments', _receipts(self.payments))


def _owner(value: str) -> int:
    if type(value) is not str or value not in OWNERS:
        raise ValueError('Treasury owner must be CB, A or B.')
    return OWNERS.index(value)


@dataclass(frozen=True)
class TreasuryTransfer:
    seller: str
    buyer: str
    face: F
    annual_cash: F

    def __post_init__(self) -> None:
        _owner(self.seller)
        _owner(self.buyer)
        if self.seller == self.buyer:
            raise ValueError('Treasury transfer requires distinct owners.')
        object.__setattr__(self, 'face', _number(self.face))
        if not self.face:
            raise ValueError('Treasury transfer requires positive face.')
        object.__setattr__(self, 'annual_cash', _number(self.annual_cash, signed=True))


def _allocation(face: F, maturity: F, quantum: F) -> tuple[tuple[int, F], ...]:
    lower = int(maturity)
    upper_weight = maturity - lower
    if upper_weight:
        low, high = distribute(face, (1 - upper_weight, upper_weight), quantum)
        return ((lower - 1, low), (lower, high))
    return ((lower - 1, face),)


def project_batch(opening: FundingOpening, batch: FundingBatch) -> FundingProjection:
    """Return RRP, repay mortgages, then net the authorized Treasury calendar.

    Explicit principal instructions use scale*1e-6 money units. Inherited stocks
    may contain off-grid dust, as in the source calendar. Fixed coupon masses
    remain exact rights and are not money-grid rounded. No new CB primary
    subscription or future remittance supplies the funding prefix.
    """
    if type(opening) is not FundingOpening or type(batch) is not FundingBatch:
        raise TypeError('Require explicit FundingOpening and FundingBatch records.')
    quantum = opening.scale * QUANTUM
    for value in (*batch.rolls, *batch.subscriptions, batch.authorization,
                  *batch.mortgage_repayments):
        if value % quantum:
            raise ValueError('Cash/principal instruction must be a whole money quantum.')

    payments = []

    def record(payer: str, payee: str, value: F, kind: str) -> None:
        if value:
            payments.append((payer, payee, value, kind, None))

    reserves = [r + face for r, face in zip(opening.reserves, opening.rrp_faces)]
    deposits = list(opening.household_deposits)
    mortgages = list(opening.mortgages)
    for bank, face in zip(BANKS, opening.rrp_faces):
        record('CB', bank, face, 'rrp_principal_repaid')
    for i, payment in enumerate(batch.mortgage_repayments):
        if payment > min(mortgages[i], deposits[i], reserves[i]):
            raise ValueError('Mortgage principal exceeds owned deposits, reserves or legal face.')
        mortgages[i] -= payment
        deposits[i] -= payment
        reserves[i] -= payment
        record(('HA', 'HB')[i], 'MortgagePool', payment, 'household_mortgage_principal')
        record('MortgagePool', 'CB', payment, 'pass_through_mbs_principal')

    due = tuple(row[0] for row in opening.treasuries)
    if any(roll > face for roll, face in zip(batch.rolls, due)):
        raise ValueError('Treasury roll exceeds consenting holder due principal.')
    if sum(batch.rolls) + sum(batch.subscriptions) > batch.authorization:
        raise ValueError('Treasury issuance exceeds explicit issuer authorization.')
    unrolled = tuple(face - roll for face, roll in zip(due, batch.rolls))
    tga = opening.tga + sum(batch.subscriptions) - sum(unrolled)
    reserves = [r + face - sub for r, face, sub
                in zip(reserves, unrolled[1:], batch.subscriptions)]
    if tga < 0 or any(r < 0 for r in reserves):
        raise ValueError('Treasury settlement lacks actual reserves or TGA funding.')

    faces = [list(row[1:]) + [ZERO] for row in opening.treasuries]
    masses = [list(row[1:]) + [ZERO] for row in opening.terms.annual_treasury]
    for i, roll in enumerate(batch.rolls):
        if roll:
            for bucket, allocated in _allocation(roll, batch.maturity, quantum):
                faces[i][bucket] += allocated
                masses[i][bucket] += opening.terms.annual_treasury[i][0] * allocated / due[i]
    record('Treasury', 'CB', unrolled[0], 'tga_funded_treasury_redemption')
    for i, (bank, sub, mass) in enumerate(zip(
            BANKS, batch.subscriptions, batch.subscription_coupon_mass), start=1):
        if sub:
            for bucket, allocated in _allocation(sub, batch.maturity, quantum):
                faces[i][bucket] += allocated
                masses[i][bucket] += mass * allocated / sub
        net = unrolled[i] - sub
        if net >= 0:
            record('Treasury', bank, net, 'treasury_net_cash')
        else:
            record(bank, 'Treasury', -net, 'treasury_net_cash')
    return FundingProjection(
        treasuries=tuple(map(tuple, faces)),
        terms=replace(opening.terms, annual_treasury=tuple(map(tuple, masses))),
        mortgages=tuple(mortgages), reserves=tuple(reserves),
        household_deposits=tuple(deposits), tga=tga, payments=tuple(payments))


def project_income(opening: FundingOpening, projection: FundingProjection,
                   observations: tuple[CouponLine, ...]) -> FundingPrefix:
    """Validate original opening obligations and their declared funded prefix.

    Treasury CB/A/B coupons precede CB-origin outflows, then other private
    flows. There is no automatic borrowing. Remittance is available only last;
    returned receipts contain income only, never duplicate projected principal.
    Caller-supplied projection cash is not authenticated ledger cash.
    """
    if type(opening) is not FundingOpening or type(projection) is not FundingProjection:
        raise TypeError('Require explicit opening and projection records.')
    expected = public_income.quote(
        opening.terms, treasuries=opening.treasuries, mortgages=opening.mortgages,
        reserves=opening.reserves, cb_faces=opening.cb_faces,
        rrp_faces=opening.rrp_faces, scale=opening.scale)
    if (type(observations) is not tuple or len(observations) != 11
            or any(type(line) is not CouponLine for line in observations)):
        raise ValueError('Require eleven immutable public coupon observations.')
    for line in observations:
        _number(line.basis)
        _number(line.contractual, signed=True)
        _number(line.settled, signed=True)
    if observations != expected:
        raise ValueError('Public observations differ from the eleven original opening obligations.')

    reserves = list(projection.reserves)
    deposits = list(projection.household_deposits)
    tga = projection.tga
    earnings = [ZERO, ZERO]

    def bank_cash(index: int, value: F) -> None:
        if reserves[index] + value < 0:
            raise ValueError('Public coupon exceeds bank-owned reserves.')
        reserves[index] += value

    for line in expected[:3]:
        value = line.settled
        if tga - value < 0:
            raise ValueError('Treasury coupon exceeds actual TGA funding.')
        tga -= value
        if line.owner != 'CB':
            index = BANKS.index(line.owner)
            bank_cash(index, value)
            earnings[index] += value

    def cb_outflow(line: CouponLine) -> bool:
        return ((line.kind in ('iorb', 'rrp') and line.settled > 0)
                or (line.kind in ('cb_loan', 'mortgage') and line.settled < 0))

    other = expected[3:]
    ordered = tuple(z for z in other if cb_outflow(z)) + tuple(
        z for z in other if not cb_outflow(z))
    for line in ordered:
        value = line.settled
        if line.kind in ('iorb', 'rrp'):
            index = BANKS.index(line.owner)
            bank_cash(index, value)
            earnings[index] += value
        elif line.kind == 'cb_loan':
            index = BANKS.index(line.owner)
            bank_cash(index, -value)
            earnings[index] -= value
        else:
            index = ('HA', 'HB').index(line.owner)
            if deposits[index] - value < 0:
                raise ValueError('Mortgage coupon exceeds owned household deposits.')
            bank_cash(index, -value)
            deposits[index] -= value
    deferred, remit = public_income.earnings_close(
        opening.deferred, public_income.cb_profit(expected))
    return FundingPrefix(
        reserves=tuple(reserves), household_deposits=tuple(deposits),
        tga=tga + remit, deferred=deferred, earnings=tuple(earnings),
        payments=public_income.expected_payments(observations, opening.deferred))


def make_transfer(treasuries: Treasuries, terms: PublicIncomeTerms,
                  seller: str, buyer: str, face: F
                  ) -> tuple[TreasuryTransfer, Treasuries, PublicIncomeTerms]:
    """Move earliest dated face and exact proportional annual coupon rights."""
    treasuries = _treasuries(treasuries)
    _owned_terms(treasuries, terms)
    source, target = _owner(seller), _owner(buyer)
    # Reuse the event's strict identity/positive-face boundary before arithmetic.
    instruction = TreasuryTransfer(seller, buyer, face, ZERO)
    if instruction.face > sum(treasuries[source]):
        raise ValueError('Treasury seller lacks actual owned principal.')
    faces = list(map(list, treasuries))
    masses = list(map(list, terms.annual_treasury))
    left, annual_cash = instruction.face, ZERO
    for bucket, available in enumerate(treasuries[source]):
        take = min(left, available)
        if take:
            moved_mass = terms.annual_treasury[source][bucket] * take / available
            faces[source][bucket] -= take
            faces[target][bucket] += take
            masses[source][bucket] -= moved_mass
            masses[target][bucket] += moved_mass
            annual_cash += moved_mass
            left -= take
        if not left:
            break
    event = replace(instruction, annual_cash=annual_cash)
    return (event, tuple(map(tuple, faces)),
            replace(terms, annual_treasury=tuple(map(tuple, masses))))


def apply_transfer(treasuries: Treasuries, terms: PublicIncomeTerms,
                   event: TreasuryTransfer) -> tuple[Treasuries, PublicIncomeTerms]:
    """Recompute current exact rights; reject forged or no-longer-matching mass."""
    if type(event) is not TreasuryTransfer:
        raise TypeError('Require an explicit immutable TreasuryTransfer.')
    expected, faces, new_terms = make_transfer(
        treasuries, terms, event.seller, event.buyer, event.face)
    if event.annual_cash != expected.annual_cash:
        raise ValueError('Treasury transfer annual coupon rights differ from owned mass.')
    return faces, new_terms


def transfer_payment(event: TreasuryTransfer) -> CashReceipt:
    """Expected explicit-par receipt only; this does not authorize settlement.

    CB sales are mathematically representable here, not a claim that the caller
    has implemented a corresponding ledger cash handler.
    """
    if type(event) is not TreasuryTransfer:
        raise TypeError('Require an explicit immutable TreasuryTransfer.')
    kind = ('public_par_purchase' if event.buyer == 'CB' else
            'public_par_sale' if event.seller == 'CB' else 'private_public_par_trade')
    return event.buyer, event.seller, event.face, kind, 'Treasury:' + event.seller
