"""Actual paid operating flows, not shareholder value or invented terminal cash."""
from dataclasses import dataclass
from fractions import Fraction as F
from . import episodes as x
from . import macro as m
from . import pricing as market


@dataclass(frozen=True)
class OperatingFlow:
    receipts: F
    wages: F
    capex: F
    @property
    def net(self):return self.receipts-self.wages-self.capex


def operating_flow(step):
    if type(step) is not x.Step:raise TypeError('Require an actual immutable project execution Step.')
    r=step.envelope.sector.last;unit=step.envelope.sector.scale*step.prepared.orders.price_factor
    totals={'services':F(0),'focal_payroll':F(0),'investment':F(0)}
    for p in r.payments:
        if p.kind not in totals:continue
        valid=(p.kind=='services' and p.payer in ('HA','HB') and p.payee=='F') or (p.kind=='focal_payroll' and (p.payer,p.payee)==('F','HB')) or (p.kind=='investment' and (p.payer,p.payee)==('F','R'))
        if not valid:raise ValueError('Operating payment has an unidentified counterparty.')
        totals[p.kind]+=p.amount
    if (totals['services'],totals['focal_payroll'],totals['investment'])!=(r.services*unit,r.payroll_focal,r.investment*unit):
        raise ValueError('Paid operating cashflow does not reconcile to actual report quantities.')
    return OperatingFlow(totals['services'],totals['focal_payroll'],totals['investment'])


def present_value(flows,forward_gross):
    if type(flows) is not tuple or type(forward_gross) is not tuple:raise TypeError('Require immutable complete cashflow and forward vectors.')
    cash=tuple(m.ledger._number(v,signed=True) for v in flows)
    curve=tuple(m.ledger._number(v) for v in forward_gross)
    # Qualified helper validates lengths, nonempty vectors and positive gross.
    positive=tuple(max(F(0),v) for v in cash);negative=tuple(max(F(0),-v) for v in cash)
    return market.price_cashflows(positive,curve)-market.price_cashflows(negative,curve)
