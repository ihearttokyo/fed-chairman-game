"""Authored quarterly public coupons; calculations are not payment approval.

Opening stocks proxy quarter averages, unlike actual daily IORB administration.
Treasury annual cash masses retain fixed coupons across consenting same-face
rolls. No policy repricing, market calibration or recovery claim is implied.
"""
from dataclasses import dataclass
from collections import Counter
from fractions import Fraction as F
from .numerics import amount, _signed, coupon

PAYMENT_KINDS=frozenset(('treasury_coupon','mortgage_coupon','mbs_coupon',
                       'iorb_coupon','cb_loan_coupon','rrp_coupon','cb_remittance'))


def pair(values, *, optional=False):
    if type(values) is not tuple or len(values)!=2:
        raise TypeError('Require two immutable owner-specific coupon terms.')
    return tuple(None if optional and x is None else _signed(x) for x in values)


@dataclass(frozen=True)
class PublicIncomeTerms:
    annual_treasury: tuple
    mortgage_rates_pct: tuple=(F(0),F(0))
    iorb_rate_pct: F=F(0)
    cb_rates_pct: tuple=(None,None)
    rrp_rates_pct: tuple=(None,None)

    def __post_init__(self):
        if type(self.annual_treasury) is not tuple or len(self.annual_treasury)!=3:
            raise TypeError('Require CB/A/B annual Treasury coupon arrays.')
        rows=[]
        for row in self.annual_treasury:
            if type(row) is not tuple or len(row)!=120:
                raise TypeError('Require 120 dated immutable coupon masses.')
            rows.append(tuple(map(_signed,row)))
        object.__setattr__(self,'annual_treasury',tuple(rows))
        object.__setattr__(self,'mortgage_rates_pct',pair(self.mortgage_rates_pct))
        object.__setattr__(self,'iorb_rate_pct',_signed(self.iorb_rate_pct))
        object.__setattr__(self,'cb_rates_pct',pair(self.cb_rates_pct,optional=True))
        object.__setattr__(self,'rrp_rates_pct',pair(self.rrp_rates_pct,optional=True))


@dataclass(frozen=True)
class CouponLine:
    kind: str
    owner: str
    basis: F
    contractual: F
    settled: F

    def __post_init__(self):
        allowed={'treasury':('CB','A','B'),'mortgage':('HA','HB'),
                 'iorb':('A','B'),'cb_loan':('A','B'),'rrp':('A','B')}
        if type(self.kind) is not str or type(self.owner) is not str or self.kind not in allowed or self.owner not in allowed[self.kind]:
            raise ValueError('Unknown public coupon obligation identity.')
        object.__setattr__(self,'basis',amount(self.basis))
        object.__setattr__(self,'contractual',_signed(self.contractual))
        object.__setattr__(self,'settled',_signed(self.settled))


def quote(terms, *, treasuries, mortgages, reserves, cb_faces, rrp_faces, scale):
    """Fixed 11 owner/holder obligations; zero executor calls, no cash approval.

Treasury cash masses aggregate per holder before monetary rounding. All other
payments round separately per identified owner. Signed rounding is toward zero;
contractual residuals are reported, never posted as fictional earnings.
"""
    if type(terms) is not PublicIncomeTerms:
        raise TypeError('Require the explicit immutable public coupon program.')
    scale=amount(scale)
    if not scale:raise ValueError('Require positive nominal scale.')
    if len(treasuries)!=3 or any(len(row)!=120 for row in treasuries):
        raise ValueError('Require the actual CB/A/B opening Treasury pools.')
    lines=[]
    for owner,faces,masses in zip(('CB','A','B'),treasuries,terms.annual_treasury):
        faces=tuple(map(amount,faces))
        if any(not face and mass for face,mass in zip(faces,masses)):
            raise ValueError('A coupon mass cannot outlive its actual principal.')
        annual=sum(masses,F(0))
        contractual,settled=coupon(F(1),100*annual,scale)
        lines.append(CouponLine('treasury',owner,sum(faces,F(0)),contractual,settled))
    for kind,owners,faces,rates in (
        ('mortgage',('HA','HB'),mortgages,terms.mortgage_rates_pct),
        ('iorb',('A','B'),reserves,(terms.iorb_rate_pct,)*2),
        ('cb_loan',('A','B'),cb_faces,terms.cb_rates_pct),
        ('rrp',('A','B'),rrp_faces,terms.rrp_rates_pct)):
        if len(faces)!=2:raise ValueError('Require two actual opening owner bases.')
        for owner,face,rate in zip(owners,faces,rates):
            face=amount(face)
            if face and rate is None:
                raise ValueError('Missing contractual '+kind+' coupon terms for '+owner)
            contractual,settled=coupon(face,rate if rate is not None else 0,scale)
            lines.append(CouponLine(kind,owner,face,contractual,settled))
    return tuple(lines)


