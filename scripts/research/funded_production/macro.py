"""Private source-feedback integration; not the adopted/native game.

Actual production is executed by the offline ledger, never Core.step/post-patched.
Only stationary same-face public Treasury rolls are supported in this section.
Fixed structural consumption targets and supplied investment are not utility or
project optima. Growing finance, full public adapter and distress resolution are
still required before adoption. No GUI/native/network work occurs here.
"""
from dataclasses import dataclass, replace, fields
from fractions import Fraction as F
import math
from . import ledger
from . import source_data

SOURCE = source_data.MODEL_DIR
SOURCE_PARAMETERS_SHA256 = source_data.SOURCE_PARAMETERS_SHA256
SOURCE_CORE_SHA256 = source_data.SOURCE_CORE_SHA256
P = source_data.load_parameters()


def finite(x):
    if isinstance(x, bool) or not isinstance(x, (int,float,F)) or not math.isfinite(x):
        raise ValueError('Require a finite numeric scalar, not Boolean.')
    return float(x)


def rational(x):
    return F(str(finite(x)))


def grid(x):
    x=finite(x); inc=P['minimum_rate_increment_pct']
    if abs(x/inc-round(x/inc))>1e-6: raise ValueError('Policy quotes require the 1bp grid.')
    return x


def effective(rate):
    scale=P['negative_rate_efficacy_scale_pct']
    return rate if rate>=0 else scale*math.tanh(rate/scale)


def round_quote(x):
    # Godot roundf uses half away from zero; Python round ties-to-even differs.
    inc=P['minimum_rate_increment_pct']; u=rational(x)/rational(inc)
    # Decimal quote identity prevents binary .005 from losing half a tick.
    whole=(abs(u)+F(1,2))//1
    return float((-whole if u<0 else whole)*rational(inc))


@dataclass(frozen=True)
class Policy:
    rate_pct: float
    guidance_pct: float
    inflation_sensitivity: float=0
    gap_sensitivity: float=0
    def __post_init__(self):
        for n in ('rate_pct','guidance_pct'): object.__setattr__(self,n,grid(getattr(self,n)))
        for n in ('inflation_sensitivity','gap_sensitivity'):
            x=finite(getattr(self,n))
            if not 0<=x<=P['guidance_sensitivity_limit']: raise ValueError('Invalid conditional sensitivity.')
            object.__setattr__(self,n,x)


@dataclass(frozen=True)
class News:
    demand_shock_pct: float=0
    supply_innovation_pct: float=0
    r_star_change_pct: float=0
    r_star_reference_change_pct: float=0
    structural_unemployment_change_pct: float=0
    def __post_init__(self):
        for f in fields(self): object.__setattr__(self,f.name,finite(getattr(self,f.name)))


