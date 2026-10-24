"""Current-information investment and conditional financing, NOT a GE forecast.

Quoted purchases are conditions, not promised household funds. Shadow finance
supports BankB/F private claims without opening BankB CB debt. Other cases stay
unknown. Public interest/liquidity/collateral and the other bank's future are not
forecast here; the single paid ledger still enforces every actual settlement.
"""
from dataclasses import dataclass, replace
from fractions import Fraction as F
from . import coupled as c, macro as m, ledger as l, pricing, prospectus as p
from .episodes import PolicyRule
from .numerics import coupon


def _curve(policy,credibility):
    effective=m.effective(policy.rate_pct)
    guided=m.effective(policy.rate_pct+credibility*(policy.guidance_pct-policy.rate_pct))
    weight=m.P['long_yield_current_rate_weight']
    long=weight*effective+(1-weight)*guided+m.P['initial_term_premium_pct']
    spread=m.P['normal_credit_spread_pct']
    return pricing.policy_curve(m.rational(effective+spread),m.rational(long+spread))


def _rates(curve):
    return (pricing.par_coupon((F(0),F(1)),curve[:2]),
            pricing.par_coupon((F(1,16),)*16,pricing.project_forward_gross(curve),coupon_at_issue=True))


@dataclass(frozen=True)
class Forecast:
    base: c.Prepared
    proposed_units: F
    units: F
    cells: tuple
    fallback_policy: m.Policy
    fulfilled_policy: m.Policy
    current_rates: tuple
    fallback_rates: tuple
    fulfilled_rates: tuple