def earnings_close(deferred, profit):
    """Zero modeled CB costs/dividends/surplus changes; not literal Fed timing."""
    deferred,profit=amount(deferred),_signed(profit)
    return max(F(0),deferred-profit),max(F(0),profit-deferred)


def cb_profit(lines):
    return sum((z.settled*(1 if z.kind in ('mortgage','cb_loan') or
                           (z.kind=='treasury' and z.owner=='CB') else
                           -1 if z.kind in ('iorb','rrp') else 0)
                for z in lines),F(0))


def validate_observations(terms,lines,*,treasuries,mortgages,scale,
                          opening_deferred,deferred):
    """Validate the complete current opening-basis snapshot, not its custody."""
    if type(lines) is not tuple or len(lines)!=11 or any(type(z) is not CouponLine for z in lines):
        raise ValueError('Missing public coupon obligation observations.')
    by={(z.kind,z.owner):z for z in lines}
    if len(by)!=11:raise ValueError('Duplicate public coupon obligation observations.')
    try:
        expected=quote(terms,treasuries=treasuries,mortgages=mortgages,
            reserves=tuple(by['iorb',b].basis for b in ('A','B')),
            cb_faces=tuple(by['cb_loan',b].basis for b in ('A','B')),
            rrp_faces=tuple(by['rrp',b].basis for b in ('A','B')),scale=scale)
    except KeyError as error:
        raise ValueError('Missing public coupon obligation identity.') from error
    if lines!=expected:
        raise ValueError('Public coupon observations differ from contractual opening bases.')
    if earnings_close(opening_deferred,cb_profit(lines))[0]!=deferred:
        raise ValueError('Deferred asset differs from paid public coupon obligations.')


def expected_payments(lines,opening_deferred):
    """Exact purpose/route/claim/amount multiset; no ledger import or posting."""
    payments=[]
    def add(payer,payee,value,kind,claim=None):
        if value<0:payer,payee,value=payee,payer,-value
        if value:payments.append((payer,payee,value,kind,claim))
    for z in lines:
        v=z.settled
        if z.kind=='treasury':
            add('Treasury','CB' if z.owner=='CB' else 'Bank'+z.owner,v,'treasury_coupon','Treasury:'+z.owner)
        elif z.kind=='mortgage':
            add(z.owner,'MortgagePool',v,'mortgage_coupon','mortgage:'+z.owner)
            add('MortgagePool','CB',v,'mbs_coupon','mortgage:'+z.owner)
        elif z.kind=='cb_loan':add('Bank'+z.owner,'CB',v,'cb_loan_coupon','cb_loan:'+z.owner)
        else:add('CB','Bank'+z.owner,v,z.kind+'_coupon',z.kind+':'+z.owner)
    add('CB','Treasury',earnings_close(opening_deferred,cb_profit(lines))[1],'cb_remittance')
    return tuple(payments)


def validate_payments(payments,lines,opening_deferred):
    actual=tuple((p.payer,p.payee,p.amount,p.kind,p.claim_id) for p in payments
                 if p.kind in PAYMENT_KINDS)
    if Counter(actual)!=Counter(expected_payments(lines,opening_deferred)):
        raise ValueError('Public receipt identities/amounts/coverage differ from coupon obligations.')
