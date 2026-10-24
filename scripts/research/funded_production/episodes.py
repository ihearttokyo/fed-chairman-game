"""Offline full-life conditional episodes using the single macro executor.

Authored project financing, not an optimal investment model or shareholder NPV.
Actual origination receipts bind the sixteen dated amortization slots; no hidden
future shocks, project rollover, terminal salvage or post-hoc book repair.
"""
from dataclasses import dataclass, replace
from fractions import Fraction as F
from . import macro as m


def physical_units(value):
    value=m.ledger._number(value)
    if value % m.ledger.QUANTUM: raise ValueError('Project requires the fixed physical quantum.')
    return value


def project_terms(prepared,units,rate_pct):
    units=physical_units(units);rate=m.ledger._number(rate_pct,signed=True)
    if type(prepared) is not m.Prepared or prepared!=m.prepare(prepared.opening,prepared.policy,prepared.news,prepared.orders.investment_units):
        raise ValueError('Inconsistent project preparation.')
    state=prepared.opening.sector;q=state.quarter+1;quantum=state.scale*m.ledger.QUANTUM
    cost=state.scale*prepared.orders.price_factor*prepared.orders.capital_resource_cost*units
    face=-(-cost//quantum)*quantum;whole=face//quantum;base=whole//16;extra=whole%16
    # For a tiny physical order, zero cash installments are omitted, not issued
    # as fake zero-principal claims. The dated schedule still has sixteen slots.
    faces=tuple((base+(i<extra))*quantum for i in range(16))
    return tuple(m.ledger.LoanOffer('B',face,rate,q+i+1,borrower='F') for i,face in enumerate(faces) if face)


@dataclass(frozen=True)
class Step:
    prepared: m.Prepared
    controls: m.ledger.Controls
    envelope: m.Envelope
    project_face_created: F=F(0)


@dataclass(frozen=True)
class Episode:
    action: str
    requested_units: F
    completed: int
    committed_calls: int
    status: str
    reason: str
    terminal: m.Envelope
    steps: tuple
    project_ids: tuple
    project_origin_face: F
    project_retired_principal: F
    project_coupon: F
    project_outstanding_face: F


@dataclass(frozen=True)
class PolicyRule:
    kind: str
    fixed: m.Policy | None=None
    def __post_init__(self):
        if type(self.kind) is not str or self.kind not in ('fixed','staff','promise'):
            raise ValueError('Unknown immutable policy rule.')
        if (self.kind=='fixed' and type(self.fixed) is not m.Policy) or (self.kind!='fixed' and self.fixed is not None):
            raise ValueError('Only the fixed rule carries an explicit policy.')
    def resolve(self,envelope):
        if type(envelope) is not m.Envelope:raise TypeError('Rule needs its own current forecast envelope.')
        if self.kind=='fixed':return self.fixed
        a=envelope.macro
        if self.kind=='staff':
            target=a.r_star_pct+a.expected_short_inflation_pct+1.5*(a.four_quarter_inflation_pct-m.P['inflation_target_pct'])+.5*a.output_gap_pct
        else:
            if not a.guidance_active:raise ValueError('No prior conditional promise is active.')
            old=a.prior_policy
            target=old.guidance_pct+old.inflation_sensitivity*(a.four_quarter_inflation_pct-a.guidance_reference_inflation_pct)+old.gap_sensitivity*(a.output_gap_pct-a.guidance_reference_gap_pct)
        quote=m.round_quote(target)
        # Match the source Staff family, not merely its rate formula.
        return m.Policy(quote,quote,1.5,.5)


def validate_blocked_rollovers(opening,ids):
    """Known current lender-program constraints, never a second claims book."""
    if type(opening) is not m.Envelope:raise TypeError('Require current immutable opening.')
    if type(ids) is not tuple or any(type(k) is not str or not k for k in ids):
        raise TypeError('Blocked rollover identities require immutable built-in strings.')
    if len(set(ids))!=len(ids):raise ValueError('Duplicate blocked rollover identity.')
    loans={loan.id:loan for loan in opening.sector.loans}
    if any(k not in loans or loans[k].borrower!='F' or loans[k].lender!='B' for k in ids):
        raise ValueError('Blocked rollover identity is not an active BankB/F claim.')
    return ids


def run_episode(opening,policies,news,action,units=F(1,4),project_rate_pct=None,*,blocked_rollover_ids=()):
    if type(opening) is not m.Envelope:raise TypeError('Require immutable current opening.')
    blocked_rollover_ids=validate_blocked_rollovers(opening,blocked_rollover_ids)
    if type(policies) is not tuple or type(news) is not tuple:raise TypeError('Forecast paths must be immutable tuples.')
    if len(policies)!=len(news) or len(policies)<19:raise ValueError('Require matching complete project/debt life paths, at least19 quarters.')
    if any(type(p) not in (m.Policy,PolicyRule) for p in policies) or any(type(n) is not m.News for n in news):raise TypeError('Forecast contains invalid current-information records.')
    if type(action) is not str or action not in ('NOW','WAIT','NEVER'):raise ValueError('Unknown project action.')
    units=physical_units(units)
    if project_rate_pct is not None:project_rate_pct=m.ledger._number(project_rate_pct,signed=True)
    # This entire known cumulative path can be invalid before any settlement;
    # never execute part of a forecast and then drop it as a malformed input.
    structural_u=opening.macro.structural_unemployment_pct
    for item in news:
        structural_u+=item.structural_unemployment_change_pct
        if not 0<structural_u<100:
            raise ValueError('Invalid structural unemployment forecast path.')
    action_q={'NOW':1,'WAIT':2,'NEVER':None}[action]
    a=opening;steps=[];ids=();face=retired=coupon=F(0);calls=0;status='completed';reason=''
    for offset,(descriptor,current_news) in enumerate(zip(policies,news),1):
        policy=descriptor.resolve(a) if type(descriptor) is PolicyRule else descriptor
        order_units=F(1)+(units if offset==action_q else F(0))
        p=m.prepare(a,policy,current_news,investment_units=order_units)
        c=m.stationary_controls(a,p)
        # Only background claims may be consensually rolled. Project principal
        # is paid from actual F deposits through the existing mandatory path.
        c=replace(c,renewals=tuple(r for r in c.renewals if r.loan_id not in ids and r.loan_id not in blocked_rollover_ids))
        rate=m.rational(p.long_yield_pct+m.P['normal_credit_spread_pct']) if project_rate_pct is None else project_rate_pct
        offers=project_terms(p,units,rate) if offset==action_q else ()
        c=replace(c,new_loans=c.new_loans+offers)
        result=m.execute(p,c);calls+=1
        if not result.ok:
            assert result.envelope==a
            status=result.status;reason=result.reason;break
        b=result.envelope;newface=F(0)
        if offers:
            created=tuple(t for t in b.sector.last.trace if t.kind=='matching_loan_created')
            project_records=created[-len(offers):]
            if len(project_records)!=len(offers):raise AssertionError('Missing actual matching project claims.')
            for t,offer in zip(project_records,offers):
                if (t.actor,t.counterparty,t.amount,dict(t.details)['maturity'])!=('B','F',offer.face,offer.maturity):raise AssertionError('Project origination receipt mismatch.')
            ids=tuple(t.claim_id for t in project_records);newface=sum((t.amount for t in project_records),F(0));face+=newface
        for pay in b.sector.last.payments:
            if pay.claim_id not in ids:continue
            if pay.kind=='private_principal':retired+=pay.amount
            elif pay.kind=='private_coupon':coupon+=pay.amount if pay.payer=='F' else -pay.amount
        steps.append(Step(p,c,b,newface));a=b
    outstanding=sum((loan.face for loan in a.sector.loans if loan.id in ids),F(0))
    if face != retired+outstanding:raise AssertionError('Project legal principal does not reconcile.')
    if status=='completed' and outstanding:raise AssertionError('Project debt improperly survived its complete quoted life.')
    return Episode(action,units,len(steps),calls,status,reason,a,tuple(steps),ids,face,retired,coupon,outstanding)
