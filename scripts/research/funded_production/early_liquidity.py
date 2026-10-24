"""Conditional early-credit arithmetic, not bank approval or another ledger.

Same-counterparty atomic novation retires old due face without gross reserve
circulation. Refinancing and new advances share one declared gross limit. Only
original nonhousehold coupon-prefix cash needs justify an additional advance.
Positive current equity is a disclosed authored eligibility rule; capacity is a
caller-asserted haircut value, never a claim of actual Reserve Bank eligibility.
"""
from dataclasses import dataclass, fields, replace
from fractions import Fraction as F
from . import public_funding as funding, public_income as income

ZERO=F(0)
QUANTUM=F(1,10**6)
BANKS=('A','B')
_IDENTITIES=(('treasury','CB'),('treasury','A'),('treasury','B'),
             ('mortgage','HA'),('mortgage','HB'),('iorb','A'),('iorb','B'),
             ('cb_loan','A'),('cb_loan','B'),('rrp','A'),('rrp','B'))


class PlanFailure(ValueError):
    """Declared conditional funding failure or missing applicable contract."""
    def __init__(self,status,reason):
        super().__init__(reason)
        self.status=status


@dataclass(frozen=True,kw_only=True)
class EarlyPlan:
    scale:F
    reserves:tuple
    old_faces:tuple
    equities:tuple
    capacities:tuple
    facility_limits:tuple
    cb_rates_pct:tuple
    tga:F
    observations:tuple
    refinanced:tuple
    cash_repayments:tuple
    peak_needs:tuple
    advances:tuple
    gross_used:tuple
    replacement_faces:tuple
    credit_reserves:tuple
    coupon_reserves:tuple
    coupon_tga:F


RECORD_TYPES=(EarlyPlan,income.CouponLine)


def ordered_nonhousehold(observations):
    """The fixed public calendar, excluding wages, HH coupons and remittance."""
    selected=tuple(z for z in observations if z.kind!='mortgage')
    treasury=tuple(z for z in selected if z.kind=='treasury')
    other=tuple(z for z in selected if z.kind!='treasury')
    def outflow(z):
        return ((z.kind in ('iorb','rrp') and z.settled>0)
                or (z.kind=='cb_loan' and z.settled<0))
    return treasury+tuple(z for z in other if outflow(z))+tuple(z for z in other if not outflow(z))


def plan(*,scale,reserves,old_faces,equities,capacities,facility_limits,cb_rates_pct,tga,observations):
    """Return conditional balances only; zero executor/transaction calls.

    Original eleven observations are frozen inputs. Nothing here reprices them
    on refinanced face or newly created reserves. No pre-coupon asset sale,
    TGA credit, future remittance or household-deposit addition is permitted.
    """
    funding.validate_records((scale,reserves,old_faces,equities,capacities,
        facility_limits,cb_rates_pct,tga,observations),RECORD_TYPES)
    scale=funding._number(scale)
    if not scale:raise ValueError('Require a positive nominal scale.')
    quantum=scale*QUANTUM
    reserves=funding._vector(reserves,2,'Actual conditional reserves')
    old_faces=funding._vector(old_faces,2,'Old CB face')
    equities=funding._vector(equities,2,'Current conditional equity',signed=True)
    capacities=funding._vector(capacities,2,'Haircut collateral capacity')
    facility_limits=funding._vector(facility_limits,2,'Shared gross facility limit')
    cb_rates_pct=funding._vector(cb_rates_pct,2,'Explicit CB rates',signed=True,optional=True)
    tga=funding._number(tga)
    if any(value%quantum for value in facility_limits):
        raise ValueError('Facility offers require whole money quanta.')
    if (type(observations) is not tuple or len(observations)!=11
            or any(type(z) is not income.CouponLine for z in observations)
            or tuple((z.kind,z.owner) for z in observations)!=_IDENTITIES):
        raise ValueError('Require the eleven exact original coupon identities.')
    for z in observations:replace(z)
    if tuple(z.basis for z in observations[7:9])!=old_faces:
        raise ValueError('Original CB coupon bases must match the old due faces.')
    refinanced=tuple((min(face,limit,capacity)//quantum)*quantum if eq>0 else ZERO
        for face,limit,capacity,eq in zip(old_faces,facility_limits,capacities,equities))
    cash=tuple(face-refi for face,refi in zip(old_faces,refinanced))
    for refi,rate in zip(refinanced,cb_rates_pct):
        if refi and rate is None:
            raise PlanFailure('unsupported_public_income','CB refinancing lacks explicit coupon terms.')
    after=tuple(reserve-pay for reserve,pay in zip(reserves,cash))
    if any(value<0 for value in after):
        raise PlanFailure('funding_failure','Maturing CB principal has no funded repayment/refinance offer.')
    running=list(after);minimum=list(after);closing_tga=tga
    for z in ordered_nonhousehold(observations):
        if z.kind=='treasury':
            closing_tga-=z.settled
            if closing_tga<0:
                raise PlanFailure('funding_failure','Treasury coupon exceeds actual TGA funding.')
            if z.owner=='CB':continue
        index=BANKS.index(z.owner)
        running[index]+=z.settled*(-1 if z.kind=='cb_loan' else 1)
        minimum[index]=min(minimum[index],running[index])
    needs=tuple(max(ZERO,-value) for value in minimum)
    advances=tuple(-(-value//quantum)*quantum for value in needs)
    gross=tuple(refi+advance for refi,advance in zip(refinanced,advances))
    for advance,used,capacity,limit,eq,rate in zip(
            advances,gross,capacities,facility_limits,equities,cb_rates_pct):
        if advance and rate is None:
            raise PlanFailure('unsupported_public_income','New CB credit lacks explicit coupon terms.')
        if (advance and eq<=0) or used>capacity or used>limit:
            raise PlanFailure('funding_failure','Early credit lacks positive equity, pledged capacity or shared gross room.')
    return EarlyPlan(scale=scale,reserves=reserves,old_faces=old_faces,equities=equities,
        capacities=capacities,facility_limits=facility_limits,cb_rates_pct=cb_rates_pct,
        tga=tga,observations=observations,refinanced=refinanced,cash_repayments=cash,
        peak_needs=needs,advances=advances,gross_used=gross,replacement_faces=gross,
        credit_reserves=tuple(a+b for a,b in zip(after,advances)),
        coupon_reserves=tuple(a+b for a,b in zip(running,advances)),coupon_tga=closing_tga)


def validate_plan(value):
    """Recompute an exact closed plan before equality; consistency, not custody."""
    funding.validate_records(value,RECORD_TYPES)
    if type(value) is not EarlyPlan:raise TypeError('Require the exact immutable EarlyPlan.')
    expected=plan(**{name:getattr(value,name) for name in (
        'scale','reserves','old_faces','equities','capacities','facility_limits',
        'cb_rates_pct','tga','observations')})
    def signature(item):
        cls=type(item)
        if cls is tuple:return cls,tuple(signature(x) for x in item)
        if cls is F:return cls,item.numerator,item.denominator
        if cls is EarlyPlan or cls is income.CouponLine:
            return cls,tuple((f.name,signature(object.__getattribute__(item,f.name))) for f in fields(cls))
        return cls,item
    if signature(value)!=signature(expected):
        raise ValueError('Stale or altered conditional early-credit plan.')
