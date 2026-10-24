"""Opt-in paid sales/hiring closure, not a qualified autonomous private planner.

Current information only. The private investment fallback is deliberately no
project until forecast/finance qualification is connected. Supplied project
units are an explicit research input, never an optimized or mandatory quota.
The stationary public-finance scenario is inherited, not generalized QE policy.
"""
from dataclasses import dataclass, replace
from fractions import Fraction as F
import math
from . import macro as m, ledger as l, households as h, pricing
from .numerics import ration
from .checkpoint import _paid_economy


def known_capital(state):
    """19 dated service stocks AFTER each opening's contractual aging/install."""
    if type(state) is not l.SectorState:
        raise TypeError('Require an immutable current ledger.')
    return tuple(sum((v.units for v in state.vintages if v.age+date+1<=15),F(0))
                 +(state.wip_units if date<=15 else 0) for date in range(19))


@dataclass(frozen=True)
class Prepared:
    opening: m.Envelope
    policy: m.Policy
    news: m.News
    source: m.Prepared
    orders: l.ProductionOrders
    forecast_residual: F
    forecast_services: F
    forecast_payroll: tuple
    private_planner_status: str='unqualified_no_project'


def prepare(opening,policy,news=m.News(),*,project_units=0):
    if type(opening) is not m.Envelope or type(policy) is not m.Policy or type(news) is not m.News:
        raise TypeError('Require immutable current-information inputs.')
    _paid_economy(opening)
    a,s=opening.macro,opening.sector
    if a.consumption_state_pct or a.deferred_consumption_units:
        raise ValueError('Legacy demand/backlog migration is not implemented; do not delete stocks.')
    units=l._number(project_units)
    if units%l.QUANTUM:
        raise ValueError('Project input must be on the physical order grid.')
    # Reuse the source public price/financial/credibility preparation, NOT its
    # old IS consumption, generated jobs, releases or structural orders.
    source=m.prepare(opening,policy,news,units,_quotes_only=True)
    try:
        multiplier=m.rational(math.exp(news.demand_shock_pct/100))
    except (OverflowError,ValueError) as error:
        raise ValueError('Demand preference impulse is not representable.') from error
    price=m.rational(source.price_index/100)
    trend=m.rational(source.trend)
    unit=s.scale*price;wage=unit*trend
    last=s.last
    previous=((20*s.scale,F(63,20)*s.scale) if last is None else
        (last.payroll_residual+last.dividend_residual+last.bank_dividend_to('HA'),
         last.payroll_focal+last.dividend_focal+last.bank_dividend_to('HB')))
    divs=((3*s.scale,F(3,20)*s.scale) if last is None else
          (last.dividend_residual+last.bank_dividend_to('HA'),
           last.dividend_focal+last.bank_dividend_to('HB')))
    old_workers=(F(17),F(3)) if last is None else (last.paid_residual_workers,last.paid_focal_workers)
    payroll=tuple(jobs*wage for jobs in old_workers)
    budgets=tuple(h.cash_stock_budget(opening_cash=s.deposit(owner),paid_wages=pay,
        previous_income=prior,forecast_income=pay+div,cash_ratio=ratio,
        demand_multiplier=multiplier).funded
        for owner,pay,prior,div,ratio in zip(('HA','HB'),payroll,previous,divs,(F(3,20),F(1,21))))
    cr=budgets[0]*F(363,400)/unit
    services=(budgets[0]*F(37,400)+budgets[1])/unit
    ar=F(20,17)*trend;af=F(5,3)*trend;v=F(5,16);chi=F(37,20)
    requested_r=(cr+chi*units)/ar
    requested_f=min(services,known_capital(s)[0]*v)/af
    lr,lf=ration(m.rational(a.workforce),requested_r,requested_f,quantum=l.QUANTUM)
    orders=replace(l.depth_orders(),market_clearing=True,price_factor=price,real_wage=trend,
        residual_workers=lr,focal_workers=lf,available_workers=m.rational(a.workforce),
        residual_productivity=ar,service_productivity=af,investment_units=units,
        residual_consumption=cr,service_a=budgets[0]*F(37,400)/unit,service_b=budgets[1]/unit,
        cash_floor_r=lr*trend,cash_floor_f=lf*trend,expected_dividends_nominal=divs,
        demand_multiplier=multiplier)
    source=replace(source,orders=orders)
    return Prepared(opening,policy,news,source,orders,cr,services,payroll,
                    'supplied_research_project' if units else 'unqualified_no_project')