@dataclass(frozen=True)
class Macro:
    quarter: int=0
    price_index: float=100
    price_history: tuple=()
    annualized_quarterly_inflation_pct: float=2
    four_quarter_inflation_pct: float=2
    expected_short_inflation_pct: float=2
    expected_long_inflation_pct: float=2
    credibility: float=.85
    inflation_miss_memory_pct: float=0
    public_support: float=70
    public_hardship_memory: float=0
    unemployment_rate_pct: float=4.5
    structural_unemployment_pct: float=4.5
    workforce: float=4000/191
    actual_output_index: float=100
    potential_output_index: float=100
    physical_max_output_index: float=100
    output_gap_pct: float=0
    annualized_actual_growth_pct: float=0
    annualized_potential_growth_pct: float=0
    growth_pct: float=2
    productivity_trend: float=1
    r_star_pct: float=1.5
    r_star_reference_pct: float=1.5
    supply_pressure_pct: float=0
    financial_restraint_pct: float=0
    consumption_state_pct: float=0
    deferred_consumption_units: float=0
    guidance_active: bool=False
    prior_policy: Policy=Policy(3.5,3.5)
    guidance_reference_inflation_pct: float=2
    guidance_reference_gap_pct: float=0
    def __post_init__(self):
        if type(self.quarter) is not int or self.quarter<0: raise ValueError('Invalid quarter.')
        if type(self.guidance_active) is not bool or type(self.prior_policy) is not Policy: raise ValueError('Invalid guidance state.')
        for f in fields(self):
            if f.name not in ('quarter','price_history','guidance_active','prior_policy'):
                object.__setattr__(self,f.name,finite(getattr(self,f.name)))
        h=tuple(finite(x) for x in self.price_history)
        if len(h)!=5 or any(x<=0 for x in h) or h[-1]!=self.price_index: raise ValueError('Require five coherent positive prices.')
        object.__setattr__(self,'price_history',h)
        if not 0<=self.credibility<=1 or not 0<self.structural_unemployment_pct<100 or not 0<=self.unemployment_rate_pct<=100: raise ValueError('Invalid confidence/labor shares.')
        if self.growth_pct<=-100 or any(getattr(self,n)<=0 for n in ('price_index','workforce','productivity_trend','actual_output_index','potential_output_index','physical_max_output_index')): raise ValueError('Positive levels/gross growth required.')
        if any(getattr(self,n)<=-100 for n in ('annualized_quarterly_inflation_pct','four_quarter_inflation_pct','expected_short_inflation_pct','expected_long_inflation_pct')): raise ValueError('Positive gross price rates required.')
        if self.deferred_consumption_units<0 or self.inflation_miss_memory_pct<0 or self.public_hardship_memory<0 or not 0<=self.public_support<=100: raise ValueError('Invalid stock or support.')


@dataclass(frozen=True)
class Envelope:
    macro: Macro
    sector: ledger.SectorState
    version: int=1
    def __post_init__(self):
        if type(self.version) is not int or self.version!=1: raise ValueError('Unsupported envelope version.')
        if type(self.macro) is not Macro or type(self.sector) is not ledger.SectorState or self.macro.quarter!=self.sector.quarter: raise ValueError('Macro/ledger quarter mismatch.')


def frontier(workers,a_r,a_f,v,capital):
    # Linear physical technology; no output inferred from mere unused capital.
    l_f=min(workers,capital*v/a_f) if a_f>a_r else 0
    return a_r*(workers-l_f)+min(a_f*l_f,capital*v)


def initial(scale=1,growth=2):
    rate=P['initial_inflation_rate_pct']; price=P['initial_price_index']
    h=tuple(price/(1+rate/100)**(age/4) for age in range(4,-1,-1))
    a=Macro(price_history=h,growth_pct=growth,
            physical_max_output_index=4*frontier(4000/191,20/17,5/3,5/16,16))
    return Envelope(a,ledger.initial_depth_reference(scale))


@dataclass(frozen=True)
class Prepared:
    opening: Envelope
    policy: Policy
    news: News
    orders: ledger.ProductionOrders
    price_index: float
    supply_pressure: float
    r_star: float
    r_star_reference: float
    trend: float
    structural_u: float
    effective_rate_pct: float
    long_yield_pct: float
    financial_restraint: float
    stance_adequacy: float
    followthrough: float
    consumption_state: float
    reference_consumption: float
    underlying_consumption: float
    release_units: float


