"""Authored finite-horizon operating-value choice, NOT shareholder NPV/welfare.

Zero post-horizon value is a scoring convention, never a terminal book change.
Forecast scenarios are supplied from current information, not actual future RNG.
"""
from dataclasses import dataclass
from fractions import Fraction as F
from . import macro as m
from .cashflows import operating_flow,present_value
from .episodes import PolicyRule,run_episode,physical_units,validate_blocked_rollovers


@dataclass(frozen=True)
class CellScore:
    key: str
    weight: F
    now: tuple
    delayed: tuple
    baseline_ok: bool=True
    now_ok: bool=True
    delayed_ok: bool=True
    def __post_init__(self):
        if type(self.key) is not str or not self.key:raise ValueError('Cell requires immutable identity.')
        w=m.ledger._number(self.weight)
        if w>1:raise ValueError('Invalid probability.')
        object.__setattr__(self,'weight',w)
        for name in ('baseline_ok','now_ok','delayed_ok'):
            if type(getattr(self,name)) is not bool:raise TypeError('Admissibility flags must be Boolean.')
        for name in ('now','delayed'):
            a=getattr(self,name)
            if type(a) is not tuple or len(a)!=2:raise TypeError('Require immutable two-horizon values.')
            object.__setattr__(self,name,tuple(None if v is None else m.ledger._number(v,signed=True) for v in a))
        if self.baseline_ok and ((self.now_ok and None in self.now) or (self.delayed_ok and None in self.delayed)):
            raise ValueError('An admissible branch cannot have missing value.')


@dataclass(frozen=True)
class Decision:
    status: str
    action: str | None
    expected_now: tuple | None
    expected_wait: tuple | None
    exercise: tuple
    now_admissible: bool
    reason: str=''


def decide(cells,tolerance=F(1,10**6)):
    if type(cells) is not tuple or not cells or any(type(z) is not CellScore for z in cells):raise TypeError('Require immutable scored forecast cells.')
    tolerance=m.ledger._number(tolerance)
    if len({c.key for c in cells})!=len(cells) or sum(c.weight for c in cells)!=1:raise ValueError('Require unique cells with total probability exactly1.')
    active=tuple(c for c in cells if c.weight)
    if any(not c.baseline_ok for c in active):return Decision('baseline_incomplete',None,None,None,(),False,'Failed positive-weight NEVER cell retained, not renormalized.')
    now_ok=all(c.now_ok for c in active)
    now=tuple(sum(c.weight*c.now[h] for c in active) for h in range(2)) if now_ok else None
    exercise=[];wait=[F(0),F(0)]
    for c in active:
        if not c.delayed_ok:
            exercise.append((c.key,False));continue
        take=tuple(v>tolerance for v in c.delayed)
        if take[0]!=take[1]:return Decision('tail_sensitive',None,now,None,tuple(exercise),now_ok,'Conditional wait exercise changes between horizons.')
        exercise.append((c.key,take[0]))
        if take[0]:
            for h in range(2):wait[h]+=c.weight*c.delayed[h]
    def rank(h):
        n=now[h] if now is not None else None
        if wait[h]<=tolerance:
            return 'NOW' if n is not None and n>tolerance else 'NEVER'
        if n is not None and n>tolerance and n>wait[h]+tolerance:return 'NOW'
        return 'WAIT_OPTION'
    ranks=(rank(0),rank(1))
    if ranks[0]!=ranks[1]:return Decision('tail_sensitive',None,now,tuple(wait),tuple(exercise),now_ok,'Root action changes between horizons.')
    return Decision('qualified_choice',ranks[0],now,tuple(wait),tuple(exercise),now_ok)


@dataclass(frozen=True)
class ForecastCell:
    key: str
    weight: F
    demand: F
    fulfilled: bool
    now: object | None
    delayed: object | None
    never: object | None
    opportunity_curve: tuple
    score: CellScore


@dataclass(frozen=True)
class Evaluation:
    decision: Decision
    cells: tuple
    execution_calls: int
    pricing_calls: int
    horizons: tuple
    criterion: str='finite-horizon unlevered operating value; zero post-horizon continuation; not shareholder NPV'


def evaluate(opening,policy,current_news=None,units=F(1,4),*,horizons=(48,64),project_rate_pct=None,blocked_rollover_ids=()):
    if type(opening) is not m.Envelope or type(policy) is not m.Policy:raise TypeError('Require current immutable information.')
    blocked_rollover_ids=validate_blocked_rollovers(opening,blocked_rollover_ids)
    if current_news is None:current_news=m.News()
    if type(current_news) is not m.News:raise TypeError('Require current immutable news, not future realized data.')
    if type(horizons) is not tuple or len(horizons)!=2 or any(type(h) is not int for h in horizons) or not 19<=horizons[0]<horizons[1]<=64:raise ValueError('Require two complete-life horizons between19 and64.')
    units=physical_units(units)
    if project_rate_pct is not None:project_rate_pct=m.ledger._number(project_rate_pct,signed=True)
    cred=m.rational(opening.macro.credibility);hmax=horizons[-1];cells=[];calls=pricing=0
    for demand in (F(-1),F(1)):
        for fulfill in (False,True):
            weight=(cred if fulfill else 1-cred)/2;key=f'demand{demand}/'+('fulfilled' if fulfill else 'staff')
            if not weight:
                score=CellScore(key,F(0),(None,None),(None,None),False,False,False)
                cells.append(ForecastCell(key,weight,demand,fulfill,None,None,None,(),score));continue
            rules=(PolicyRule('fixed',policy),PolicyRule('promise' if fulfill else 'staff'))+(PolicyRule('staff'),)*(hmax-2)
            news=(current_news,m.News(demand_shock_pct=demand))+(m.News(),)*(hmax-2)
            # All actions see the same current-information rule/scenario, but
            # future rules resolve on that action's actual counterfactual state.
            never=run_episode(opening,rules,news,'NEVER',units,project_rate_pct,blocked_rollover_ids=blocked_rollover_ids)
            now=run_episode(opening,rules,news,'NOW',units,project_rate_pct,blocked_rollover_ids=blocked_rollover_ids)
            delayed=run_episode(opening,rules,news,'WAIT',units,project_rate_pct,blocked_rollover_ids=blocked_rollover_ids)
            calls+=sum(e.committed_calls for e in (never,now,delayed))
            if delayed.steps and never.steps and delayed.steps[0]!=never.steps[0]:raise AssertionError('WAIT and NEVER must share their own no-project information prefix.')
            baseline_ok=never.completed==hmax
            curve=tuple(1+m.rational(s.prepared.long_yield_pct+m.P['normal_credit_spread_pct'])/400 for s in never.steps)
            if any(g<=0 for g in curve):raise ValueError('Opportunity curve has nonpositive gross forward.')
            base=tuple(operating_flow(s).net for s in never.steps)
            def values(episode):
                nonlocal pricing
                if not baseline_ok or episode.completed!=hmax:return (None,None)
                differences=tuple(operating_flow(s).net-b for s,b in zip(episode.steps,base))
                pricing+=4 # two horizons x positive/negative pricing legs
                return tuple(present_value(differences[:h],curve[:h]) for h in horizons)
            score=CellScore(key,weight,values(now),values(delayed),baseline_ok,now.completed==hmax,delayed.completed==hmax)
            cells.append(ForecastCell(key,weight,demand,fulfill,now,delayed,never,curve,score))
    decision=decide(tuple(z.score for z in cells),tolerance=opening.sector.scale*F(1,10**6))
    return Evaluation(decision,tuple(cells),calls,pricing,horizons)