def _validated(p):
    if (type(p) is not Prepared or type(p.orders) is not l.ProductionOrders or
            p!=prepare(p.opening,p.policy,p.news,project_units=p.orders.investment_units)):
        raise ValueError('Stale or inconsistent sales-driven preparation.')


def controls(p):
    """Authored ample-facility, consenting legacy-roll scenario; NOT approval.

    Only payroll shortfalls create opening working-credit requests. Project
    commitments reserve remaining opening capital headroom; the actual ledger
    may decline/cancel them. No project/operating maturity is silently rolled.
    """
    _validated(p)
    s=p.opening.sector;q=s.quarter+1;book=s.public_book
    if book is None:
        raise NotImplementedError('Require the stationary public-book scenario.')
    rolls=(book.treasuries[0],book.private_treasuries[0][0],book.private_treasuries[1][0])
    fiscal=l.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls))
    curve=pricing.policy_curve(m.rational(p.source.effective_rate_pct+m.P['normal_credit_spread_pct']),
                               m.rational(p.source.long_yield_pct+m.P['normal_credit_spread_pct']))
    unit=s.scale*p.orders.price_factor;quantum=s.scale*l.QUANTUM
    offers=[]
    for actor,bank,jobs in (('R','A',p.orders.residual_workers),('F','B',p.orders.focal_workers)):
        need=max(F(0),jobs*unit*p.orders.real_wage-s.deposit(actor))
        face=-(-need//quantum)*quantum
        if face:offers.append(pricing.operating_offer(bank,face,q,actor,curve))
    renewals=tuple(l.Renewal(z.id,z.face,z.rate_pct,q+48 if z.id=='L0' else q+4)
        for z in s.loans if z.maturity==q and not isinstance(z,(l.OperatingLoan,l.ProjectLoan)))
    commitment=None
    if p.orders.investment_units:
        risk=sum((z.face for z in s.loans if z.lender=='B'),F(0))
        gross=sum((z.face for z in offers if z.lender=='B'),F(0))
        room=max(F(0),s.bank_equity('B')/l.COVENANT-risk-gross)
        ceiling=(room//quantum)*quantum
        commitment=pricing.project_commitment('B',ceiling,curve)
    return l.Controls(household_mode='cash_stock_close_v1',facility_limits=(100*s.scale,100*s.scale),
        public_instructions=fiscal,new_loans=tuple(offers),renewals=renewals,
        project_commitment=commitment)


def execute(p,finance):
    _validated(p)
    if type(finance) is not l.Controls or finance.household_mode!='cash_stock_close_v1':
        raise ValueError('Sales-driven closure requires explicit closing-budget finance.')
    s=p.opening.sector;book=s.public_book
    if book is None:raise NotImplementedError('Require the stationary public-book scenario.')
    rolls=(book.treasuries[0],book.private_treasuries[0][0],book.private_treasuries[1][0])
    allowed=l.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls))
    if finance.public_instructions!=allowed or finance.asset_purchase_request or any(finance.asset_offers) or finance.security_bids is not None or book.rrp_claims:
        raise NotImplementedError('Full public QE/MBS/interest/RRP adapter remains unqualified.')
    out=l.advance_given_orders(s,p.orders,finance)
    if not out.ok:return m.Transition(False,p.opening,out.status,out.reason)
    return m._close_paid(p.source,out.state,closing_households=True)