def prepare(envelope,policy,news=News(),investment_units=F(1),*,_quotes_only=False):
    if type(envelope) is not Envelope or type(policy) is not Policy or type(news) is not News: raise TypeError('Require immutable current-information inputs.')
    if isinstance(envelope.sector.public_book,ledger.PublicIncomeBook):
        raise NotImplementedError('Public-income macro preparation remains unqualified.')
    if type(_quotes_only) is not bool:raise TypeError('Quote-only selection must be Boolean.')
    investment_units=ledger._number(investment_units)
    a=envelope.macro; s=envelope.sector; cred=a.credibility
    supply=P['supply_pressure_persistence']*a.supply_pressure_pct+news.supply_innovation_pct
    reference=a.r_star_reference_pct+news.r_star_reference_change_pct
    rstar=reference+P['r_star_reversion_persistence']*(a.r_star_pct-a.r_star_reference_pct)+news.r_star_change_pct
    u=a.structural_unemployment_pct+news.structural_unemployment_change_pct
    if not 0<u<100: raise ValueError('Invalid structural unemployment.')
    trend=a.productivity_trend*(1+a.growth_pct/100)**.25
    e=effective(policy.rate_pct); eg=effective(policy.rate_pct+cred*(policy.guidance_pct-policy.rate_pct))
    cw=P['long_yield_current_rate_weight']; sw=P['real_rate_short_weight']; premium=P['initial_term_premium_pct']
    long=cw*e+(1-cw)*eg+premium
    # Stationary public program only. Local access/solvency wedges are NOT
    # duplicated here; they act through actual sector credit and paid activity.
    spot=sw*(e-a.expected_short_inflation_pct)+(1-sw)*(long-premium-a.expected_long_inflation_pct)-rstar
    restraint=P['real_rate_gap_persistence']*a.financial_restraint_pct+(1-P['real_rate_gap_persistence'])*spot
    target=P['policy_inflation_response']*(a.four_quarter_inflation_pct-P['inflation_target_pct'])+P['policy_output_gap_response']*a.output_gap_pct
    scale=P['negative_rate_efficacy_scale_pct']; floor_guide=effective(policy.guidance_pct) if cred==1 else -scale
    floor_long=-cw*scale+(1-cw)*floor_guide+premium
    floor_spot=sw*(-scale-a.expected_short_inflation_pct)+(1-sw)*(floor_long-premium-a.expected_long_inflation_pct)-rstar
    loading=sw+(1-sw)*(cw+(1-cw)*(1-cred)); distance=abs(spot-target)
    best=distance if loading==0 else max(0,floor_spot-target)
    tol=P['credibility_stance_scale_pct']; adequacy=math.exp(-max(0,distance-best)/tol)*tol/(tol+best)
    commitment=policy.rate_pct
    if a.guidance_active:
        old=a.prior_policy
        commitment=round_quote(old.guidance_pct+old.inflation_sensitivity*(a.four_quarter_inflation_pct-a.guidance_reference_inflation_pct)+old.gap_sensitivity*(a.output_gap_pct-a.guidance_reference_gap_pct))
    follow=math.exp(-abs(policy.rate_pct-commitment)/P['credibility_followthrough_tolerance_pct']) if a.guidance_active else 1
    base=P['inflation_persistence']*(1+a.annualized_quarterly_inflation_pct/100)+(1-P['inflation_persistence'])*(1+a.expected_short_inflation_pct/100)
    price=a.price_index*(base*math.exp((P['inflation_output_gap_sensitivity']*a.output_gap_pct+P['inflation_supply_sensitivity']*supply)/(100+P['inflation_target_pct'])))**.25
    if _quotes_only:
        # Private source quote extraction, not a legacy executable preparation.
        # Avoid even evaluating the discarded IS/employment/backlog machinery.
        return Prepared(envelope,policy,news,ledger.depth_orders(),price,supply,rstar,
                        reference,trend,u,e,long,restraint,adequacy,follow,0,0,0,0)
    # Authored consumption sensitivity, distinct from identified aggregate IS.
    x=P['output_gap_persistence']*a.consumption_state_pct-.12*restraint+news.demand_shock_pct-P['supply_output_gap_sensitivity']*supply
    reference_c=18.15*trend; underlying=reference_c*math.exp(x/100)
    stock=a.deferred_consumption_units; stock_pct=100*stock/reference_c
    release_fraction=(P['demand_release_base_fraction']+(P['demand_release_max_fraction']-P['demand_release_base_fraction'])*stock_pct/(P['demand_release_backlog_scale_pct']+stock_pct))/(1+(max(0,restraint)/P['demand_release_financing_scale_pct'])**2)
    release=stock*release_fraction; cr=underlying+release; services=5*trend
    capital=float(sum(v.units for v in s.vintages if v.age<15)+s.wip_units)
    ar=20/17*trend; af=5/3*trend; v=5/16; chi=1.85
    potential=frontier(a.workforce*(1-u/100),ar,af,v,capital)
    desired_y=cr+chi*float(investment_units)+services; gap=100*(desired_y/potential-1)
    labor_u=u*math.exp(-P['unemployment_gap_sensitivity']*gap/u) if gap>=0 else 100-(100-u)*math.exp(P['unemployment_gap_sensitivity']*gap/(100-u))
    planned_u=a.unemployment_rate_pct+(1-P['unemployment_gap_persistence'])*(labor_u-a.unemployment_rate_pct)
    jobs=a.workforce*(1-planned_u/100); needed_r=(cr+chi*float(investment_units))/ar; needed_f=services/af
    lr=jobs*needed_r/(needed_r+needed_f); lf=jobs*needed_f/(needed_r+needed_f)
    orders=replace(ledger.depth_orders(),market_clearing=True,price_factor=rational(price/100),real_wage=rational(trend),residual_workers=rational(lr),focal_workers=rational(lf),available_workers=rational(a.workforce),residual_productivity=rational(ar),service_productivity=rational(af),investment_units=investment_units,residual_consumption=rational(cr),service_a=rational(services*37/100),service_b=rational(services*63/100),cash_floor_r=rational(lr*trend),cash_floor_f=rational(lf*trend))
    return Prepared(envelope,policy,news,orders,price,supply,rstar,reference,trend,u,e,long,restraint,adequacy,follow,x,reference_c,underlying,release)


