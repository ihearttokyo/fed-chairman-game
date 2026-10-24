"""Immutable private production/finance fixture, not the maintained game engine.

Authored par public claims, 80% collateral value, 10% private capital covenant,
fixed-price technology and household preferences are hand cases, not estimates.
The legacy public ledger is PRINCIPAL ONLY. Opt-in PublicIncomeBook adds a
stationary contractual income program. FundedPublicBook adds an explicitly
funded principal/coupon journal, NOT a qualified macro/forecast policy bridge.
PaydatePublicBook separately dates household coupons after actually paid wages;
its fixed journal witnesses are consistency observations, never custody proof.
PublicBook identifies currency/TGA/MBS
and funded Treasury calendars, QE and bank-owned RRP claims. Signed PRIVATE coupons are
contractual cashflows; negative-coupon experiments are not a Fed-policy/NIM model.
Only active claims, physical vintages and the current ordered trace are retained.
"""
from dataclasses import dataclass, replace
from collections import Counter
import copy
from fractions import Fraction as F
import math

from . import numerics as precision
from . import households as household
from . import source_data
from . import public_income
from . import public_funding
from . import early_liquidity
from .public_income import PublicIncomeTerms, CouponLine
from .public_funding import FundingOpening, FundingBatch, TreasuryTransfer

ZERO = F(0)
QUANTUM = F(1, 1000000)
HAIRCUT_VALUE = F(4, 5)
COVENANT = F(1, 10)
ACTORS = ('R', 'F', 'HA', 'HB')
BANKS = ('A', 'B')
HOME = {'R': 'A', 'HA': 'A', 'F': 'B', 'HB': 'B'}


def _number(value, signed=False):
    if isinstance(value, bool) or not isinstance(value, (int, float, F)):
        raise TypeError('Require a finite numeric amount, not Boolean or text.')
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError('Amounts and rates must be finite.')
        value = F(str(value))
    else:
        value = F(value)
    if not signed and value < 0:
        raise ValueError('Amount must be nonnegative.')
    return value


def _integer(value, name, minimum=0):
    if type(value) is not int:
        raise TypeError(f'{name} must be an integer, not Boolean.')
    if value < minimum:
        raise ValueError(f'{name} must be at least {minimum}.')
    return value


def _bank(bank):
    if type(bank) is not str:
        raise TypeError('Bank selectors must be immutable built-in text.')
    if bank not in BANKS:
        raise ValueError('Bank must be A or B.')
    return BANKS.index(bank)


def _borrower(actor):
    if type(actor) is not str or actor not in ('R','F'):
        raise ValueError('Industrial borrower must be immutable identified R or F.')
    return actor


def _money(value, scale):
    value = _number(value)
    if value % (scale * QUANTUM):
        raise ValueError('Cash/principal instruction must be a whole money quantum.')
    return value