def forecast(opening,policy,news=m.News()):
    base=c.prepare(opening,policy,news)
    a,s=opening.macro,opening.sector;o=base.orders
    grow=m.rational((1+a.growth_pct/100)**.25)
    price_grow=m.rational((1+a.expected_long_inflation_pct/100)**.25)
    capital=c.known_capital(s);v=o.capital_productivity
    deficit=max(F(0),base.forecast_services*grow/v-capital[1])
    proposed=-(-deficit//l.QUANTUM)*l.QUANTUM
    wage=s.scale*o.price_factor*o.real_wage
    risk_a=sum((z.face for z in s.loans if z.lender=='A'),F(0))
    credit_a=max(F(0),s.bank_equity('A')/l.COVENANT-risk_a)
    credit_a=(credit_a//(s.scale*l.QUANTUM))*(s.scale*l.QUANTUM)
    possible_r=min(m.rational(a.workforce)-o.focal_workers,
                   (s.deposit('R')+credit_a)/wage)
    room=max(F(0),(possible_r*o.residual_productivity-base.forecast_residual)/o.capital_resource_cost)
    units=min(proposed,(room//l.QUANTUM)*l.QUANTUM)
    fallback=PolicyRule('staff').resolve(opening)  # Once; never on fake future state.
    # The next decision observes THIS quarter's close, not next quarter's close.
    node_price=base.source.price_index
    node_inflation=100*(node_price/a.price_history[1]-1)
    node_gap=.72*a.output_gap_pct
    rate=m.round_quote(policy.guidance_pct+policy.inflation_sensitivity*(node_inflation-a.four_quarter_inflation_pct)
                       +policy.gap_sensitivity*(node_gap-a.output_gap_pct))
    fulfilled=m.Policy(rate,rate,1.5,.5)
    current=_curve(policy,a.credibility)
    # Closing-date valuation excludes the opening-to-current-closing interval.
    future=pricing.project_forward_gross(current)
    opportunity=future+(future[-1],)*2
    available=max(F(0),m.rational(a.workforce)-base.forecast_residual/o.residual_productivity)
    cells=[]
    for sign in (-1,1):
        for promise in (False,True):
            observed=fulfilled if promise else fallback
            signature='|'.join(str(m.rational(getattr(observed,key))) for key in
                ('rate_pct','guidance_pct','inflation_sensitivity','gap_sensitivity'))
            demand=tuple(base.forecast_services*grow**h*(1 if h==0 else
                         1+F(sign,100)*F(18,25)**(h-1)) for h in range(19))
            prices=tuple(s.scale*o.price_factor*price_grow**h for h in range(19))
            cells.append(p.ForecastCell(sign,promise,demand,capital,(available,)*19,
                tuple(o.service_productivity*grow**h for h in range(19)),prices,
                tuple(wage*(price_grow*grow)**h for h in range(19)),
                tuple(price*o.capital_resource_cost for price in prices),opportunity,
                observable_node=f'published-demand:{sign}/observed-policy:{signature}'))
    return Forecast(base,proposed,units,tuple(cells),fallback,fulfilled,
                    _rates(current),_rates(_curve(fallback,a.credibility)),
                    _rates(_curve(fulfilled,a.credibility)))


@dataclass(frozen=True)
class Claim:
    id: str
    face: F
    rate: F
    maturity: int
    kind: str
    allowance: F=F(0)
    candidate: bool=False


@dataclass(frozen=True)
class FinanceDate:
    date: int
    cash: F
    receipts: F
    payroll: F
    working_credit: F
    principal_paid: F
    project_principal_paid: F
    project_draw: F
    project_coupon: F
    operating_coupon: F
    bank_interest: F
    bank_equity: F
    opening_risk: F
    project_ceiling: F
    project_outstanding: F
    firm_dividend: F
    bank_dividend: F


@dataclass(frozen=True)
class Financing:
    demand_sign: int
    fulfilled: bool
    action: str
    complete: bool | None
    reason: str
    dates: tuple
    draw_probes: int=0
    opening_claim_count: int=0  # Sum of opening sizes, NOT every arithmetic visit.


def _assets(state,date,build,invoice):
    active=tuple(v for v in state.vintages if v.age+date+1<=15)
    depreciation=sum((v.basis/16 for v in active),F(0))
    basis=sum((v.basis*(14-v.age-date)/16 for v in active),F(0))
    if date<=15:
        depreciation+=state.wip_basis/16
        basis+=state.wip_basis*(15-date)/16
    if build is not None and date==build:basis+=invoice
    if build is not None and build<date<=build+16:
        depreciation+=invoice/16
        basis+=invoice*(16-(date-build))/16
    return depreciation,basis


def conditional_finance(f,cell,action,rows):
    """Conservative private quote given sales; no future actual executor calls.

    Future payroll credit is conditional on gross opening bank capital, never
    a promise to refinance principal. Project reservations exclude coupon income
    not yet earned. Same-face legacy consent is the inherited scenario, not a
    general right; typed operating/project claims always pay at maturity.
    """
    s=f.base.opening.sector;q=s.quarter+1
    unsupported=(any(z.bank=='B' for z in s.cb_loans) or
        any((z.lender=='B' and z.borrower!='F') or (z.borrower=='F' and z.lender!='B')
            or (z.borrower=='F' and not z.performing) for z in s.loans))
    def result(ok,reason,dates=(),probes=0,visits=0):
        return Financing(cell.demand_sign,cell.fulfilled,action,ok,reason,tuple(dates),probes,visits)
    if unsupported:return result(None,'unsupported_opening_finance')
    claims=[Claim(z.id,z.face,z.rate_pct,z.maturity-q,
        'project' if isinstance(z,l.ProjectLoan) else 'operating' if isinstance(z,l.OperatingLoan) else 'legacy',z.allowance)
        for z in s.loans if z.borrower=='F']
    def quote_id(stem):
        known={z.id for z in claims}
        while stem in known:stem='quote-'+stem
        return stem
    build={'NOW':0,'WAIT':1,'NEVER':None}[action]
    if not f.units:build=None
    cash=s.deposit('F');equity=s.bank_equity('B');quantum=s.scale*l.QUANTUM
    dates=[];probes=visits=0;invoice=F(0)
    for row in rows:
        date=row.date;opening_risk=sum((z.face for z in claims),F(0))
        visits+=len(claims)
        if any(z.maturity<date for z in claims):return result(False,'overdue_claim',dates,probes,visits)
        op_rate=(f.current_rates if date==0 else
                 (f.fulfilled_rates if cell.fulfilled else f.fallback_rates) if date==1 else f.fallback_rates)[0]
        working=-(-max(F(0),row.payroll-cash)//quantum)*quantum
        if working:
            if equity<=0 or equity<l.COVENANT*(opening_risk+working):
                return result(False,'operating_capital',dates,probes,visits)
            claims.append(Claim(quote_id(f'work-{date}'),working,op_rate,date+1,'operating'))
            cash+=working
        ceiling=max(F(0),equity/l.COVENANT-opening_risk-working)
        ceiling=(ceiling//quantum)*quantum if date==build else F(0)
        cash-=row.payroll
        if cash<0:return result(False,'payroll_cash',dates,probes,visits)
        cash+=row.receipts
        earned=op_coupon=principal=project_principal=F(0)
        pending=list(claims);coupon_paid=set()
        # At most two settlement events per opening claim: coupon and maturity.
        # A later same-date bank-paid coupon can fund an earlier cash-short due.
        for _ in range(2*len(pending)+1):
            progressed=False
            for claim in tuple(pending):
                if claim.id not in coupon_paid:
                    cp=coupon(claim.face,claim.rate,s.scale)[1]
                    if cp>cash:continue
                    cash-=cp;equity+=cp;earned+=cp;coupon_paid.add(claim.id)
                    if claim.kind=='operating':op_coupon+=cp
                    progressed=True
                if claim.maturity==date:
                    if claim.kind=='legacy':
                        if equity<=0 or equity<l.COVENANT*sum(z.face for z in claims):
                            return result(False,'legacy_renewal_capital',dates,probes,visits)
                        claims[claims.index(claim)]=replace(claim,id=quote_id('renewed-'+claim.id),
                            maturity=date+(48 if claim.id=='L0' else 4))
                    else:
                        if cash<claim.face:continue
                        cash-=claim.face;principal+=claim.face;equity+=claim.allowance
                        if claim.candidate:project_principal+=claim.face
                        claims.remove(claim)
                pending.remove(claim);progressed=True
            if not pending:break
            if not progressed:
                reason='mandatory_coupon' if any(z.id not in coupon_paid for z in pending) else 'mandatory_principal'
                return result(False,reason,dates,probes,visits)
        else:raise AssertionError('Finite conditional settlement bound exhausted.')
        draw=project_coupon=F(0)
        if date==build:
            # Waiting resources are a separate conditional feasibility check.
            residual_jobs=f.base.forecast_residual/f.base.orders.residual_productivity
            available=max(F(0),m.rational(f.base.opening.macro.workforce)-row.workers-residual_jobs)
            residual_productivity=(f.base.orders.residual_productivity*
                                   cell.labor_productivity[date]/f.base.orders.service_productivity)
            if f.units*f.base.orders.capital_resource_cost>available*residual_productivity:
                return result(False,'construction_resources',dates,probes,visits)
            invoice=row.construction
            rate=f.current_rates[1] if date==0 else (f.fulfilled_rates if cell.fulfilled else f.fallback_rates)[1]
            draw,n=l._minimum_project_draw(cash,invoice,row.payroll,ceiling,rate,s.scale)
            probes+=n
            if draw is None:return result(False,'project_funding',dates,probes,visits)
            risk=sum((z.face for z in claims),F(0))
            if draw and (equity<=0 or equity<l.COVENANT*(risk+draw)):
                return result(False,'project_capital',dates,probes,visits)
            faces=l._project_faces(draw,s.scale) if draw else ()
            for index,face in enumerate(faces,1):
                if face:claims.append(Claim(quote_id(f'candidate-{date}-{index}'),face,rate,date+index,'project',candidate=True))
            project_coupon=sum((coupon(face,rate,s.scale)[1] for face in faces),F(0))
            cash+=draw-invoice-project_coupon;equity+=project_coupon;earned+=project_coupon
            if cash<row.payroll or equity<0:return result(False,'project_settlement',dates,probes,visits)
        for claim in sorted((z for z in claims if z.kind=='operating'),key=lambda z:(z.maturity,z.id)):
            paid=(min(claim.face,max(F(0),cash-row.payroll))//quantum)*quantum
            if not paid:continue
            remaining=claim.face-paid;release=max(F(0),claim.allowance-remaining)
            cash-=paid;principal+=paid;equity+=release
            claims.remove(claim)
            if remaining:claims.append(replace(claim,face=remaining,allowance=claim.allowance-release))
        depreciation,basis=_assets(s,date,build,invoice)
        profit=row.receipts-row.payroll-depreciation-earned
        borrower_equity=cash+basis-sum((z.face for z in claims),F(0))
        dividend=(min(max(F(0),profit),max(F(0),cash-row.payroll),max(F(0),borrower_equity))//quantum)*quantum
        cash-=dividend
        if equity<0:return result(False,'bank_insolvency',dates,probes,visits)
        risk=sum((z.face for z in claims),F(0))
        bank_div=(min(max(F(0),earned),max(F(0),equity-l.COVENANT*risk))//quantum)*quantum
        equity-=bank_div
        dates.append(FinanceDate(date,cash,row.receipts,row.payroll,working,principal,
            project_principal,draw,project_coupon,op_coupon,earned,equity,opening_risk,ceiling,
            sum((z.face for z in claims if z.candidate),F(0)),dividend,bank_div))
    return result(True,'conditional_complete',dates,probes,visits)


@dataclass(frozen=True)
class Evaluation:
    forecast: Forecast
    cells: tuple
    quotation: p.Quotation
    financing: tuple
    financing_dates: int
    executor_calls: int=0


def evaluate(opening,policy,news=m.News()):
    f=forecast(opening,policy,news)
    physical=p.evaluate(f.cells,m.rational(opening.macro.credibility),units=f.units,
                        capital_productivity=f.base.orders.capital_productivity,
                        tolerance=opening.sector.scale*l.QUANTUM)
    cells=[];finances=[]
    for cell in f.cells:
        flags={}
        for action,flag in (('NEVER','baseline_ok'),('NOW','now_ok'),('WAIT','wait_ok')):
            rows=tuple(r for r in physical.rows if
                (r.demand_sign,r.fulfilled,r.action)==(cell.demand_sign,cell.fulfilled,action))
            case=conditional_finance(f,cell,action,rows)
            finances.append(case);flags[flag]=case.complete
        cells.append(replace(cell,**flags))
    # Only conditional admissibility changed; never rebuild/reprice physical rows.
    quoted=replace(physical,decision=p._decision(tuple(cells),physical.cells,
                                              opening.sector.scale*l.QUANTUM))
    attempted=sum(len(z.dates)+(1 if z.complete is False else 0) for z in finances)
    return Evaluation(f,tuple(cells),quoted,tuple(finances),attempted)


@dataclass(frozen=True)
class ForecastError:
    requested_units: F
    paid_units: F
    services: F
    payroll: F
    firm_cash: F | None


@dataclass(frozen=True)
class Adoption:
    plan: Evaluation
    transition: m.Transition
    error: ForecastError | None


def adopt(opening,policy,news=m.News()):
    plan=evaluate(opening,policy,news)
    units=plan.forecast.units if plan.quotation.decision.action=='NOW' else F(0)
    prepared=c.prepare(opening,policy,news,project_units=units)
    out=c.execute(prepared,c.controls(prepared))
    if not out.ok:return Adoption(plan,out,None)
    report=out.envelope.sector.last
    action='NOW' if units else 'NEVER'
    current=next(r for r in plan.quotation.rows if r.action==action and r.date==0)
    case=next(z for z in plan.financing if z.action==action)
    predicted=case.dates[0].cash if case.dates else None
    error=ForecastError(units,out.envelope.sector.wip_units,
        report.services-current.services,report.payroll_focal-current.payroll,
        None if predicted is None else out.envelope.sector.deposit('F')-predicted)
    return Adoption(plan,out,error)