def stationary_controls(envelope,p):
    """Disclosed ample-facility/consenting same-face-roll test scenario.

    Not an optimal lender/project policy or an assumption of automatic real-world
    finance. New working loans are actually underwritten/funded by the ledger.
    """
    if p.opening!=envelope: raise ValueError('Stale preparation.')
    a=envelope.sector; book=a.public_book; q=a.quarter+1; s=a.scale
    rolls=(book.treasuries[0],book.private_treasuries[0][0],book.private_treasuries[1][0])
    pi=ledger.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls))
    unit=s*p.orders.price_factor; quantum=s*ledger.QUANTUM; offers=[]
    for actor,bank,workers in (('R','A',p.orders.residual_workers),('F','B',p.orders.focal_workers)):
        short=max(F(0),workers*unit*p.orders.real_wage-a.deposit(actor)); face=-(-short//quantum)*quantum
        if face: offers.append(ledger.LoanOffer(bank,face,rational(p.long_yield_pct+P['normal_credit_spread_pct']),q+3,borrower=actor))
    renewals=tuple(ledger.Renewal(l.id,l.face,l.rate_pct,q+48 if l.id=='L0' else q+4) for l in a.loans if l.maturity==q)
    return ledger.Controls(public_instructions=pi,facility_limits=(100*s,100*s),new_loans=tuple(offers),renewals=renewals)


@dataclass(frozen=True)
class Transition:
    ok: bool
    envelope: Envelope
    status: str
    reason: str=''
    paid_release_units: float=0
    committed_calls: int=1


def execute(p,controls):
    if type(p) is not Prepared or type(controls) is not ledger.Controls: raise TypeError('Require prepared inputs and explicit finance.')
    if type(p.orders) is not ledger.ProductionOrders or p != prepare(p.opening,p.policy,p.news,p.orders.investment_units):
        raise ValueError('Inconsistent preparation; recompute from current immutable inputs.')
    if controls.household_mode != 'fixed':
        raise NotImplementedError('This section requires fixed structural household targets; wealth-mode macro mapping remains unimplemented.')
    a=p.opening.macro; state=p.opening.sector; book=state.public_book
    rolls=(book.treasuries[0],book.private_treasuries[0][0],book.private_treasuries[1][0])
    allowed=ledger.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls))
    if controls.public_instructions!=allowed or controls.asset_purchase_request or any(controls.asset_offers) or controls.security_bids is not None or book.rrp_claims:
        raise NotImplementedError('This macro section supports stationary same-face Treasury rolls only; full public adapter is not yet qualified.')
    out=ledger.advance_given_orders(state,p.orders,controls)
    if not out.ok: return Transition(False,p.opening,out.status,out.reason)
    return _close_paid(p,out.state)