def _floor(value, quantum):
    return (value // quantum) * quantum


def _amount_pair(values, name):
    if not isinstance(values, (tuple, list)) or len(values) != 2:
        raise TypeError(f'{name} requires exactly two bank amounts.')
    return tuple(_number(x) for x in values)


@dataclass(frozen=True)
class ProductionOrders:
    """Exogenous physical orders and current quotes, not a production planner.

    The fixed nominal unit is State.scale; these quotes never rebase stocks,
    contractual debt or historical capital basis. Workforce 0 explicitly shuts
    down hiring. The 4000/191 workforce is the authored 20/(1-.045) reference.
    """
    price_factor: F = F(1)
    real_wage: F = F(1)
    residual_workers: F = F(17)
    focal_workers: F = F(3)
    investment_units: F = F(1)
    residual_consumption: F = F(19)
    service_a: F = F(1)
    service_b: F = F(4)
    available_workers: F = F(4000, 191)
    residual_productivity: F = F(20, 17)
    service_productivity: F = F(5, 3)
    capital_productivity: F = F(5, 16)
    capital_resource_cost: F = F(1)
    cash_floor_r: F = F(17)
    cash_floor_f: F = F(3)
    preferences_a: household.Preferences = household.Preferences(19, 1, 3)
    preferences_b: household.Preferences = household.Preferences(0, 4, 1)
    expected_dividends_nominal: tuple | None = None
    initial_dividends_real: tuple = (F(3), F(1))
    market_clearing: bool = False
    max_clearing_rounds: int = 64
    demand_multiplier: F = F(1)

    def __post_init__(self):
        if type(self.market_clearing) is not bool:
            raise TypeError('market_clearing must be a built-in Boolean.')
        _integer(self.max_clearing_rounds, 'max_clearing_rounds', 1)
        positive = ('price_factor', 'real_wage', 'residual_productivity',
                    'service_productivity', 'capital_productivity',
                    'capital_resource_cost')
        for name in (*positive, 'residual_workers', 'focal_workers',
                     'investment_units', 'residual_consumption', 'service_a',
                     'service_b', 'available_workers', 'cash_floor_r', 'cash_floor_f', 'demand_multiplier'):
            value = _number(getattr(self, name))
            if name in positive and not value:
                raise ValueError(f'{name} must be positive.')
            object.__setattr__(self, name, value)
        for name in ('preferences_a', 'preferences_b'):
            prefs = getattr(self, name)
            if type(prefs) is not household.Preferences:
                raise TypeError('Both households require immutable Preferences.')
            # Validate the scalar contract as well as the frozen record type.
            for weight in (prefs.residual, prefs.services, prefs.cash):
                _number(weight)
        if self.preferences_b.residual:
            raise ValueError('This executor has no household-B residual-good purchase route.')
        if self.expected_dividends_nominal is not None:
            object.__setattr__(self, 'expected_dividends_nominal',
                               _amount_pair(self.expected_dividends_nominal, 'Expected dividends'))
        object.__setattr__(self, 'initial_dividends_real',
                           _amount_pair(self.initial_dividends_real, 'Initial dividends'))


# Both names refer to the same frozen instruction type, not an inheritance layer.
ImmutableProductionOrders = ProductionOrders
_DEFAULT_ORDERS = ProductionOrders()


@dataclass(frozen=True)
class LoanOffer:
    lender: str
    face: F
    rate_pct: F
    maturity: int
    borrower: str = 'F'

    def __post_init__(self):
        _bank(self.lender)
        _borrower(self.borrower)
        object.__setattr__(self, 'face', _number(self.face))
        object.__setattr__(self, 'rate_pct', _number(self.rate_pct, signed=True))
        _integer(self.maturity, 'Loan maturity', 1)
        if not self.face:
            raise ValueError('New loans must have positive face.')


@dataclass(frozen=True)
class OperatingLoanOffer(LoanOffer):
    """New two-settlement operating credit with a closing surplus-cash sweep.

    The originator validates maturity relative to its actual settlement date.
    Selecting this contract does not grant credit or change legacy loan terms.
    """


@dataclass(frozen=True)
class Renewal:
    loan_id: str
    face: F
    rate_pct: F
    maturity: int

    def __post_init__(self):
        if type(self.loan_id) is not str or not self.loan_id:
            raise TypeError('Renewal requires an identified loan.')
        object.__setattr__(self, 'face', _number(self.face))
        object.__setattr__(self, 'rate_pct', _number(self.rate_pct, signed=True))
        _integer(self.maturity, 'Renewal maturity', 1)
        if not self.face:
            raise ValueError('Use actual repayment rather than a zero-face renewal.')


def _cohorts(values):
    if not isinstance(values, (tuple, list)):
        raise TypeError('Treasury cohorts require an immutable numeric sequence.')
    if len(values) != 120:
        raise ValueError('Require all 120 Treasury maturity buckets.')
    return tuple(_number(x) for x in values)


def _distribute(face, weights, quantum):
    """Exact face, largest remainders, lower index wins equal remainders."""
    return precision.distribute(face, weights, quantum)


@dataclass(frozen=True)
class RRPClaim:
    bank: str
    face: F
    start: int
    maturity: int
    collateral: tuple

    def __post_init__(self):
        _bank(self.bank)
        object.__setattr__(self, 'face', _number(self.face))
        _integer(self.start, 'RRP start')
        _integer(self.maturity, 'RRP maturity', 1)
        if not self.face or self.maturity != self.start + 1:
            raise ValueError('RRP principal must have a positive one-quarter term.')
        if not isinstance(self.collateral, (tuple, list)):
            raise TypeError('RRP collateral requires identified bucket/face pairs.')
        pairs = []
        for pair in self.collateral:
            if not isinstance(pair, (tuple, list)) or len(pair) != 2:
                raise TypeError('RRP collateral requires bucket/face pairs.')
            index, face = pair
            _integer(index, 'RRP collateral index', 1)
            face = _number(face)
            if index >= 120 or not face:
                raise ValueError('RRP collateral requires positive eligible Treasury face.')
            pairs.append((index, face))
        if len({i for i, _ in pairs}) != len(pairs) or sum(v for _, v in pairs) != self.face:
            raise ValueError('RRP collateral must uniquely back the exact claim face.')
        object.__setattr__(self, 'collateral', tuple(pairs))


@dataclass(frozen=True)
class PublicBook:
    treasuries: tuple
    mbs: F
    mortgages: tuple
    currency: tuple
    tga: F
    capital_other: F = ZERO
    private_treasuries: tuple | None = None
    rrp_claims: tuple = ()

    def __post_init__(self):
        object.__setattr__(self, 'treasuries', _cohorts(self.treasuries))
        if self.private_treasuries is not None:
            if not isinstance(self.private_treasuries, (tuple, list)) or len(self.private_treasuries) != 2:
                raise TypeError('Require two identified private Treasury cohort arrays.')
            object.__setattr__(self, 'private_treasuries', tuple(_cohorts(x) for x in self.private_treasuries))
        if not isinstance(self.rrp_claims, (tuple, list)) or any(not isinstance(x, RRPClaim) for x in self.rrp_claims):
            raise TypeError('Require immutable identified RRP claims.')
        object.__setattr__(self, 'rrp_claims', tuple(self.rrp_claims))
        if len({c.bank for c in self.rrp_claims}) != len(self.rrp_claims):
            raise ValueError('Only one RRP claim per bank is permitted.')
        allocated = [ZERO] * 120
        for claim in self.rrp_claims:
            for index, face in claim.collateral:
                allocated[index] += face
        if any(v > self.treasuries[i] for i, v in enumerate(allocated)):
            raise ValueError('RRP claims cannot share or exceed owned Fed Treasury collateral.')
        for name in ('mortgages','currency'):
            object.__setattr__(self,name,_amount_pair(getattr(self,name),name))
        for name in ('mbs','tga'):
            object.__setattr__(self,name,_number(getattr(self,name)))
        object.__setattr__(self,'capital_other',_number(self.capital_other,signed=True))
        if self.mbs != sum(self.mortgages):
            raise ValueError('Pass-through pool assets must back the exact Fed MBS face.')


@dataclass(frozen=True,kw_only=True)
class PublicIncomeBook(PublicBook):
    """Opt-in stationary coupon program; legacy book fields are untouched."""
    terms: PublicIncomeTerms
    deferred_asset: F=ZERO
    income_paid_through: int=0
    observations: tuple=()
    opening_deferred_asset: F=ZERO

    def __post_init__(self):
        super().__post_init__()
        if self.private_treasuries is None:
            raise ValueError('Public income requires identified holder pools.')
        if type(self.terms) is not PublicIncomeTerms:
            raise TypeError('Require explicit public coupon terms.')
        object.__setattr__(self,'deferred_asset',_number(self.deferred_asset))
        object.__setattr__(self,'opening_deferred_asset',_number(self.opening_deferred_asset))
        _integer(self.income_paid_through,'Public income paid-through',0)
        if type(self.observations) is not tuple:
            raise TypeError('Require immutable public coupon observations.')
        if not self.income_paid_through:
            if self.observations or self.deferred_asset or self.opening_deferred_asset:
                raise ValueError('Fresh public-income books cannot invent prior earnings/losses.')
        elif len(self.observations)!=11 or any(type(z) is not CouponLine for z in self.observations):
            raise ValueError('Missing current public coupon obligation observations.')
        faces=(self.treasuries,*self.private_treasuries)
        if any(not face and mass for row,masses in zip(faces,self.terms.annual_treasury)
               for face,mass in zip(row,masses)):
            raise ValueError('Public coupon mass requires actual owned Treasury face.')


@dataclass(frozen=True, kw_only=True)
class FundedPublicBook(PublicIncomeBook):
    """One bounded opening/batch/transfer proof for the current paid quarter.

    The snapshot establishes consistency, not custody or a second paid ledger.
    Semantic validation belongs at ledger/codec boundaries, not intermediate
    journal replacements while principal and income phases are still running.
    """
    opening: FundingOpening | None = None
    funding: FundingBatch | None = None
    transfers: tuple[TreasuryTransfer, ...] = ()

    def __post_init__(self):
        super().__post_init__()
        if self.opening is not None and type(self.opening) is not FundingOpening:
            raise TypeError('Require an explicit immutable funding opening.')
        if self.funding is not None and type(self.funding) is not FundingBatch:
            raise TypeError('Require an explicit immutable funding batch.')
        if type(self.transfers) is not tuple or any(type(z) is not TreasuryTransfer for z in self.transfers):
            raise TypeError('Require ordered immutable Treasury transfer events.')


PAYDATE_PHASES = ('opening', 'principal', 'early_income', 'funded_payroll',
                  'household_income', 'income_close', 'trading_close')


@dataclass(frozen=True, kw_only=True)
class PaydateSnapshot:
    """Read-only boundary observations of the ONE journal, never owned cash."""
    reserves: tuple
    wallets: tuple  # ACTORS order: R, F, HA, HB, including firm-owned cash.
    cb_faces: tuple
    treasuries: tuple
    terms: PublicIncomeTerms
    mortgages: tuple
    rrp_faces: tuple
    currency: tuple
    capital_other: F
    tga: F
    deferred: F
    previous_income: tuple  # Signed actual prior disposable income, or Q0 seeds.
    previous_dividends: tuple  # Actual prior firm+bank dividends; (None, None) at Q0.

    def __post_init__(self):
        for name in ('reserves', 'cb_faces', 'mortgages', 'rrp_faces', 'currency'):
            object.__setattr__(self, name, public_funding._vector(getattr(self, name), 2, name))
        object.__setattr__(self, 'wallets', public_funding._vector(self.wallets, 4, 'Wallets'))
        object.__setattr__(self, 'previous_income', public_funding._vector(
            self.previous_income, 2, 'Previous paid disposable income', signed=True))
        object.__setattr__(self, 'previous_dividends', public_funding._vector(
            self.previous_dividends, 2, 'Previous paid dividends', optional=True))
        object.__setattr__(self, 'treasuries', public_funding._treasuries(self.treasuries))
        public_funding._owned_terms(self.treasuries, self.terms)
        for name in ('tga', 'deferred'):
            object.__setattr__(self, name, public_funding._number(getattr(self, name)))
        object.__setattr__(self, 'capital_other', public_funding._number(self.capital_other, signed=True))


@dataclass(frozen=True)
class PaydatePhase:
    name: str
    payment_end: int
    trace_end: int
    snapshot: PaydateSnapshot

    def __post_init__(self):
        if type(self.name) is not str or self.name not in PAYDATE_PHASES:
            raise ValueError('Unknown fixed paydate phase.')
        _integer(self.payment_end, 'Phase payment boundary')
        _integer(self.trace_end, 'Phase trace boundary', 1)
        if type(self.snapshot) is not PaydateSnapshot:
            raise TypeError('Require an explicit immutable paydate snapshot.')


@dataclass(frozen=True, kw_only=True)
class PaydatePublicBook(FundedPublicBook):
    """Fresh opt-in paid-payroll calendar; no funded-career migration.

    Positions reference the actual Report payments/trace, not a projection or
    another spendable ledger. Consistency witnesses establish no custody.
    """
    phases: tuple = ()
    paid_wages: tuple = (ZERO, ZERO)
    household_income: tuple = (ZERO, ZERO)

    def __post_init__(self):
        super().__post_init__()
        if type(self.phases) is not tuple or any(type(p) is not PaydatePhase for p in self.phases):
            raise TypeError('Require immutable ordered paydate phase witnesses.')
        object.__setattr__(self, 'paid_wages', public_funding._vector(self.paid_wages, 2, 'Paid wages'))
        object.__setattr__(self, 'household_income', public_funding._vector(
            self.household_income, 2, 'Signed settled household income', signed=True))


EARLY_PAYDATE_PHASES = ('opening', 'principal', 'early_credit', 'early_income',
                        'funded_payroll', 'household_income', 'income_close', 'trading_close')


@dataclass(frozen=True)
class EarlyPhase:
    """Separate fixed schema; never admitted as an old PaydatePhase."""
    name: str
    payment_end: int
    trace_end: int
    snapshot: PaydateSnapshot

    def __post_init__(self):
        if type(self.name) is not str or self.name not in EARLY_PAYDATE_PHASES:
            raise ValueError('Unknown fixed early-paydate phase.')
        _integer(self.payment_end, 'Early phase payment boundary')
        _integer(self.trace_end, 'Early phase trace boundary', 1)
        if type(self.snapshot) is not PaydateSnapshot:
            raise TypeError('Require an exact read-only PaydateSnapshot.')


@dataclass(frozen=True)
class EarlyCreditWitness:
    """Asserted original claims/current conditions, not historical custody."""
    plan: early_liquidity.EarlyPlan
    old_loans: tuple
    private_loans: tuple
    replacement_loans: tuple

    def __post_init__(self):
        if type(self.plan) is not early_liquidity.EarlyPlan:
            raise TypeError('Require the exact conditional early-credit plan.')
        for name in ('old_loans', 'private_loans', 'replacement_loans'):
            if type(getattr(self, name)) is not tuple:
                raise TypeError('Require immutable early-credit claim collections.')


@dataclass(frozen=True)
class LaterCreditWitness:
    """A current-condition observation for one actual later reserve advance."""
    bank: str
    payment_position: int
    trace_start: int
    snapshot: PaydateSnapshot
    private_loans: tuple
    transit_deposits: tuple
    old_loan: object
    offered_limit: F
    gross_before: F
    advance: F
    new_loan: object

    def __post_init__(self):
        if type(self.bank) is not str or self.bank not in BANKS:
            raise TypeError('Require a known exact bank identity.')
        _integer(self.payment_position, 'Later CB payment position')
        _integer(self.trace_start, 'Later CB trace position')
        if type(self.snapshot) is not PaydateSnapshot or type(self.private_loans) is not tuple:
            raise TypeError('Require exact immutable later-credit observations.')
        object.__setattr__(self, 'transit_deposits', public_funding._vector(
            self.transit_deposits, 2, 'Actual undelivered transit deposits'))
        for name in ('offered_limit', 'gross_before', 'advance'):
            object.__setattr__(self, name, public_funding._number(getattr(self, name)))


@dataclass(frozen=True, kw_only=True)
class EarlyPaydateBook(FundedPublicBook):
    """Fresh opt-in atomic-novation calendar, NOT a migrated paid book."""
    phases: tuple = ()
    paid_wages: tuple = (ZERO, ZERO)
    household_income: tuple = (ZERO, ZERO)
    early_credit: EarlyCreditWitness | None = None
    closing_cb_loans: tuple = ()
    closing_private_loans: tuple = ()
    later_credit: tuple = ()

    def __post_init__(self):
        super().__post_init__()
        if type(self.phases) is not tuple or any(type(p) is not EarlyPhase for p in self.phases):
            raise TypeError('Require exact immutable EarlyPhase witnesses.')
        object.__setattr__(self, 'paid_wages', public_funding._vector(self.paid_wages, 2, 'Paid wages'))
        object.__setattr__(self, 'household_income', public_funding._vector(
            self.household_income, 2, 'Signed settled household income', signed=True))
        if self.early_credit is not None and type(self.early_credit) is not EarlyCreditWitness:
            raise TypeError('Require an exact immutable early-credit witness.')
        if type(self.later_credit) is not tuple or any(type(w) is not LaterCreditWitness for w in self.later_credit):
            raise TypeError('Require exact immutable later-credit witnesses.')
        if type(self.closing_cb_loans) is not tuple or type(self.closing_private_loans) is not tuple:
            raise TypeError('Require immutable closing CB claims.')


HOUSEHOLD_LIQUIDITY_PHASES = ('opening', 'principal', 'early_credit', 'early_income',
    'funded_payroll', 'household_credit', 'household_income', 'income_close', 'trading_close')


@dataclass(frozen=True)
class HouseholdLiquidityPhase:
    """New exact nine-phase schema, never an old EarlyPhase/PaydatePhase."""
    name: str
    payment_end: int
    trace_end: int
    snapshot: PaydateSnapshot

    def __post_init__(self):
        if type(self.name) is not str or self.name not in HOUSEHOLD_LIQUIDITY_PHASES:
            raise ValueError('Unknown fixed household-liquidity phase.')
        _integer(self.payment_end, 'Household phase payment boundary')
        _integer(self.trace_end, 'Household phase trace boundary', 1)
        if type(self.snapshot) is not PaydateSnapshot:
            raise TypeError('Require an exact read-only PaydateSnapshot.')


@dataclass(frozen=True)
class HouseholdLiquidityWitness:
    """Current post-payroll conditions; private inventory binds to real flows."""
    plan: early_liquidity.HouseholdLiquidityPlan
    private_loans: tuple

    def __post_init__(self):
        if type(self.plan) is not early_liquidity.HouseholdLiquidityPlan:
            raise TypeError('Require the exact HouseholdLiquidityPlan.')
        if type(self.private_loans) is not tuple:
            raise TypeError('Require immutable current private claim observations.')


@dataclass(frozen=True, kw_only=True)
class HouseholdLiquidityBook(FundedPublicBook):
    """Fresh opt-in actual-payroll liquidity; no paid-book/schema migration."""
    phases: tuple = ()
    paid_wages: tuple = (ZERO, ZERO)
    household_income: tuple = (ZERO, ZERO)
    early_credit: EarlyCreditWitness | None = None
    closing_cb_loans: tuple = ()
    closing_private_loans: tuple = ()
    later_credit: tuple = ()
    household_credit: HouseholdLiquidityWitness | None = None

    def __post_init__(self):
        super().__post_init__()
        if type(self.phases) is not tuple or any(type(p) is not HouseholdLiquidityPhase for p in self.phases):
            raise TypeError('Require exact immutable HouseholdLiquidityPhase witnesses.')
        object.__setattr__(self, 'paid_wages', public_funding._vector(self.paid_wages, 2, 'Paid wages'))
        object.__setattr__(self, 'household_income', public_funding._vector(
            self.household_income, 2, 'Signed settled household income', signed=True))
        if self.early_credit is not None and type(self.early_credit) is not EarlyCreditWitness:
            raise TypeError('Require the exact early-credit witness.')
        if self.household_credit is not None and type(self.household_credit) is not HouseholdLiquidityWitness:
            raise TypeError('Require the exact household-liquidity witness.')
        if type(self.later_credit) is not tuple or any(type(w) is not LaterCreditWitness for w in self.later_credit):
            raise TypeError('Require exact immutable actual draw witnesses.')
        if type(self.closing_cb_loans) is not tuple or type(self.closing_private_loans) is not tuple:
            raise TypeError('Require immutable closing actual claims.')


def _is_early_paydate(book):
    return type(book) is EarlyPaydateBook or type(book) is HouseholdLiquidityBook


def _is_paydate(book):
    return type(book) is PaydatePublicBook or _is_early_paydate(book)


def _validate_paydate_book(book, scale, quarter, payments=None, trace=None):
    # Code-owned exact selector; callers/data cannot supply a validator/schema.
    if type(book) is HouseholdLiquidityBook:
        return validate_household_liquidity_public(book, scale, quarter, payments, trace)
    if type(book) is EarlyPaydateBook:
        return validate_early_paydate_public(book, scale, quarter, payments, trace)
    if type(book) is PaydatePublicBook:
        return validate_paydate_public(book, scale, quarter, payments, trace)
    raise TypeError('Require an exact known paydate book.')


# Include unsupported cash routes too, so invented receipts cannot disappear
# from the exact principal/trade multiset merely by selecting another kind.
FUNDED_PUBLIC_PAYMENT_KINDS = frozenset((
    'rrp_principal_repaid', 'rrp_principal_advanced',
    'household_mortgage_principal', 'pass_through_mbs_principal',
    'tga_funded_treasury_redemption', 'treasury_net_cash',
    'private_public_par_trade', 'public_par_purchase', 'public_par_sale'))


def validate_funded_public(book, scale, quarter, payments=None):
    """Bind current final rights and receipts to the ORIGINAL opening bases.

    Closing private reserves/deposits may include subsequent production and
    credit operations. Their early public prefix is checked live by the sole
    transaction, not inferred from unrelated closing private balances here.
    """
    if type(book) is not FundedPublicBook:
        raise TypeError('Require the exact funded public book subtype.')
    scale = public_funding._number(scale)
    if not scale:
        raise ValueError('Nominal scale must be positive.')
    _integer(quarter, 'Funded public quarter')
    if book.income_paid_through != quarter:
        raise ValueError('Funded public income clock differs from the ledger quarter.')
    if not quarter:
        if book.opening is not None or book.funding is not None or book.transfers:
            raise ValueError('Fresh funded public books cannot invent a paid snapshot/batch/transfer.')
        if book.observations or book.deferred_asset or book.opening_deferred_asset:
            raise ValueError('Fresh funded public books cannot invent paid obligations.')
        expected_principal = ()
    else:
        opening, batch = book.opening, book.funding
        if type(opening) is not FundingOpening or type(batch) is not FundingBatch:
            raise ValueError('Paid funded public book requires its opening snapshot and batch.')
        if opening.quarter != quarter or opening.scale != scale:
            raise ValueError('Funding opening source clock/scale differs from the ledger.')
        projection = public_funding.project_batch(opening, batch)
        prefix = public_funding.project_income(opening, projection, book.observations)
        faces, terms = projection.treasuries, projection.terms
        expected_principal = list(projection.payments)
        for event in book.transfers:
            if event.seller == 'CB':
                raise ValueError('Funded public CB secondary sales lack a cash settlement handler.')
            _money(event.face, scale)
            faces, terms = public_funding.apply_transfer(faces, terms, event)
            expected_principal.append(public_funding.transfer_payment(event))
        if (book.treasuries, *book.private_treasuries) != faces or book.terms != terms:
            raise ValueError('Funded public closing Treasury face/coupon rights differ from the batch/transfers.')
        if book.mortgages != projection.mortgages or book.mbs != sum(projection.mortgages):
            raise ValueError('Funded public closing mortgages differ from matched principal repayments.')
        if (book.tga != prefix.tga or book.deferred_asset != prefix.deferred
                or book.opening_deferred_asset != opening.deferred):
            raise ValueError('Funded public TGA/deferred close differs from paid opening obligations.')
        if book.rrp_claims:
            raise ValueError('Funded public new RRP contracts are not implemented.')
    if payments is not None:
        payments = tuple(payments)
        actual = tuple((p.payer, p.payee, p.amount, p.kind, p.claim_id)
                       for p in payments if p.kind in FUNDED_PUBLIC_PAYMENT_KINDS)
        if Counter(actual) != Counter(expected_principal):
            raise ValueError('Funded public principal/trade receipt identities/amounts/coverage differ from obligations.')
        public_income.validate_payments(payments, book.observations, book.opening_deferred_asset)


def _paydate_receipt(payment):
    return payment.payer, payment.payee, payment.amount, payment.kind, payment.claim_id


def _paydate_ordered_lines(lines, household_phase=False):
    selected = tuple(z for z in lines if (z.kind == 'mortgage') == household_phase)
    treasury = tuple(z for z in selected if z.kind == 'treasury')
    other = tuple(z for z in selected if z.kind != 'treasury')
    def cb_outflow(z):
        return ((z.kind in ('iorb', 'rrp') and z.settled > 0)
                or (z.kind in ('cb_loan', 'mortgage') and z.settled < 0))
    return treasury + tuple(z for z in other if cb_outflow(z)) + tuple(
        z for z in other if not cb_outflow(z))


def _paydate_coupon_receipts(lines):
    """Exact ordered receipts, without adding an early hypothetical remittance."""
    receipts = []
    def add(payer, payee, value, kind, claim):
        if value < 0:
            payer, payee, value = payee, payer, -value
        if value:
            receipts.append((payer, payee, value, kind, claim))
    for z in lines:
        claim = z.kind + ':' + z.owner
        if z.kind == 'treasury':
            add('Treasury', 'CB' if z.owner == 'CB' else 'Bank' + z.owner,
                z.settled, 'treasury_coupon', 'Treasury:' + z.owner)
        elif z.kind == 'mortgage':
            add(z.owner, 'MortgagePool', z.settled, 'mortgage_coupon', claim)
            add('MortgagePool', 'CB', z.settled, 'mbs_coupon', claim)
        elif z.kind == 'cb_loan':
            add('Bank' + z.owner, 'CB', z.settled, 'cb_loan_coupon', claim)
        else:
            add('CB', 'Bank' + z.owner, z.settled, z.kind + '_coupon', claim)
    return tuple(receipts)


def _paydate_income_snapshot(snapshot, lines):
    """Reconcile fixed coupon receipts at a boundary, not a spendable ledger."""
    reserves, wallets, tga = list(snapshot.reserves), list(snapshot.wallets), snapshot.tga
    for z in lines:
        value = z.settled
        if z.kind == 'treasury':
            tga -= value
            if z.owner != 'CB':
                reserves[BANKS.index(z.owner)] += value
        elif z.kind in ('iorb', 'rrp'):
            reserves[BANKS.index(z.owner)] += value
        elif z.kind == 'cb_loan':
            reserves[BANKS.index(z.owner)] -= value
        else:
            wallets[ACTORS.index(z.owner)] -= value
            reserves[BANKS.index(HOME[z.owner])] -= value
        if tga < 0 or min(reserves) < 0 or min(wallets) < 0:
            raise ValueError('Paydate coupon prefix exceeds actual TGA, reserves or owned deposits.')
    return replace(snapshot, reserves=tuple(reserves), wallets=tuple(wallets), tga=tga)


def _paydate_private_snapshot(snapshot, payment, transfers, transfer_index, scale):
    """Reconcile actual posted cash, including interposed credit and reserves.

    This is monetary movement validation only, not re-execution of production,
    credit approval or a claim to authenticate an asserted historical opening.
    """
    payer, payee, value, kind, claim = _paydate_receipt(payment)
    reserves, wallets, cb = list(snapshot.reserves), list(snapshot.wallets), list(snapshot.cb_faces)
    changes = {}
    def reserve_move(source, target):
        if source != target:
            reserves[BANKS.index(source)] -= value
            reserves[BANKS.index(target)] += value
    actor_routes = {
        'residual_payroll': ('R', 'HA'), 'focal_payroll': ('F', 'HB'),
        'residual_consumption': ('HA', 'R'), 'investment': ('F', 'R'),
        'residual_dividend': ('R', 'HA'), 'focal_dividend': ('F', 'HB')}
    if kind in actor_routes or kind == 'services':
        allowed = (('HA', 'F'), ('HB', 'F')) if kind == 'services' else (actor_routes[kind],)
        if (payer, payee) not in allowed or claim is not None:
            raise ValueError('Misidentified paydate private cash receipt.')
        wallets[ACTORS.index(payer)] -= value
        wallets[ACTORS.index(payee)] += value
        reserve_move(HOME[payer], HOME[payee])
    elif kind in ('loan_origination', 'renewal_net_cash', 'private_coupon', 'private_principal'):
        if not claim:
            raise ValueError('Private debt cash requires an identified claim.')
        bank_names = {'BankA': 'A', 'BankB': 'B'}
        if payer in bank_names and payee in ('R', 'F') and kind != 'private_principal':
            wallets[ACTORS.index(payee)] += value
            reserve_move(bank_names[payer], HOME[payee])
        elif payee in bank_names and payer in ('R', 'F') and kind != 'loan_origination':
            wallets[ACTORS.index(payer)] -= value
            reserve_move(HOME[payer], bank_names[payee])
        else:
            raise ValueError('Unsupported private-debt cash route in paydate journal.')
    elif kind == 'bank_dividend':
        if (payer, payee) not in (('BankA', 'HA'), ('BankB', 'HB')) or claim is not None:
            raise ValueError('Bank distribution requires its actual equity owner.')
        wallets[ACTORS.index(payee)] += value
    elif kind in ('cb_draw', 'cb_refinance'):
        if payer != 'CB' or payee not in BANKS or not claim:
            raise ValueError('Misidentified actual CB credit receipt.')
        index = BANKS.index(payee)
        if snapshot.terms.cb_rates_pct[index] is None:
            raise ValueError('Actual CB credit requires explicit contractual terms.')
        reserves[index] += value
        cb[index] += value
    elif kind in ('cb_cash_repayment', 'cb_collateral_prepayment'):
        if payee != 'CB' or payer not in BANKS or not claim:
            raise ValueError('Misidentified actual CB repayment receipt.')
        index = BANKS.index(payer)
        reserves[index] -= value
        cb[index] -= value
    elif kind in ('private_public_par_trade', 'public_par_purchase'):
        if transfer_index >= len(transfers):
            raise ValueError('Public par receipt lacks its exact coupon-rights transfer.')
        event = transfers[transfer_index]
        _money(event.face, scale)
        if event.seller == 'CB' or _paydate_receipt(payment) != public_funding.transfer_payment(event):
            raise ValueError('Public par receipt differs from its exact ordered transfer.')
        faces, terms = public_funding.apply_transfer(snapshot.treasuries, snapshot.terms, event)
        changes.update(treasuries=faces, terms=terms)
        reserves[BANKS.index(event.seller)] += value
        if event.buyer != 'CB':
            reserves[BANKS.index(event.buyer)] -= value
        transfer_index += 1
    else:
        raise ValueError('Unsupported monetary receipt in paydate private phase: ' + kind)
    if min(reserves) < 0 or min(wallets) < 0 or min(cb) < 0:
        raise ValueError('Paydate cash/debt prefix exceeds actually owned balances.')
    return replace(snapshot, reserves=tuple(reserves), wallets=tuple(wallets),
                   cb_faces=tuple(cb), **changes), transfer_index


def _paydate_recorded_orders(trace):
    """Decode the one actual orders observation, not another execution plan.

    Called only AFTER strict record/scalar admission. Constructing this frozen
    input validates units, preferences and explicit forecast coverage; it does
    not re-execute hiring, trading or any other quarter behavior.
    """
    markers = tuple((i + 1, n) for i, n in enumerate(trace) if n.kind == 'production_orders')
    if len(markers) != 1:
        raise ValueError('Require exactly one recorded paydate production-orders marker.')
    position, marker = markers[0]
    if (marker.actor != 'production' or marker.counterparty != 'goods'
            or marker.amount != ZERO or marker.claim_id is not None):
        raise ValueError('Misidentified paydate production-orders marker.')
    direct = ('price_factor', 'real_wage', 'residual_workers', 'focal_workers',
              'investment_units', 'residual_consumption', 'service_a', 'service_b',
              'available_workers', 'residual_productivity', 'service_productivity',
              'capital_productivity', 'capital_resource_cost', 'cash_floor_r',
              'cash_floor_f', 'market_clearing', 'max_clearing_rounds', 'demand_multiplier')
    preference_keys = tuple('preference_' + owner + '_' + field
                            for owner in ('a', 'b') for field in ('residual', 'services', 'cash'))
    special = ('expected_a_nominal', 'expected_b_nominal',
               'initial_dividend_a_real', 'initial_dividend_b_real')
    data = dict(marker.details)
    if len(data) != len(marker.details) or set(data) != set((*direct, *preference_keys, *special)):
        raise ValueError('Missing, duplicated or extra recorded paydate production-order inputs.')
    forecasts = (data['expected_a_nominal'], data['expected_b_nominal'])
    if (forecasts[0] is None) != (forecasts[1] is None):
        raise ValueError('Explicit paydate dividend forecasts require both household observations.')
    orders = ProductionOrders(**{name: data[name] for name in direct},
        preferences_a=household.Preferences(*(data['preference_a_' + field]
            for field in ('residual', 'services', 'cash'))),
        preferences_b=household.Preferences(*(data['preference_b_' + field]
            for field in ('residual', 'services', 'cash'))),
        expected_dividends_nominal=None if forecasts[0] is None else forecasts,
        initial_dividends_real=(data['initial_dividend_a_real'], data['initial_dividend_b_real']))
    if not orders.market_clearing:
        raise ValueError('Recorded paydate orders must use explicit market clearing.')
    return position, orders


@dataclass(frozen=True)
class _EarlyAssets:
    """Internal read-only collateral arithmetic view; never a ledger/codec."""
    loans: tuple
    securities_faces: tuple

    def securities(self, bank):
        return self.securities_faces[BANKS.index(bank)]


def _early_conditions(snapshot, private_loans):
    assets = _EarlyAssets(private_loans, tuple(sum(row, ZERO) for row in snapshot.treasuries[1:]))
    equities = tuple(snapshot.reserves[i] + assets.securities(bank)
        + sum((z.face-z.allowance for z in private_loans if z.lender == bank), ZERO)
        - snapshot.wallets[i] - snapshot.wallets[i+2] - snapshot.cb_faces[i]
        for i, bank in enumerate(BANKS))
    capacities = tuple(HAIRCUT_VALUE * (assets.securities(bank) + _private_collateral(assets, bank))
                       for bank in BANKS)
    return assets, equities, capacities


def _early_cb_id(quarter, bank, opening_loans):
    """Deterministic current-period identity, disjoint from ALL opening claims.

    Use the immutable original inventory, never the mutable current CB map:
    fully cash-repaid opening IDs remain reserved for subsequent actual draws.
    This identifies one aggregate current-period cohort, not historical custody.
    """
    candidate = f'CB{quarter}:{bank}'
    reserved = {loan.id for loan in opening_loans}
    while candidate in reserved:
        candidate += ':new'
    return candidate


def _early_credit_events(witness, quarter, securities):
    """Fixed scalar observation/retirement recipe; rolled face is NOT cash."""
    plan = witness.plan
    old = {z.bank: z for z in witness.old_loans}
    assets = _EarlyAssets(witness.private_loans, securities)
    events = []
    def note(kind, bank, value, claim=None, **details):
        events.append(Trace(kind, bank, 'CB', value, claim, tuple(details.items())))
    def facility(bank, amount, gross, face):
        index = BANKS.index(bank)
        note('facility_applied', bank, amount, _early_cb_id(quarter, bank, witness.old_loans),
             offered=plan.facility_limits[index], gross_applied=gross, capacity=plan.capacities[index])
        for pledge in _pledges(assets, bank, face):
            note('collateral_pledged', bank, pledge.face, pledge.claim_id, kind_of_asset=pledge.kind)
    for i, bank in enumerate(BANKS):
        refi, cash, advance = plan.refinanced[i], plan.cash_repayments[i], plan.advances[i]
        note('early_credit_condition', bank, advance, reserves=plan.reserves[i],
             old_face=plan.old_faces[i], equity=plan.equities[i], capacity=plan.capacities[i],
             offered=plan.facility_limits[i], prior_gross=ZERO, refinanced=refi,
             cash_repaid=cash, gross_applied=plan.gross_used[i], rate_pct=plan.cb_rates_pct[i])
        if bank in old:
            loan = old[bank]
            note('cb_principal_retired', bank, loan.face, loan.id,
                 net_cash_repaid=cash, refinanced=refi)
            if cash:
                events.append(Payment(bank, 'CB', cash, 'cb_cash_repayment', loan.id))
            if refi:
                note('cb_refinance', bank, refi, _early_cb_id(quarter, bank, witness.old_loans), old_id=loan.id)
                facility(bank, refi, refi, refi)
        if advance:
            events.append(Payment('CB', bank, advance, 'cb_draw', _early_cb_id(quarter, bank, witness.old_loans)))
            facility(bank, advance, plan.gross_used[i], plan.replacement_faces[i])
    return tuple(events)


def _validate_early_credit(book, scale, quarter, principal, receipts, trace):
    witness = book.early_credit
    if type(witness) is not EarlyCreditWitness:
        raise ValueError('Missing exact original early-credit witness.')
    replace(witness)
    if any(type(z) is not CBLoan for z in witness.old_loans + witness.replacement_loans):
        raise TypeError('Require exact original/replacement CB cohort types.')
    early_liquidity.validate_plan(witness.plan)
    for loan in witness.private_loans:
        if type(loan) not in (Loan, OperatingLoan, ProjectLoan):
            raise TypeError('Require exact private collateral claim types.')
        replace(loan)
        if loan.start >= quarter or loan.last_coupon_paid >= quarter:
            raise ValueError('Early collateral cannot anticipate new private claims or coupons.')
    if len({z.id for z in witness.private_loans}) != len(witness.private_loans):
        raise ValueError('Private collateral claims cannot be duplicated.')
    if tuple(z.bank for z in witness.old_loans) != tuple(b for b, face in zip(BANKS, principal.cb_faces) if face):
        raise ValueError('Old CB identities differ from original actual liabilities.')
    original_assets = _EarlyAssets(witness.private_loans,
        tuple(sum(row, ZERO) for row in book.opening.treasuries[1:]))
    for loan in witness.old_loans:
        if type(loan) is not CBLoan:
            raise TypeError('Require exact original CB cohorts.')
        replace(loan)
        if (loan.start >= quarter or loan.maturity != quarter
                or loan.face != principal.cb_faces[BANKS.index(loan.bank)]
                or loan.collateral != _pledges(original_assets, loan.bank, loan.face)):
            raise ValueError('Original early CB identity/maturity/pledges differ from due obligations.')
    assets, equities, capacities = _early_conditions(principal, witness.private_loans)
    plan = witness.plan
    expected = early_liquidity.plan(scale=scale, reserves=principal.reserves,
        old_faces=principal.cb_faces, equities=equities, capacities=capacities,
        facility_limits=plan.facility_limits, cb_rates_pct=principal.terms.cb_rates_pct,
        tga=principal.tga, observations=book.observations)
    if plan != expected:
        raise ValueError('Early credit plan differs from actual declared original conditions.')
    replacements = tuple(CBLoan(_early_cb_id(quarter, bank, witness.old_loans), bank, face, quarter, quarter+1,
        _pledges(assets, bank, face)) for bank, face in zip(BANKS, plan.replacement_faces) if face)
    if witness.replacement_loans != replacements:
        raise ValueError('Early replacement claims/pledges differ from actual novation and advance.')
    events = _early_credit_events(witness, quarter, assets.securities_faces)
    expected_payments = tuple(_paydate_receipt(z) for z in events if type(z) is Payment)
    start, end = book.phases[1], book.phases[2]
    if receipts[start.payment_end:end.payment_end] != expected_payments:
        raise ValueError('Early credit actual net cash differs from novation/advance obligations.')
    expected_trace = []
    position = start.payment_end
    for event in events:
        if type(event) is Trace:
            expected_trace.append(event)
        else:
            expected_trace.append(Trace(event.kind, event.payer, event.payee, event.amount, event.claim_id))
            expected_trace.append(Trace('paydate_payment', event.payer, event.payee, event.amount,
                event.claim_id, (('payment_kind', event.kind), ('position', position))))
            position += 1
    if tuple(expected_trace) != trace[start.trace_end:end.trace_end-1]:
        raise ValueError('Early credit ordered conditions/retirement/facility/pledge trace differs.')
    return replace(principal, reserves=plan.credit_reserves, cb_faces=plan.replacement_faces)


def _validate_later_credit(book, scale, quarter, current, payment, position, trace):
    matches = tuple(w for w in book.later_credit if w.payment_position == position)
    if len(matches) != 1:
        raise ValueError('Each later CB advance requires its unique actual-condition witness.')
    witness = matches[0]
    replace(witness)
    if witness.snapshot != current or witness.bank != payment.payee:
        raise ValueError('Later credit conditions differ from the actual preceding cash boundary.')
    bank = witness.bank
    if bank not in BANKS:
        raise ValueError('Later credit requires a known bank.')
    i = BANKS.index(bank)
    _integer(witness.payment_position, 'Later credit payment position')
    _integer(witness.trace_start, 'Later credit trace position')
    value = public_funding._number(witness.advance)
    _money(value, scale)
    used = public_funding._number(witness.gross_before)
    limit = public_funding._number(witness.offered_limit)
    transit = public_funding._vector(witness.transit_deposits, 2, 'Actual transit deposits')
    for loan in witness.private_loans:
        if type(loan) not in (Loan, OperatingLoan, ProjectLoan):
            raise TypeError('Require exact private claim types for later collateral.')
        replace(loan)
        if loan.start > quarter or loan.last_coupon_paid > quarter:
            raise ValueError('Later collateral cannot use future private claims or coupons.')
    if len({z.id for z in witness.private_loans}) != len(witness.private_loans):
        raise ValueError('Later collateral cannot reuse duplicated legal claims.')
    assets, equities, capacities = _early_conditions(current, witness.private_loans)
    old = witness.old_loan
    face = current.cb_faces[i]
    if old is None:
        if face:
            raise ValueError('Later credit cannot drop its outstanding CB cohort.')
    else:
        if type(old) is not CBLoan:
            raise TypeError('Require exact current CB cohort metadata.')
        replace(old)
        if (old.face != face or old.bank != bank or old.id != _early_cb_id(quarter, bank, book.early_credit.old_loans)
                or old.start != quarter or old.maturity != quarter + 1):
            raise ValueError('Later credit cannot overwrite an unretired original CB claim.')
        # An appended but undelivered new private claim need not have already
        # replaced the old pool. Its OLD exclusive pledges must still be owned.
        owned = {('private_loan', z.id): z.face-z.allowance for z in witness.private_loans
                 if z.lender == bank and z.performing}
        owned['public_security', 'Treasury:'+bank] = assets.securities(bank)
        pledged = {}
        for pledge in old.collateral:
            if type(pledge) is not Collateral:
                raise TypeError('Require exact old pledge identities.')
            replace(pledge)
            key = (pledge.kind, pledge.claim_id)
            pledged[key] = pledged.get(key, ZERO) + pledge.face
        if (sum(pledged.values(), ZERO) != face/HAIRCUT_VALUE
                or any(amount > owned.get(key, ZERO) for key, amount in pledged.items())):
            raise ValueError('Later advance reused or lost actually owned old collateral.')
    expected_gross = sum((n.amount for n in trace[:witness.trace_start]
                         if n.kind == 'facility_applied' and n.actor == bank), ZERO)
    if (not value or used != expected_gross or limit != book.early_credit.plan.facility_limits[i]
            or used+value > limit or face+value > capacities[i] or equities[i]-transit[i] <= 0
            or current.terms.cb_rates_pct[i] is None):
        raise ValueError('Later CB credit lacks actual equity/terms/collateral/shared gross room.')
    new = CBLoan(_early_cb_id(quarter, bank, book.early_credit.old_loans), bank, face+value, quarter, quarter+1,
                 _pledges(assets, bank, face+value))
    if witness.new_loan != new or payment != Payment('CB', bank, value, 'cb_draw', new.id):
        raise ValueError('Later actual CB advance differs from its unique legal claim/pledges.')
    expected = [Trace('cb_draw', 'CB', bank, value, new.id),
        Trace('paydate_payment', 'CB', bank, value, new.id,
              (('payment_kind', 'cb_draw'), ('position', position))),
        Trace('facility_applied', bank, 'CB', value, new.id,
              (('offered', limit), ('gross_applied', used+value), ('capacity', capacities[i])))]
    expected.extend(Trace('collateral_pledged', bank, 'CB', z.face, z.claim_id,
                          (('kind_of_asset', z.kind),)) for z in new.collateral)
    if tuple(expected) != trace[witness.trace_start:witness.trace_start+len(expected)]:
        raise ValueError('Later actual credit/facility/pledge metadata differs from current conditions.')


def _validate_early_gross_usage(book, trace):
    """Later borrowing shares gross limits; actual repayment never resets usage."""
    used = dict.fromkeys(BANKS, ZERO)
    retired = dict.fromkeys(BANKS, ZERO)
    debt = dict(zip(BANKS, book.opening.cb_faces))
    cohorts = dict.fromkeys(BANKS, None)
    early_start, early_end = book.phases[1].trace_end, book.phases[2].trace_end
    later_facilities = {w.trace_start+3 for w in book.later_credit}
    later_pledges = {w.trace_start+4+j for w in book.later_credit
                     for j in range(len(w.new_loan.collateral))}
    for position, note in enumerate(trace, 1):
        if note.kind == 'paydate_payment' and position > early_end:
            kind = dict(note.details)['payment_kind']
            if kind in ('cb_draw', 'cb_refinance'):
                bank = note.counterparty
                expected_id = _early_cb_id(book.income_paid_through, bank, book.early_credit.old_loans)
                if note.claim_id != expected_id or cohorts[bank] not in (None, expected_id):
                    raise ValueError('Later CB credit must retain its witnessed current-period cohort identity.')
                cohorts[bank] = note.claim_id
                debt[bank] += note.amount
            elif kind in ('cb_cash_repayment', 'cb_collateral_prepayment'):
                bank = note.actor
                if cohorts[bank] is None or note.claim_id != cohorts[bank]:
                    raise ValueError('Later CB repayment must identify its actual witnessed cohort.')
                debt[bank] -= note.amount
        if position == early_end:
            debt = dict(zip(BANKS, book.early_credit.plan.replacement_faces))
            cohorts.update((loan.bank, loan.id) for loan in book.early_credit.replacement_loans)
        if note.kind in ('facility_applied', 'collateral_pledged', 'cb_principal_retired', 'cb_refinance'):
            if position <= early_start:
                raise ValueError('Credit metadata cannot precede its explicit early-credit phase.')
        if note.kind == 'cb_refinance' and position > early_end:
            raise ValueError('Later metadata cannot fictitiously refinance an already novated original cohort.')
        if note.kind == 'cb_principal_retired':
            if position > early_end:
                raise ValueError('Original CB principal cannot be retired twice or outside atomic early novation.')
            retired[note.actor] += note.amount
        if note.kind == 'cb_early_principal_retired':
            data = dict(note.details)
            prior = trace[position-2] if position >= 2 else None
            if (position <= early_end or note.actor not in BANKS or note.counterparty != 'CB'
                    or prior is None or prior.kind != 'paydate_payment'
                    or dict(prior.details).get('payment_kind') != 'cb_collateral_prepayment'
                    or prior.actor != note.actor or prior.counterparty != 'CB'
                    or prior.claim_id != note.claim_id or prior.amount != note.amount
                    or tuple(data) != ('remaining',) or len(data) != len(note.details)
                    or data['remaining'] != debt[note.actor]):
                raise ValueError('Later collateral retirement metadata lacks its exact actual cash repayment.')
            public_funding._number(note.amount)
            public_funding._number(data['remaining'])
            retired[note.actor] += note.amount
        if note.kind == 'collateral_pledged' and position > early_end and position not in later_pledges:
            raise ValueError('Unpaired extra later collateral metadata is not an actual credit event.')
        if note.kind != 'facility_applied':
            continue
        if position > early_end and position not in later_facilities:
            raise ValueError('Unpaired extra later facility metadata is not actual reserve creation.')
        if note.actor not in BANKS or note.counterparty != 'CB':
            raise ValueError('Unidentified shared early/later facility usage.')
        i = BANKS.index(note.actor)
        data = dict(note.details)
        if tuple(data) != ('offered', 'gross_applied', 'capacity') or len(data) != len(note.details):
            raise ValueError('Facility usage requires its exact scalar metadata.')
        for value in (note.amount, *data.values()):
            public_funding._number(value)
        used[note.actor] += note.amount
        if (not note.amount or data['offered'] != book.early_credit.plan.facility_limits[i]
                or data['gross_applied'] != used[note.actor]
                or used[note.actor] > data['offered']
                or note.claim_id != _early_cb_id(book.income_paid_through, note.actor, book.early_credit.old_loans)
                or (position > early_end and debt[note.actor] > data['capacity'])):
            raise ValueError('Early/later credit exceeds its one shared gross limit/capacity.')
    for bank in BANKS:
        if used[bank] < book.early_credit.plan.gross_used[BANKS.index(bank)]:
            raise ValueError('Early gross refinancing/advance usage was dropped.')
        closing_loans = tuple(z for z in book.closing_cb_loans if z.bank == bank)
        if any(cohorts[bank] is None or loan.id != cohorts[bank] for loan in closing_loans):
            raise ValueError('Closing CB claim identity differs from its witnessed replacement/draw origin.')
        closing = sum((z.face for z in closing_loans), ZERO)
        if book.opening.cb_faces[BANKS.index(bank)] + used[bank] - retired[bank] != closing:
            raise ValueError('Original CB liabilities plus actual gross credit minus actual retirement do not reconcile.')


def _household_private_origin(loan):
    """Fixed full claim signature; never select a class/callback from data."""
    if type(loan) is Loan:
        kind = 'loan'
    elif type(loan) is OperatingLoan:
        kind = 'operating'
    elif type(loan) is ProjectLoan:
        kind = 'project'
    else:
        raise TypeError('Require an exact legal private claim.')
    replace(loan)
    if any(type(value) is not F for value in (loan.face, loan.rate_pct, loan.allowance)):
        raise TypeError('Private history requires canonical actual claim amounts/rates.')
    return Trace('household_private_origin', loan.lender, loan.borrower, loan.face, loan.id,
        (('claim_type', kind), ('rate_pct', loan.rate_pct), ('maturity', loan.maturity),
         ('start', loan.start), ('last_coupon_paid', loan.last_coupon_paid),
         ('allowance', loan.allowance), ('performing', loan.performing)))


def _household_private_pending(loan, old_id=None):
    signature = _household_private_origin(loan)
    return replace(signature, kind='household_private_pending',
                   details=(('old_id', old_id), *signature.details))


def _validate_household_private_history(book, scale, quarter, payments, trace):
    """Reconcile each draw's inventory/transit at its ACTUAL trace prefix.

    Full scalar pending signatures precede fund(): a real undelivered loan is
    already an asset AND a lender transit liability. Following legal delivery,
    payment and terms receipts must complete it. Future signatures cannot move
    backward. This validates internal history, not underwriting or custody.
    No record class, schema or callback is selected by journal data.
    """
    loans = [_household_private_origin(z) for z in book.early_credit.private_loans]
    seen = {z.claim_id for z in loans}
    transit = [ZERO, ZERO]
    pending = None
    origins = {}
    cash_used, reserves_used, zero_renewals = set(), set(), set()
    draw_at = {}
    for w in book.later_credit:
        _integer(w.trace_start, 'Actual private-history draw position')
        if w.trace_start in draw_at:
            raise ValueError('Duplicated actual private-history draw position.')
        draw_at[w.trace_start] = w
    keys = ('claim_type', 'rate_pct', 'maturity', 'start', 'last_coupon_paid', 'allowance', 'performing')

    def same(actual, expected):
        return (actual == expected and type(actual.amount) is F
                and tuple(type(v) for _,v in actual.details) == tuple(type(v) for _,v in expected.details))

    def signature_tuple(values):
        return tuple(_household_private_origin(z) for z in values)

    def find(claim):
        matches = [z for z in loans if z.claim_id == claim]
        if len(matches) != 1:
            raise ValueError('Private settlement lacks its unique chronologically owned claim.')
        return matches[0]

    def changed(loan, *, face=None, **updates):
        data = dict(loan.details); data.update(updates)
        return replace(loan, amount=loan.amount if face is None else face,
                       details=tuple((k, data[k]) for k in keys))

    def reserve(index, source, target, amount, claim, purpose):
        if amount and source != target:
            expected = Trace('reserve_settlement', source, target, amount, claim, (('purpose', purpose),))
            if index < 0 or not same(trace[index], expected) or index in reserves_used:
                raise ValueError('Private delivery/settlement lacks its actual chronological reserve leg.')
            reserves_used.add(index)

    def cash(receipt, posted):
        if not receipt.amount:
            return
        if not 0 <= posted < len(trace) or trace[posted].kind != 'paydate_payment':
            raise ValueError('Private claim transition lacks its actual cash receipt.')
        position = dict(trace[posted].details)['position']
        if payments[position] != receipt or posted in cash_used:
            raise ValueError('Private claim transition changed or reused an actual cash receipt.')
        cash_used.add(posted)

    for index, note in enumerate(trace):
        if index in draw_at:
            # fund() may run ONLY between recorded deposit creation and its
            # actual delivery. A delivery marker cannot erase transit while
            # the matching wallet/cash receipt is still unposted.
            if pending is not None and (pending['delta'] <= 0 or not pending['created'] or pending['delivered']):
                raise ValueError('Draw cannot interrupt atomic private creation/delivery settlement.')
            w = draw_at[index]
            if signature_tuple(w.private_loans) != tuple(loans) or w.transit_deposits != tuple(transit):
                raise ValueError('Draw private claims/transit differ from actual chronological creation and settlement.')
        if note.kind == 'paydate_phase':
            if pending is not None or any(transit):
                raise ValueError('Unfinished private creation cannot cross an actual phase boundary.')
            if note.counterparty == 'funded_payroll':
                if (type(book.household_credit) is not HouseholdLiquidityWitness
                        or signature_tuple(book.household_credit.private_loans) != tuple(loans)):
                    raise ValueError('Household private inventory differs from actual delivered history.')
        if note.kind == 'household_private_pending':
            data = dict(note.details)
            if (tuple(data) != ('old_id', *keys) or len(data) != len(note.details)
                    or note.actor not in BANKS or note.counterparty not in ('R', 'F')
                    or type(note.amount) is not F or not note.amount or not note.claim_id
                    or note.claim_id in seen or pending is not None
                    or data['claim_type'] not in ('loan', 'operating', 'project')
                    or type(data['rate_pct']) is not F or type(data['allowance']) is not F
                    or type(data['performing']) is not bool):
                raise ValueError('Private pending creation requires its fixed canonical full fields.')
            for key in ('maturity', 'start', 'last_coupon_paid'):
                _integer(data[key], 'Pending private '+key)
            _money(note.amount, scale)
            old_id = data['old_id']
            if old_id is not None and type(old_id) is not str:
                raise TypeError('Pending renewal requires a plain original claim identity.')
            signature = replace(note, kind='household_private_origin', details=note.details[1:])
            if old_id is None:
                stage = 'funded_payroll' if book.phases[3].trace_end <= index < book.phases[4].trace_end else 'trading'
                if (not (book.phases[3].trace_end <= index < book.phases[4].trace_end
                         or book.phases[7].trace_end <= index < book.phases[8].trace_end)
                        or data['allowance'] or not data['performing']
                        or data['start'] not in ((quarter-1,) if stage == 'funded_payroll' else (quarter-1, quarter))
                        or data['last_coupon_paid'] != data['start'] or data['maturity'] <= data['start']
                        or (data['claim_type'] == 'operating' and data['maturity'] != data['start']+2)
                        or (data['claim_type'] == 'project' and (stage != 'trading' or note.counterparty != 'F'
                            or data['start'] != quarter-1 or not 2 <= data['maturity']-data['start'] <= 17))):
                    raise ValueError('Private creation differs from its actual fixed-calendar legal terms.')
                old, delta = None, note.amount
            else:
                old = find(old_id); prior = dict(old.details)
                delta = note.amount-old.amount
                if (index < book.phases[7].trace_end or prior['claim_type'] == 'project'
                        or prior['maturity'] != quarter or prior['last_coupon_paid'] != quarter
                        or (note.actor, note.counterparty, data['claim_type'], data['performing']) !=
                           (old.actor, old.counterparty, prior['claim_type'], prior['performing'])
                        or data['start'] != quarter or data['last_coupon_paid'] != quarter
                        or data['maturity'] <= quarter or data['allowance'] != min(prior['allowance'], note.amount)
                        or (data['claim_type'] == 'operating' and data['maturity'] != quarter+2)):
                    raise ValueError('Renewal did not retire its actual due, coupon-paid legal claim.')
                if delta < 0:
                    reserve(index-1, HOME[old.counterparty], old.actor, -delta, old.claim_id, 'renewal_principal')
                loans.remove(old)
            loans.append(signature); seen.add(note.claim_id)
            pending = dict(signature=signature, old=old, delta=delta, created=False, delivered=False)
            if delta > 0:
                transit[BANKS.index(note.actor)] += delta
        elif note.kind == 'loan_deposit_created':
            if pending is None or pending['delta'] <= 0 or pending['created']:
                raise ValueError('Private transit creation lacks its preceding actual pending claim.')
            loan = pending['signature']
            if (not same(note, Trace('loan_deposit_created', loan.actor, loan.counterparty, pending['delta'], loan.claim_id))
                    or trace[index-1].kind != 'household_private_pending'):
                raise ValueError('Private transit creation differs from its actual pending claim.')
            pending['created'] = True
        elif note.kind == 'loan_deposit_delivered':
            if pending is None or not pending['created'] or pending['delivered']:
                raise ValueError('Private deposit delivery lacks its actual undelivered liability.')
            loan, old, delta = pending['signature'], pending['old'], pending['delta']
            if not same(note, Trace('loan_deposit_delivered', loan.actor, loan.counterparty, delta, loan.claim_id)):
                raise ValueError('Private deposit delivery changed its actual lender/owner/amount.')
            reserve(index-1, loan.actor, HOME[loan.counterparty], delta,
                    loan.claim_id if old is None else old.claim_id,
                    'loan_origination' if old is None else 'renewal_advance')
            transit[BANKS.index(loan.actor)] -= delta
            pending['delivered'] = True
        elif note.kind == 'matching_loan_created':
            if pending is None or pending['old'] is not None or not pending['delivered']:
                raise ValueError('Private origination lacks completed actual creation/delivery.')
            loan = pending['signature']; data = dict(loan.details)
            if not same(note, Trace('matching_loan_created', loan.actor, loan.counterparty, loan.amount, loan.claim_id,
                    (('maturity', data['maturity']), ('start', data['start']), ('rate_pct', data['rate_pct'])))):
                raise ValueError('Delivered private terms differ from the preceding pending creation.')
            cash(Payment('Bank'+loan.actor, loan.counterparty, loan.amount, 'loan_origination', loan.claim_id), index-1)
            origins[index+1] = loan
            pending = None
        elif note.kind == 'household_private_origin':
            expected = origins.pop(index, None)
            if expected is None or not same(note, expected):
                raise ValueError('Private full delivery terms lack their chronological matching origination.')
        elif note.kind == 'coupon_paid':
            loan = find(note.claim_id); data = dict(loan.details)
            contractual, paid = precision.coupon(loan.amount, data['rate_pct'], scale, QUANTUM)
            if (index < book.phases[7].trace_end or data['start'] == quarter
                    or data['last_coupon_paid'] != quarter-1
                    or not same(note, Trace('coupon_paid', loan.actor, loan.counterparty, paid, loan.claim_id,
                        (('contractual', contractual), ('paid_quarter', quarter))))):
                raise ValueError('Private coupon changed its actual outstanding contract or settlement clock.')
            payer, payee = ((loan.counterparty, 'Bank'+loan.actor) if paid >= 0 else
                            ('Bank'+loan.actor, loan.counterparty))
            cash(Payment(payer, payee, abs(paid), 'private_coupon', loan.claim_id), index-1)
            reserve(index-3, HOME[loan.counterparty] if paid >= 0 else loan.actor,
                    loan.actor if paid >= 0 else HOME[loan.counterparty], abs(paid), loan.claim_id, 'private_coupon')
            loans[loans.index(loan)] = changed(loan, last_coupon_paid=quarter)
        elif note.kind == 'matching_principal_retired':
            loan = find(note.claim_id); data = dict(loan.details)
            remaining = loan.amount-note.amount
            released = max(ZERO, data['allowance']-remaining)
            if (index < book.phases[7].trace_end or note.amount <= 0 or remaining < 0
                    or not same(note, Trace('matching_principal_retired', loan.counterparty, loan.actor, note.amount,
                                     loan.claim_id, (('allowance_recovery', released),)))):
                raise ValueError('Private principal retirement changed the actual outstanding claim.')
            cash(Payment(loan.counterparty, 'Bank'+loan.actor, note.amount, 'private_principal', loan.claim_id), index-1)
            reserve(index-3, HOME[loan.counterparty], loan.actor, note.amount, loan.claim_id, 'private_principal')
            loans.remove(loan)
            if remaining:
                loans.append(changed(loan, face=remaining, allowance=data['allowance']-released))
        elif note.kind == 'renewal_old_retired':
            if pending is None or pending['old'] is None or (pending['delta'] > 0 and not pending['delivered']):
                raise ValueError('Renewal lacks its actual signed replacement/delivery.')
            old = pending['old']; new = pending['signature']
            released = dict(old.details)['allowance']-dict(new.details)['allowance']
            if not same(note, Trace('renewal_old_retired', old.actor, old.counterparty, old.amount, old.claim_id,
                             (('allowance_released', released),))):
                raise ValueError('Renewal changed its actual retired identity/allowance.')
            pending['retired_at'] = index
        elif note.kind == 'renewal_new_created':
            if pending is None or pending.get('retired_at') != index-1:
                raise ValueError('Renewal lacks its immediately preceding actual old retirement.')
            old, new, delta = pending['old'], pending['signature'], pending['delta']; data = dict(new.details)
            if not same(note, Trace('renewal_new_created', new.actor, new.counterparty, new.amount, new.claim_id,
                    (('old_id', old.claim_id), ('maturity', data['maturity']), ('rate_pct', data['rate_pct'])))):
                raise ValueError('Renewal changed its signed replacement terms.')
            if delta:
                cash(Payment('Bank'+new.actor if delta > 0 else new.counterparty,
                    new.counterparty if delta > 0 else 'Bank'+new.actor, abs(delta), 'renewal_net_cash', new.claim_id), index+2)
            else:
                expected = Trace('renewal_net_cash', new.actor, new.counterparty, ZERO, new.claim_id)
                if index+1 >= len(trace) or not same(trace[index+1], expected):
                    raise ValueError('Same-face renewal lacks its actual zero cash observation.')
                zero_renewals.add(index+1)
            pending = None
    debt_cash = {i for i,n in enumerate(trace) if n.kind == 'paydate_payment'
                 and dict(n.details)['payment_kind'] in ('loan_origination', 'private_coupon', 'private_principal', 'renewal_net_cash')}
    private_reserves = {i for i,n in enumerate(trace) if n.kind == 'reserve_settlement'
                        and dict(n.details).get('purpose') in ('loan_origination', 'private_coupon', 'private_principal',
                                                              'renewal_advance', 'renewal_principal')}
    if (pending is not None or any(transit) or origins or cash_used != debt_cash or reserves_used != private_reserves
            or any(n.kind == 'renewal_net_cash' and not n.amount and i not in zero_renewals for i,n in enumerate(trace))
            or signature_tuple(book.closing_private_loans) != tuple(loans)):
        raise ValueError('Closing private claims/transit differ from the complete actual ordered settlement history.')



def _validate_household_credit(book, scale, quarter, current, payments, trace):
    witness = book.household_credit
    if type(witness) is not HouseholdLiquidityWitness:
        raise ValueError('Missing exact actual household-liquidity witness.')
    replace(witness)
    early_liquidity.validate_household_plan(witness.plan)
    loans = witness.private_loans
    _, equities, capacities = _early_conditions(current, loans)
    begin, end = book.phases[4], book.phases[5]
    gross = tuple(sum((n.amount for n in trace[:begin.trace_end]
        if n.kind == 'facility_applied' and n.actor == bank), ZERO) for bank in BANKS)
    expected = early_liquidity.household_plan(scale=scale, reserves=current.reserves,
        household_deposits=current.wallets[2:], cb_faces=current.cb_faces,
        equities=equities, capacities=capacities, facility_limits=book.early_credit.plan.facility_limits,
        gross_used=gross, cb_rates_pct=current.terms.cb_rates_pct, observations=book.observations)
    if witness.plan != expected:
        raise ValueError('Household reserve plan differs from actual post-payroll conditions.')
    receipts = payments[begin.payment_end:end.payment_end]
    expected_receipts = tuple(Payment('CB', bank, amount, 'cb_draw',
        _early_cb_id(quarter, bank, book.early_credit.old_loans))
        for bank, amount in zip(BANKS, expected.advances) if amount)
    if receipts != expected_receipts:
        raise ValueError('Household phase must contain only the minimum actual ordered bank advances.')
    for position, receipt in enumerate(receipts, begin.payment_end):
        matches = tuple(w for w in book.later_credit if w.payment_position == position)
        if len(matches) != 1 or matches[0].private_loans != loans or any(matches[0].transit_deposits):
            raise ValueError('Household draw collateral differs from actually delivered private claims.')
        _validate_later_credit(book, scale, quarter, current, receipt, position, trace)
        current, transfer = _paydate_private_snapshot(current, receipt, (), 0, scale)
    return current


def validate_paydate_public(book, scale, quarter, payments=None, trace=None):
    if type(book) is not PaydatePublicBook:
        raise TypeError('Require the exact original PaydatePublicBook.')
    return _validate_paydate_public(book, scale, quarter, payments, trace, early=False)


def validate_early_paydate_public(book, scale, quarter, payments=None, trace=None):
    if type(book) is not EarlyPaydateBook:
        raise TypeError('Require the exact EarlyPaydateBook.')
    return _validate_paydate_public(book, scale, quarter, payments, trace, early=True)


def validate_household_liquidity_public(book, scale, quarter, payments=None, trace=None):
    if type(book) is not HouseholdLiquidityBook:
        raise TypeError('Require the exact HouseholdLiquidityBook.')
    return _validate_paydate_public(book, scale, quarter, payments, trace, early=True, household_credit=True)


def _validate_paydate_public(book, scale, quarter, payments, trace, *, early, household_credit=False):
    """Semantically bind one actual ordered paid journal; never run a quarter.

    The old funded validator intentionally keeps its exact-type and projection
    semantics. This calendar instead reconciles intervening real movements and
    fixed phase boundaries. These asserted observations are not custody proof.
    """
    # FIRST: instance metadata, scalar proxies and malformed record trees must
    # never reach equality, dict conversion or dataclass reconstruction below.
    if type(early) is not bool or type(household_credit) is not bool or (household_credit and not early):
        raise TypeError('Require an exact code-owned paydate validator selection.')
    records = ((EarlyPaydateBook, EarlyPhase, EarlyCreditWitness, LaterCreditWitness, early_liquidity.EarlyPlan,
                CBLoan, Collateral, Loan, OperatingLoan, ProjectLoan) if early else
               (PaydatePublicBook, PaydatePhase))
    if household_credit:
        records = (*records, HouseholdLiquidityBook, HouseholdLiquidityPhase,
                   HouseholdLiquidityWitness, early_liquidity.HouseholdLiquidityPlan)
    public_funding.validate_records((book, payments, trace), (
        *records, PaydateSnapshot, FundingOpening, FundingBatch, TreasuryTransfer,
        PublicIncomeTerms, CouponLine, Payment, Trace, RRPClaim))
    expected_book = EarlyPaydateBook if early else PaydatePublicBook
    phase_type = EarlyPhase if early else PaydatePhase
    phase_names = EARLY_PAYDATE_PHASES if early else PAYDATE_PHASES
    offset = 1 if early else 0
    tail = 1 if household_credit else 0
    if household_credit:
        expected_book, phase_type, phase_names = HouseholdLiquidityBook, HouseholdLiquidityPhase, HOUSEHOLD_LIQUIDITY_PHASES
    if type(book) is not expected_book:
        raise TypeError('Require the exact selected paydate book subtype.')
    if early:
        replace(book)
    scale = public_funding._number(scale)
    if not scale:
        raise ValueError('Nominal scale must be positive.')
    _integer(quarter, 'Paydate public quarter')
    if book.income_paid_through != quarter:
        raise ValueError('Paydate income clock differs from the ledger quarter.')
    if not quarter:
        if (book.opening is not None or book.funding is not None or book.transfers or book.phases
                or book.observations or book.deferred_asset or book.opening_deferred_asset
                or any(book.paid_wages) or any(book.household_income)):
            raise ValueError('Fresh paydate books cannot invent paid history.')
        if early and (book.early_credit is not None or book.closing_cb_loans or book.closing_private_loans or book.later_credit):
            raise ValueError('Fresh early books cannot invent credit history.')
        if household_credit and book.household_credit is not None:
            raise ValueError('Fresh household-liquidity books cannot invent credit history.')
        if payments or trace:
            raise ValueError('Fresh paydate books cannot invent a paid journal.')
        return
    if payments is None or trace is None:
        raise ValueError('Paid paydate books require their actual ordered payments AND trace.')
    if type(payments) is not tuple or type(trace) is not tuple:
        raise TypeError('Require immutable actual paydate journal streams.')
    if any(type(p) is not Payment for p in payments) or any(type(n) is not Trace for n in trace):
        raise TypeError('Require exact immutable actual payment/trace records.')
    if offset:
        for payment in payments:
            replace(payment)
        for note in trace:
            replace(note)
            if note.kind in ('paydate_phase', 'paydate_payment'):
                data = dict(note.details)
                key = 'payment_end' if note.kind == 'paydate_phase' else 'position'
                if type(data.get(key)) is not int:
                    raise TypeError('Actual early journal positions must be plain integers.')
    receipts = public_funding._receipts(tuple(map(_paydate_receipt, payments)))
    phases = book.phases
    if type(phases) is not tuple or any(type(p) is not phase_type for p in phases):
        raise TypeError('Require exact immutable actual paydate phase records.')
    for phase in phases:
        if type(phase.snapshot) is not PaydateSnapshot:
            raise TypeError('Require exact immutable actual paydate boundary snapshots.')
        # Recheck scalar/array contracts without mutating the asserted history.
        replace(phase.snapshot)
        _integer(phase.payment_end, 'Actual phase payment boundary')
        _integer(phase.trace_end, 'Actual phase trace boundary', 1)
    if (tuple(p.name for p in phases) != phase_names
            or phases[0].payment_end != 0 or phases[0].trace_end != 1
            or phases[-1].payment_end != len(payments) or phases[-1].trace_end != len(trace)):
        raise ValueError('Dropped, duplicated, stale or reordered paydate phase boundaries.')
    if (any(a.payment_end > b.payment_end or a.trace_end >= b.trace_end
            for a, b in zip(phases, phases[1:]))
            or any(p.payment_end > len(payments) or p.trace_end > len(trace) for p in phases)):
        raise ValueError('Paydate phase positions are outside their ordered actual journal.')
    markers = tuple((i + 1, n) for i, n in enumerate(trace) if n.kind == 'paydate_phase')
    expected_markers = tuple((p.trace_end, Trace('paydate_phase', 'journal', p.name, ZERO,
                                              details=(('payment_end', p.payment_end),))) for p in phases)
    if markers != expected_markers:
        raise ValueError('Paydate phase witnesses differ from the ordered journal markers.')
    posted = tuple((i + 1, n) for i, n in enumerate(trace) if n.kind == 'paydate_payment')
    if len(posted) != len(payments):
        raise ValueError('Dropped or duplicated actual paydate payment witnesses.')
    for position, ((trace_position, note), payment) in enumerate(zip(posted, payments)):
        expected = Trace('paydate_payment', payment.payer, payment.payee, payment.amount,
                         payment.claim_id, (('payment_kind', payment.kind), ('position', position)))
        original_note = Trace(payment.kind, payment.payer, payment.payee,
                              payment.amount, payment.claim_id)
        if (note != expected or trace_position < 2 or trace[trace_position - 2] != original_note
                or any((position < p.payment_end) != (trace_position < p.trace_end) for p in phases)):
            raise ValueError('Actual paydate payment order/identity differs from its phase witnesses.')
    opening, batch = book.opening, book.funding
    if type(opening) is not FundingOpening or type(batch) is not FundingBatch:
        raise ValueError('Paid paydate book requires its original opening and authorized batch.')
    start = phases[0].snapshot
    if quarter == 1:
        if (start.previous_income != (20 * scale, F(63, 20) * scale)
                or start.previous_dividends != (None, None)):
            raise ValueError('Fresh paydate opening must identify its fixed income seeds, not invented history.')
    elif any(value is None for value in start.previous_dividends):
        raise ValueError('Continued paydate opening requires actual previous paid dividend observations.')
    expected_opening = FundingOpening(quarter=quarter, scale=scale, terms=start.terms,
        treasuries=start.treasuries, mortgages=start.mortgages, reserves=start.reserves,
        household_deposits=start.wallets[2:], cb_faces=start.cb_faces,
        rrp_faces=start.rrp_faces, tga=start.tga, deferred=start.deferred)
    if opening != expected_opening:
        raise ValueError('Paydate opening differs from its original actual boundary.')
    lines = public_income.quote(opening.terms, treasuries=opening.treasuries,
        mortgages=opening.mortgages, reserves=opening.reserves, cb_faces=opening.cb_faces,
        rrp_faces=opening.rrp_faces, scale=scale)
    if book.observations != lines:
        raise ValueError('Paydate observations differ from eleven original opening coupon bases.')
    def span(index):
        return receipts[phases[index - 1].payment_end:phases[index].payment_end]
    def boundary(index, expected):
        if phases[index].snapshot != expected:
            raise ValueError('Paydate actual monetary boundary differs from posted ' + phases[index].name + '.')
    projection = public_funding.project_batch(opening, batch)
    if span(1) != projection.payments:
        raise ValueError('Paydate principal receipts differ from the exact authorized ordered batch.')
    current = replace(start, reserves=projection.reserves,
        wallets=(*start.wallets[:2], *projection.household_deposits),
        mortgages=projection.mortgages, treasuries=projection.treasuries,
        terms=projection.terms, rrp_faces=(ZERO, ZERO), tga=projection.tga)
    boundary(1, current)
    if offset:
        current = _validate_early_credit(book, scale, quarter, current, receipts, trace)
        boundary(2, current)
    if household_credit:
        _validate_household_private_history(book, scale, quarter, payments, trace)
    early_lines = _paydate_ordered_lines(lines)
    if span(2 + offset) != _paydate_coupon_receipts(early_lines):
        raise ValueError('Paydate early coupons differ from their original ordered obligations.')
    current = _paydate_income_snapshot(current, early_lines)
    boundary(2 + offset, current)
    transfer_index = 0
    wages = [ZERO, ZERO]
    payroll_order = []
    for position, p in enumerate(payments[phases[2 + offset].payment_end:phases[3 + offset].payment_end],
                                 phases[2 + offset].payment_end):
        if p.kind not in ('cb_draw', 'cb_refinance', 'cb_cash_repayment', 'cb_collateral_prepayment',
                          'private_public_par_trade', 'public_par_purchase', 'loan_origination',
                          'residual_payroll', 'focal_payroll'):
            raise ValueError('Future income, purchases or private debt bridged funded payroll.')
        if p.kind in ('residual_payroll', 'focal_payroll'):
            index = ('residual_payroll', 'focal_payroll').index(p.kind)
            payroll_order.append(index)
            wages[index] += p.amount
        if offset and p.kind == 'cb_draw':
            _validate_later_credit(book, scale, quarter, current, p, position, trace)
        current, transfer_index = _paydate_private_snapshot(current, p, book.transfers, transfer_index, scale)
    if payroll_order != sorted(set(payroll_order)) or tuple(wages) != book.paid_wages:
        raise ValueError('Duplicated, reordered or tampered actual funded payroll receipts.')
    boundary(3 + offset, current)
    if household_credit:
        current = _validate_household_credit(book, scale, quarter, current, payments, trace)
        boundary(5, current)
    delayed = _paydate_ordered_lines(lines, household_phase=True)
    if span(4 + offset + tail) != _paydate_coupon_receipts(delayed):
        raise ValueError('Paydate household coupon/pass-through receipts differ from actual signed obligations.')
    income = tuple(-z.settled for z in lines if z.kind == 'mortgage')
    if book.household_income != income:
        raise ValueError('Paydate signed household income differs from its actual matched coupons.')
    current = _paydate_income_snapshot(current, delayed)
    boundary(4 + offset + tail, current)
    deferred, remit = public_income.earnings_close(opening.deferred, public_income.cb_profit(lines))
    if span(5 + offset + tail) != ((('CB', 'Treasury', remit, 'cb_remittance', None),) if remit else ()):
        raise ValueError('Paydate remittance was dropped, duplicated or moved before all coupons.')
    current = replace(current, tga=current.tga + remit, deferred=deferred)
    boundary(5 + offset + tail, current)
    # Intentions must identify the actual wallet decomposition, not a negative
    # pseudo-opening cash amount or a forecast promoted to spendable cash.
    from .paydate_households import cash_stock_budget
    budgets = tuple((i + 1, n) for i, n in enumerate(trace) if n.kind == 'household_budget')
    if tuple(n.actor for _, n in budgets) != ('HA', 'HB'):
        raise ValueError('Missing, duplicated or reordered actual paydate household budgets.')
    orders_position, orders = _paydate_recorded_orders(trace)
    if not phases[5 + offset + tail].trace_end < orders_position < budgets[0][0]:
        raise ValueError('Recorded paydate production orders must precede both frozen household budgets.')
    if any(phases[5 + offset + tail].trace_end < position < budgets[-1][0] for position, _ in posted):
        raise ValueError('Actual trading cash cannot move before both paydate budgets freeze.')
    if orders.expected_dividends_nominal is not None:
        forecasts, source = orders.expected_dividends_nominal, 'explicit_forecast'
    elif quarter == 1:
        forecasts, source = tuple(value * scale for value in orders.initial_dividends_real), 'initial_reference'
    else:
        forecasts, source = start.previous_dividends, 'last_paid_dividends'
    for index, (trace_position, note) in enumerate(budgets):
        data = dict(note.details)
        required = ('opening_cash', 'paid_wages', 'settled_income', 'income_previous',
                    'income_forecast', 'cash_ratio', 'adjustment', 'desired', 'funded',
                    'forecast', 'forecast_source')
        if (len(data) != len(note.details) or any(k not in data for k in required)
                or data.get('mode') != 'cash_stock_close_v1' or note.counterparty != 'goods'
                or not phases[5 + offset + tail].trace_end < trace_position < phases[6 + offset + tail].trace_end
                or any(i < trace_position for i, n in posted if dict(n.details)['payment_kind']
                       in ('services', 'investment', 'residual_consumption'))):
            raise ValueError('Paydate household budgets must freeze once before discretionary purchases.')
        for key in required:
            if key != 'forecast_source':
                public_funding._number(data[key], signed=key in (
                    'settled_income', 'income_previous', 'income_forecast'))
        public_funding._number(data.get('demand_multiplier', F(1)))
        public_funding._number(note.amount)
        cash = phases[2 + offset].snapshot.wallets[index + 2]
        if (data['opening_cash'] != cash or data['paid_wages'] != wages[index]
                or data['settled_income'] != income[index]
                or data['income_forecast'] != wages[index] + data['forecast'] + income[index]
                or data['income_previous'] != start.previous_income[index]
                or data['forecast_source'] != source or data['forecast'] != forecasts[index]
                or data.get('demand_multiplier', F(1)) != orders.demand_multiplier
                or data['cash_ratio'] != (F(3, 20), F(1, 21))[index]
                or data['adjustment'] != F(1, 4)):
            raise ValueError('Paydate budget decomposition differs from actual cash/wages/signed income.')
        quote = cash_stock_budget(opening_cash=cash, paid_wages=wages[index],
            settled_income=income[index], previous_income=data['income_previous'],
            forecast_income=data['income_forecast'], cash_ratio=data['cash_ratio'],
            adjustment=data['adjustment'], demand_multiplier=data.get('demand_multiplier', F(1)))
        if (quote.wallet != note.amount or quote.wallet != current.wallets[index + 2]
                or quote.funded != data['funded'] or quote.desired != data['desired']):
            raise ValueError('Paydate budget intention/wallet differs from the actual settled cash.')
        owner = ('HA', 'HB')[index]
        residual = sum((p.amount for p in payments
                        if p.payer == owner and p.kind == 'residual_consumption'), ZERO)
        services = sum((p.amount for p in payments
                        if p.payer == owner and p.kind == 'services'), ZERO)
        prefs = (orders.preferences_a, orders.preferences_b)[index]
        goods = prefs.residual + prefs.services
        residual_limit = quote.funded * prefs.residual / goods if goods else ZERO
        service_limit = quote.funded * prefs.services / goods if goods else ZERO
        # Exact nominal upper bounds, not equalities: supply rationing and
        # whole-physical-quantum rounding can leave a funded intention unfilled.
        if (residual + services > quote.funded or residual > residual_limit
                or services > service_limit):
            raise ValueError('Actual household goods spending exceeds its frozen funded budget/basket.')
    for position, p in enumerate(payments[phases[5 + offset + tail].payment_end:phases[6 + offset + tail].payment_end],
                                 phases[5 + offset + tail].payment_end):
        if p.kind in ('residual_payroll', 'focal_payroll'):
            raise ValueError('Payroll cannot occur after the mandatory household coupon date.')
        if offset and p.kind == 'cb_draw':
            _validate_later_credit(book, scale, quarter, current, p, position, trace)
        current, transfer_index = _paydate_private_snapshot(current, p, book.transfers, transfer_index, scale)
    boundary(6 + offset + tail, current)
    if transfer_index != len(book.transfers):
        raise ValueError('Dropped, duplicated or reordered actual Treasury transfer receipts.')
    if (current.treasuries != (book.treasuries, *book.private_treasuries)
            or current.terms != book.terms or current.mortgages != book.mortgages
            or book.mbs != sum(current.mortgages) or current.tga != book.tga
            or current.deferred != book.deferred_asset or start.deferred != book.opening_deferred_asset
            or book.currency != current.currency or book.capital_other != current.capital_other
            or book.rrp_claims or any(current.rrp_faces)):
        raise ValueError('Paydate closing rights/TGA/deferred differ from the actual ordered journal.')
    if offset:
        if any(type(z) is not CBLoan for z in book.closing_cb_loans):
            raise TypeError('Require exact closing CB cohort records.')
        later_positions = tuple(i for i, p in enumerate(payments)
            if i >= phases[3].payment_end and p.kind == 'cb_draw')
        if tuple(w.payment_position for w in book.later_credit) != later_positions:
            raise ValueError('Dropped, duplicated or reordered later actual credit witnesses.')
        if any(p.kind == 'cb_refinance' for p in payments[phases[3].payment_end:]):
            raise ValueError('Atomic novation is trace, never a later fictitious gross cash receipt.')
        _validate_early_gross_usage(book, trace)
        expected_faces = tuple(sum((z.face for z in book.closing_cb_loans if z.bank == b), ZERO) for b in BANKS)
        if current.cb_faces != expected_faces:
            raise ValueError('Closing early CB cohorts differ from actual witnessed liabilities.')
        assets = _EarlyAssets(book.closing_private_loans,
            tuple(sum(row, ZERO) for row in current.treasuries[1:]))
        for private in book.closing_private_loans:
            if type(private) not in (Loan, OperatingLoan, ProjectLoan):
                raise TypeError('Require exact closing private claim identities.')
            replace(private)
        if len({z.id for z in book.closing_private_loans}) != len(book.closing_private_loans):
            raise ValueError('Closing private collateral cannot be duplicated.')
        if len({z.bank for z in book.closing_cb_loans}) != len(book.closing_cb_loans):
            raise ValueError('Closing CB cohorts cannot overlap.')
        for loan in book.closing_cb_loans:
            if loan.collateral != _pledges(assets, loan.bank, loan.face):
                raise ValueError('Closing CB pledges differ from actual owned eligible claims.')
            if type(loan) is not CBLoan or loan.start != quarter or loan.maturity != quarter + 1:
                raise ValueError('Closing early CB claims require their current replacement date.')
            replace(loan)
    public_income.validate_payments(payments, book.observations, book.opening_deferred_asset)


@dataclass(frozen=True)
class PublicInstructions:
    currency_to_deposits: tuple = (ZERO,ZERO)
    mortgage_repayments: tuple = (ZERO,ZERO)
    treasury_subscriptions: tuple = (ZERO,ZERO)
    treasury_issue_authorization: F = ZERO
    treasury_redemption: F = ZERO
    treasury_rolls: tuple = (ZERO, ZERO, ZERO)  # Fed, Bank A, Bank B consent
    rrp_request: F = ZERO
    rrp_offers: tuple = (ZERO, ZERO)
    replacement_maturity: F = F(118, 5)

    def __post_init__(self):
        values=self.currency_to_deposits
        if not isinstance(values,(tuple,list)) or len(values)!=2:
            raise TypeError('Currency conversion requires two identified household amounts.')
        object.__setattr__(self,'currency_to_deposits',tuple(_number(x,signed=True) for x in values))
        for name in ('mortgage_repayments','treasury_subscriptions','rrp_offers'):
            object.__setattr__(self,name,_amount_pair(getattr(self,name),name))
        if not isinstance(self.treasury_rolls, (tuple, list)) or len(self.treasury_rolls) != 3:
            raise TypeError('Treasury rolls require Fed/A/B holder instructions.')
        object.__setattr__(self, 'treasury_rolls', tuple(_number(x) for x in self.treasury_rolls))
        maturity = _number(self.replacement_maturity)
        if not 1 <= maturity <= 120:
            raise ValueError('Replacement Treasury maturity must lie in 1..120 quarters.')
        object.__setattr__(self, 'replacement_maturity', maturity)
        for name in ('treasury_issue_authorization','treasury_redemption','rrp_request'):
            object.__setattr__(self,name,_number(getattr(self,name)))


@dataclass(frozen=True)
class FundedPublicInstructions(PublicInstructions):
    subscription_coupon_mass: tuple = (None, None)

    def __post_init__(self):
        super().__post_init__()
        batch = FundingBatch(rolls=self.treasury_rolls,
            subscriptions=self.treasury_subscriptions,
            subscription_coupon_mass=self.subscription_coupon_mass,
            authorization=self.treasury_issue_authorization,
            maturity=self.replacement_maturity,
            mortgage_repayments=self.mortgage_repayments)
        object.__setattr__(self, 'subscription_coupon_mass', batch.subscription_coupon_mass)


@dataclass(frozen=True)
class ClosingCreditForecast:
    """Conditional nominal plans for A/R and B/F, not credit approvals.

    Project amounts are already gross funding requests, separate from payroll.
    No future realized cash, executable callback or borrower-wallet duplication
    across lenders is permitted by this deliberately narrow mapping.
    """
    payroll_nominal: tuple
    project_gross_nominal: tuple = (ZERO, ZERO)

    def __post_init__(self):
        for name in ('payroll_nominal', 'project_gross_nominal'):
            object.__setattr__(self, name, _amount_pair(getattr(self, name), name))


@dataclass(frozen=True)
class ProjectCommitment:
    """One optional F construction tranche; a ceiling is not an issued loan."""
    lender: str
    face_ceiling: F
    rate_pct: F

    def __post_init__(self):
        _bank(self.lender)
        object.__setattr__(self, 'face_ceiling', _number(self.face_ceiling))
        object.__setattr__(self, 'rate_pct', _number(self.rate_pct, signed=True))


@dataclass(frozen=True)
class Controls:
    facility_limits: tuple = (ZERO, ZERO)
    security_bids: tuple | None = None
    asset_purchase_request: F = ZERO
    asset_offers: tuple = (ZERO, ZERO)
    new_loans: tuple = ()
    renewals: tuple = ()
    household_mode: str = 'fixed'
    public_instructions: PublicInstructions | None = None
    bank_capital_targets: tuple | None = None
    closing_credit_forecast: ClosingCreditForecast | None = None
    project_commitment: ProjectCommitment | None = None

    def __post_init__(self):
        if self.bank_capital_targets is not None:
            object.__setattr__(self, 'bank_capital_targets',
                               _amount_pair(self.bank_capital_targets, 'bank_capital_targets'))
        if self.public_instructions is not None and not isinstance(self.public_instructions,PublicInstructions):
            raise TypeError('Require immutable explicit public instructions.')
        for name in ('facility_limits', 'asset_offers'):
            object.__setattr__(self, name, _amount_pair(getattr(self, name), name))
        if self.security_bids is not None:
            object.__setattr__(self, 'security_bids',
                               _amount_pair(self.security_bids, 'security_bids'))
        object.__setattr__(self, 'asset_purchase_request',
                           _number(self.asset_purchase_request))
        for name, cls in (('new_loans', LoanOffer), ('renewals', Renewal)):
            values = getattr(self, name)
            if not isinstance(values, (tuple, list)) or any(not isinstance(v, cls) for v in values):
                raise TypeError(f'{name} requires an ordered collection of {cls.__name__}.')
            object.__setattr__(self, name, tuple(values))
        if len({r.loan_id for r in self.renewals}) != len(self.renewals):
            raise ValueError('Duplicate renewal quotes are invalid.')
        if type(self.household_mode) is not str:
            raise TypeError('Household mode must be immutable built-in text.')
        if self.household_mode not in ('fixed', 'wallet', 'liquidity', 'cash_stock_close_v1'):
            raise ValueError('Unknown household mode.')
        if self.closing_credit_forecast is not None:
            if type(self.closing_credit_forecast) is not ClosingCreditForecast:
                raise TypeError('Require an immutable ClosingCreditForecast, not a callback.')
            if self.household_mode != 'cash_stock_close_v1':
                raise ValueError('Closing forecasts require the explicit closing-budget mode.')
        if self.project_commitment is not None:
            if type(self.project_commitment) is not ProjectCommitment:
                raise TypeError('Require an immutable ProjectCommitment, not a callback.')
            if self.household_mode != 'cash_stock_close_v1':
                raise ValueError('Project commitments require the explicit closing-budget mode.')


@dataclass(frozen=True,kw_only=True)
class PublicIncomeControls(Controls):
    """Explicit current administered rate; never reprice fixed security coupons."""
    iorb_rate_pct: F

    def __post_init__(self):
        super().__post_init__()
        object.__setattr__(self,'iorb_rate_pct',_number(self.iorb_rate_pct,signed=True))


def _dividend_capital_floor(controls, bank, risk):
    """A payout target retains earned equity; it never changes underwriting."""
    required = COVENANT * risk
    if controls.bank_capital_targets is not None:
        required = max(required, controls.bank_capital_targets[_bank(bank)])
    return required


@dataclass(frozen=True)
class Loan:
    id: str
    lender: str
    face: F
    rate_pct: F
    maturity: int
    start: int
    last_coupon_paid: int
    allowance: F = ZERO
    borrower: str = 'F'
    performing: bool = True

    def __post_init__(self):
        if type(self.id) is not str or not self.id:
            raise ValueError('Loan identity is required.')
        _bank(self.lender)
        _borrower(self.borrower)
        if type(self.performing) is not bool:
            raise TypeError('Performing status must be Boolean.')
        for name in ('face', 'allowance'):
            object.__setattr__(self, name, _number(getattr(self, name)))
        object.__setattr__(self, 'rate_pct', _number(self.rate_pct, signed=True))
        for name in ('start', 'last_coupon_paid', 'maturity'):
            _integer(getattr(self, name), name)
        if (not self.face or self.allowance > self.face or self.maturity <= self.start
                or self.last_coupon_paid < self.start):
            raise ValueError('Invalid active private loan terms.')


@dataclass(frozen=True)
class OperatingLoan(Loan):
    """Explicit prepayable operating contract; inherited fields retain ownership."""

    def __post_init__(self):
        super().__post_init__()
        if self.maturity != self.start + 2:
            raise ValueError('Operating loans require exactly two settlement dates.')


@dataclass(frozen=True)
class ProjectLoan(Loan):
    """Protected actual project principal; no explicit renewal/novation."""

    def __post_init__(self):
        super().__post_init__()
        if self.borrower != 'F' or not 2 <= self.maturity - self.start <= 17:
            raise ValueError('Project principal requires its F owner and dated construction schedule.')


@dataclass(frozen=True)
class Collateral:
    kind: str
    claim_id: str
    face: F

    def __post_init__(self):
        if type(self.kind) is not str or self.kind not in ('public_security', 'private_loan') or type(self.claim_id) is not str:
            raise ValueError('Collateral must identify an owned eligible claim.')
        object.__setattr__(self, 'face', _number(self.face))


@dataclass(frozen=True)
class CBLoan:
    id: str
    bank: str
    face: F
    start: int
    maturity: int
    collateral: tuple = ()

    def __post_init__(self):
        _bank(self.bank)
        if type(self.id) is not str or not self.id:
            raise ValueError('CB claim identity is required.')
        object.__setattr__(self, 'face', _number(self.face))
        _integer(self.start, 'CB start')
        _integer(self.maturity, 'CB maturity', 1)
        object.__setattr__(self, 'collateral', tuple(self.collateral))
        if (not self.face or self.maturity != self.start + 1
                or any(not isinstance(x, Collateral) for x in self.collateral)):
            raise ValueError('CB principal has a one-quarter identified term.')


@dataclass(frozen=True)
class Bank:
    name: str
    reserves: F
    securities: F
    deposits: tuple  # R/HA for A, F/HB for B

    def __post_init__(self):
        _bank(self.name)
        for name in ('reserves', 'securities'):
            object.__setattr__(self, name, _number(getattr(self, name)))
        object.__setattr__(self, 'deposits', _amount_pair(self.deposits, 'deposits'))


@dataclass(frozen=True)
class Vintage:
    age: int
    units: F
    basis: F

    def __post_init__(self):
        _integer(self.age, 'Vintage age')
        if self.age > 15:
            raise ValueError('Retired capital cannot remain active.')
        object.__setattr__(self, 'units', _number(self.units))
        object.__setattr__(self, 'basis', _number(self.basis))

    @property
    def net_book(self):
        return self.basis * (15 - self.age) / 16


@dataclass(frozen=True)
class Payment:
    payer: str
    payee: str
    amount: F
    kind: str
    claim_id: str | None = None

    def __post_init__(self):
        if not all(type(x) is str for x in (self.payer, self.payee, self.kind)):
            raise TypeError('Payments require identified parties and purpose.')
        if self.claim_id is not None and type(self.claim_id) is not str:
            raise TypeError('A payment claim ID must be immutable text.')
        object.__setattr__(self, 'amount', _number(self.amount))


@dataclass(frozen=True)
class Trace:
    kind: str
    actor: str
    counterparty: str
    amount: F
    claim_id: str | None = None
    details: tuple = ()

    def __post_init__(self):
        if not all(type(x) is str for x in (self.kind, self.actor, self.counterparty)):
            raise TypeError('Trace parties and purpose must be immutable text.')
        if self.claim_id is not None and type(self.claim_id) is not str:
            raise TypeError('A trace claim ID must be immutable text.')
        object.__setattr__(self, 'amount', _number(self.amount, signed=True))
        # Details are flat immutable key/value pairs, never mutable payloads.
        details = tuple(tuple(x) for x in self.details)
        if any(len(x) != 2 or type(x[0]) is not str
               or not isinstance(x[1], (str, int, F, bool, type(None))) for x in details):
            raise TypeError('Trace details must contain immutable scalar values.')
        object.__setattr__(self, 'details', details)


@dataclass(frozen=True)
class Report:
    quarter: int
    real_output: F
    services: F
    investment: F
    residual_consumption: F
    paid_residual_workers: F
    paid_focal_workers: F
    payroll_residual: F
    payroll_focal: F
    depreciation: F
    private_interest: F
    dividend_residual: F
    dividend_focal: F
    dividend_bank: F
    cb_borrowed: F
    cb_repaid: F
    asset_purchase_applied: F
    asset_purchase_unfilled: F
    payments: tuple
    trace: tuple

    def __post_init__(self):
        _integer(self.quarter, 'Report quarter', 1)
        for name in self.__dataclass_fields__:
            if name not in ('quarter', 'payments', 'trace'):
                object.__setattr__(self, name, _number(getattr(self, name), name == 'private_interest'))
        for name, cls in (('payments', Payment), ('trace', Trace)):
            values = tuple(getattr(self, name))
            if any(not isinstance(x, cls) for x in values):
                raise TypeError('Invalid current report records.')
            object.__setattr__(self, name, values)
        if self.real_output != self.residual_consumption + self.services + self.investment:
            raise ValueError('GDP has exactly the three paid real production components.')

    @property
    def consumption(self):
        return self.residual_consumption + self.services

    @property
    def interest(self):
        return self.private_interest

    def bank_dividend_to(self, owner):
        if owner not in ('HA', 'HB'):
            raise ValueError('Unknown bank-equity owner.')
        return sum((p.amount for p in self.payments
                    if p.kind == 'bank_dividend' and p.payee == owner), ZERO)

    def public_income_to(self, owner):
        if owner not in ('HA','HB'):raise ValueError('Unknown household owner.')
        return sum((p.amount*((p.payee==owner)-(p.payer==owner))
                    for p in self.payments if p.kind=='mortgage_coupon'),ZERO)

    def disposable_income(self, owner):
        if owner not in ('HA','HB'):raise ValueError('Unknown household owner.')
        return ((self.payroll_residual+self.dividend_residual if owner=='HA' else
                 self.payroll_focal+self.dividend_focal)+self.bank_dividend_to(owner)
                +self.public_income_to(owner))


@dataclass(frozen=True)
class SectorState:
    quarter: int
    scale: F
    banks: tuple
    loans: tuple
    cb_loans: tuple
    vintages: tuple
    wip_units: F
    wip_basis: F
    public_securities: F
    gov_debt_face: F
    next_private_id: int = 1
    last: Report | None = None
    public_book: PublicBook | None = None

    def __post_init__(self):
        _integer(self.quarter, 'Quarter')
        _integer(self.next_private_id, 'Next private ID', 1)
        for name in ('scale', 'wip_units', 'wip_basis', 'public_securities', 'gov_debt_face'):
            object.__setattr__(self, name, _number(getattr(self, name)))
        if not self.scale:
            raise ValueError('Nominal price/wage scale must be positive.')
        for name, cls in (('banks', Bank), ('loans', Loan), ('cb_loans', CBLoan), ('vintages', Vintage)):
            values = tuple(getattr(self, name))
            if any(not isinstance(x, cls) for x in values):
                raise TypeError(f'{name} requires immutable identified records.')
            object.__setattr__(self, name, values)
        if tuple(b.name for b in self.banks) != BANKS:
            raise ValueError('Exactly Bank A and Bank B are required, in order.')
        if len({v.age for v in self.vintages}) != len(self.vintages):
            raise ValueError('Only one active vintage per age is permitted.')
        if len({l.id for l in self.loans}) != len(self.loans):
            raise ValueError('Duplicate active private claim.')
        if any(l.start > self.quarter or l.last_coupon_paid > self.quarter for l in self.loans):
            raise ValueError('Loan timestamps cannot be in the future.')
        if len({l.bank for l in self.cb_loans}) != len(self.cb_loans):
            raise ValueError('Only one active CB cohort per bank is permitted.')
        if any(l.start > self.quarter for l in self.cb_loans):
            raise ValueError('CB loan cannot start in the future.')
        book=self.public_book
        if book is not None:
            if not isinstance(book,PublicBook):
                raise TypeError('Require immutable public accounts.')
            if book.private_treasuries is None:
                raise ValueError('PublicBook requires identified private Treasury maturity arrays.')
            if any(sum(cohorts) != bank.securities for cohorts, bank in zip(book.private_treasuries, self.banks)):
                raise ValueError('Private Treasury cohorts must match their bank-owned face.')
            if any(c.start > self.quarter or c.maturity != self.quarter + 1 for c in book.rrp_claims):
                raise ValueError('Active RRP claims must mature next quarter and cannot start in the future.')
            if self.public_securities != sum(book.treasuries)+book.mbs:
                raise ValueError('Fed public assets must identify actual Treasury and MBS holdings.')
        mbs=book.mbs if book else ZERO
        public_liabilities=sum(book.currency)+book.tga+book.capital_other+sum(c.face for c in book.rrp_claims) if book else ZERO
        if self.gov_debt_face != self.public_securities-mbs + sum(b.securities for b in self.banks):
            raise ValueError('Existing public face must reconcile with its issuer.')
        deferred=book.deferred_asset if isinstance(book,PublicIncomeBook) else ZERO
        if isinstance(book,PublicIncomeBook) and book.income_paid_through!=self.quarter:
            raise ValueError('Public income clock must match the current ledger quarter.')
        if isinstance(book,FundedPublicBook):
            if _is_paydate(book):
                _validate_paydate_book(book, self.scale, self.quarter,
                    None if self.last is None else self.last.payments,
                    None if self.last is None else self.last.trace)
                if self.quarter:
                    closing = book.phases[-1].snapshot
                    if (closing.reserves != tuple(b.reserves for b in self.banks)
                            or closing.wallets != tuple(self.deposit(a) for a in ACTORS)
                            or closing.cb_faces != tuple(self.cb_debt(b) for b in BANKS)):
                        raise ValueError('Actual closing state differs from its paydate journal witness.')
                    if _is_early_paydate(book):
                        if book.closing_cb_loans != self.cb_loans or book.closing_private_loans != self.loans:
                            raise ValueError('Closing actual claims differ from early journal identities/pledges.')
                        gross = sum((n.amount for n in self.last.trace if n.kind == 'facility_applied'), ZERO)
                        retired = sum((n.amount for n in self.last.trace if n.kind in (
                            'cb_principal_retired', 'cb_early_principal_retired')), ZERO)
                        if self.last.cb_borrowed != gross or self.last.cb_repaid != retired:
                            raise ValueError('Reported gross CB borrowing/retirement differs from actual trace.')
                    if book.paid_wages != (self.last.payroll_residual, self.last.payroll_focal):
                        raise ValueError('Actual paydate payroll differs from its paid report.')
            else:
                validate_funded_public(book,self.scale,self.quarter)
            if not self.quarter:
                public_income.quote(book.terms,
                    treasuries=(book.treasuries,*book.private_treasuries),mortgages=book.mortgages,
                    reserves=tuple(b.reserves for b in self.banks),
                    cb_faces=tuple(self.cb_debt(b) for b in BANKS),
                    rrp_faces=tuple(self.rrp_face(b) for b in BANKS),scale=self.scale)
        elif isinstance(book,PublicIncomeBook) and self.quarter:
            public_income.validate_observations(book.terms,book.observations,
                treasuries=(book.treasuries,*book.private_treasuries),mortgages=book.mortgages,
                scale=self.scale,opening_deferred=book.opening_deferred_asset,deferred=book.deferred_asset)
        if self.public_securities + sum(l.face for l in self.cb_loans)+deferred != sum(b.reserves for b in self.banks)+public_liabilities:
            raise ValueError('CB assets must match actual reserve liabilities.')
        for bank in BANKS:
            pool = _pledges(self, bank, self.cb_debt(bank))
            active = tuple(l for l in self.cb_loans if l.bank == bank)
            if active and active[0].collateral != pool:
                raise ValueError('CB collateral must identify actual currently pledged owned assets.')
        if self.last is not None and (not isinstance(self.last, Report) or self.last.quarter != self.quarter):
            raise ValueError('Only the current report is retained.')

    def deposit(self, actor):
        if actor not in ACTORS:
            raise ValueError('Unknown private deposit owner.')
        b = self.banks[_bank(HOME[actor])]
        return b.deposits[0 if actor in ('R', 'F') else 1]

    def reserves(self, bank):
        return self.banks[_bank(bank)].reserves

    def securities(self, bank):
        return self.banks[_bank(bank)].securities

    def cb_debt(self, bank):
        _bank(bank)
        return sum((l.face for l in self.cb_loans if l.bank == bank), ZERO)

    def bank_equity(self, bank):
        b = self.banks[_bank(bank)]
        return (b.reserves + b.securities + self.rrp_face(bank)
                + sum((l.face-l.allowance for l in self.loans if l.lender == bank), ZERO)
                - sum(b.deposits) - self.cb_debt(bank))

    def rrp_face(self, bank):
        _bank(bank)
        return sum((c.face for c in self.public_book.rrp_claims if c.bank == bank), ZERO) if self.public_book else ZERO

    @property
    def loan_face(self):
        return sum((l.face for l in self.loans), ZERO)

    @property
    def capital_units(self):
        return sum((v.units for v in self.vintages), ZERO)

    @property
    def net_capital(self):
        return self.wip_basis + sum((v.net_book for v in self.vintages), ZERO)

    def borrower_debt(self, actor):
        _borrower(actor)
        return sum((l.face for l in self.loans if l.borrower==actor),ZERO)

    @property
    def residual_equity(self):
        return self.deposit('R')-self.borrower_debt('R')

    @property
    def focal_equity(self):
        return self.deposit('F') + self.net_capital - self.borrower_debt('F')

    @property
    def private_wealth(self):
        return (sum((b.reserves+b.securities for b in self.banks), ZERO)
                + self.net_capital - sum((l.face for l in self.cb_loans), ZERO)
                - sum((l.allowance for l in self.loans), ZERO)
                + (sum(self.public_book.currency)-sum(self.public_book.mortgages)
                   + sum(c.face for c in self.public_book.rrp_claims) if self.public_book else ZERO))


State = SectorState


def _private_collateral(state, bank):
    return sum((l.face-l.allowance for l in state.loans
                if l.lender == bank and l.performing), ZERO)


def _pledges(state, bank, debt):
    """One pool per bank, with each net private claim/public face used once."""
    needed = debt / HAIRCUT_VALUE
    result = []
    for loan in state.loans:
        if loan.lender == bank and loan.performing and needed:
            face = min(needed, loan.face-loan.allowance)
            if face:
                result.append(Collateral('private_loan', loan.id, face))
                needed -= face
    if needed:
        face = min(needed, state.securities(bank))
        if face:
            result.append(Collateral('public_security', 'Treasury:'+bank, face))
            needed -= face
    if needed:
        raise ValueError('CB debt exceeds actual eligible closing collateral.')
    return tuple(result)


def initial(scale=1, reserves=4, legacy_rate_pct=4):
    s, r = _number(scale), _number(reserves)
    if not s:
        raise ValueError('Nominal price/wage scale must be positive.')
    # reserves is the opening nominal stock in unscaled initial-GDP units.
    r *= s
    return SectorState(0, s,
        (Bank('A', r*F(3,4), 18*s, (17*s,3*s)),
         Bank('B', r*F(1,4), ZERO, (3*s,s))),
        (Loan('L0','B',10*s,legacy_rate_pct,48,0,0),), (),
        tuple(Vintage(age, F(1), s) for age in range(16)), F(1), s,
        r, r+18*s)


def initial_core(scale=1,legacy_rate_pct=4):
    """Source opening stocks; authored household/pool ownership, not US calibration."""
    params=source_data.load_parameters()
    ref=source_data.load_portfolio()
    scale=_number(scale)
    a=initial(scale=scale,reserves=params['initial_reserves_pct_initial_gdp'],legacy_rate_pct=legacy_rate_pct)
    assets=_number(params['initial_asset_stock_pct_initial_gdp'])*scale
    share=F(ref['source_treasury_principal_usd'])/(F(ref['source_treasury_principal_usd'])+F(str(ref['mbs_stock_billion_usd']))*10**9)
    quantum=scale*QUANTUM
    treasury_total=_floor(assets*share,quantum)
    weights=tuple(F(str(x)) for x in ref['treasury_maturity_weights'])
    cohorts = _distribute(treasury_total, weights, quantum)
    # AUTHORED bank maturity distribution, not observed bank holdings.
    private = (_distribute(a.securities('A'), weights, quantum), (ZERO,) * 120)
    mbs=assets-treasury_total
    mortgage_a=_floor(mbs*F(3,4),quantum)
    currency=_number(params['initial_currency_pct_initial_gdp'])*scale
    tga=_number(params['initial_treasury_account_pct_initial_gdp'])*scale
    capital=assets-sum(b.reserves for b in a.banks)-currency-tga
    book=PublicBook(tuple(cohorts),mbs,(mortgage_a,mbs-mortgage_a),(currency*F(3,4),currency*F(1,4)),tga,capital,private)
    return replace(a,public_securities=assets,gov_debt_face=treasury_total+sum(b.securities for b in a.banks),public_book=book)


def initial_depth_reference(scale=1):
    """Fresh authored chi=1.85 opening book; never migrate/revalue a career.

    Not an estimated US technology or an adopted replacement for initial_core.
    Its source-file dependency is the same read-only fixture as initial_core.
    """
    state = initial_core(scale=scale)
    basis = F(37, 20) * state.scale
    return replace(state,
                   banks=(state.banks[0], replace(state.banks[1],
                          deposits=(state.deposit('F'), F(3, 20)*state.scale))),
                   vintages=tuple(replace(v, basis=basis) for v in state.vintages),
                   wip_basis=basis)


def public_income_terms(state, *, treasury_rates_pct=(0,0,0),
                        mortgage_rates_pct=(0,0),iorb_rate_pct=0,
                        cb_rates_pct=(None,None),rrp_rates_pct=(None,None)):
    """Author an opening contract; holder rates are not estimated coupon data."""
    _state(state)
    book=state.public_book
    if book is None:raise ValueError('Require explicit public positions.')
    if type(treasury_rates_pct) is not tuple or len(treasury_rates_pct)!=3:
        raise TypeError('Require explicit CB/A/B Treasury rates.')
    rates=tuple(_number(x,signed=True) for x in treasury_rates_pct)
    annual=tuple(tuple(face*rate/100 for face in row) for row,rate in
                 zip((book.treasuries,*book.private_treasuries),rates))
    return PublicIncomeTerms(annual,tuple(mortgage_rates_pct),iorb_rate_pct,
                             tuple(cb_rates_pct),tuple(rrp_rates_pct))


def enable_public_income(state,terms):
    """Fresh research books only; never migrate an existing career or report."""
    _state(state)
    if state.quarter or state.last is not None or type(state.public_book) is not PublicBook:
        raise ValueError('Public-income activation requires a fresh legacy reference book.')
    book=state.public_book
    values={name:getattr(book,name) for name in PublicBook.__dataclass_fields__}
    enabled=PublicIncomeBook(**values,terms=terms)
    # Coverage is checked even before the first transaction is attempted.
    public_income.quote(terms,treasuries=(book.treasuries,*book.private_treasuries),
        mortgages=book.mortgages,reserves=tuple(b.reserves for b in state.banks),
        cb_faces=tuple(state.cb_debt(b) for b in BANKS),
        rrp_faces=tuple(state.rrp_face(b) for b in BANKS),scale=state.scale)
    return replace(state,public_book=enabled)


def enable_funded_public(state, terms):
    """Fresh exact legacy Q0 only; no activation/migration of paid careers."""
    _state(state)
    if state.quarter or state.last is not None or type(state.public_book) is not PublicBook:
        raise ValueError('Funded public activation requires a fresh exact legacy reference book.')
    book = state.public_book
    values = {name: getattr(book, name) for name in PublicBook.__dataclass_fields__}
    enabled = FundedPublicBook(**values, terms=terms)
    # FundingOpening applies the pure API's strict scalar/term boundary without
    # inventing a paid Q1 record in the fresh book.
    FundingOpening(quarter=1, scale=state.scale, terms=terms,
        treasuries=(book.treasuries, *book.private_treasuries),
        mortgages=book.mortgages, reserves=tuple(b.reserves for b in state.banks),
        household_deposits=tuple(state.deposit(h) for h in ('HA', 'HB')),
        cb_faces=tuple(state.cb_debt(b) for b in BANKS),
        rrp_faces=tuple(state.rrp_face(b) for b in BANKS), tga=book.tga)
    # The SectorState boundary also checks all actual Q0 CB/RRP contracts.
    return replace(state, public_book=enabled)


def enable_paydate_public(state, terms):
    """Fresh exact legacy Q0 only; no migration from ANY paid/enabled book."""
    _state(state)
    if state.quarter or state.last is not None or type(state.public_book) is not PublicBook:
        raise ValueError('Paydate public activation requires a fresh exact legacy reference book.')
    book = state.public_book
    values = {name: getattr(book, name) for name in PublicBook.__dataclass_fields__}
    enabled = PaydatePublicBook(**values, terms=terms)
    FundingOpening(quarter=1, scale=state.scale, terms=terms,
        treasuries=(book.treasuries, *book.private_treasuries),
        mortgages=book.mortgages, reserves=tuple(b.reserves for b in state.banks),
        household_deposits=tuple(state.deposit(h) for h in ('HA', 'HB')),
        cb_faces=tuple(state.cb_debt(b) for b in BANKS),
        rrp_faces=tuple(state.rrp_face(b) for b in BANKS), tga=book.tga)
    return replace(state, public_book=enabled)


def enable_early_paydate_public(state, terms):
    """Fresh exact legacy Q0 only; no migration from ANY paid/enabled book."""
    _admit_early_state(state, terms)
    _state(state)
    if state.quarter or state.last is not None or type(state.public_book) is not PublicBook:
        raise ValueError('Early-paydate public activation requires a fresh exact legacy reference book.')
    book = state.public_book
    values = {name: getattr(book, name) for name in PublicBook.__dataclass_fields__}
    enabled = EarlyPaydateBook(**values, terms=terms)
    FundingOpening(quarter=1, scale=state.scale, terms=terms,
        treasuries=(book.treasuries, *book.private_treasuries),
        mortgages=book.mortgages, reserves=tuple(b.reserves for b in state.banks),
        household_deposits=tuple(state.deposit(h) for h in ('HA', 'HB')),
        cb_faces=tuple(state.cb_debt(b) for b in BANKS),
        rrp_faces=tuple(state.rrp_face(b) for b in BANKS), tga=book.tga)
    return replace(state, public_book=enabled)


def enable_household_liquidity_public(state, terms):
    """Fresh exact legacy Q0 ONLY; never reinterpret a paid/enabled book."""
    _admit_early_state(state, terms)
    _state(state)
    if state.quarter or state.last is not None or type(state.public_book) is not PublicBook:
        raise ValueError('Household liquidity requires a fresh exact legacy reference book.')
    book = state.public_book
    enabled = HouseholdLiquidityBook(**{name:getattr(book, name)
        for name in PublicBook.__dataclass_fields__}, terms=terms)
    FundingOpening(quarter=1, scale=state.scale, terms=terms,
        treasuries=(book.treasuries, *book.private_treasuries), mortgages=book.mortgages,
        reserves=tuple(b.reserves for b in state.banks),
        household_deposits=tuple(state.deposit(h) for h in ('HA', 'HB')),
        cb_faces=tuple(state.cb_debt(b) for b in BANKS),
        rrp_faces=tuple(state.rrp_face(b) for b in BANKS), tga=book.tga)
    return replace(state, public_book=enabled)


def depth_orders():
    """Orders matching the new authored depth reference, not the old C19 book."""
    return ProductionOrders(capital_resource_cost=F(37, 20),
                            residual_consumption=F(363, 20),
                            service_a=F(37, 20), service_b=F(63, 20),
                            preferences_a=household.Preferences(F(363, 20), F(37, 20), 3),
                            preferences_b=household.Preferences(0, F(63, 20), F(3, 20)),
                            initial_dividends_real=(F(3), F(3, 20)))


@dataclass(frozen=True)
class Outcome:
    ok: bool
    status: str
    state: SectorState
    reason: str = ''
    claim_id: str | None = None

    def __post_init__(self):
        if type(self.ok) is not bool or not isinstance(self.state, SectorState):
            raise TypeError('An outcome requires a Boolean and immutable SectorState.')
        if not isinstance(self.status, str) or not isinstance(self.reason, str):
            raise TypeError('Outcome status and reason must be text.')
        if self.claim_id is not None and type(self.claim_id) is not str:
            raise TypeError('Outcome claim ID must be text.')


class _Failure(Exception):
    def __init__(self, status, reason, claim_id=None):
        super().__init__(reason)
        self.status, self.reason, self.claim_id = status, reason, claim_id


class _Transaction:
    """Ephemeral journal; no mutable part escapes to either immutable State."""
    def __init__(self, state, controls, quarter):
        if isinstance(state.public_book, FundedPublicBook):
            if _is_paydate(state.public_book):
                if quarter != state.quarter + 1:
                    raise ValueError('Paydate books permit only complete atomic quarters, not quarterless mutations.')
                _validate_paydate_book(state.public_book, state.scale, state.quarter,
                    None if state.last is None else state.last.payments,
                    None if state.last is None else state.last.trace)
            else:
                validate_funded_public(state.public_book, state.scale, state.quarter,
                                      None if state.last is None else state.last.payments)
        self.original, self.scale, self.quarter = state, state.scale, quarter
        self.money_quantum = self.scale * QUANTUM
        self.r = {b.name:b.reserves for b in state.banks}
        self.s = {b.name:b.securities for b in state.banks}
        self.d = {a:state.deposit(a) for a in ACTORS}
        # The borrower owns these newly issued lender deposits until primary-bank delivery.
        self.transit_deposits = dict.fromkeys(BANKS, ZERO)
        self.loans = list(state.loans)
        self.cb = {l.bank:l for l in state.cb_loans}
        self.next_id = state.next_private_id
        self.public = state.public_securities
        self.public_book = state.public_book
        if isinstance(controls,PublicIncomeControls):
            if not isinstance(self.public_book,PublicIncomeBook):
                raise ValueError('Public administered-rate command requires its enabled book.')
            self.public_book=replace(self.public_book,
                terms=replace(self.public_book.terms,iorb_rate_pct=controls.iorb_rate_pct))
        self.treasuries = ({'CB': list(state.public_book.treasuries),
                            **{b: list(c) for b, c in zip(BANKS, state.public_book.private_treasuries)}}
                           if state.public_book else None)
        self.rrp = list(state.public_book.rrp_claims) if state.public_book else []
        self.annual_masses = ({o: list(row) for o, row in zip(
            ('CB', *BANKS), self.public_book.terms.annual_treasury)}
            if isinstance(self.public_book, FundedPublicBook) else None)
        self.transfers = (list(self.public_book.transfers)
            if isinstance(self.public_book, FundedPublicBook) and quarter == state.quarter else [])
        self.funding_opening = self.funding_batch = None
        self.funding_projection = self.funding_prefix = None
        self.paydate_phases = []
        self.paydate_stage = None
        self.paydate_lines = ()
        self.later_credit = []
        self.gov_face = state.gov_debt_face
        self.trace, self.payments = [], []
        self.limits = dict(zip(BANKS, controls.facility_limits))
        self.used = dict.fromkeys(BANKS, ZERO)
        self.bids = dict(zip(BANKS, controls.security_bids if controls.security_bids is not None else (0, self.scale)))
        self.cb_borrowed = self.cb_repaid = ZERO
        self.qe_applied = ZERO
        self.earnings = dict.fromkeys(BANKS, ZERO)
        for value in (*self.limits.values(), *self.bids.values(), controls.asset_purchase_request, *controls.asset_offers):
            _money(value, self.scale)

    def note(self, kind, actor, counterparty, amount=0, claim_id=None, **details):
        self.trace.append(Trace(kind, actor, counterparty, amount, claim_id, tuple(details.items())))

    def record(self, payer, payee, value, kind, claim_id=None):
        if value:
            self.payments.append(Payment(payer,payee,value,kind,claim_id))
            self.note(kind,payer,payee,value,claim_id)
            if _is_paydate(self.public_book):
                self.note('paydate_payment', payer, payee, value, claim_id,
                          payment_kind=kind, position=len(self.payments) - 1)

    def securities(self, bank):
        return self.s[bank]

    def debt(self, bank):
        return self.cb[bank].face if bank in self.cb else ZERO

    def risk(self, bank):
        return sum((l.face for l in self.loans if l.lender == bank), ZERO)

    def equity(self, bank):
        return (self.r[bank]+self.s[bank]+sum((c.face for c in self.rrp if c.bank == bank), ZERO)
                + sum((l.face-l.allowance for l in self.loans if l.lender == bank), ZERO)
                - sum(self.d[a] for a in ACTORS if HOME[a] == bank)
                - self.transit_deposits[bank]-self.debt(bank))

    def capacity(self, bank):
        return HAIRCUT_VALUE * (self.s[bank]+_private_collateral(self,bank))

    def free_securities(self, bank):
        pledged_public = max(ZERO, self.debt(bank)/HAIRCUT_VALUE - _private_collateral(self,bank))
        return _floor(max(ZERO,self.s[bank]-pledged_public), self.money_quantum)

    def check_capital(self, bank, claim_id=None):
        if self.equity(bank) <= 0 or self.equity(bank) < COVENANT*self.risk(bank):
            raise _Failure('credit_constraint',f'Bank {bank} has insufficient private capital headroom.',claim_id)

    def prepay_uncovered_cb(self, bank):
        excess=max(ZERO,self.debt(bank)-self.capacity(bank))
        if not excess:
            return
        if excess>self.r[bank]:
            raise _Failure('funding_failure','Released collateral requires actual bank-owned CB repayment funds.')
        old=self.cb[bank]
        remaining=old.face-excess
        self.r[bank]-=excess
        self.cb_repaid+=excess
        if remaining:
            self.cb[bank]=replace(old,face=remaining,collateral=_pledges(self,bank,remaining))
        else:
            del self.cb[bank]
        self.record(bank,'CB',excess,'cb_collateral_prepayment',old.id)
        self.note('cb_early_principal_retired',bank,'CB',excess,old.id,remaining=remaining)

    def refresh_cb(self, bank):
        if bank in self.cb:
            loan = self.cb[bank]
            try:
                pool = _pledges(self,bank,loan.face)
            except ValueError as error:
                raise _Failure('funding_failure',str(error),loan.id) from error
            self.cb[bank] = replace(loan,collateral=pool)

    def _draw(self, bank, value, refinance=False):
        if not value:
            return
        if isinstance(self.public_book,PublicIncomeBook) and self.public_book.terms.cb_rates_pct[_bank(bank)] is None:
            raise _Failure('unsupported_public_income','New CB credit lacks explicit coupon terms.')
        if self.equity(bank) <= 0:
            raise _Failure('funding_failure',f'Bank {bank} is not solvent for CB funding.')
        if value > self.limits[bank]-self.used[bank] or self.debt(bank)+value > self.capacity(bank):
            raise _Failure('funding_failure',f'Bank {bank} lacks an offered collateral-backed facility.')
        observed = None
        identity = f'CB{self.quarter}:{bank}'
        if _is_early_paydate(self.public_book):
            identity = _early_cb_id(self.quarter, bank, self.original.cb_loans)
            old = self.cb.get(bank)
            stages = (('funded_payroll', 'household_credit', 'trading')
                      if type(self.public_book) is HouseholdLiquidityBook else ('funded_payroll', 'trading'))
            if (refinance or self.paydate_stage not in stages
                    or (old is not None and (old.id != identity or old.start != self.quarter
                                            or old.maturity != self.quarter+1))):
                raise _Failure('unsupported_public_income', 'Later credit cannot overwrite an unretired CB cohort.')
            observed = (len(self.payments), len(self.trace), self._paydate_snapshot(),
                        tuple(self.loans), tuple(self.transit_deposits[b] for b in BANKS), old,
                        self.limits[bank], self.used[bank])
        debt = self.debt(bank)+value
        self.cb[bank] = CBLoan(identity,bank,debt,self.quarter,self.quarter+1,
                               _pledges(self,bank,debt))
        self.used[bank] += value
        self.r[bank] += value
        self.cb_borrowed += value
        self.record('CB',bank,value,'cb_refinance' if refinance else 'cb_draw',self.cb[bank].id)
        self.note('facility_applied',bank,'CB',value,self.cb[bank].id,
                  offered=self.limits[bank],gross_applied=self.used[bank],capacity=self.capacity(bank))
        for position in self.cb[bank].collateral:
            self.note('collateral_pledged',bank,'CB',position.face,position.claim_id,kind_of_asset=position.kind)
        if observed is not None:
            self.later_credit.append(LaterCreditWitness(bank, *observed, value, self.cb[bank]))

    def sell_for_funding(self, bank, shortfall):
        buyer = 'B' if bank == 'A' else 'A'
        if self.equity(bank) <= 0 or self.equity(buyer) <= 0:
            return
        sale = _floor(min(shortfall,self.bids[buyer],self.r[buyer],self.free_securities(bank)),self.money_quantum)
        if sale:
            self.transfer_treasuries(bank, buyer, sale)
            self.s[bank] -= sale
            self.s[buyer] += sale
            self.r[buyer] -= sale
            self.r[bank] += sale
            self.bids[buyer] -= sale
            self.record(buyer,bank,sale,'private_public_par_trade','Treasury:'+bank)
            self.note('public_face_transfer',bank,buyer,sale,'Treasury:'+bank)
            self.refresh_cb(bank)

    def fund(self, bank, value):
        if value <= self.r[bank]:
            return
        shortfall = value-self.r[bank]
        self.sell_for_funding(bank,shortfall)
        shortfall = value-self.r[bank]
        if shortfall > 0:
            # Existing stocks need not lie on the flow grid. The minimum
            # quantum-funded draw may leave sub-quantum cash with its owner;
            # never round an existing reserve stock or draw fractional quanta.
            required = -(-shortfall // self.money_quantum)*self.money_quantum
            available = _floor(min(self.limits[bank]-self.used[bank],
                                   max(ZERO,self.capacity(bank)-self.debt(bank))),self.money_quantum)
            if required > available:
                raise _Failure('funding_failure',f'Bank {bank} cannot fund owned-payment reserve settlement.')
            self._draw(bank,required)

    def reserve_transfer(self, source, target, value, kind, claim_id=None):
        if value and source != target:
            self.fund(source,value)
            self.r[source] -= value
            self.r[target] += value
            self.note('reserve_settlement',source,target,value,claim_id,purpose=kind)

    def pay(self, payer, payee, value, kind, claim_id=None):
        if value > self.d[payer]:
            raise _Failure('credit_default',f'{payer} lacks owned deposits for {kind}.',claim_id)
        self.reserve_transfer(HOME[payer],HOME[payee],value,kind,claim_id)
        self.d[payer] -= value
        self.d[payee] += value
        self.record(payer,payee,value,kind,claim_id)

    def coupon(self, loan):
        borrower=loan.borrower
        if loan.start == self.quarter or loan.last_coupon_paid == self.quarter:
            return ZERO
        if loan.last_coupon_paid != self.quarter-1:
            raise _Failure('credit_default','Unpaid opening coupon cannot be erased by refinancing.',loan.id)
        contractual, interest = precision.coupon(loan.face,loan.rate_pct,self.scale,QUANTUM)
        if interest >= 0:
            if interest > self.d[borrower]:
                raise _Failure('credit_default','Mandatory coupon exceeds focal-owned deposits.' if borrower=='F' else 'Mandatory coupon exceeds residual-owned deposits.',loan.id)
            self.reserve_transfer(HOME[borrower],loan.lender,interest,'private_coupon',loan.id)
            self.d[borrower] -= interest
            self.record(borrower,'Bank'+loan.lender,interest,'private_coupon',loan.id)
        else:
            self.reserve_transfer(loan.lender,HOME[borrower],-interest,'private_coupon',loan.id)
            self.d[borrower] -= interest
            self.record('Bank'+loan.lender,borrower,-interest,'private_coupon',loan.id)
        self.earnings[loan.lender] += interest
        self.note('coupon_paid',loan.lender,borrower,interest,loan.id,contractual=contractual,paid_quarter=self.quarter)
        index = self.loans.index(loan)
        self.loans[index] = replace(loan,last_coupon_paid=self.quarter)
        return interest

    def originate(self, offer, at_open=False, _project=False):
        borrower=offer.borrower
        _money(offer.face,self.scale)
        start = self.quarter-1 if at_open else self.quarter
        if offer.maturity <= start:
            raise ValueError('New loan maturity must be a future quarter.')
        loan_type = (ProjectLoan if _project else
                     OperatingLoan if isinstance(offer, OperatingLoanOffer) else Loan)
        if _project and (not at_open or borrower != 'F' or type(offer) is not LoanOffer):
            raise ValueError('Project draw requires an opening F tranche, not an operating offer.')
        if loan_type is OperatingLoan and offer.maturity != start + 2:
            raise ValueError('Operating credit requires two settlement dates.')
        bank = offer.lender
        # Equity is unchanged by matching loan/deposit creation/settlement.
        if self.equity(bank) <= 0 or self.equity(bank) < COVENANT*(self.risk(bank)+offer.face):
            raise _Failure('credit_constraint','Loan offer exceeds lender closing capital headroom.')
        loan = loan_type(f'L{self.next_id}',bank,offer.face,offer.rate_pct,offer.maturity,
                    start,start,borrower=borrower)
        self.next_id += 1
        self.loans.append(loan)
        self.transit_deposits[bank] += offer.face
        if type(self.public_book) is HouseholdLiquidityBook:
            self.trace.append(_household_private_pending(loan))
        self.note('loan_deposit_created',bank,borrower,offer.face,loan.id)
        self.reserve_transfer(bank,HOME[borrower],offer.face,'loan_origination',loan.id)
        self.transit_deposits[bank] -= offer.face
        self.d[borrower] += offer.face
        self.note('loan_deposit_delivered',bank,borrower,offer.face,loan.id)
        self.record('Bank'+bank,borrower,offer.face,'loan_origination',loan.id)
        self.note('matching_loan_created',bank,borrower,offer.face,loan.id,maturity=loan.maturity,start=loan.start,rate_pct=loan.rate_pct)
        if type(self.public_book) is HouseholdLiquidityBook:
            self.trace.append(_household_private_origin(loan))
        return loan.id

    def principal(self, loan, value):
        borrower=loan.borrower
        _money(value,self.scale)
        if value > loan.face:
            raise ValueError('Principal repayment exceeds legal face.')
        if value > self.d[borrower]:
            raise _Failure('credit_default','Maturing principal exceeds focal-owned deposits.' if borrower=='F' else 'Maturing principal exceeds residual-owned deposits.',loan.id)
        self.reserve_transfer(HOME[borrower],loan.lender,value,'private_principal',loan.id)
        self.d[borrower] -= value
        remaining = loan.face-value
        # A recovered provision is not coupon income or principal profit.
        # Only allowance that cannot remain on the remaining face is released.
        release = max(ZERO,loan.allowance-remaining)
        self.loans.remove(loan)
        if remaining:
            self.loans.append(replace(loan,face=remaining,allowance=loan.allowance-release))
        self.record(borrower,'Bank'+loan.lender,value,'private_principal',loan.id)
        self.note('matching_principal_retired',borrower,loan.lender,value,loan.id,allowance_recovery=release)
        self.prepay_uncovered_cb(loan.lender)
        self.refresh_cb(loan.lender)

    def renew(self, loan, quote):
        borrower=loan.borrower
        if isinstance(loan, ProjectLoan):
            raise ValueError('Protected project principal cannot be renewed.')
        _money(quote.face,self.scale)
        if quote.maturity <= self.quarter:
            raise ValueError('Renewal maturity must be a future quarter.')
        loan_type = OperatingLoan if isinstance(loan, OperatingLoan) else Loan
        if loan_type is OperatingLoan and quote.maturity != self.quarter + 2:
            raise ValueError('Operating renewal must preserve two settlement dates.')
        if loan.maturity != self.quarter or loan.last_coupon_paid != self.quarter:
            raise ValueError('Renewal requires the due loan and its fully paid current coupon.')
        bank = loan.lender
        # Retire old risk before testing replacement risk, not old+new gross.
        new_risk = self.risk(bank)-loan.face+quote.face
        # Novation is not evidence that an impaired exposure became healthy.
        # Only a funded principal reduction can force an allowance recovery
        # when the old reserve exceeds the remaining legal face.
        carried_allowance = min(loan.allowance,quote.face)
        released_allowance = loan.allowance-carried_allowance
        closing_equity = self.equity(bank)+released_allowance
        if closing_equity <= 0 or closing_equity < COVENANT*new_risk:
            raise _Failure('credit_constraint','Renewal exceeds replacement capital headroom.',loan.id)
        delta = quote.face-loan.face
        new = loan_type(f'L{self.next_id}',bank,quote.face,quote.rate_pct,quote.maturity,
                   self.quarter,self.quarter,carried_allowance,borrower=borrower,performing=loan.performing)
        if delta < 0:
            if -delta > self.d[borrower]:
                raise _Failure('credit_default','Renewal principal reduction exceeds owned deposits.',loan.id)
            self.reserve_transfer(HOME[borrower],bank,-delta,'renewal_principal',loan.id)
        # Book the signed replacement before its incremental deposit withdrawal.
        # Only the additional face creates a new borrower-owned lender liability.
        self.loans.remove(loan)
        self.loans.append(new)
        if type(self.public_book) is HouseholdLiquidityBook:
            self.trace.append(_household_private_pending(new, loan.id))
        if delta > 0:
            self.transit_deposits[bank] += delta
            self.note('loan_deposit_created',bank,borrower,delta,new.id)
            self.reserve_transfer(bank,HOME[borrower],delta,'renewal_advance',loan.id)
            self.transit_deposits[bank] -= delta
            self.note('loan_deposit_delivered',bank,borrower,delta,new.id)
        self.d[borrower] += delta
        self.next_id += 1
        self.note('renewal_old_retired',bank,borrower,loan.face,loan.id,allowance_released=released_allowance)
        self.note('renewal_new_created',bank,borrower,new.face,new.id,old_id=loan.id,maturity=new.maturity,rate_pct=new.rate_pct)
        if delta:
            self.record('Bank'+bank if delta>0 else borrower,borrower if delta>0 else 'Bank'+bank,
                        abs(delta),'renewal_net_cash',new.id)
        else:
            self.note('renewal_net_cash',bank,borrower,ZERO,new.id)
        self.prepay_uncovered_cb(bank)
        self.refresh_cb(bank)

    def _paydate_snapshot(self):
        book = self.public_book
        last = self.original.last
        previous_income = ((20 * self.scale, F(63, 20) * self.scale) if last is None else
                           tuple(last.disposable_income(h) for h in ('HA', 'HB')))
        previous_dividends = ((None, None) if last is None else
            (last.dividend_residual + last.bank_dividend_to('HA'),
             last.dividend_focal + last.bank_dividend_to('HB')))
        terms = replace(book.terms, annual_treasury=tuple(
            tuple(self.annual_masses[o]) for o in ('CB', *BANKS)))
        return PaydateSnapshot(reserves=tuple(self.r[b] for b in BANKS),
            wallets=tuple(self.d[a] for a in ACTORS), cb_faces=tuple(self.debt(b) for b in BANKS),
            treasuries=tuple(tuple(self.treasuries[o]) for o in ('CB', *BANKS)), terms=terms,
            mortgages=book.mortgages,
            rrp_faces=tuple(sum((c.face for c in self.rrp if c.bank == b), ZERO) for b in BANKS),
            currency=book.currency, capital_other=book.capital_other,
            tga=book.tga, deferred=book.deferred_asset,
            previous_income=previous_income, previous_dividends=previous_dividends)

    def paydate_boundary(self, name):
        """Observe the current sole journal; do not copy it into spendable cash."""
        if not _is_paydate(self.public_book):
            raise ValueError('Paydate boundary requires its explicit book.')
        phase_names = EARLY_PAYDATE_PHASES if _is_early_paydate(self.public_book) else PAYDATE_PHASES
        phase_type = EarlyPhase if _is_early_paydate(self.public_book) else PaydatePhase
        if type(self.public_book) is HouseholdLiquidityBook:
            phase_names, phase_type = HOUSEHOLD_LIQUIDITY_PHASES, HouseholdLiquidityPhase
        if len(self.paydate_phases) >= len(phase_names) or name != phase_names[len(self.paydate_phases)]:
            raise ValueError('Duplicate, missing or reordered fixed paydate phase.')
        snapshot = self._paydate_snapshot()
        self.note('paydate_phase', 'journal', name, payment_end=len(self.payments))
        self.paydate_phases.append(phase_type(name, len(self.payments), len(self.trace), snapshot))
        if name == 'trading_close':
            extra = ({'closing_cb_loans': tuple(self.cb[b] for b in BANKS if b in self.cb),
                       'closing_private_loans': tuple(self.loans), 'later_credit': tuple(self.later_credit)}
                     if _is_early_paydate(self.public_book) else {})
            self.public_book = replace(self.public_book, phases=tuple(self.paydate_phases), **extra)
            self.paydate_stage = 'trading_close'

    def _post_paydate_coupons(self, lines):
        """Actual mandatory cash posting, deliberately without automatic fund()."""
        tga = self.public_book.tga
        def record(payer, payee, value, kind, claim):
            if value < 0:
                payer, payee, value = payee, payer, -value
            self.record(payer, payee, value, kind, claim)
        def bank_cash(bank, value):
            if self.r[bank] + value < 0:
                raise _Failure('funding_failure', 'Public coupon exceeds bank-owned reserves.')
            self.r[bank] += value
        for z in lines:
            value, owner, claim = z.settled, z.owner, z.kind + ':' + z.owner
            if z.kind == 'treasury':
                if tga - value < 0:
                    raise _Failure('funding_failure', 'Treasury coupon exceeds actual TGA funding.')
                tga -= value
                if owner != 'CB':
                    bank_cash(owner, value)
                    self.earnings[owner] += value
                record('Treasury', 'CB' if owner == 'CB' else 'Bank' + owner,
                       value, 'treasury_coupon', 'Treasury:' + owner)
            elif z.kind in ('iorb', 'rrp'):
                bank_cash(owner, value)
                self.earnings[owner] += value
                record('CB', 'Bank' + owner, value, z.kind + '_coupon', claim)
            elif z.kind == 'cb_loan':
                bank_cash(owner, -value)
                self.earnings[owner] -= value
                record('Bank' + owner, 'CB', value, 'cb_loan_coupon', claim)
            else:
                if self.d[owner] - value < 0:
                    raise _Failure('funding_failure', 'Mortgage coupon exceeds owned borrower deposits after actual payroll.')
                bank_cash(HOME[owner], -value)
                self.d[owner] -= value
                record(owner, 'MortgagePool', value, 'mortgage_coupon', claim)
                record('MortgagePool', 'CB', value, 'mbs_coupon', claim)
        self.public_book = replace(self.public_book, tga=tga)

    def settle_early_credit(self):
        """Atomically retire old face, net replacement, then add peak cash only.

        Old pledges are released by novation, not shared with overlapping debt.
        Current equity is measured BEFORE removing old debt/cash repayment.
        """
        if not _is_early_paydate(self.public_book) or self.paydate_stage != 'principal':
            raise _Failure('unsupported_public_income', 'Early credit requires its explicit principal boundary.')
        if any(self.used.values()):
            raise ValueError('Early public credit must precede every current facility use.')
        old_loans = tuple(self.cb[b] for b in BANKS if b in self.cb)
        for old in old_loans:
            if old.start >= self.quarter or old.maturity != self.quarter:
                raise _Failure('funding_failure', 'Early novation requires original due CB cohorts.', old.id)
        try:
            plan = early_liquidity.plan(scale=self.scale,
                reserves=tuple(self.r[b] for b in BANKS), old_faces=tuple(self.debt(b) for b in BANKS),
                equities=tuple(self.equity(b) for b in BANKS),
                capacities=tuple(self.capacity(b) for b in BANKS),
                facility_limits=tuple(self.limits[b] for b in BANKS),
                cb_rates_pct=self.public_book.terms.cb_rates_pct,
                tga=self.public_book.tga, observations=self.paydate_lines)
        except early_liquidity.PlanFailure as error:
            raise _Failure(error.status, str(error)) from error
        # Plan is conditional arithmetic. Recheck actual current constraints and
        # construct exclusive pledges from THIS sole journal, not supplied cash.
        replacements = []
        for i, bank in enumerate(BANKS):
            face = plan.replacement_faces[i]
            if (face > self.limits[bank] - self.used[bank] or face > self.capacity(bank)
                    or (face and self.equity(bank) <= 0)
                    or plan.cash_repayments[i] > self.r[bank]):
                raise _Failure('funding_failure', 'Actual early-credit conditions changed or are unfunded.')
            if face:
                if self.public_book.terms.cb_rates_pct[i] is None:
                    raise _Failure('unsupported_public_income', 'New CB cohort lacks explicit contractual terms.')
                replacements.append(CBLoan(_early_cb_id(self.quarter, bank, self.original.cb_loans), bank, face,
                    self.quarter, self.quarter+1, _pledges(self, bank, face)))
        witness = EarlyCreditWitness(plan, old_loans, tuple(self.loans), tuple(replacements))
        securities = tuple(self.s[b] for b in BANKS)
        # No gross reserve credit for rolled face: only D - (O - F) is cash.
        self.cb = {z.bank:z for z in replacements}
        for i, bank in enumerate(BANKS):
            self.r[bank] = plan.credit_reserves[i]
            self.used[bank] += plan.gross_used[i]
            self.cb_borrowed += plan.gross_used[i]
            self.cb_repaid += plan.old_faces[i]
        self.public_book = replace(self.public_book, early_credit=witness)
        for event in _early_credit_events(witness, self.quarter, securities):
            if type(event) is Payment:
                self.record(event.payer, event.payee, event.amount, event.kind, event.claim_id)
            else:
                self.trace.append(event)
        self.paydate_stage = 'early_credit'
        self.paydate_boundary('early_credit')

    def settle_paydate_public(self, instructions):
        if type(self.public_book) is not PaydatePublicBook:
            raise _Failure('unsupported_public_income', 'Require the exact original paydate convention.')
        return self._settle_paydate_public(instructions)

    def settle_early_paydate_public(self, instructions):
        if type(self.public_book) is not EarlyPaydateBook:
            raise _Failure('unsupported_public_income', 'Require the exact early-paydate convention.')
        return self._settle_paydate_public(instructions)

    def settle_household_liquidity_public(self, instructions):
        if type(self.public_book) is not HouseholdLiquidityBook:
            raise _Failure('unsupported_public_income', 'Require the exact household-liquidity convention.')
        return self._settle_paydate_public(instructions)

    def _settle_paydate_public(self, instructions):
        """Original bases, actual principal and nonhousehold coupons ONLY.

        Payroll/CB operations follow in the actual caller journal. This phase
        neither forecasts their funding nor prematurely marks income complete.
        """
        book, source = self.public_book, self.original
        if not _is_paydate(book) or self.paydate_stage is not None:
            raise _Failure('unsupported_public_income', 'Duplicate or invalid paydate opening phase.')
        if self.quarter != source.quarter + 1 or book.income_paid_through != self.quarter - 1:
            raise _Failure('unsupported_public_income', 'Stale paydate public opening.')
        if not isinstance(instructions, PublicInstructions):
            raise TypeError('Require immutable explicit public instructions.')
        if (any(instructions.currency_to_deposits) or instructions.rrp_request
                or any(instructions.rrp_offers) or instructions.treasury_redemption):
            raise _Failure('unsupported_public_income', 'Paydate currency, new RRP and direct redemption remain unsupported.')
        try:
            opening = FundingOpening(quarter=self.quarter, scale=self.scale, terms=book.terms,
                treasuries=(source.public_book.treasuries, *source.public_book.private_treasuries),
                mortgages=source.public_book.mortgages,
                reserves=tuple(b.reserves for b in source.banks),
                household_deposits=tuple(source.deposit(h) for h in ('HA', 'HB')),
                cb_faces=tuple(source.cb_debt(b) for b in BANKS),
                rrp_faces=tuple(source.rrp_face(b) for b in BANKS),
                tga=source.public_book.tga, deferred=source.public_book.deferred_asset)
            batch = FundingBatch(rolls=instructions.treasury_rolls,
                subscriptions=instructions.treasury_subscriptions,
                subscription_coupon_mass=getattr(instructions, 'subscription_coupon_mass', (None, None)),
                authorization=instructions.treasury_issue_authorization,
                maturity=instructions.replacement_maturity,
                mortgage_repayments=instructions.mortgage_repayments)
            lines = public_income.quote(opening.terms, treasuries=opening.treasuries,
                mortgages=opening.mortgages, reserves=opening.reserves,
                cb_faces=opening.cb_faces, rrp_faces=opening.rrp_faces, scale=self.scale)
        except (TypeError, ValueError) as error:
            raise _Failure('unsupported_public_income', str(error)) from error
        # Only principal has a standalone projection. Income deliberately does
        # NOT call project_income: its delayed payment must use actual wages.
        try:
            projection = public_funding.project_batch(opening, batch)
        except ValueError as error:
            raise _Failure('funding_failure', str(error)) from error
        self.funding_opening, self.funding_batch, self.funding_projection = opening, batch, projection
        self.paydate_lines = lines
        self.transfers = []
        self.paydate_boundary('opening')
        self.paydate_stage = 'principal'
        self.rrp.sort(key=lambda claim: BANKS.index(claim.bank))
        self.close_rrp()
        self.settle_public(instructions, calendar=True)
        self.paydate_boundary('principal')
        if _is_early_paydate(self.public_book):
            self.settle_early_credit()
        self.paydate_stage = 'early_income'
        self._post_paydate_coupons(_paydate_ordered_lines(lines))
        self.paydate_boundary('early_income')
        self.paydate_stage = 'funded_payroll'

    def settle_paydate_households(self, paid_wages):
        if type(self.public_book) is not PaydatePublicBook:
            raise _Failure('unsupported_public_income', 'Require the exact original household calendar.')
        return self._settle_paydate_households(paid_wages)

    def settle_early_paydate_households(self, paid_wages):
        if type(self.public_book) is not EarlyPaydateBook:
            raise _Failure('unsupported_public_income', 'Require the exact early household calendar.')
        return self._settle_paydate_households(paid_wages)

    def settle_household_liquidity_households(self, paid_wages):
        if type(self.public_book) is not HouseholdLiquidityBook:
            raise _Failure('unsupported_public_income', 'Require the exact household-liquidity convention.')
        return self._settle_paydate_households(paid_wages)

    def settle_household_credit(self):
        """Reserve-only draw at ACTUAL funded payroll, inside this one journal."""
        if type(self.public_book) is not HouseholdLiquidityBook or self.paydate_stage != 'funded_payroll':
            raise _Failure('unsupported_public_income', 'Household liquidity requires actual funded payroll.')
        if any(self.transit_deposits.values()):
            raise ValueError('Undelivered private deposits cannot supply household collateral or wages.')
        try:
            plan = early_liquidity.household_plan(scale=self.scale,
                reserves=tuple(self.r[b] for b in BANKS),
                household_deposits=tuple(self.d[h] for h in ('HA', 'HB')),
                cb_faces=tuple(self.debt(b) for b in BANKS),
                equities=tuple(self.equity(b) for b in BANKS),
                capacities=tuple(self.capacity(b) for b in BANKS),
                facility_limits=tuple(self.limits[b] for b in BANKS),
                gross_used=tuple(self.used[b] for b in BANKS),
                cb_rates_pct=self.public_book.terms.cb_rates_pct, observations=self.paydate_lines)
        except early_liquidity.PlanFailure as error:
            raise _Failure(error.status, str(error)) from error
        self.public_book = replace(self.public_book,
            household_credit=HouseholdLiquidityWitness(plan, tuple(self.loans)))
        self.paydate_stage = 'household_credit'
        for bank, amount in zip(BANKS, plan.advances):
            # _draw rechecks live equity/capacity/remaining gross and creates
            # matching current-cohort debt. NO fund(), security sale or HH gift.
            self._draw(bank, amount)
        self.paydate_boundary('household_credit')

    def _settle_paydate_households(self, paid_wages):
        """Post signed mandatory coupons after REAL payroll, then close income."""
        if not _is_paydate(self.public_book) or self.paydate_stage != 'funded_payroll':
            raise _Failure('unsupported_public_income', 'Paydate household coupons require their actual funded-payroll phase.')
        paid_wages = public_funding._vector(paid_wages, 2, 'Actual paid wages')
        self.paydate_boundary('funded_payroll')
        if type(self.public_book) is HouseholdLiquidityBook:
            self.settle_household_credit()
        self.paydate_stage = 'household_income'
        self._post_paydate_coupons(_paydate_ordered_lines(self.paydate_lines, household_phase=True))
        self.paydate_boundary('household_income')
        self.paydate_stage = 'income_close'
        # Interposed trades may have changed face and exact annual rights.
        # Synchronize and close CURRENT book, never the early captured snapshot.
        self.sync_public()
        book = self.public_book
        profit = public_income.cb_profit(self.paydate_lines)
        deferred, remit = public_income.earnings_close(self.funding_opening.deferred, profit)
        self.record('CB', 'Treasury', remit, 'cb_remittance')
        self.public_book = replace(book, tga=book.tga + remit, deferred_asset=deferred,
            opening_deferred_asset=self.funding_opening.deferred,
            income_paid_through=self.quarter, observations=self.paydate_lines,
            paid_wages=paid_wages,
            household_income=tuple(-z.settled for z in self.paydate_lines if z.kind == 'mortgage'))
        for z in self.paydate_lines:
            self.note('public_coupon_observed', z.owner, z.kind, z.settled,
                basis=z.basis, contractual=z.contractual, rounding=z.settled-z.contractual)
        self.note('cb_earnings_closed', 'CB', 'Treasury', profit,
            opening_deferred=self.funding_opening.deferred, deferred=deferred, remittance=remit)
        self.paydate_boundary('income_close')
        self.paydate_stage = 'trading'

    def settle_funded_public(self, instructions):
        """Authorize/project once, then post principal and income in this journal.

        Projections are comparisons only. close_rrp/settle_public and the existing
        coupon handlers alone move actual cash, retire/issue face and report it.
        """
        book = self.public_book
        if _is_paydate(book):
            raise _Failure('unsupported_public_income', 'Paydate books require their separate fixed paid-payroll phases.')
        if not isinstance(book, FundedPublicBook):
            raise _Failure('unsupported_public_income', 'Require explicit funded public books.')
        if (self.funding_opening is not None or self.quarter != self.original.quarter + 1
                or book.income_paid_through != self.quarter - 1):
            raise _Failure('unsupported_public_income', 'Duplicate or stale funded public phase.')
        if not isinstance(instructions, PublicInstructions):
            raise TypeError('Require immutable explicit public instructions.')
        if (any(instructions.currency_to_deposits) or instructions.rrp_request
                or any(instructions.rrp_offers) or instructions.treasury_redemption):
            raise _Failure('unsupported_public_income', 'Funded public currency, new RRP and direct redemption remain unsupported.')
        source = self.original
        try:
            opening = FundingOpening(quarter=self.quarter, scale=self.scale, terms=book.terms,
                treasuries=(source.public_book.treasuries, *source.public_book.private_treasuries),
                mortgages=source.public_book.mortgages,
                reserves=tuple(b.reserves for b in source.banks),
                household_deposits=tuple(source.deposit(h) for h in ('HA', 'HB')),
                cb_faces=tuple(source.cb_debt(b) for b in BANKS),
                rrp_faces=tuple(source.rrp_face(b) for b in BANKS),
                tga=source.public_book.tga, deferred=source.public_book.deferred_asset)
            batch = FundingBatch(rolls=instructions.treasury_rolls,
                subscriptions=instructions.treasury_subscriptions,
                subscription_coupon_mass=getattr(instructions, 'subscription_coupon_mass', (None, None)),
                authorization=instructions.treasury_issue_authorization,
                maturity=instructions.replacement_maturity,
                mortgage_repayments=instructions.mortgage_repayments)
            lines = public_income.quote(opening.terms, treasuries=opening.treasuries,
                mortgages=opening.mortgages, reserves=opening.reserves,
                cb_faces=opening.cb_faces, rrp_faces=opening.rrp_faces, scale=self.scale)
        except (ValueError, TypeError) as error:
            raise _Failure('unsupported_public_income', str(error)) from error
        try:
            projection = public_funding.project_batch(opening, batch)
            prefix = public_funding.project_income(opening, projection, lines)
        except ValueError as error:
            raise _Failure('funding_failure', str(error)) from error
        self.funding_opening, self.funding_batch = opening, batch
        self.funding_projection, self.funding_prefix = projection, prefix
        self.transfers = []
        self.close_rrp()
        self.settle_public(instructions, calendar=True)
        # No private trade/draw is allowed to bridge a public prefix shortfall.
        if ((tuple(tuple(self.treasuries[o]) for o in ('CB', *BANKS)), self.public_book.terms,
             self.public_book.mortgages, tuple(self.r[b] for b in BANKS),
             tuple(self.d[h] for h in ('HA', 'HB')), self.public_book.tga)
                != (projection.treasuries, projection.terms, projection.mortgages,
                    projection.reserves, projection.household_deposits, projection.tga)):
            raise ValueError('Actual funded public principal prefix differs from its projection.')
        actual = tuple((p.payer, p.payee, p.amount, p.kind, p.claim_id)
                       for p in self.payments if p.kind in FUNDED_PUBLIC_PAYMENT_KINDS)
        if Counter(actual) != Counter(projection.payments):
            raise ValueError('Actual funded public principal receipts differ from the batch.')
        self.settle_public_income()

    def settle_public_income(self):
        """One optional atomic income phase; no borrowing to pay these coupons.

        Snapshot opening bases, return due RRP principal, pay Treasury coupons,
        then CB-origin payments and private obligations, and remit last. This
        fixed research order does not establish universal intraday solvency.
        """
        book=self.public_book
        if _is_paydate(book):
            raise _Failure('unsupported_public_income', 'Paydate income cannot use the legacy early-income phase.')
        if not isinstance(book,PublicIncomeBook):
            raise _Failure('unsupported_public_income','Require explicit public-income books.')
        if book.income_paid_through!=self.quarter-1 or self.quarter!=self.original.quarter+1:
            raise _Failure('unsupported_public_income','Duplicate or stale public-income phase.')
        funded=isinstance(book,FundedPublicBook)
        if funded and self.funding_opening is None:
            raise _Failure('unsupported_public_income','Funded income requires its authorized principal phase first.')
        opening=self.original
        try:
            if funded:
                snapshot=self.funding_opening
                lines=public_income.quote(snapshot.terms,treasuries=snapshot.treasuries,
                    mortgages=snapshot.mortgages,reserves=snapshot.reserves,
                    cb_faces=snapshot.cb_faces,rrp_faces=snapshot.rrp_faces,scale=self.scale)
            else:
                lines=public_income.quote(book.terms,
                    treasuries=(opening.public_book.treasuries,*opening.public_book.private_treasuries),
                    mortgages=opening.public_book.mortgages,
                    reserves=tuple(b.reserves for b in opening.banks),
                    cb_faces=tuple(opening.cb_debt(b) for b in BANKS),
                    rrp_faces=tuple(opening.rrp_face(b) for b in BANKS),scale=self.scale)
        except ValueError as error:
            raise _Failure('unsupported_public_income',str(error)) from error
        if not funded:
            self.close_rrp()
        profit=ZERO;tga=book.tga
        def record(payer,payee,value,kind,claim):
            if value<0:payer,payee,value=payee,payer,-value
            self.record(payer,payee,value,kind,claim)
        def bank_cash(bank,value):
            if self.r[bank]+value<0:
                raise _Failure('funding_failure','Public coupon exceeds bank-owned reserves.')
            self.r[bank]+=value
        for line in lines:
            if line.kind!='treasury':continue
            value=line.settled
            if tga-value<0:
                raise _Failure('funding_failure','Treasury coupon exceeds actual TGA funding.')
            tga-=value
            if line.owner=='CB':profit+=value;payee='CB'
            else:
                bank_cash(line.owner,value);self.earnings[line.owner]+=value
                payee='Bank'+line.owner
            record('Treasury',payee,value,'treasury_coupon','Treasury:'+line.owner)
        # Pay CB-origin obligations first. A later private debit can use only
        # reserves/deposits actually received, never an anticipated remittance.
        other=[z for z in lines if z.kind!='treasury']
        def cb_outflow(z):
            return ((z.kind in ('iorb','rrp') and z.settled>0) or
                    (z.kind in ('cb_loan','mortgage') and z.settled<0))
        ordered=[z for z in other if cb_outflow(z)]+[z for z in other if not cb_outflow(z)]
        for line in ordered:
            value=line.settled;owner=line.owner;claim=line.kind+':'+owner
            if line.kind in ('iorb','rrp'):
                bank_cash(owner,value);self.earnings[owner]+=value;profit-=value
                record('CB','Bank'+owner,value,line.kind+'_coupon',claim)
            elif line.kind=='cb_loan':
                bank_cash(owner,-value);self.earnings[owner]-=value;profit+=value
                record('Bank'+owner,'CB',value,'cb_loan_coupon',claim)
            else:
                bank=HOME[owner]
                if self.d[owner]-value<0:
                    raise _Failure('funding_failure','Mortgage coupon exceeds owned borrower deposits.')
                bank_cash(bank,-value);self.d[owner]-=value;profit+=value
                record(owner,'MortgagePool',value,'mortgage_coupon',claim)
                record('MortgagePool','CB',value,'mbs_coupon',claim)
        deferred,remit=public_income.earnings_close(book.deferred_asset,profit)
        tga+=remit
        self.record('CB','Treasury',remit,'cb_remittance')
        # The deferred asset is explicit and cannot fund purchases/collateral.
        self.public_book=replace(book,tga=tga,deferred_asset=deferred,
                                 income_paid_through=self.quarter,observations=lines,
                                 opening_deferred_asset=book.deferred_asset)
        if funded:
            prefix=self.funding_prefix
            if ((tuple(self.r[b] for b in BANKS),tuple(self.d[h] for h in ('HA','HB')),
                 tga,deferred,tuple(self.earnings[b] for b in BANKS)) !=
                    (prefix.reserves,prefix.household_deposits,prefix.tga,prefix.deferred,prefix.earnings)):
                raise ValueError('Actual funded public postincome prefix differs from opening obligations.')
            validate_funded_public(self.public_book,self.scale,self.quarter,self.payments)
        if any(z.settled or z.contractual for z in lines) or book.deferred_asset:
            for z in lines:
                self.note('public_coupon_observed',z.owner,z.kind,z.settled,
                    basis=z.basis,contractual=z.contractual,rounding=z.settled-z.contractual)
            self.note('cb_earnings_closed','CB','Treasury',profit,
                      opening_deferred=book.deferred_asset,deferred=deferred,remittance=remit)

    def sync_public(self):
        if self.public_book is not None:
            extra = {}
            if isinstance(self.public_book, FundedPublicBook):
                extra = dict(terms=replace(self.public_book.terms,
                    annual_treasury=tuple(tuple(self.annual_masses[o]) for o in ('CB', *BANKS))),
                    transfers=tuple(self.transfers))
            self.public_book = replace(
                self.public_book, treasuries=tuple(self.treasuries['CB']),
                private_treasuries=tuple(tuple(self.treasuries[b]) for b in BANKS),
                rrp_claims=tuple(self.rrp), **extra)

    def transfer_treasuries(self, seller, buyer, face):
        """Transfer actual dated par face; bank CB pledges use a fungible pool."""
        if self.treasuries is None:
            return  # Qualified legacy scalar-only private fixture.
        funded=isinstance(self.public_book,FundedPublicBook)
        if face and funded:
            if seller == 'CB':
                raise _Failure('unsupported_public_income','CB secondary Treasury sale has no actual cash handler.')
            if _is_paydate(self.public_book):
                permitted = self.paydate_stage in ('funded_payroll', 'trading')
            else:
                permitted = self.public_book.income_paid_through == self.quarter
            if self.funding_opening is None or not permitted:
                raise _Failure('unsupported_public_income','Funded Treasury trades require the completed current public phase.')
            _money(face,self.scale)
            if face > self.free_securities(seller):
                raise _Failure('funding_failure','Treasury seller lacks actual unencumbered principal.')
            terms=replace(self.public_book.terms,
                annual_treasury=tuple(tuple(self.annual_masses[o]) for o in ('CB',*BANKS)))
            try:
                event,_,new_terms=public_funding.make_transfer(
                    tuple(tuple(self.treasuries[o]) for o in ('CB',*BANKS)),terms,seller,buyer,face)
            except ValueError as error:
                raise _Failure('funding_failure',str(error)) from error
        elif face and isinstance(self.public_book,PublicIncomeBook):
            raise _Failure('unsupported_public_income','Treasury coupon transfer is not implemented.')
        left = face
        for index, available in enumerate(self.treasuries[seller]):
            take = min(left, available)
            if take:
                self.treasuries[seller][index] -= take
                self.treasuries[buyer][index] += take
                left -= take
                self.note('treasury_cohort_transfer', seller, buyer, take,
                          bucket=index, maturity=self.quarter+index+1)
            if not left:
                break
        if left:
            raise _Failure('funding_failure', 'Dated Treasury seller lacks actual owned principal.')
        if face and funded:
            self.annual_masses={o:list(row) for o,row in zip(('CB',*BANKS),new_terms.annual_treasury)}
            self.transfers.append(event)

    def add_treasury(self, owner, face, maturity):
        if not face:
            return
        lower = int(maturity)
        upper_weight = maturity-lower
        if upper_weight:
            low, high = _distribute(face, (1-upper_weight, upper_weight), self.money_quantum)
            self.treasuries[owner][lower-1] += low
            self.treasuries[owner][lower] += high
        else:
            self.treasuries[owner][lower-1] += face

    def close_rrp(self):
        for claim in self.rrp:
            if claim.start >= self.quarter or claim.maturity != self.quarter:
                raise ValueError('Opening RRP claims must be old and mature this quarter.')
            self.r[claim.bank] += claim.face
            self.record('CB', claim.bank, claim.face, 'rrp_principal_repaid')
            self.note('rrp_old_retired', claim.bank, 'CB', claim.face,
                      start=claim.start, maturity=claim.maturity)
        self.rrp.clear()

    def new_rrp(self, instructions):
        if isinstance(self.public_book,FundedPublicBook) and (instructions.rrp_request or any(instructions.rrp_offers)):
            raise _Failure('unsupported_public_income','New funded public RRP contracts are not implemented.')
        left = instructions.rrp_request
        # One eligible pool across banks: bucket zero is due next quarter.
        available = self.treasuries['CB'].copy()
        available[0] = ZERO
        for claim in self.rrp:
            for index, face in claim.collateral:
                available[index] -= face
        for bank, offer in zip(BANKS, instructions.rrp_offers):
            value = _floor(min(left, offer, self.r[bank], sum(available)), self.money_quantum)
            self.note('rrp_offer', bank, 'CB', offer, requested=left,
                      reserves=self.r[bank], eligible_collateral=sum(available))
            if not value:
                continue
            collateral = []
            remaining = value
            for index in range(1, 120):
                take = min(remaining, available[index])
                if take:
                    collateral.append((index, take))
                    available[index] -= take
                    remaining -= take
                if not remaining:
                    break
            claim = RRPClaim(bank, value, self.quarter, self.quarter+1, tuple(collateral))
            self.rrp.append(claim)
            self.r[bank] -= value
            left -= value
            self.record(bank, 'CB', value, 'rrp_principal_advanced')
            self.note('rrp_new_created', bank, 'CB', value,
                      start=claim.start, maturity=claim.maturity)
            for index, face in collateral:
                self.note('rrp_collateral_pledged', 'CB', bank, face, bucket=index)
        self.note('rrp_unfilled', 'CB', 'banks', left)

    def settle_public(self, instructions, calendar=False):
        book = self.public_book
        if book is None:
            raise ValueError('Public instructions require identified opening public accounts.')
        income=isinstance(book,PublicIncomeBook)
        funded=isinstance(book,FundedPublicBook)
        old_masses=book.terms.annual_treasury if income else None
        if funded:
            if not calendar or self.funding_opening is None or book.income_paid_through != self.quarter-1:
                raise _Failure('unsupported_public_income','Funded public settlement requires its current authorized quarterly phase.')
            if (any(instructions.currency_to_deposits) or instructions.rrp_request
                    or any(instructions.rrp_offers) or instructions.treasury_redemption):
                raise _Failure('unsupported_public_income','Funded public currency, new RRP and direct settlement remain unsupported.')
        elif income:
            due=tuple(self.treasuries[o][0] for o in ('CB',*BANKS))
            if (any(instructions.currency_to_deposits) or any(instructions.mortgage_repayments)
                    or any(instructions.treasury_subscriptions) or instructions.treasury_redemption
                    or instructions.rrp_request or any(instructions.rrp_offers)
                    or (calendar and instructions.treasury_rolls!=due)
                    or (not calendar and any(instructions.treasury_rolls))):
                raise _Failure('unsupported_public_income','Income program requires stationary same-face Treasury rolls and no new quantity operations.')
        if calendar:
            if instructions.treasury_redemption:
                raise ValueError('Quarter steps automatically settle full due principal; use explicit rolls.')
        elif (any(instructions.treasury_rolls) or instructions.rrp_request
              or any(instructions.rrp_offers)):
            raise ValueError('Direct public settlement does not support Treasury rolls or RRP instructions.')
        for value in (*instructions.currency_to_deposits, *instructions.mortgage_repayments,
                      *instructions.treasury_subscriptions, *instructions.treasury_rolls,
                      *instructions.rrp_offers, instructions.rrp_request,
                      instructions.treasury_issue_authorization, instructions.treasury_redemption):
            _money(abs(value), self.scale)
        currency = list(book.currency); mortgages = list(book.mortgages)
        for i, (owner, bank) in enumerate((('HA','A'), ('HB','B'))):
            conversion = instructions.currency_to_deposits[i]
            if conversion > currency[i] or -conversion > self.d[owner]:
                raise _Failure('funding_failure', 'Currency conversion exceeds actual owner funds.')
            if self.r[bank]+conversion < 0:
                raise _Failure('funding_failure', 'Currency withdrawal exceeds bank-owned reserves.')
            currency[i] -= conversion; self.d[owner] += conversion; self.r[bank] += conversion
            self.note('owned_currency_conversion', owner, bank, conversion)
            payment = instructions.mortgage_repayments[i]
            if payment > mortgages[i] or payment > self.d[owner] or payment > self.r[bank]:
                raise _Failure('funding_failure', 'Mortgage principal exceeds owned borrower funds, bank reserves or legal debt.')
            self.d[owner] -= payment; self.r[bank] -= payment; mortgages[i] -= payment
            self.public -= payment
            self.record(owner, 'MortgagePool', payment, 'household_mortgage_principal')
            self.record('MortgagePool', 'CB', payment, 'pass_through_mbs_principal')
        subscriptions = instructions.treasury_subscriptions
        rolls = instructions.treasury_rolls
        if sum(subscriptions)+sum(rolls) > instructions.treasury_issue_authorization:
            raise _Failure('funding_failure', 'Treasury new and rolled principal exceed explicit issuer authorization.')
        owners = ('CB', *BANKS)
        dues = (tuple(self.treasuries[o][0] for o in owners) if calendar
                else (instructions.treasury_redemption, ZERO, ZERO))
        if not calendar and dues[0] > self.treasuries['CB'][0]:
            raise _Failure('funding_failure', 'Treasury redemption exceeds due held principal.')
        if any(roll > due for roll, due in zip(rolls, dues)):
            raise _Failure('funding_failure', 'Treasury roll exceeds the consenting holder due principal.')
        unrolled = tuple(due-roll for due, roll in zip(dues, rolls))
        closing_tga = book.tga+sum(subscriptions)-sum(unrolled)
        closing_reserves = tuple(self.r[b]+due-sub for b, due, sub in zip(BANKS, unrolled[1:], subscriptions))
        if closing_tga < 0 or any(r < 0 for r in closing_reserves):
            raise _Failure('funding_failure', 'Treasury settlement lacks actual holder reserves or TGA funding.')
        # Retire full due and issue replacements only with holder and issuer consent.
        for owner, due, roll in zip(owners, dues, rolls):
            if calendar:
                self.treasuries[owner] = self.treasuries[owner][1:]+[ZERO]
            else:
                self.treasuries[owner][0] -= due
            self.add_treasury(owner, roll, instructions.replacement_maturity)
            self.note('treasury_old_retired', owner, 'Treasury', due)
            self.note('treasury_rolled', owner, 'Treasury', roll)
            self.note('treasury_new_issued', 'Treasury', owner, roll, rolled=True)
        self.public -= unrolled[0]
        self.gov_face += sum(rolls)+sum(subscriptions)-sum(dues)
        # Actual net settlement only: no fictitious gross cash for rolled face.
        self.record('Treasury', 'CB', unrolled[0], 'tga_funded_treasury_redemption')
        for bank, due, sub, reserve in zip(BANKS, unrolled[1:], subscriptions, closing_reserves):
            self.r[bank] = reserve
            self.s[bank] += sub-due
            self.add_treasury(bank, sub, instructions.replacement_maturity)
            self.note('treasury_new_issued', 'Treasury', bank, sub, rolled=False)
            net = due-sub
            self.note('treasury_net_settlement', 'Treasury', bank, net)
            self.record('Treasury' if net >= 0 else bank, bank if net >= 0 else 'Treasury',
                        abs(net), 'treasury_net_cash')
        updates = dict(mbs=sum(mortgages), mortgages=tuple(mortgages),
                       currency=tuple(currency), tga=closing_tga)
        if income and calendar:
            rows=[]
            for i,(masses,due,roll) in enumerate(zip(old_masses,dues,rolls)):
                row=list(masses[1:])+[ZERO]
                # Use exactly the same principal rounding/allocation as add_treasury.
                maturity=instructions.replacement_maturity;lower=int(maturity)
                upper=maturity-lower
                low,high=(_distribute(roll,(1-upper,upper),self.money_quantum)
                          if upper else (roll,ZERO))
                if due:
                    row[lower-1]+=masses[0]*low/due
                    if high:row[lower]+=masses[0]*high/due
                if funded and i:
                    sub=subscriptions[i-1]
                    mass=self.funding_batch.subscription_coupon_mass[i-1]
                    if sub:
                        low,high=(_distribute(sub,(1-upper,upper),self.money_quantum)
                                  if upper else (sub,ZERO))
                        row[lower-1]+=mass*low/sub
                        if high:row[lower]+=mass*high/sub
                rows.append(tuple(row))
            updates.update(
                treasuries=tuple(self.treasuries['CB']),
                private_treasuries=tuple(tuple(self.treasuries[b]) for b in BANKS),
                rrp_claims=tuple(self.rrp),
                terms=replace(book.terms,annual_treasury=tuple(rows)))
            if funded:
                self.annual_masses={o:list(row) for o,row in zip(owners,rows)}
                updates.update(opening=self.funding_opening,funding=self.funding_batch,
                               transfers=tuple(self.transfers))
        # Faces and their annual rights must change together: no orphan-mass
        # intermediate dataclass when a due holding is fully retired.
        self.public_book=replace(book,**updates)

    def qe(self, request, offers):
        if (isinstance(self.public_book,PublicIncomeBook)
                and not isinstance(self.public_book,FundedPublicBook) and (request or any(offers))):
            raise _Failure('unsupported_public_income','QE coupon transfer is not implemented.')
        left = request
        for bank, offer in zip(BANKS,offers):
            value = _floor(min(left,offer,self.free_securities(bank)),self.money_quantum)
            self.note('public_purchase_offer',bank,'CB',offer,'Treasury:'+bank,
                      unencumbered=self.free_securities(bank),requested=left)
            if value:
                self.transfer_treasuries(bank, 'CB', value)
                self.s[bank] -= value
                self.public += value
                self.r[bank] += value
                self.qe_applied += value
                left -= value
                self.record('CB',bank,value,'public_par_purchase','Treasury:'+bank)
                self.refresh_cb(bank)
        self.note('public_purchase_unfilled','CB','banks',left,
                  reason='No additional offered unencumbered existing public face.' if left else 'Request filled.')

    def cb_maturities(self):
        for bank in BANKS:
            old = self.cb.get(bank)
            if old is None:
                continue
            if (_is_early_paydate(self.public_book)
                    and old.start == self.quarter and old.maturity == self.quarter + 1):
                continue  # Original maturity was atomically retired in early_credit.
            if old.maturity != self.quarter:
                raise ValueError('Opening CB principal must mature this quarter.')
            # Same-counterparty novation: retire old debt and net the offered
            # replacement against it. No fictitious gross reserve circulation.
            refi = _floor(min(old.face,self.limits[bank],self.capacity(bank)),self.money_quantum)
            if self.equity(bank) <= 0:
                refi = ZERO
            if (refi and isinstance(self.public_book,PublicIncomeBook)
                    and self.public_book.terms.cb_rates_pct[_bank(bank)] is None):
                raise _Failure('unsupported_public_income','CB refinancing lacks explicit coupon terms.')
            residual = old.face-refi
            # Mark old retired and refi pledged before asset funding, so only
            # genuinely unencumbered inventory can be sold for the cash leg.
            del self.cb[bank]
            if refi:
                self.cb[bank] = CBLoan(f'CB{self.quarter}:{bank}',bank,refi,self.quarter,self.quarter+1,
                                      _pledges(self,bank,refi))
                self.used[bank] += refi
                self.cb_borrowed += refi
            # Pro forma removal of principal reduces assets and liabilities
            # equally. Reserve balance is checked before the net cash debit.
            if residual > self.r[bank]:
                # Equity during netting must exclude principal yet to debit.
                # A temporary reserve debit is not permitted; use an explicit
                # pro-forma adjustment for the asset-sale solvency check.
                seller_eq = self.equity(bank)-residual
                buyer = 'B' if bank=='A' else 'A'
                if seller_eq>0 and self.equity(buyer)>0:
                    value = _floor(min(residual-self.r[bank],self.bids[buyer],
                                       self.r[buyer],self.free_securities(bank)),self.money_quantum)
                    if value:
                        self.transfer_treasuries(bank, buyer, value)
                        self.s[bank] -= value; self.s[buyer] += value
                        self.r[bank] += value; self.r[buyer] -= value
                        self.bids[buyer] -= value
                        self.record(buyer,bank,value,'private_public_par_trade','Treasury:'+bank)
                        self.note('public_face_transfer',bank,buyer,value,'Treasury:'+bank)
            if residual > self.r[bank]:
                raise _Failure('funding_failure','Maturing CB principal has no funded repayment/refinance offer.',old.id)
            self.r[bank] -= residual
            self.cb_repaid += old.face
            self.note('cb_principal_retired',bank,'CB',old.face,old.id,
                      net_cash_repaid=residual,refinanced=refi)
            self.record(bank,'CB',residual,'cb_cash_repayment',old.id)
            if refi:
                self.note('cb_refinance',bank,'CB',refi,self.cb[bank].id,old_id=old.id)
                self.note('facility_applied',bank,'CB',refi,self.cb[bank].id,
                          offered=self.limits[bank],gross_applied=self.used[bank],capacity=self.capacity(bank))
                for position in self.cb[bank].collateral:
                    self.note('collateral_pledged',bank,'CB',position.face,position.claim_id,kind_of_asset=position.kind)
            self.refresh_cb(bank)

    def finish(self, **changes):
        if any(self.transit_deposits.values()):
            raise ValueError('Undelivered borrower deposits cannot escape a transaction.')
        for bank in BANKS:
            self.refresh_cb(bank)
        self.sync_public()
        if isinstance(self.public_book,FundedPublicBook):
            report=changes.get('last')
            if _is_paydate(self.public_book):
                if self.paydate_stage != 'trading_close':
                    raise ValueError('Paydate journal cannot finish an incomplete mandatory/payment calendar.')
                _validate_paydate_book(self.public_book, self.scale, self.quarter,
                    None if report is None else report.payments,
                    None if report is None else report.trace)
            else:
                validate_funded_public(self.public_book,self.scale,self.quarter,
                                      None if report is None else report.payments)
        banks = tuple(Bank(b,self.r[b],self.s[b],
                           tuple(self.d[a] for a in (('R','HA') if b=='A' else ('F','HB')))) for b in BANKS)
        return replace(self.original,quarter=self.quarter,banks=banks,loans=tuple(self.loans),
                       cb_loans=tuple(self.cb[b] for b in BANKS if b in self.cb),
                       public_securities=self.public,next_private_id=self.next_id,
                       public_book=self.public_book,gov_debt_face=self.gov_face,**changes)


def _admit_early_state(state, *inputs):
    records = (SectorState, Bank, Loan, OperatingLoan, ProjectLoan, CBLoan, Collateral,
        Vintage, PublicBook, PublicIncomeBook, FundedPublicBook, PaydatePublicBook,
        PaydatePhase, EarlyPaydateBook, EarlyPhase, EarlyCreditWitness, LaterCreditWitness,
        HouseholdLiquidityBook, HouseholdLiquidityPhase, HouseholdLiquidityWitness,
        early_liquidity.EarlyPlan, early_liquidity.HouseholdLiquidityPlan,
        PaydateSnapshot, PublicIncomeTerms, CouponLine,
        FundingOpening, FundingBatch, TreasuryTransfer, RRPClaim, Report, Payment, Trace,
        Controls, PublicIncomeControls, PublicInstructions, FundedPublicInstructions,
        ProductionOrders, household.Preferences, LoanOffer, OperatingLoanOffer,
        Renewal, ProjectCommitment, ClosingCreditForecast)
    public_funding.validate_records((state, *inputs), records)
    if type(state) is not SectorState:
        raise TypeError('Require the exact canonical early SectorState.')
    for collection, allowed in ((state.banks, (Bank,)),
            (state.loans, (Loan, OperatingLoan, ProjectLoan)),
            (state.cb_loans, (CBLoan,)), (state.vintages, (Vintage,))):
        if type(collection) is not tuple:
            raise TypeError('Require exact immutable actual sector collections.')
        for record in collection:
            if not any(type(record) is cls for cls in allowed):
                raise TypeError('Require exact known actual sector claim/balance records.')
            if type(record) is CBLoan:
                for pledge in record.collateral:
                    if type(pledge) is not Collateral:
                        raise TypeError('Require exact identified CB collateral.')
                    replace(pledge)
            replace(record)
    if state.public_book is not None:
        if isinstance(state.public_book, PublicIncomeBook):
            replace(state.public_book.terms)
        for claim in state.public_book.rrp_claims:
            replace(claim)
        replace(state.public_book)


def _state(state):
    if not isinstance(state,SectorState):
        raise TypeError('Require the coherent immutable SectorState.')


def _find(state, loan_id):
    if type(loan_id) is not str:
        raise TypeError('Loan identity must be text.')
    for loan in state.loans:
        if loan.id == loan_id:
            return loan
    raise ValueError('Unknown active private loan: '+loan_id)


def _helper_finish(tx):
    try:
        return tx.finish()
    except _Failure as error:
        raise ValueError(error.reason) from error


def settle_public(state,instructions):
    _state(state)
    if not isinstance(instructions,PublicInstructions):
        raise TypeError('Require explicit immutable public instructions.')
    tx=_Transaction(state,Controls(),state.quarter)
    try:
        tx.settle_public(instructions)
        return tx.finish()
    except _Failure as error:
        raise ValueError(error.reason) from error


def originate(state, offer):
    _state(state)
    if not isinstance(offer,LoanOffer):
        raise TypeError('Origination requires an explicit LoanOffer.')
    tx = _Transaction(state,Controls(security_bids=(0,0)),state.quarter)
    try:
        tx.originate(offer)
    except _Failure as error:
        raise ValueError(error.reason) from error
    return _helper_finish(tx)


def repay(state, loan_id, amount):
    _state(state)
    loan = _find(state,loan_id)
    value = _money(amount,state.scale)
    if not value:
        return state
    tx = _Transaction(state,Controls(security_bids=(0,0)),state.quarter)
    try:
        tx.principal(loan,value)
    except _Failure as error:
        raise ValueError(error.reason) from error
    return _helper_finish(tx)


def provision(state, loan_id, amount):
    """Add a noncash allowance, never reduce the matching legal borrower debt."""
    _state(state)
    loan = _find(state,loan_id)
    value = _money(amount,state.scale)
    if loan.allowance+value > loan.face:
        raise ValueError('Provision exceeds remaining unprovided legal face.')
    tx = _Transaction(state,Controls(security_bids=(0,0)),state.quarter)
    tx.loans[tx.loans.index(loan)] = replace(loan,allowance=loan.allowance+value)
    return _helper_finish(tx)


def discharge(state, loan_id, amount, release_allowance=0):
    """Legal forgiveness is distinct from provisioning or principal payment."""
    _state(state)
    loan = _find(state,loan_id)
    value, release = _money(amount,state.scale), _money(release_allowance,state.scale)
    if value>loan.face or release>min(value,loan.allowance):
        raise ValueError('Discharge/release exceeds the identified legal face/allowance.')
    remaining, allowance = loan.face-value,loan.allowance-release
    if allowance>remaining:
        raise ValueError('Remaining allowance exceeds remaining legal face; specify its release.')
    if not value:
        return state
    tx = _Transaction(state,Controls(security_bids=(0,0)),state.quarter)
    tx.loans.remove(loan)
    if remaining:
        tx.loans.append(replace(loan,face=remaining,allowance=allowance))
    return _helper_finish(tx)


def step(state, controls=Controls(), orders=None):
    return advance_given_orders(state, _DEFAULT_ORDERS if orders is None else orders, controls)


def _closing_credit_floor(tx, controls, bank):
    """Quote from actual post-firm-payout cash, before paying bank income."""
    risk = tx.risk(bank)
    floor = _dividend_capital_floor(controls, bank, risk)
    forecast = controls.closing_credit_forecast
    if forecast is None:
        return floor
    index = _bank(bank)
    borrower = ('R', 'F')[index]
    cash = tx.d[borrower]
    payroll = forecast.payroll_nominal[index]
    # Each quoted sufficient-cash request rounds UP on the nominal money grid.
    wage_request = -((-max(ZERO, payroll - cash)) // tx.money_quantum) * tx.money_quantum
    project = forecast.project_gross_nominal[index]
    project_request = -((-project) // tx.money_quantum) * tx.money_quantum
    gross = wage_request + project_request
    target = max(floor, COVENANT * (risk + gross))
    tx.note('closing_credit_quote', bank, borrower, target,
            firm_cash=cash, forecast_payroll=payroll, closing_risk=risk,
            wage_request=wage_request, project_request=project_request,
            gross_request=gross, target=target,
            unfunded_target=max(ZERO, target - tx.equity(bank)),
            status='conditional_quote_not_approval')
    return target


def _previous_credit_quotes(last):
    """Admit diagnostic metadata explicitly; never accept last-write-wins."""
    quotes = {}
    if last is None:
        return quotes
    for note in last.trace:
        if note.kind != 'closing_credit_quote':
            continue
        bank = note.actor
        index = _bank(bank)
        if bank in quotes or note.counterparty != ('R', 'F')[index]:
            raise ValueError('Duplicate or misidentified closing credit quote.')
        data = dict(note.details)
        if len(data) != len(note.details) or not {'forecast_payroll', 'gross_request'} <= data.keys():
            raise ValueError('Missing or duplicate closing credit metadata.')
        _number(data['forecast_payroll'])
        _number(data['gross_request'])
        quotes[bank] = data
    return quotes


def _closing_household_plans(tx, orders, controls, wage, lr, lf):
    """Version-1 research behavior: freeze owned budgets after actual payroll.

    Income seeds and target ratios are authored reference conventions, not cash
    grants or inferred history. Later income comes from the last paid report.
    This does not implement endogenous hiring, investment or a macro adapter.
    """
    last = tx.original.last
    if orders.expected_dividends_nominal is not None:
        forecasts = orders.expected_dividends_nominal
        source = 'explicit_forecast'
    elif last is None:
        forecasts = tuple(x * tx.scale for x in orders.initial_dividends_real)
        source = 'initial_reference'
    else:
        forecasts = (last.dividend_residual + last.bank_dividend_to('HA'),
                     last.dividend_focal + last.bank_dividend_to('HB'))
        source = 'last_paid_dividends'
    previous = ((20 * tx.scale, F(63, 20) * tx.scale) if last is None else
                tuple(last.disposable_income(owner) for owner in ('HA','HB'))
                if isinstance(tx.public_book,PublicIncomeBook) else
                (last.payroll_residual+last.dividend_residual+last.bank_dividend_to('HA'),
                 last.payroll_focal+last.dividend_focal+last.bank_dividend_to('HB')))
    unit = tx.scale * orders.price_factor
    previous_quotes = _previous_credit_quotes(last)
    plans = []
    for owner, prefs, wages, prior, forecast, ratio in zip(
            ('HA', 'HB'), (orders.preferences_a, orders.preferences_b),
            (lr * wage, lf * wage), previous, forecasts, (F(3, 20), F(1, 21))):
        opening = tx.d[owner] - wages  # Legacy net pre-payroll wallet convention.
        income_enabled=isinstance(tx.public_book,PublicIncomeBook)
        current_public=(sum((p.amount*((p.payee==owner)-(p.payer==owner))
                            for p in tx.payments if p.kind=='mortgage_coupon'),ZERO)
                        if income_enabled else ZERO)
        paydate = _is_paydate(tx.public_book)
        extra = {}
        if paydate:
            from .paydate_households import cash_stock_budget as budget
            # Principal repayments are already settled. Keep this actual
            # pre-payroll cash distinct from D+I, which may be negative.
            opening = tx.paydate_phases[3 if _is_early_paydate(tx.public_book) else 2].snapshot.wallets[ACTORS.index(owner)]
            extra = dict(settled_income=current_public)
        else:
            budget=(household.net_cash_stock_budget if income_enabled else household.cash_stock_budget)
        quote = budget(
            opening_cash=opening, paid_wages=wages, previous_income=prior,
            forecast_income=wages + forecast+current_public, cash_ratio=ratio,
            demand_multiplier=orders.demand_multiplier, **extra)
        if paydate and quote.wallet != tx.d[owner]:
            raise ValueError('Paydate household budget differs from the actually settled wallet.')
        goods = prefs.residual + prefs.services
        plans.append((quote.funded * prefs.residual / goods / unit,
                      quote.funded * prefs.services / goods / unit)
                     if goods else (ZERO, ZERO))
        tx.note('household_budget', owner, 'goods', quote.wallet,
                mode='cash_stock_close_v1', opening_cash=opening, paid_wages=wages,
                income_previous=prior, income_forecast=wages + forecast+current_public,
                forecast=forecast, forecast_source=source, cash_ratio=ratio,
                adjustment=F(1, 4), desired=quote.desired, funded=quote.funded,
                **extra,
                **({'demand_multiplier':orders.demand_multiplier}
                   if orders.demand_multiplier != 1 else {}))
        bank, borrower = ('A', 'R') if owner == 'HA' else ('B', 'F')
        if bank in previous_quotes:
            old = previous_quotes[bank]
            offered = sum((o.face for o in controls.new_loans
                           if o.lender == bank and o.borrower == borrower), ZERO)
            tx.note('closing_credit_forecast_observed', bank, borrower,
                    wages - old['forecast_payroll'],
                    forecast_quarter=tx.quarter - 1,
                    payroll_forecast=old['forecast_payroll'], payroll_paid=wages,
                    payroll_error=wages - old['forecast_payroll'],
                    gross_request_forecast=old['gross_request'], gross_new_offered=offered,
                    offer_error=offered - old['gross_request'])
    (cr, sa), (_, sb) = plans
    return cr, sa, sb


def _project_faces(draw, scale):
    return _distribute(draw, (F(1),) * 16, scale * QUANTUM)


def _minimum_project_draw(cash, invoice, buffer, ceiling, rate, scale):
    """First sufficient integer-money draw; forecast math, not credit approval.

    Bound the search by the actual integer ceiling's bit length, not a false
    fixed 64 probes on Python's unbounded integer domain. Private coupons of
    400% or more cannot add current net funding; this does not cap policy rates.
    """
    cash, invoice, buffer, ceiling, scale = map(_number, (cash, invoice, buffer, ceiling, scale))
    rate = _number(rate, signed=True)
    if not scale:
        raise ValueError('Project monetary scale must be positive.')
    ceiling = _money(ceiling, scale)
    if cash >= invoice + buffer:
        return ZERO, 0
    if not ceiling or rate >= 400:
        return None, 0
    quantum = scale * QUANTUM
    def enough(ticks):
        draw = ticks * quantum
        coupon = sum((precision.coupon(face, rate, scale, QUANTUM)[1]
                      for face in _project_faces(draw, scale)), ZERO)
        return cash + draw - coupon >= invoice + buffer
    high = int(ceiling / quantum)
    if not enough(high):
        return None, 1
    low, probes = 1, 1
    while low < high:
        middle = (low + high) // 2
        probes += 1
        if enough(middle):
            high = middle
        else:
            low = middle + 1
    return low * quantum, probes


def _reserve_project(tx, controls):
    plan = controls.project_commitment
    if plan is None:
        return None
    ceiling = _money(plan.face_ceiling, tx.scale)
    offered = sum((o.face for o in controls.new_loans if o.lender == plan.lender), ZERO)
    risk, equity = tx.risk(plan.lender), tx.equity(plan.lender)
    approved = not ceiling or (equity > 0 and equity >= COVENANT * (risk + offered + ceiling))
    limit = ceiling if approved else ZERO
    tx.note('project_reservation', plan.lender, 'F', limit, requested=ceiling,
            approved=approved, opening_risk=risk, gross_new_offers=offered,
            opening_equity=equity, required_equity=COVENANT * (risk + offered + ceiling))
    return limit


def _stage_project(tx, plan, draw, invoice, buffer):
    """Preflight current owned cash and atomic delivery on a private journal.

    No later SectorState is fabricated. The immutable predecessor remains the
    same object; every mutable journal container is copied. Failed trials never
    alter the live journal, including private IDs and actual background flows.
    """
    stage = copy.deepcopy(tx, {id(tx.original): tx.original})
    coupon = ZERO
    if draw:
        bank = plan.lender
        if stage.equity(bank) <= 0 or stage.equity(bank) < COVENANT * (stage.risk(bank) + draw):
            raise _Failure('credit_constraint', 'Project draw exceeds actual current capital headroom.')
        ids = []
        for h, face in enumerate(_project_faces(draw, tx.scale), 1):
            if face:
                ids.append(stage.originate(LoanOffer(bank, face, plan.rate_pct,
                           tx.quarter + h, borrower='F'), at_open=True, _project=True))
        for loan_id in ids:
            coupon += stage.coupon(next(z for z in stage.loans if z.id == loan_id))
    stage.pay('F', 'R', invoice, 'investment')
    if stage.d['F'] < buffer:
        raise ValueError('Project solver/delivery mismatch: actual payroll buffer is unfunded.')
    if any(stage.equity(b) < 0 for b in BANKS):
        raise _Failure('credit_default', 'Signed project settlement leaves an insolvent bank.')
    stage.note('project_draw_settled', plan.lender, 'F', draw,
               invoice=invoice, coupon=coupon, retained_cash=stage.d['F'])
    if stage.original is not tx.original or set(stage.__dict__) != set(tx.__dict__):
        raise ValueError('Project journal ownership mismatch.')
    tx.__dict__.update(stage.__dict__)
    return coupon


def _clear_market(tx, orders, controls, vintages, capital, depreciation, lr, lf,
                  project_ceiling=None):
    """Bounded chronological clearing of frozen orders with actual owned cash.

    This is a fixed-price trading program, not a GE or household-optimality
    claim. The caller owns the single report/finish and atomic failure boundary.
    """
    unit = tx.scale * orders.price_factor
    wage = unit * orders.real_wage
    chi = orders.capital_resource_cost
    renewals = {r.loan_id: r for r in controls.renewals}
    closing = controls.household_mode == 'cash_stock_close_v1'
    if closing:
        desired_cr, desired_sa, desired_sb = _closing_household_plans(tx, orders, controls, wage, lr, lf)
    elif controls.household_mode == 'fixed':
        desired_cr, desired_sa, desired_sb = (orders.residual_consumption,
                                              orders.service_a, orders.service_b)
    else:
        if orders.expected_dividends_nominal is not None:
            forecasts = orders.expected_dividends_nominal
            source = 'explicit_forecast'
        elif tx.original.last is None:
            forecasts = tuple(x * tx.scale for x in orders.initial_dividends_real)
            source = 'initial_reference'
        else:
            last = tx.original.last
            forecasts = (last.dividend_residual + last.bank_dividend_to('HA'),
                         last.dividend_focal + last.bank_dividend_to('HB'))
            source = 'last_paid_dividends'
        plans = []
        for owner, prefs, forecast in zip(('HA', 'HB'),
                (orders.preferences_a, orders.preferences_b), forecasts):
            budget = tx.d[owner] / unit
            goods = prefs.residual + prefs.services
            # Forecast is the current unpaid distribution, never a deposit.
            # Unlike allocate(), do NOT clip the one frozen plan to cash here.
            spend = (budget if controls.household_mode == 'wallet' else
                     goods * (budget + forecast / unit) / (goods + prefs.cash))
            plans.append((spend * prefs.residual / goods,
                          spend * prefs.services / goods) if goods else (ZERO, ZERO))
            tx.note('household_budget', owner, 'goods', tx.d[owner],
                    forecast=forecast, forecast_source=source)
        (desired_cr, desired_sa), (_, desired_sb) = plans

    cr = sa = sb = physical_i = ZERO
    interest = dict.fromkeys(('R', 'F'), ZERO)
    accrued = dict.fromkeys(('R', 'F'), ZERO)
    negative_paid = dict.fromkeys(('R', 'F'), ZERO)
    distributed = dict.fromkeys(('R', 'F'), ZERO)
    bank_paid = dict.fromkeys(BANKS, ZERO)
    service_capacity = min(capital * orders.capital_productivity,
                           lf * orders.service_productivity)
    resource_capacity = lr * orders.residual_productivity
    installed_basis = sum((v.net_book for v in vintages), ZERO)

    def coupon_due(loan):
        return loan.start != tx.quarter and loan.last_coupon_paid != tx.quarter

    for loan in tx.loans:
        if coupon_due(loan):
            if loan.last_coupon_paid != tx.quarter - 1:
                raise _Failure('credit_default',
                               'Unpaid opening coupon cannot be erased by refinancing.', loan.id)
            accrued[loan.borrower] += max(ZERO, precision.coupon(
                loan.face, loan.rate_pct, tx.scale, QUANTUM)[1])

    def commitments(borrower):
        """Cash legally due, not gross face of a same-face consenting roll."""
        pending = ZERO
        for loan in tx.loans:
            if loan.borrower != borrower:
                continue
            if coupon_due(loan):
                pending += max(ZERO, precision.coupon(
                    loan.face, loan.rate_pct, tx.scale, QUANTUM)[1])
            if loan.maturity <= tx.quarter:
                quote = renewals.get(loan.id)
                pending += max(ZERO, loan.face - quote.face) if quote else loan.face
        return pending

    def debt_pending(borrower):
        return any(l.borrower == borrower and
                   (coupon_due(l) or l.maturity <= tx.quarter) for l in tx.loans)

    def settle_debt_pass(borrower):
        changed = False
        for loan in tuple(tx.loans):
            if loan.borrower != borrower:
                continue
            if loan.maturity < tx.quarter:
                raise _Failure('credit_default',
                               'Overdue private maturity cannot be silently extended.', loan.id)
            if coupon_due(loan):
                due = precision.coupon(loan.face, loan.rate_pct, tx.scale, QUANTUM)[1]
                if due > tx.d[borrower]:
                    continue  # Only borrower cash shortage may wait for actual sales.
                paid_coupon = tx.coupon(loan)
                interest[borrower] += paid_coupon
                negative_paid[borrower] += min(ZERO, paid_coupon)
                changed = True
                loan = next(l for l in tx.loans if l.id == loan.id)
            if loan.maturity == tx.quarter:
                quote = renewals.get(loan.id)
                cash_due = max(ZERO, loan.face - quote.face) if quote else loan.face
                if cash_due > tx.d[borrower]:
                    continue
                # Reserve, collateral and capital failures escape immediately:
                # no partially mutated financial transaction is ever continued.
                if quote:
                    tx.renew(loan, quote)
                else:
                    tx.principal(loan, loan.face)
                changed = True
        return changed

    def settle_debt(borrower):
        if not closing:
            return settle_debt_pass(borrower)
        changed=False
        # Finish fundable same-date dues before deciding whether to cancel the
        # optional project. No future receipts, extra credit or relaxed capital.
        count=sum(loan.borrower==borrower for loan in tx.loans)
        for _ in range(2*count+1):
            progress=settle_debt_pass(borrower)
            changed|=progress
            if not progress:return changed
        raise AssertionError('Finite closing debt-settlement bound exhausted.')

    def distribute_firms():
        paid = ZERO
        investment = chi * physical_i
        receipts = {'R': (cr + investment) * unit, 'F': (sa + sb) * unit}
        for borrower, owner, payroll, dep, floor, basis, kind in (
                ('R', 'HA', lr * wage, ZERO, orders.cash_floor_r, ZERO, 'residual_dividend'),
                ('F', 'HB', lf * wage, depreciation, orders.cash_floor_f,
                 installed_basis + investment * unit, 'focal_dividend')):
            # Positive expenses accrue even while cash-short; negative coupon
            # income is earned only on actual bank payment (signed interest).
            profit = (receipts[borrower] - payroll - dep - accrued[borrower]
                      - negative_paid[borrower])
            equity = tx.d[borrower] + basis - sum(
                (l.face for l in tx.loans if l.borrower == borrower), ZERO)
            # An unfilled optional I plan is neither an invoice reserve nor
            # paid capital basis. Dividends can precede later-round purchases.
            buffer = payroll if closing else floor * unit
            dividend = _floor(min(max(ZERO, profit - distributed[borrower]),
                max(ZERO, tx.d[borrower] - buffer - commitments(borrower)),
                max(ZERO, equity)), tx.money_quantum)
            tx.pay(borrower, owner, dividend, kind)
            distributed[borrower] += dividend
            paid += dividend
        return paid

    def distribute_banks():
        paid = ZERO
        for bank in BANKS:
            equity = tx.equity(bank)
            if equity < 0:
                raise _Failure('credit_default', f'Bank {bank} is insolvent after settled flows.')
            floor = (_closing_credit_floor(tx, controls, bank) if closing else
                     _dividend_capital_floor(controls, bank, tx.risk(bank)))
            dividend = _floor(min(max(ZERO, tx.earnings[bank] - bank_paid[bank]),
                max(ZERO, equity - floor)), tx.money_quantum)
            owner = 'HA' if bank == 'A' else 'HB'
            tx.d[owner] += dividend
            tx.record('Bank' + bank, owner, dividend, 'bank_dividend')
            bank_paid[bank] += dividend
            paid += dividend
            tx.refresh_cb(bank)
        return paid

    def sweep_operating_cash():
        # Only the new contractual subtype authorizes this automatic repayment.
        # Legacy and protected project installments remain ordinary Loan claims.
        buffers = {'R': lr * wage, 'F': lf * wage}
        for loan in sorted((l for l in tx.loans if isinstance(l, OperatingLoan)),
                           key=lambda l: (l.maturity, l.id)):
            cash = tx.d[loan.borrower]
            value = _floor(min(loan.face, max(ZERO, cash - buffers[loan.borrower])),
                           tx.money_quantum)
            if not value:
                continue
            tx.principal(loan, value)
            tx.note('operating_cash_sweep', loan.borrower, loan.lender, value, loan.id,
                    cash_before=cash, buffer=buffers[loan.borrower],
                    cash_after=tx.d[loan.borrower], face_before=loan.face,
                    face_after=loan.face - value)

    limit_reached = False
    project_attempted = False
    project_drawn = ZERO
    for rounds in range(1, orders.max_clearing_rounds + 1):
        progress = False
        # Declare proportional simultaneous HA basket funding before services
        # execute. No buyer can pledge the same current cash twice.
        _, funded_sa = precision.ration(tx.d['HA'] / unit,
            max(ZERO, desired_cr - cr), max(ZERO, desired_sa - sa), quantum=QUANTUM)
        funded_sb = min(max(ZERO, desired_sb - sb), tx.d['HB'] / unit)
        buy_sa, buy_sb = precision.ration(max(ZERO, service_capacity - sa - sb),
                                         funded_sa, funded_sb, quantum=QUANTUM)
        tx.pay('HA', 'F', buy_sa * unit, 'services')
        tx.pay('HB', 'F', buy_sb * unit, 'services')
        sa += buy_sa
        sb += buy_sb
        progress |= bool(buy_sa + buy_sb)
        progress |= settle_debt('F')
        progress |= settle_debt('R')
        project = controls.project_commitment
        if project is not None and not project_attempted:
            project_attempted = True
            invoice = chi * orders.investment_units * unit
            reason = None
            if orders.investment_units:
                if chi * orders.investment_units > resource_capacity:
                    reason = 'insufficient_physical_resources'
                elif debt_pending('F'):
                    reason = 'unpaid_mandatory_F_claim'
                else:
                    draw, probes = _minimum_project_draw(tx.d['F'], invoice, lf * wage,
                                                        project_ceiling, project.rate_pct, tx.scale)
                    tx.note('project_draw_quote', project.lender, 'F', draw or ZERO,
                            probes=probes, feasible=draw is not None, ceiling=project_ceiling)
                    if draw is None:
                        reason = 'insufficient_current_finance'
                    else:
                        try:
                            paid_coupon = _stage_project(tx, project, draw, invoice, lf * wage)
                        except _Failure as error:
                            reason = error.status
                        else:
                            physical_i = orders.investment_units
                            project_drawn = draw
                            interest['F'] += paid_coupon
                            accrued['F'] += max(ZERO, paid_coupon)
                            negative_paid['F'] += min(ZERO, paid_coupon)
                            progress = True
            if reason:
                tx.note('project_cancelled', 'F', project.lender, reason=reason,
                        requested_units=orders.investment_units, invoice=invoice)
        funded_cr = min(max(ZERO, desired_cr - cr), tx.d['HA'] / unit)
        i_order = (ZERO if project is not None or debt_pending('F') else min(
            max(ZERO, orders.investment_units - physical_i),
            max(ZERO, tx.d['F'] - (lf * wage if closing else orders.cash_floor_f * unit)) / (chi * unit)))
        resources = max(ZERO, resource_capacity - cr - chi * physical_i)
        buy_cr, i_resources = precision.ration(resources, funded_cr, chi * i_order,
                                               quantum=QUANTUM)
        buy_i = _floor(i_resources / chi, QUANTUM)
        # Resource-share flooring can strand a whole physical-I quantum when
        # chi is nonintegral. Buy it only from genuinely unused capacity AND
        # the same already funded order; no cash or physical unit is invented.
        spare = max(ZERO, resources - buy_cr - chi * buy_i)
        buy_i += _floor(min(max(ZERO, i_order - buy_i), spare / chi), QUANTUM)
        buy_real_i = chi * buy_i
        # Only genuine resource dust from physical-I quantization may go to CR.
        buy_cr += _floor(min(funded_cr - buy_cr,
            max(ZERO, _floor(resources, QUANTUM) - buy_cr - buy_real_i)), QUANTUM)
        tx.pay('HA', 'R', buy_cr * unit, 'residual_consumption')
        tx.pay('F', 'R', buy_real_i * unit, 'investment')
        cr += buy_cr
        physical_i += buy_i
        progress |= bool(buy_cr + buy_i)
        progress |= settle_debt('R')
        if not closing:
            progress |= bool(distribute_firms())
            progress |= bool(distribute_banks())
        if not progress:
            break
    else:
        limit_reached = True

    # Last legal settlement attempt is not a fabricated clearing or forgiveness.
    settle_debt('F')
    settle_debt('R')
    for loan in tx.loans:
        if coupon_due(loan) or loan.maturity <= tx.quarter:
            raise _Failure('credit_default', 'Mandatory private cash obligation remains unpaid.', loan.id)
    if controls.project_commitment is not None:
        tx.note('project_reservation_expired', controls.project_commitment.lender, 'F',
                project_ceiling - project_drawn, drawn=project_drawn)
    if closing:
        sweep_operating_cash()
    distribute_firms()
    distribute_banks()
    for bank in BANKS:
        shortfall = max(ZERO, COVENANT * tx.risk(bank) - tx.equity(bank))
        if shortfall:
            tx.note('capital_shortfall', bank, 'capital_covenant', shortfall)
    tx.note('market_clearing', 'production', 'markets', rounds=rounds,
            limit_reached=limit_reached, unfilled_cr=max(ZERO, desired_cr - cr),
            unfilled_sa=max(ZERO, desired_sa - sa), unfilled_sb=max(ZERO, desired_sb - sb),
            unfilled_i=max(ZERO, orders.investment_units - physical_i))
    return (cr, physical_i, sa + sb, sum(interest.values(), ZERO),
            distributed['R'], distributed['F'], sum(bank_paid.values(), ZERO))


def advance_given_orders(state, orders, controls=Controls()):
    """Execute one atomic quarter using supplied orders; no endogenous planner."""
    _state(state)
    if _is_early_paydate(state.public_book):
        _admit_early_state(state, orders, controls)
        replace(state)  # Includes prior actual witness before any current IORB.
    if isinstance(state.public_book,PublicIncomeBook) and state.quarter:
        if state.last is None:
            raise ValueError('Public-income full-quarter continuation requires its actual paid report.')
        if isinstance(state.public_book,FundedPublicBook):
            if _is_paydate(state.public_book):
                _validate_paydate_book(state.public_book, state.scale, state.quarter,
                                       state.last.payments, state.last.trace)
            else:
                validate_funded_public(state.public_book,state.scale,state.quarter,state.last.payments)
        else:
            public_income.validate_payments(state.last.payments,state.public_book.observations,
                                           state.public_book.opening_deferred_asset)
    if not isinstance(controls,Controls):
        raise TypeError('Step requires explicit Controls.')
    if type(orders) is not ProductionOrders:
        raise TypeError('Advance requires immutable ProductionOrders.')
    if _is_paydate(state.public_book) and (
            controls.household_mode != 'cash_stock_close_v1' or not orders.market_clearing):
        raise ValueError('Paydate books require explicit closing cash-stock budgets AND market clearing.')
    if controls.household_mode == 'cash_stock_close_v1' and not orders.market_clearing:
        raise ValueError('Closing household budgets require explicit market clearing.')
    if orders.demand_multiplier != 1 and controls.household_mode != 'cash_stock_close_v1':
        raise ValueError('A demand multiplier requires the explicit closing-budget mode.')
    if controls.household_mode != 'cash_stock_close_v1' and (
            any(isinstance(l, (OperatingLoan, ProjectLoan)) for l in state.loans) or
            any(isinstance(o, OperatingLoanOffer) for o in controls.new_loans)):
        raise ValueError('Operating cash-sweep contracts require the closing-budget mode.')
    q, s = state.quarter+1,state.scale
    unit = s * orders.price_factor
    wage = unit * orders.real_wage
    chi = orders.capital_resource_cost
    if controls.project_commitment is not None:
        _money(controls.project_commitment.face_ceiling, s)
        if orders.investment_units != _floor(orders.investment_units, QUANTUM):
            raise ValueError('A full project tranche must be on the physical order grid.')
    # Quote misuse is a programmer error, checked before any economic work.
    for renewal in controls.renewals:
        loan = _find(state,renewal.loan_id)
        if isinstance(loan, ProjectLoan):
            raise ValueError('Protected project principal cannot be renewed.')
        if loan.maturity != q or renewal.maturity<=q:
            raise ValueError('Renewal must identify a loan due now and a future new maturity.')
        if isinstance(loan, OperatingLoan) and renewal.maturity != q + 2:
            raise ValueError('Operating renewal must preserve two settlement dates.')
        _money(renewal.face,s)
    for offer in controls.new_loans:
        if offer.maturity<q:
            raise ValueError('Opening credit cannot mature before the current quarter closes.')
        if isinstance(offer, OperatingLoanOffer) and offer.maturity != q + 1:
            raise ValueError('Opening operating credit requires two settlement dates.')
        _money(offer.face,s)
    tx = _Transaction(state,controls,q)
    try:
        if tx.public_book is not None:
            instructions = controls.public_instructions or PublicInstructions()
            if type(tx.public_book) is HouseholdLiquidityBook:
                tx.settle_household_liquidity_public(instructions)
            elif type(tx.public_book) is EarlyPaydateBook:
                tx.settle_early_paydate_public(instructions)
            elif type(tx.public_book) is PaydatePublicBook:
                tx.settle_paydate_public(instructions)
            elif isinstance(tx.public_book,FundedPublicBook):
                tx.settle_funded_public(instructions)
            elif isinstance(tx.public_book,PublicIncomeBook):
                tx.settle_public_income()
                tx.settle_public(instructions, calendar=True)
            else:
                tx.close_rrp()
                tx.settle_public(instructions, calendar=True)
            tx.cb_maturities()
            tx.qe(controls.asset_purchase_request, controls.asset_offers)
            tx.new_rrp(instructions)
        else:
            if controls.public_instructions is not None:
                tx.settle_public(controls.public_instructions)
            # Preserve the qualified legacy no-PublicBook ordering.
            tx.qe(controls.asset_purchase_request, controls.asset_offers)
            tx.cb_maturities()
        project_ceiling = _reserve_project(tx, controls)
        for offer in controls.new_loans:
            tx.originate(offer,at_open=True)
        # Last quarter's paid investment becomes serviceable before current
        # payroll; installed age-15 units retire. New investment is WIP only.
        vintages = tuple(replace(v,age=v.age+1) for v in state.vintages if v.age<15)
        if state.wip_units or state.wip_basis:
            vintages += (Vintage(0,state.wip_units,state.wip_basis),)
        capital = sum((v.units for v in vintages),ZERO)
        depreciation = sum((v.basis for v in vintages),ZERO)/16
        # First constrain each request by its own cash/technology, then share
        # the actual workforce. Standby R labor is paid but unsold goods are not GDP.
        feasible_r = min(orders.residual_workers, tx.d['R']/wage)
        feasible_f = min(orders.focal_workers, tx.d['F']/wage,
                         capital*orders.capital_productivity/orders.service_productivity)
        lr, lf = precision.ration(orders.available_workers, feasible_r, feasible_f,
                                 quantum=QUANTUM)
        tx.pay('R','HA',lr*wage,'residual_payroll')
        tx.pay('F','HB',lf*wage,'focal_payroll')
        if type(tx.public_book) is HouseholdLiquidityBook:
            tx.settle_household_liquidity_households((lr*wage, lf*wage))
        elif type(tx.public_book) is EarlyPaydateBook:
            tx.settle_early_paydate_households((lr*wage, lf*wage))
        elif type(tx.public_book) is PaydatePublicBook:
            tx.settle_paydate_households((lr*wage, lf*wage))
        if orders != _DEFAULT_ORDERS:
            tx.note('production_orders','production','goods',
                    price_factor=orders.price_factor, real_wage=orders.real_wage,
                    residual_workers=orders.residual_workers, focal_workers=orders.focal_workers,
                    investment_units=orders.investment_units,
                    residual_consumption=orders.residual_consumption,
                    service_a=orders.service_a, service_b=orders.service_b,
                    available_workers=orders.available_workers,
                    residual_productivity=orders.residual_productivity,
                    service_productivity=orders.service_productivity,
                    capital_productivity=orders.capital_productivity,
                    capital_resource_cost=chi, cash_floor_r=orders.cash_floor_r,
                    cash_floor_f=orders.cash_floor_f,
                    preference_a_residual=orders.preferences_a.residual,
                    preference_a_services=orders.preferences_a.services,
                    preference_a_cash=orders.preferences_a.cash,
                    preference_b_services=orders.preferences_b.services,
                    preference_b_cash=orders.preferences_b.cash,
                    expected_a_nominal=(None if orders.expected_dividends_nominal is None
                                        else orders.expected_dividends_nominal[0]),
                    expected_b_nominal=(None if orders.expected_dividends_nominal is None
                                        else orders.expected_dividends_nominal[1]),
                    initial_dividend_a_real=orders.initial_dividends_real[0],
                    initial_dividend_b_real=orders.initial_dividends_real[1],
                    **({'demand_multiplier': orders.demand_multiplier,
                        'preference_b_residual': orders.preferences_b.residual}
                       if _is_paydate(tx.public_book) else {}),
                    **({'market_clearing': orders.market_clearing,
                        'max_clearing_rounds': orders.max_clearing_rounds}
                       if orders.market_clearing or orders.max_clearing_rounds != 64 else {}))
        if orders.market_clearing:
            cr, physical_i, services, interest, dr, df, bank_div = _clear_market(
                tx, orders, controls, vintages, capital, depreciation, lr, lf, project_ceiling)
            investment = chi * physical_i
        else:
            if controls.household_mode=='fixed':
                cr_order, sa_order = precision.ration(tx.d['HA']/unit,
                    orders.residual_consumption, orders.service_a, quantum=QUANTUM)
                sb_order = _floor(min(orders.service_b,tx.d['HB']/unit),QUANTUM)
            else:
                if orders.expected_dividends_nominal is not None:
                    da_nom, db_nom = orders.expected_dividends_nominal
                    source = 'explicit_forecast'
                elif state.last is None:
                    da_nom, db_nom = (x*s for x in orders.initial_dividends_real)
                    source = 'initial_reference'
                else:
                    da_nom = state.last.dividend_residual+state.last.bank_dividend_to('HA')
                    db_nom = state.last.dividend_focal+state.last.bank_dividend_to('HB')
                    source = 'last_paid_dividends'
                aa = household.allocate(tx.d['HA']/unit,da_nom/unit,orders.preferences_a,controls.household_mode)
                ab = household.allocate(tx.d['HB']/unit,db_nom/unit,orders.preferences_b,controls.household_mode)
                cr_order,sa_order = _floor(aa.residual,QUANTUM),_floor(aa.services,QUANTUM)
                sb_order = _floor(ab.services,QUANTUM)
                tx.note('household_budget','HA','goods',tx.d['HA'],forecast=da_nom,forecast_source=source)
                tx.note('household_budget','HB','goods',tx.d['HB'],forecast=db_nom,forecast_source=source)
            sa,sb = precision.ration(min(capital*orders.capital_productivity,
                                         lf*orders.service_productivity),sa_order,sb_order,quantum=QUANTUM)
            tx.pay('HA','F',sa*unit,'services')
            tx.pay('HB','F',sb*unit,'services')
            services = sa+sb
            focal_interest = sum((tx.coupon(loan) for loan in tuple(tx.loans) if loan.borrower=='F'),ZERO)
            renewals = {r.loan_id:r for r in controls.renewals}
            for loan in tuple(tx.loans):
                if loan.borrower!='F':
                    continue
                if loan.maturity < q:
                    raise _Failure('credit_default','Overdue private maturity cannot be silently extended.',loan.id)
                if loan.maturity == q:
                    if loan.id in renewals:
                        tx.renew(loan,renewals[loan.id])
                    else:
                        tx.principal(loan,loan.face)
            # Investment uses only owned cash after coupons AND due principal.
            i_order = min(orders.investment_units,
                          max(ZERO,tx.d['F']-orders.cash_floor_f*unit)/(chi*unit))
            resources = lr*orders.residual_productivity
            cr, i_resources = precision.ration(resources,cr_order,chi*i_order,quantum=QUANTUM)
            physical_i = _floor(i_resources/chi,QUANTUM)
            investment = chi*physical_i  # fixed-base real value, not physical units
            # Converting resource shares to physical capital can leave resource dust.
            # Redirect only whole resource quanta to still-unfilled, funded CR orders;
            # never invent investment from an unpurchased consumption order.
            cr += _floor(min(cr_order-cr,
                             max(ZERO,_floor(resources,QUANTUM)-cr-investment)),QUANTUM)
            tx.pay('HA','R',cr*unit,'residual_consumption')
            tx.pay('F','R',investment*unit,'investment')
            residual_interest = sum((tx.coupon(loan) for loan in tuple(tx.loans) if loan.borrower=='R'),ZERO)
            for loan in tuple(tx.loans):
                if loan.borrower!='R':
                    continue
                if loan.maturity<q:
                    raise _Failure('credit_default','Overdue private maturity cannot be silently extended.',loan.id)
                if loan.maturity==q:
                    if loan.id in renewals:
                        tx.renew(loan,renewals[loan.id])
                    else:
                        tx.principal(loan,loan.face)
            interest=focal_interest+residual_interest
            profit_r = (cr+investment)*unit-lr*wage-residual_interest
            profit_f = services*unit-lf*wage-focal_interest-depreciation
            net_capital = sum((v.net_book for v in vintages),investment*unit)
            focal_equity = tx.d['F']+net_capital-sum((l.face for l in tx.loans if l.borrower=='F'),ZERO)
            residual_equity=tx.d['R']-sum((l.face for l in tx.loans if l.borrower=='R'),ZERO)
            dr = _floor(min(max(ZERO,profit_r),max(ZERO,tx.d['R']-orders.cash_floor_r*unit),max(ZERO,residual_equity)),tx.money_quantum)
            df = _floor(min(max(ZERO,profit_f),max(ZERO,tx.d['F']-orders.cash_floor_f*unit),max(ZERO,focal_equity)),tx.money_quantum)
            tx.pay('R','HA',dr,'residual_dividend')
            tx.pay('F','HB',df,'focal_dividend')
            bank_div = ZERO
            for bank in BANKS:
                # Existing performing business may retain earnings under a capital
                # shortfall. New credit/renewal still has its separate covenant;
                # blocking the whole quarter would prevent earned recapitalization.
                if tx.equity(bank)<0:
                    raise _Failure('credit_default',f'Bank {bank} is insolvent after settled flows.')
                shortfall=max(ZERO,COVENANT*tx.risk(bank)-tx.equity(bank))
                if shortfall:
                    tx.note('capital_shortfall',bank,'capital_covenant',shortfall)
                dividend = _floor(min(max(ZERO,tx.earnings[bank]),
                                      max(ZERO,tx.equity(bank)-_dividend_capital_floor(controls,bank,tx.risk(bank)))),tx.money_quantum)
                # The bank's actual owner is HA (A) or HB (B); creation of an
                # owner deposit reduces equity dollar for dollar, not reserves.
                owner = 'HA' if bank=='A' else 'HB'
                tx.d[owner] += dividend
                tx.record('Bank'+bank,owner,dividend,'bank_dividend')
                bank_div += dividend
                tx.refresh_cb(bank)
        output = cr+investment+services
        tx.note('real_output','production','goods',output,
                residual_consumption=cr,investment=investment,services=services,
                paid_focal_workers=lf,productive_capital=capital)
        if _is_paydate(tx.public_book):
            tx.paydate_boundary('trading_close')
        report = Report(q,output,services,investment,cr,lr,lf,lr*wage,lf*wage,depreciation,
                        interest,dr,df,bank_div,tx.cb_borrowed,tx.cb_repaid,tx.qe_applied,
                        controls.asset_purchase_request-tx.qe_applied,tuple(tx.payments),tuple(tx.trace))
        if isinstance(tx.public_book,PublicIncomeBook):
            public_income.validate_payments(report.payments,tx.public_book.observations,
                                           tx.public_book.opening_deferred_asset)
        result = tx.finish(vintages=vintages,wip_units=physical_i,wip_basis=investment*unit,last=report)
        return Outcome(True,'ok',result)
    except _Failure as error:
        return Outcome(False,error.status,state,error.reason,error.claim_id)
