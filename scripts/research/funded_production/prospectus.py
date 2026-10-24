"""Bounded partial-equilibrium quotations, not paid paths or credit approvals.

Inputs must be declared current-information forecasts. Types cannot establish
their provenance. This pure table does not build forecasts from future states,
run an executor, choose hiring, underwrite a bank or settle any borrower wallet.
Conditional admission flags must come from a separate financing assessment.
"""
from dataclasses import dataclass
from fractions import Fraction as F
from .numerics import amount


def _vector(values, length, *, positive=False):
    if type(values) is not tuple or len(values)!=length:
        raise TypeError(f'Require an immutable {length}-date quote vector.')
    values=tuple(map(amount,values))
    if positive and any(x==0 for x in values):
        raise ValueError('This quote requires strictly positive levels/factors.')
    return values


@dataclass(frozen=True)
class ForecastCell:
    demand_sign: int
    fulfilled: bool
    demand: tuple
    known_capital: tuple
    workers: tuple
    labor_productivity: tuple
    service_price: tuple
    wage: tuple
    construction_cost: tuple
    forward_gross: tuple
    observable_node: str='next-release'
    baseline_ok: bool | None=None
    now_ok: bool | None=None
    wait_ok: bool | None=None

    def __post_init__(self):
        if type(self.demand_sign) is not int or self.demand_sign not in (-1,1):
            raise ValueError('Require a declared negative/positive demand signal.')
        if type(self.fulfilled) is not bool:
            raise TypeError('Promise fulfillment must be Boolean.')
        if type(self.observable_node) is not str or not self.observable_node:
            raise ValueError('Require an explicit next-observation group.')
        for n in ('baseline_ok','now_ok','wait_ok'):
            value=getattr(self,n)
            if value is not None and type(value) is not bool:
                raise TypeError('Conditional admission must be Boolean or unknown.')
        for n in ('demand','known_capital','workers','labor_productivity',
                  'service_price','wage','construction_cost','forward_gross'):
            object.__setattr__(self,n,_vector(getattr(self,n),18 if n=='forward_gross' else 19,
                positive=n in ('labor_productivity','service_price','wage','forward_gross')))


@dataclass(frozen=True)
class Row:
    demand_sign: int
    fulfilled: bool
    action: str
    date: int
    services: F
    workers: F
    receipts: F
    payroll: F
    construction: F
    operating_cash: F
    present_value: F


@dataclass(frozen=True)
class CellValue:
    demand_sign: int
    fulfilled: bool
    observable_node: str
    weight: F
    now_value: F
    wait_value: F


@dataclass(frozen=True)
class Decision:
    status: str
    action: str | None
    expected_now: F | None
    wait_value: F | None
    now_admissible: bool
    exercise: tuple=()


@dataclass(frozen=True)
class Quotation:
    rows: tuple
    cells: tuple
    decision: Decision
    scalar_rows: int=228
    executor_calls: int=0
    criterion: str='declared unlevered service value; zero salvage; conditional admission only'


def evaluate(cells,credibility,*,units,capital_productivity,tolerance=F(1,10**6)):
    """Quote four cells x three actions x 19 dates, with node-level exercise.

    Each vector is an explicit authored conditional quotation, NOT an actual
    future tape. Known capital must already include dated committed WIP and
    exclude this optional tranche. The whole invoice is units times the quoted
    per-unit construction cost. No proceeds/coupon/principal affect this score.
    All PVs are measured at current construction date zero, including WAIT.

    Admission flags assert conditional baseline/borrower/lender checks elsewhere;
    None never silently becomes approval. A positive-weight failed baseline is
    retained. Default observability groups all four cells; finer groups require
    evidence of information observable before WAIT exercise, not terminal IDs.
    """
    if type(cells) is not tuple or len(cells)!=4 or any(type(c) is not ForecastCell for c in cells):
        raise TypeError('Require exactly four immutable forecast cells.')
    if {(c.demand_sign,c.fulfilled) for c in cells}!={(-1,False),(-1,True),(1,False),(1,True)}:
        raise ValueError('Require each signal/promise cell exactly once.')
    credibility,units,v,tolerance=map(amount,(credibility,units,capital_productivity,tolerance))
    if credibility>1 or v==0:
        raise ValueError('Require credibility in [0,1] and positive capital productivity.')
    rows=[];values=[]
    for c in cells:
        discount=F(1);discounts=[discount]
        for gross in c.forward_gross:
            discount/=gross
            discounts.append(discount)
        totals={}
        for action,start in (('NOW',0),('WAIT',1),('NEVER',None)):
            total=F(0)
            for h in range(19):
                extra=units if start is not None and start+1<=h<=start+16 else F(0)
                service=min(c.demand[h],v*(c.known_capital[h]+extra),
                            c.labor_productivity[h]*c.workers[h])
                labor=service/c.labor_productivity[h]
                receipts,payroll=service*c.service_price[h],labor*c.wage[h]
                construction=units*c.construction_cost[h] if h==start else F(0)
                cash=receipts-payroll-construction
                pv=cash*discounts[h]
                rows.append(Row(c.demand_sign,c.fulfilled,action,h,service,labor,
                                receipts,payroll,construction,cash,pv))
                total+=pv
            totals[action]=total
        weight=(credibility if c.fulfilled else 1-credibility)/2
        values.append(CellValue(c.demand_sign,c.fulfilled,c.observable_node,weight,
                     totals['NOW']-totals['NEVER'],totals['WAIT']-totals['NEVER']))
    return Quotation(tuple(rows),tuple(values),_decision(cells,values,tolerance))


def _decision(cells,values,tolerance):
    """Internal reducer for the same physical cells with updated admission only."""
    active=tuple((c,z) for c,z in zip(cells,values) if z.weight)
    if any(c.baseline_ok is False for c,z in active):
        decision=Decision('baseline_incomplete',None,None,None,False)
    elif any(getattr(c,n) is None for c,z in active for n in ('baseline_ok','now_ok','wait_ok')):
        decision=Decision('admission_incomplete',None,None,None,False)
    else:
        now_ok=all(c.now_ok for c,z in active)
        now=sum((z.weight*z.now_value for c,z in active),F(0)) if now_ok else None
        groups={}
        for c,z in active:
            groups.setdefault(c.observable_node,[]).append((c,z))
        wait=F(0);exercise=[]
        for node,members in groups.items():
            mass=sum(z.weight for c,z in members)
            weighted=sum((z.weight*z.wait_value for c,z in members),F(0))
            take=all(c.wait_ok for c,z in members) and weighted/mass>tolerance
            exercise.append((node,take))
            if take: wait+=weighted
        # An ineligible sub-tolerance option cannot veto an eligible investment.
        if now is not None and now>tolerance and (wait<=tolerance or now>wait+tolerance): action='NOW'
        elif wait>tolerance: action='WAIT'
        else: action='NEVER'
        decision=Decision('quoted_choice',action,now,wait,now_ok,tuple(exercise))
    return decision
