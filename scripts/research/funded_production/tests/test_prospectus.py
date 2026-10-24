"""Prospective pure-table contract: no paid forecast executor or hidden exercise."""
from dataclasses import replace, FrozenInstanceError
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import prospectus as p


def cell(sign, fulfilled, **changes):
    fields = dict(demand_sign=sign, fulfilled=fulfilled,
        demand=(F(1),)*19, known_capital=(F(0),)*19,
        workers=(F(1),)*19, labor_productivity=(F(1),)*19,
        service_price=(F(1),)*19, wage=(F(1,2),)*19,
        construction_cost=(F(4),)*19, forward_gross=(F(1),)*18,
        baseline_ok=True, now_ok=True, wait_ok=True)
    fields.update(changes)
    return p.ForecastCell(**fields)


def cells(**changes):
    return tuple(cell(sign, fulfilled, **changes)
                 for sign in (-1, 1) for fulfilled in (False, True))


def quote(items=None, units=1, **changes):
    return p.evaluate(cells() if items is None else items, F(1,2),
                      units=units, capital_productivity=1, **changes)


class ProspectusTests(unittest.TestCase):
    def test_exact_228_rows_lifetimes_whole_invoice_no_financing_or_executor(self):
        with patch('scripts.research.funded_production.ledger.advance_given_orders',
                   side_effect=AssertionError('Pure prospectus must not execute')):
            out = quote()
        self.assertEqual((len(out.rows), out.scalar_rows, out.executor_calls), (228, 228, 0))
        for sign in (-1, 1):
            for fulfilled in (False, True):
                rows = [r for r in out.rows if (r.demand_sign,r.fulfilled)==(sign,fulfilled)]
                for action, start in (('NOW',0), ('WAIT',1)):
                    branch = [r for r in rows if r.action==action]
                    self.assertEqual([r.date for r in branch if r.services], list(range(start+1,start+17)))
                    self.assertEqual([r.date for r in branch if r.construction], [start])
                    self.assertEqual(sum(r.construction for r in branch), 4)
                    self.assertEqual(sum(r.operating_cash for r in branch), 4)
                self.assertTrue(all(r.services==r.operating_cash==0 for r in rows if r.action=='NEVER'))
        self.assertTrue(all(z.now_value==z.wait_value==4 for z in out.cells))
        self.assertEqual((out.decision.status,out.decision.action), ('quoted_choice','WAIT'))
        with self.assertRaises(FrozenInstanceError): out.rows[0].date=10

    def test_only_sold_capacity_counts_and_workers_bind(self):
        out = quote(cells(known_capital=(F(2),)*19))
        self.assertTrue(all(z.now_value==z.wait_value==-4 for z in out.cells))
        self.assertEqual(out.decision.action,'NEVER')
        out = quote(cells(workers=(F(1,4),)*19))
        self.assertTrue(all(z.now_value==z.wait_value==-2 for z in out.cells))
        active = next(r for r in out.rows if r.action=='NOW' and r.date==1)
        self.assertEqual((active.services,active.workers,active.receipts,active.payroll),
                         (F(1,4),F(1,4),F(1,4),F(1,8)))

    def test_current_nominal_pv_and_earlier_profitable_project(self):
        gross=F(101,100)
        out=quote(cells(forward_gross=(gross,)*18))
        now=sum(F(1,2)/gross**h for h in range(1,17))-4
        wait=now/gross
        self.assertEqual(out.cells[0].now_value,now)
        self.assertEqual(out.cells[0].wait_value,wait)
        self.assertEqual(out.decision.action,'NOW')
        current=next(r for r in out.rows if r.action=='NOW' and r.date==0)
        self.assertEqual((current.operating_cash,current.present_value),(-4,-4))

    def test_observable_nodes_not_terminal_cell_identity_determine_wait_option(self):
        hidden=tuple(cell(sign,f,demand=(F(int(sign>0)),)*19)
                     for sign in (-1,1) for f in (False,True))
        out=quote(hidden)
        self.assertEqual((out.decision.expected_now,out.decision.wait_value),(0,0))
        self.assertEqual(out.decision.action,'NEVER')
        revealed=tuple(replace(c,observable_node='high' if c.demand_sign>0 else 'low') for c in hidden)
        out=quote(revealed)
        self.assertEqual((out.decision.expected_now,out.decision.wait_value),(0,2))
        self.assertEqual(out.decision.action,'WAIT')
        self.assertEqual(out.decision.exercise,(('low',False),('high',True)))

    def test_node_robust_finance_admissibility_and_unknown_is_not_approval(self):
        c=list(cells());c[0]=replace(c[0],now_ok=False,wait_ok=False)
        out=quote(tuple(c))
        self.assertFalse(out.decision.now_admissible)
        self.assertEqual(out.decision.action,'NEVER')
        for field in ('baseline_ok','now_ok','wait_ok'):
            unknown=list(cells());unknown[0]=replace(unknown[0],**{field:None})
            d=quote(tuple(unknown)).decision
            self.assertEqual((d.status,d.action),('admission_incomplete',None))
        failed=list(cells());failed[0]=replace(failed[0],baseline_ok=False)
        self.assertEqual(quote(tuple(failed)).decision.status,'baseline_incomplete')
        defaults=replace(cells()[0],baseline_ok=None,now_ok=None,wait_ok=None)
        self.assertEqual((defaults.baseline_ok,defaults.now_ok,defaults.wait_ok),(None,None,None))

    def test_zero_weight_bad_baseline_not_renormalized_positive_weight_required(self):
        c=tuple(replace(x,baseline_ok=False,now_ok=None,wait_ok=None) if not x.fulfilled else x
                for x in cells())
        out=p.evaluate(c,1,units=1,capital_productivity=1)
        self.assertEqual([z.weight for z in out.cells],[0,F(1,2),0,F(1,2)])
        self.assertEqual(out.decision.action,'WAIT')
        self.assertEqual(quote(c).decision.status,'baseline_incomplete')

    def test_subthreshold_wait_cannot_veto_eligible_now(self):
        eps=F(1,10**6)
        items=tuple(replace(c,observable_node=f'observed-release-{i}',
            construction_cost=(8-F(3,2)*eps,8-3*eps if i==0 else F(8))+(F(8),)*17)
            for i,c in enumerate(cells()))
        d=quote(items).decision
        self.assertEqual((d.expected_now,d.wait_value),(F(3,2)*eps,F(3,4)*eps))
        self.assertEqual(d.action,'NOW')
        # If both root alternatives qualify, the tolerance tie still favors WAIT.
        items=tuple(replace(c,construction_cost=(8-F(3,2)*eps,8-F(11,10)*eps)+(F(8),)*17)
                    for c in cells())
        self.assertEqual(quote(items).decision.action,'WAIT')

    def test_revealing_demand_sign_does_not_discard_feasible_now(self):
        gross=F(101,100)
        annuity=sum(1/gross**h for h in range(1,17))
        items=tuple(cell(sign,f,service_price=(1+F(101,50)/annuity if sign>0 else F(1),)*19,
                         wage=(F(1),)*19,construction_cost=(F(1,200),)*19,
                         forward_gross=(gross,)*18)
                    for sign in (-1,1) for f in (False,True))
        shared=quote(items,tolerance=1).decision
        revealed=quote(tuple(replace(c,observable_node=str(c.demand_sign)) for c in items),
                       tolerance=1).decision
        self.assertEqual(shared.expected_now,F(201,200))
        self.assertEqual(revealed.wait_value,F(403,404))
        self.assertEqual((shared.action,revealed.action),('NOW','NOW'))

    def test_tolerance_and_money_scale_are_not_hidden_economic_caps(self):
        base=quote()
        scaled=quote(cells(service_price=(F(7),)*19,wage=(F(7,2),)*19,
                           construction_cost=(F(28),)*19),tolerance=F(7,10**6))
        self.assertEqual(scaled.cells[0].now_value,7*base.cells[0].now_value)
        self.assertEqual(scaled.decision.action,base.decision.action)
        self.assertEqual(quote(tolerance=4).decision.action,'NEVER')
        self.assertEqual(quote(units=0).decision.action,'NEVER')

    def test_invalid_immutable_inputs_rejected_before_rows(self):
        for kwargs in (dict(demand=[1]*19),dict(known_capital=(0,)*18),
                       dict(wage=(True,)*19),dict(labor_productivity=(0,)*19),
                       dict(forward_gross=(0,)*18),dict(construction_cost=(-1,)*19),
                       dict(demand_sign=True),dict(fulfilled=1),dict(now_ok=1),
                       dict(observable_node=''),dict(service_price=(float('nan'),)*19)):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises((ValueError,TypeError)):cell(-1,False,**kwargs)
        for invalid in (cells()[:3],(cells()[0],)*4,list(cells())):
            with self.assertRaises((ValueError,TypeError)):quote(invalid)
        for cred in (-1,2,True,float('inf')):
            with self.assertRaises((ValueError,TypeError)):
                p.evaluate(cells(),cred,units=1,capital_productivity=1)


if __name__=='__main__': unittest.main()
