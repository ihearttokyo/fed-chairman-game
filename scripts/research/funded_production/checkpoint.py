"""Exact offline-reference checkpoints and commands, not native game saves.

The only monetary book and transition engine remain the reference macro/ledger.
Hashes establish content consistency, not authenticity or historical custody.
No function in this module writes files or generates counterfactual forecasts.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F
from pathlib import Path
from types import MappingProxyType
import hashlib
import json
import math
import re
import sys

from . import source_data
from . import public_funding
from . import episodes as e
m = e.m

_PACKAGE_DIR = Path(__file__).resolve().parent
_MODULE_NAMES = ('__init__', 'source_data', 'numerics', 'households', 'pricing', 'public_income', 'public_funding',
                 'ledger', 'macro', 'episodes', 'cashflows', 'choice', 'checkpoint',
                 'prospectus', 'coupled', 'investment', 'public_forecast',
                 'public_scenarios', 'public_branches', 'public_market')
_SOURCE_PATHS = {name: _PACKAGE_DIR / (name + '.py') for name in _MODULE_NAMES}
_SOURCE_PATHS.update({'model.' + name: source_data.MODEL_DIR / name
                      for name in source_data.SOURCE_DIGESTS})
_SOURCES = MappingProxyType({name: hashlib.sha256(path.read_bytes()).hexdigest()
                            for name, path in _SOURCE_PATHS.items()})
_SOURCE_PATHS = MappingProxyType(_SOURCE_PATHS)


def _check_sources():
    source_data.check_sources()
    for key, path in _SOURCE_PATHS.items():
        if hashlib.sha256(path.read_bytes()).hexdigest() != _SOURCES[key]:
            raise ValueError('Reference source content changed: ' + key)
    for name in _MODULE_NAMES:
        identity = __package__ if name == '__init__' else __package__ + '.' + name
        loaded = sys.modules.get(identity)
        if loaded is not None and Path(getattr(loaded, '__file__', '')).resolve() != (
                _PACKAGE_DIR / (name + '.py')).resolve():
            raise ValueError('Incompatible cached package module identity: ' + name)


_check_sources()


def _paid_economy(economy):
    if type(economy) is not m.Envelope:
        raise TypeError('Require the canonical reference Envelope.')
    # Validate the wrapper's version/type/clock contract even for fresh Q0;
    # valid Macro and Sector components alone do not validate their envelope.
    replace(economy)
    a, s = economy.macro, economy.sector
    if not a.quarter:
        if s.last is not None:
            raise ValueError('Opening state cannot carry a paid-quarter report.')
        return
    r = s.last
    if r is None or r.quarter != a.quarter:
        raise ValueError('Missing current paid-quarter report.')
    if a.actual_output_index != 4 * float(r.real_output):
        raise ValueError('Macro GDP differs from actual paid production.')
    jobs = r.paid_residual_workers + r.paid_focal_workers
    if a.unemployment_rate_pct != 100 * (1 - float(jobs) / a.workforce):
        raise ValueError('Macro unemployment differs from actual paid employment.')
    unit = s.scale * m.rational(a.price_index / 100)
    routes = {
        'services': (('HA', 'F'), ('HB', 'F')),
        'residual_consumption': (('HA', 'R'),),
        'investment': (('F', 'R'),),
        'residual_payroll': (('R', 'HA'),),
        'focal_payroll': (('F', 'HB'),),
        'residual_dividend': (('R', 'HA'),),
        'focal_dividend': (('F', 'HB'),),
        'bank_dividend': (('BankA', 'HA'), ('BankB', 'HB')),
    }
    public_routes={
        'treasury_coupon':(('Treasury','CB'),('Treasury','BankA'),('Treasury','BankB')),
        'iorb_coupon':(('CB','BankA'),('CB','BankB')),
        'rrp_coupon':(('CB','BankA'),('CB','BankB')),
        'cb_loan_coupon':(('BankA','CB'),('BankB','CB')),
        'mortgage_coupon':(('HA','MortgagePool'),('HB','MortgagePool')),
        'mbs_coupon':(('MortgagePool','CB'),),
        'cb_remittance':(('CB','Treasury'),),
    }
    mortgage={};mbs={}
    paid = dict.fromkeys(routes, F(0))
    for payment in r.payments:
        if payment.kind in public_routes:
            if not isinstance(s.public_book,m.ledger.PublicIncomeBook):
                raise ValueError('Public-income receipt requires its declared program.')
            allowed=public_routes[payment.kind]
            pair=(payment.payer,payment.payee)
            if pair not in allowed and (payment.kind=='cb_remittance' or pair[::-1] not in allowed):
                raise ValueError('Unidentified public-income payment route.')
            if payment.kind in ('mortgage_coupon','mbs_coupon'):
                target=mortgage if payment.kind=='mortgage_coupon' else mbs
                if payment.claim_id not in ('mortgage:HA','mortgage:HB'):
                    raise ValueError('Missing matched mortgage/pass-through identity.')
                if payment.kind=='mortgage_coupon':
                    owner=payment.claim_id.split(':')[1]
                    if owner not in pair:
                        raise ValueError('Mortgage income attributed to another owner.')
                    signed=payment.amount*(1 if payment.payer==owner else -1)
                else:signed=payment.amount*(1 if payment.payee=='CB' else -1)
                target[payment.claim_id]=target.get(payment.claim_id,F(0))+signed
        if payment.kind in paid:
            if (payment.payer, payment.payee) not in routes[payment.kind]:
                raise ValueError('Unidentified production/payment counterparty.')
            paid[payment.kind] += payment.amount
    if mortgage!=mbs:
        raise ValueError('Mortgage payments and MBS pass-through differ.')
    if isinstance(s.public_book,m.ledger.PublicIncomeBook):
        m.ledger.public_income.validate_payments(r.payments,s.public_book.observations,
                                               s.public_book.opening_deferred_asset)
    if isinstance(s.public_book,m.ledger.FundedPublicBook):
        m.ledger.validate_funded_public(s.public_book,s.scale,s.quarter,r.payments)
    if (paid['services'], paid['residual_consumption'], paid['investment'],
            paid['residual_payroll'], paid['focal_payroll']) != (
            r.services * unit, r.residual_consumption * unit, r.investment * unit,
            r.payroll_residual, r.payroll_focal):
        raise ValueError('Current report differs from actual paid invoices.')
    if (paid['residual_dividend'], paid['focal_dividend'], paid['bank_dividend']) != (
            r.dividend_residual, r.dividend_focal, r.dividend_bank):
        raise ValueError('Current income history differs from identified paid dividends.')
    wage = unit * m.rational(a.productivity_trend)
    if (r.payroll_residual, r.payroll_focal) != (
            r.paid_residual_workers * wage, r.paid_focal_workers * wage):
        raise ValueError('Employment differs from actual paid payroll.')


def _ids(value):
    if type(value) is not tuple or any(type(k) is not str or not k for k in value):
        raise TypeError('Require immutable nonempty claim identities.')
    if len(set(value)) != len(value):
        raise ValueError('Duplicate claim identity.')
    return value


@dataclass(frozen=True)
class CandidateState:
    economy: m.Envelope
    blocked_rollover_ids: tuple = ()
    project_origin: F = F(0)
    project_paid: F = F(0)

    def __post_init__(self):
        _paid_economy(self.economy)
        e.validate_blocked_rollovers(self.economy, self.blocked_rollover_ids)
        for name in ('project_origin', 'project_paid'):
            object.__setattr__(self, name, m.ledger._money(
                getattr(self, name), self.economy.sector.scale))
        outstanding = sum((l.face for l in self.economy.sector.loans
                           if l.id in self.blocked_rollover_ids), F(0))
        if self.project_origin != self.project_paid + outstanding:
            raise ValueError('Project origin/paid/active principal do not reconcile.')


def _hash_text(value):
    if type(value) is not str or re.fullmatch('[0-9a-f]{64}', value) is None:
        raise ValueError('Require a canonical SHA256 digest.')


@dataclass(frozen=True)
class DecisionEvent:
    policy: m.Policy
    news: m.News
    additional_units: F
    project_rate_pct: F | None
    controls: m.ledger.Controls
    new_project_ids: tuple
    before_digest: str
    after_digest: str

    def __post_init__(self):
        if type(self.policy) is not m.Policy or type(self.news) is not m.News:
            raise TypeError('Require canonical current policy/news identities.')
        if type(self.controls) is not m.ledger.Controls:
            raise TypeError('Require canonical actually supplied Controls.')
        object.__setattr__(self, 'additional_units', e.physical_units(self.additional_units))
        if self.project_rate_pct is not None:
            object.__setattr__(self, 'project_rate_pct',
                               m.ledger._number(self.project_rate_pct, signed=True))
        _ids(self.new_project_ids)
        if not self.additional_units and self.new_project_ids:
            raise ValueError('No new project identities without a project order.')
        _hash_text(self.before_digest)
        _hash_text(self.after_digest)


@dataclass(frozen=True)
class StepOutcome:
    ok: bool
    state: CandidateState
    event: DecisionEvent | None
    status: str
    reason: str = ''

    def __post_init__(self):
        if type(self.ok) is not bool or type(self.state) is not CandidateState:
            raise TypeError('Invalid candidate outcome.')
        if type(self.status) is not str or not self.status or type(self.reason) is not str:
            raise TypeError('Require actual typed status/reason.')
        if (self.ok and type(self.event) is not DecisionEvent) or (not self.ok and self.event is not None):
            raise ValueError('Only committed transitions carry a decision event.')


# Fixed logical identities; no module/class name from data is ever imported.
_TYPES = MappingProxyType({
    **{cls.__name__: cls for cls in (m.Macro, m.Envelope, m.Policy, m.News)},
    **{name: getattr(m.ledger, name) for name in (
        'SectorState', 'Bank', 'Loan', 'CBLoan', 'Collateral', 'Vintage',
        'PublicBook', 'PublicIncomeBook', 'PublicIncomeTerms', 'CouponLine', 'PublicIncomeControls', 'RRPClaim', 'Report', 'Payment', 'Trace', 'Controls',
        'FundedPublicBook', 'FundedPublicInstructions',
        'LoanOffer', 'Renewal', 'PublicInstructions', 'ClosingCreditForecast',
        'OperatingLoanOffer', 'OperatingLoan', 'ProjectCommitment', 'ProjectLoan')},
    **{name: getattr(public_funding, name) for name in (
        'FundingOpening', 'FundingBatch', 'TreasuryTransfer')},
    'CandidateState': CandidateState,
    'DecisionEvent': DecisionEvent,
})
_TAGS = MappingProxyType({cls: name for name, cls in _TYPES.items()})
_SCHEMA = 1
_FORMAT = 'funded-production-reference'
_MAX_TEXT = 2 * 1024 * 1024
_MAX_NODES = 50000
_MAX_DEPTH = 64


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False)


def _pack(value):
    cls = type(value)
    if value is None or cls in (str, bool, int):
        return value
    if cls is float:
        if not math.isfinite(value):
            raise ValueError('Nonfinite values are not checkpoint data.')
        return value
    if cls is F:
        return {'$fraction': [str(value.numerator), str(value.denominator)]}
    if cls is tuple:
        return {'$tuple': [_pack(x) for x in value]}
    if cls in _TAGS:
        return {'$type': _TAGS[cls], 'fields': {
            f.name: _pack(getattr(value, f.name)) for f in fields(value)}}
    raise TypeError('Untrusted checkpoint value/type.')


def _unpack(value, budget, depth=0):
    budget[0] -= 1
    if budget[0] < 0 or depth > _MAX_DEPTH:
        raise ValueError('Checkpoint structure exceeds bounded format limits.')
    if value is None or type(value) in (str, bool, int):
        return value
    if type(value) is float:
        if not math.isfinite(value):
            raise ValueError('Nonfinite checkpoint value.')
        return value
    if type(value) is not dict:
        raise TypeError('Only tagged immutable structured values are allowed.')
    if set(value) == {'$fraction'}:
        pair = value['$fraction']
        if type(pair) is not list or len(pair) != 2 or any(type(x) is not str for x in pair):
            raise ValueError('Fraction requires exact numerator/denominator decimal strings.')
        n, d = pair
        if re.fullmatch(r'0|-?[1-9][0-9]*', n) is None or re.fullmatch(r'[1-9][0-9]*', d) is None:
            raise ValueError('Invalid canonical fraction components.')
        result = F(int(n), int(d))
        if (str(result.numerator), str(result.denominator)) != (n, d):
            raise ValueError('Fraction must be reduced and canonical.')
        return result
    if set(value) == {'$tuple'}:
        if type(value['$tuple']) is not list:
            raise TypeError('Invalid immutable tuple encoding.')
        return tuple(_unpack(x, budget, depth + 1) for x in value['$tuple'])
    if set(value) == {'$type', 'fields'}:
        tag, members = value['$type'], value['fields']
        if type(tag) is not str or tag not in _TYPES:
            raise ValueError('Unknown checkpoint class identity.')
        cls = _TYPES[tag]
        if type(members) is not dict or set(members) != {f.name for f in fields(cls)}:
            raise ValueError('Unknown or missing dataclass fields.')
        result = cls(**{k: _unpack(v, budget, depth + 1) for k, v in members.items()})
        # Constructors may normalize public API inputs. On disk the original
        # canonical scalar types/values must already be present, never coerced.
        if _canonical(_pack(result)) != _canonical(value):
            raise ValueError('Serialized fields are not canonical constructor values.')
        return result
    raise ValueError('Unknown structured checkpoint value.')


def _body(kind, payload):
    return {'format': _FORMAT, 'schema': _SCHEMA, 'kind': kind, 'sources': dict(_SOURCES), 'payload': payload}


def _digest(body):
    return hashlib.sha256(_canonical(body).encode('ascii')).hexdigest()


def _require_state(state):
    if type(state) is not CandidateState:
        raise TypeError('Require an immutable CandidateState.')


def state_digest(state):
    _check_sources()
    _require_state(state)
    return _digest(_body('checkpoint', _pack(state)))


def _encode(value, kind, cls):
    _check_sources()
    if type(value) is not cls:
        raise TypeError('Incorrect root checkpoint/event identity.')
    payload = _pack(value)
    # Writer and reader share admission/canonical checks. Never emit text that
    # this same format cannot restore under its node/depth budget.
    _unpack(payload, [_MAX_NODES])
    body = _body(kind, payload)
    text = _canonical({**body, 'digest': _digest(body)})
    if len(text) > _MAX_TEXT:
        raise ValueError('Checkpoint exceeds bounded text size.')
    return text


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key.')
        result[key] = value
    return result


def _nonfinite(value):
    raise ValueError('Nonfinite JSON numeric constant.')


def _float(value):
    number = float(value)
    if not math.isfinite(number):
        raise ValueError('Nonfinite JSON numeric value.')
    return number


def _decode(text, kind, cls):
    _check_sources()
    if type(text) is not str:
        raise TypeError('Checkpoint operations accept text only, not paths/bytes.')
    if len(text) > _MAX_TEXT:
        raise ValueError('Checkpoint exceeds bounded text size.')
    try:
        root = json.loads(text, object_pairs_hook=_pairs, parse_constant=_nonfinite, parse_float=_float)
        if type(root) is not dict or set(root) != {'format', 'schema', 'kind', 'sources', 'payload', 'digest'}:
            raise ValueError('Invalid root checkpoint fields.')
        if root['format'] != _FORMAT or type(root['schema']) is not int or root['schema'] != _SCHEMA or root['kind'] != kind:
            raise ValueError('Unsupported checkpoint schema/kind.')
        if type(root['sources']) is not dict or root['sources'] != dict(_SOURCES):
            raise ValueError('Checkpoint sources differ from current trusted content.')
        _hash_text(root['digest'])
        body = {k: v for k, v in root.items() if k != 'digest'}
        if _digest(body) != root['digest']:
            raise ValueError('Checkpoint content digest mismatch.')
        value = _unpack(root['payload'], [_MAX_NODES])
        if type(value) is not cls:
            raise ValueError('Incorrect root checkpoint/event class.')
        return value
    except (RecursionError, OverflowError) as error:
        raise ValueError('Checkpoint exceeds bounded numeric/structure limits.') from error


def encode_checkpoint(state):
    return _encode(state, 'checkpoint', CandidateState)


def decode_checkpoint(text):
    return _decode(text, 'checkpoint', CandidateState)


def encode_event(event):
    return _encode(event, 'event', DecisionEvent)


def decode_event(text):
    return _decode(text, 'event', DecisionEvent)


def initial(growth=2, scale=1):
    _check_sources()
    return CandidateState(m.initial(growth=growth, scale=scale))


def _prepare(state, policy, news, additional_units, project_rate_pct):
    _check_sources()
    _require_state(state)
    if type(policy) is not m.Policy or type(news) is not m.News:
        raise TypeError('Require canonical current policy/news identities.')
    units = e.physical_units(additional_units)
    rate = None if project_rate_pct is None else m.ledger._number(project_rate_pct, signed=True)
    p = m.prepare(state.economy, policy, news, investment_units=F(1) + units)
    c = m.stationary_controls(state.economy, p)
    c = replace(c, renewals=tuple(r for r in c.renewals if r.loan_id not in state.blocked_rollover_ids))
    quote = m.rational(p.long_yield_pct + m.P['normal_credit_spread_pct']) if rate is None else rate
    offers = e.project_terms(p, units, quote) if units else ()
    c = replace(c, new_loans=c.new_loans + offers)
    return p, c, offers, units, rate


def _commit(state, p, controls, offers, units, rate):
    before = state_digest(state)
    result = m.execute(p, controls)  # Exactly one actual transition, never a forecast.
    if not result.ok:
        if result.envelope != state.economy:
            raise ValueError('Failed transition did not preserve its predecessor.')
        return StepOutcome(False, state, None, result.status, result.reason)
    economy = result.envelope
    created = tuple(t for t in economy.sector.last.trace if t.kind == 'matching_loan_created')
    if len(created) != len(controls.new_loans):
        raise ValueError('Actual origination count differs from supplied controls.')
    for receipt, offer in zip(created, controls.new_loans):
        details = dict(receipt.details)
        if (receipt.actor, receipt.counterparty, receipt.amount, details.get('maturity'),
                details.get('rate_pct'), details.get('start')) != (
                offer.lender, offer.borrower, offer.face, offer.maturity, offer.rate_pct,
                economy.sector.quarter - 1):
            raise ValueError('Actual origination receipt differs from its supplied offer.')
    project_receipts = created[-len(offers):] if offers else ()
    new_ids = _ids(tuple(t.claim_id for t in project_receipts))
    tracked = _ids(state.blocked_rollover_ids + new_ids)
    paid = F(0)
    for payment in economy.sector.last.payments:
        if payment.claim_id in tracked and payment.kind == 'private_principal':
            if (payment.payer, payment.payee) != ('F', 'BankB'):
                raise ValueError('Unidentified project principal payment.')
            paid += payment.amount
    active = {loan.id for loan in economy.sector.loans}
    blocked = tuple(k for k in tracked if k in active)
    successor = CandidateState(economy, blocked,
        state.project_origin + sum((t.amount for t in project_receipts), F(0)), state.project_paid + paid)
    event = DecisionEvent(p.policy, p.news, units, rate, controls, new_ids, before, state_digest(successor))
    return StepOutcome(True, successor, event, result.status, result.reason)


def adopt(state, policy, news=m.News(), additional_units=0, project_rate_pct=None):
    prepared, controls, offers, units, rate = _prepare(state, policy, news, additional_units, project_rate_pct)
    return _commit(state, prepared, controls, offers, units, rate)


def replay(state, event):
    """Reject malformed commands before execution; mismatches never return a successor."""
    _check_sources()
    _require_state(state)
    if type(event) is not DecisionEvent:
        raise TypeError('Require a canonical immutable DecisionEvent.')
    if state_digest(state) != event.before_digest:
        raise ValueError('Replay predecessor digest mismatch.')
    p, controls, offers, units, rate = _prepare(state, event.policy, event.news,
                                              event.additional_units, event.project_rate_pct)
    if _canonical(_pack(controls)) != _canonical(_pack(event.controls)):
        raise ValueError('Replay controls differ from canonical current controls.')
    result = _commit(state, p, controls, offers, units, rate)
    if result.ok and _canonical(_pack(result.event)) != _canonical(_pack(event)):
        raise ValueError('Actual replay event/successor differs from recorded command.')
    return result