def _close_paid(p,b,*,closing_households=False):
    """Paid-output closure; each caller validates its own prepared program."""
    a=p.opening.macro; r=b.last; output=4*float(r.real_output)
    if output<=0: return Transition(False,p.opening,'terminal_crisis','Zero paid GDP; economic crisis successor remains required.')
    orders=p.orders; capital=float(b.capital_units)
    potential=4*frontier(a.workforce*(1-p.structural_u/100),float(orders.residual_productivity),float(orders.service_productivity),float(orders.capital_productivity),capital)
    maximum=4*frontier(a.workforce,float(orders.residual_productivity),float(orders.service_productivity),float(orders.capital_productivity),capital)
    unemployment=100*(1-float(r.paid_residual_workers+r.paid_focal_workers)/a.workforce)
    h=(*a.price_history[1:],p.price_index); four=100*(h[-1]/h[0]-1); inflation_scale=100+P['inflation_target_pct']; cred=a.credibility
    anchor=P['short_expectation_anchor_weight']*cred
    recent=(1-anchor)*(1+a.four_quarter_inflation_pct/100)+anchor*(1+a.expected_long_inflation_pct/100)
    expected_short=100*(((1-P['short_expectation_recent_weight'])*(1+a.expected_short_inflation_pct/100)+P['short_expectation_recent_weight']*recent)*math.exp(P['short_expectation_supply_sensitivity']*p.supply_pressure/inflation_scale)-1)
    long_anchor=cred*P['inflation_target_pct']+(1-cred)*a.four_quarter_inflation_pct
    expected_long=a.expected_long_inflation_pct+P['long_expectation_adjustment']*(long_anchor-a.expected_long_inflation_pct)
    miss=P['credibility_miss_persistence']*a.inflation_miss_memory_pct+(1-P['credibility_miss_persistence'])*abs(a.four_quarter_inflation_pct-P['inflation_target_pct'])
    score=.4*math.exp(-miss/P['credibility_miss_tolerance_pct'])+.4*p.stance_adequacy+.2*p.followthrough
    closing_cred=max(0,min(1,cred+P['credibility_adjustment']*(score-cred)))
    hardship=P['public_inflation_burden_weight']*abs(four-P['inflation_target_pct'])+P['public_unemployment_burden_weight']*max(0,unemployment-p.structural_u)
    memory=P['public_hardship_memory_persistence']*a.public_hardship_memory+(1-P['public_hardship_memory_persistence'])*hardship
    support_target=max(0,min(100,P['public_support_base']-hardship-P['public_hardship_memory_weight']*memory))
    paid_release=0 if closing_households else min(p.release_units,max(0,float(r.residual_consumption)-p.underlying_consumption))
    backlog=0 if closing_households else (1-P['demand_cancellation_fraction'])*a.deferred_consumption_units-paid_release+P['deferred_demand_share']*max(0,p.reference_consumption-float(r.residual_consumption))
    macro=replace(a,quarter=b.quarter,price_index=p.price_index,price_history=h,annualized_quarterly_inflation_pct=100*((p.price_index/a.price_index)**4-1),four_quarter_inflation_pct=four,expected_short_inflation_pct=expected_short,expected_long_inflation_pct=expected_long,credibility=closing_cred,inflation_miss_memory_pct=miss,public_support=a.public_support+P['public_support_adjustment']*(support_target-a.public_support),public_hardship_memory=memory,unemployment_rate_pct=unemployment,structural_unemployment_pct=p.structural_u,actual_output_index=output,potential_output_index=potential,physical_max_output_index=maximum,output_gap_pct=100*(output/potential-1),annualized_actual_growth_pct=100*((output/a.actual_output_index)**4-1),annualized_potential_growth_pct=100*((potential/a.potential_output_index)**4-1),productivity_trend=p.trend,r_star_pct=p.r_star,r_star_reference_pct=p.r_star_reference,supply_pressure_pct=p.supply_pressure,financial_restraint_pct=p.financial_restraint,consumption_state_pct=0 if closing_households else p.consumption_state,deferred_consumption_units=backlog,guidance_active=True,prior_policy=p.policy,guidance_reference_inflation_pct=a.four_quarter_inflation_pct,guidance_reference_gap_pct=a.output_gap_pct)
    return Transition(True,Envelope(macro,b),'ok',paid_release_units=paid_release)
