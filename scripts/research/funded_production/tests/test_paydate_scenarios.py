"""Pure new-book date coverage and unchanged conservative public information."""
from dataclasses import replace,FrozenInstanceError
from fractions import Fraction as F
import unittest
from unittest.mock import patch
from scripts.research.funded_production import paydate_scenarios as n
from scripts.research.funded_production import public_scenarios as old
from scripts.research.funded_production import public_forecast as p,ledger as l
from scripts.research.funded_production import public_market as market
from scripts.research.funded_production.tests.test_paydate_market import opening,date
from scripts.research.funded_production.tests.test_public_paydate_journal import legacy
from scripts.research.funded_production import macro as m


def cells(descriptor=None):
    descriptor=date() if descriptor is None else descriptor
    return tuple(n.ScenarioCell(sign,fulfilled,(descriptor,)*19)
                 for sign in (-1,1) for fulfilled in (False,True))


class PaydateScenarioTests(unittest.TestCase):
    def setUp(self):
        self.guards=[]
        for target,name in ((l,'advance_given_orders'),(l,'_Transaction'),(p,'prepare'),(p,'execute')):
            guard=patch.object(target,name,side_effect=AssertionError('Pure scenarios'))
            self.guards.append(guard.start());self.addCleanup(guard.stop)
    def tearDown(self):self.assertTrue(all(x.call_count==0 for x in self.guards))

    def test_exact_cartesian_cells_required_without_changing_old_schema(self):
        table=cells();self.assertEqual(n.validated_cells(table),table)
        with self.assertRaises(FrozenInstanceError):table[0].demand_sign=1
        for wrong in (list(table),table[:3],table[:3]+table[:1]):
            with self.assertRaises((TypeError,ValueError)):n.validated_cells(wrong)
        with self.assertRaises(TypeError):old.validated_cells(table)
        with self.assertRaises(TypeError):n.validated_cells(tuple(
            old.ScenarioCell(c.demand_sign,c.fulfilled,(old.FullRollDate(m.Policy(3.5,3.5),m.News(),0,(100,100)),)*19)
            for c in table))

    def test_date_coverage_explicit_and_missing_is_unknown(self):
        value=opening()
        descriptor=date()
        self.assertEqual(n.resolve_date(value,descriptor),market.resolve_paydate_date(value,descriptor))
        with self.assertRaises(n.MissingCoverage):n.resolve_date(value,None)
        with self.assertRaises(TypeError):n.ScenarioCell(-1,False,(descriptor,)*18)
        with self.assertRaises((TypeError,ValueError)):n.ScenarioCell(True,False,(descriptor,)*19)
        with self.assertRaises((TypeError,ValueError)):n.ScenarioCell(-1,1,(descriptor,)*19)
        old_date=old.FullRollDate(m.Policy(3.5,3.5),m.News(),0,(100,100))
        with self.assertRaises(TypeError):n.ScenarioCell(-1,False,(old_date,)*19)

    def test_current_observation_has_old_key_for_equal_own_public_facts(self):
        base,terms=legacy()
        a=replace(m.initial(growth=0),sector=l.enable_funded_public(base,terms))
        b=replace(a,sector=l.enable_paydate_public(base,terms))
        current=market.resolve_paydate_date(b,date())
        self.assertEqual(n.wait_observation(b,current),old.wait_observation(a,current))
        with self.assertRaises((TypeError,NotImplementedError)):old.wait_observation(b,current)
        with self.assertRaises((TypeError,NotImplementedError)):n.wait_observation(a,current)

    def test_hidden_macro_and_cell_labels_cannot_separate_wait_groups(self):
        value=opening();current=n.resolve_date(value,date())
        changed=replace(value,macro=replace(value.macro,credibility=F(1,2),r_star_pct=-2))
        self.assertEqual(n.wait_observation(value,current),n.wait_observation(changed,current))
        self.assertNotEqual(n.wait_observation(value,current),
                           n.wait_observation(value,replace(current,news=m.News(demand_shock_pct=1))))

    def test_descriptor_metadata_never_runs_callbacks(self):
        calls=[];descriptor=date()
        class Schema(dict):
            def values(self):calls.append('metadata');return super().values()
        object.__setattr__(descriptor,'__dataclass_fields__',Schema())
        with self.assertRaises((TypeError,ValueError)):n.ScenarioCell(-1,False,(descriptor,)*19)
        self.assertEqual(calls,[])

    def test_future_dates_do_not_enter_current_wait_key(self):
        value=opening();current=n.resolve_date(value,date())
        a=cells();changed=list(a[0].dates)
        changed[-1]=date(policy=m.Policy(-3,-3),news=m.News(demand_shock_pct=-20))
        b=(replace(a[0],dates=tuple(changed)),)+a[1:]
        self.assertNotEqual(a,b)
        self.assertEqual(n.wait_observation(value,n.resolve_date(value,a[0].dates[0])),
                         n.wait_observation(value,n.resolve_date(value,b[0].dates[0])))
        self.assertIs(n.MissingCoverage,old.MissingCoverage)


if __name__=='__main__':unittest.main()
