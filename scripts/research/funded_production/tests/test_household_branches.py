"""Household single-project future admission and ONE twelve-call prefix."""
from dataclasses import fields, replace
from fractions import Fraction as F
import inspect
import unittest
from unittest.mock import patch
from scripts.research.funded_production import public_branches as b, public_recurring_branches as r
from scripts.research.funded_production import public_household_paydate as current
from scripts.research.funded_production.tests.test_household_scenarios import (
    modules, opening, date, cells, counted, COUNTS, PAID_STATES, l, m, k)
from scripts.research.funded_production.tests.test_paydate_branches import pure_paths


class HouseholdBranchesPureTests(unittest.TestCase):
    def setUp(self):
        self.q=modules();self.guards=[]
        for obj,name in ((l,'advance_given_orders'),(l,'_Transaction'),(m,'_close_paid')):
            guard=patch.object(obj,name,side_effect=AssertionError('No actual future'))
            self.guards.append(guard.start());self.addCleanup(guard.stop)
    def tearDown(self):self.assertTrue(all(g.call_count==0 for g in self.guards))
    def quote(self,**changes):
        args=dict(opening=opening(),cells=cells(missing=0),units=F(1,2),forward_gross=(F(1),)*18)
        args.update(changes);return self.q.evaluate(**args)

    def test_closed_selector_and_unchanged_public_signatures_records(self):
        self.assertEqual(str(inspect.signature(self.q.evaluate)),str(inspect.signature(b.evaluate)))
        self.assertIs(self.q.Quotation,b.Quotation)
        pair=b._pair(True,household=True)
        self.assertIs(pair[0],current);self.assertIs(pair[1],self.q);self.assertIs(pair[2],l.HouseholdLiquidityBook)
        for paydate,household in ((False,True),(True,1),(1,False),(b.p,True),(True,lambda:True)):
            with self.assertRaises(TypeError):b._pair(paydate,household=household)

    def test_missing_coverage_retains_twelve_unknown_paths_and_no_recommendation(self):
        quote=self.quote()
        self.assertEqual((quote.status,quote.action,quote.executor_calls,quote.unknown_coverage),
                         ('admission_incomplete',None,0,12))
        self.assertTrue(all(p.total_pv is None and not p.rows for p in quote.paths))
        with self.assertRaises((TypeError,ValueError)):k._pack(quote)
        from scripts.research.funded_production import public_paydate_branches as strict
        for fn in (b.evaluate,strict.evaluate):
            with self.assertRaises((TypeError,ValueError)):fn(opening(),cells(),units=0,forward_gross=(F(1),)*18)

    def test_invalid_future_nested_fields_grids_root_and_curve_fail_before_executor(self):
        table=cells();future=replace(table[0].dates[18],facility_limits=(F(1,10**7),F(100)))
        for changes in (dict(units=True),dict(units=F(1,10**7)),dict(forward_gross=(F(1),)*17),
            dict(tolerance=False),dict(opening=opening(convention='early')),
            dict(cells=(replace(table[0],dates=(*table[0].dates[:18],future)),*table[1:]))):
            with self.assertRaises((TypeError,ValueError)):self.quote(**changes)
        descriptor=date();object.__setattr__(descriptor,'__dataclass_fields__',{})
        cell=replace(table[0]);object.__setattr__(cell,'dates',(descriptor,)*19)
        with self.assertRaises((TypeError,ValueError)):self.quote(cells=(cell,*table[1:]))

    def test_cyclic_admission_and_exceptional_source_finally_do_not_execute(self):
        cell=cells()[0];object.__setattr__(cell,'dates',(cell,)*19)
        with self.assertRaisesRegex(ValueError,'cycles'):self.quote(cells=(cell,*cells()[1:]))
        events=[];root=opening();original=k._check_sources
        def checked():events.append('source');return original()
        def broken(state,*args,**kwargs):
            events.append('mutation');object.__setattr__(state.macro,'public_support',71)
            raise AssertionError('original error')
        with patch.object(k,'_check_sources',side_effect=checked),patch.object(current,'prepare',side_effect=broken):
            with self.assertRaisesRegex(ValueError,'mutated'):self.quote(opening=root,cells=cells())
        self.assertGreater(len(events)-1,events.index('mutation'))
        self.assertEqual(events[-1],'source')

    def test_full_current_disclosure_common_even_unused_bids_and_facilities(self):
        table=cells()
        for changes in (dict(new_issue_authorization=1),dict(subscription_limits=(1,0)),
            dict(subscription_rates_pct=(-4,0)),dict(facility_limits=(99,100)),
            dict(allocation_priority=('B','A')),dict(full_roll=False)):
            current_date=replace(table[0].dates[0],**changes)
            altered=(replace(table[0],dates=(current_date,*table[0].dates[1:])),*table[1:])
            with self.assertRaisesRegex(ValueError,'[Cc]urrent'):self.quote(cells=altered)

    def test_reducer_never_uses_hidden_cell_and_incomplete_baselines_veto(self):
        paths=pure_paths(now=-1)
        self.assertEqual(b._select(paths,F(0))[:4],('completed','NEVER',-1,0))
        altered=tuple(replace(p,status='failed',total_pv=None,incremental_pv=None)
            if p.action=='NEVER' and p.fulfilled else p for p in paths)
        self.assertEqual(b._select(altered,F(0))[:2],('baseline_incomplete',None))
        unknown=tuple(replace(p,status='unknown',total_pv=None,incremental_pv=None)
            if p.fulfilled else p for p in paths)
        self.assertEqual(b._select(unknown,F(0))[:2],('admission_incomplete',None))

    def test_terminal_adapter_return_is_not_a_paid_macro_row_or_raw_refusal_claim(self):
        # PURE boundary contract: a symbolic adapter result, NOT a raw journal.
        # Real raw-paid/zero-GDP classification remains in the unchanged current
        # adapter; future refusal counters must not be called raw-paid counts.
        root=opening();table=cells();discounts=(F(1),)*19
        terminal=m.Transition(False,root,'terminal_crisis','Zero paid GDP')
        with patch.object(current,'execute',return_value=terminal) as execute:
            single=b._run_path(root,table[0],'NOW',F(1,2),discounts,F(1,4),paydate=True,household=True)
            recurring=r._run_path(root,table[0],'NOW',F(1,2),F(1),discounts,F(1,4),household=True)
        self.assertEqual(execute.call_count,2)  # Two SYNTHETIC adapter returns.
        for path in (single,recurring):
            self.assertEqual((path.status,path.executor_calls,path.paid_closes,path.refused_closes),('failed',1,0,1))
            self.assertEqual(path.rows,());self.assertIsNone(path.total_pv)
        self.assertTrue(all(g.call_count==0 for g in self.guards))

    def test_known_treasury_failure_is_not_missing_and_source_failure_propagates(self):
        root=opening(treasury_rates_pct=(1000,0,0))
        quote=self.quote(opening=root,cells=cells())
        self.assertEqual((quote.status,quote.action,quote.executor_calls,quote.prefix_failures),
                         ('baseline_incomplete',None,0,12))
        self.assertTrue(all(p.status=='failed' for p in quote.paths))
        with patch.object(k,'_check_sources',side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError,'source drift'):self.quote()

    def test_programmer_exception_mutation_checks_predecessor_and_root(self):
        root=opening()
        def broken(state,*args,**kwargs):
            object.__setattr__(state.macro,'public_support',state.macro.public_support+1)
            raise AssertionError('original error')
        with patch.object(current,'prepare',side_effect=broken):
            with self.assertRaisesRegex(ValueError,'mutated'):
                self.quote(opening=root,cells=cells())
        with patch.object(current,'prepare',side_effect=AssertionError('programmer error')):
            with self.assertRaisesRegex(AssertionError,'programmer error'):self.quote(cells=cells())


class HouseholdBranchesActualPrefixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root=opening(debt=True);cls.before=repr(cls.root);before=dict(COUNTS)
        with counted():cls.quote=modules().evaluate(cls.root,cells(missing=1),units=F(1,2),forward_gross=(F(1),)*18)
        cls.counts={name:COUNTS[name]-before[name] for name in COUNTS}
    def test_one_real_household_attempt_per_paid_prefix_and_no_future_adoption(self):
        quote=self.quote
        self.assertEqual(self.counts,dict(attempts=12,paid=12,refused=0,raw_exceptions=0,
            transactions=12,macro_calls=12,macro_closes=12,macro_exceptions=0))
        self.assertEqual((quote.executor_calls,quote.paid_closes,quote.unknown_coverage),(12,12,12))
        self.assertEqual((quote.status,quote.action),('admission_incomplete',None))
        self.assertEqual(repr(self.root),self.before)
        self.assertTrue(all(type(s.sector.public_book) is l.HouseholdLiquidityBook for s in PAID_STATES))
        def check(value):
            self.assertNotIsInstance(value,(m.Envelope,l.Report,current.Prepared))
            if type(value) is tuple:
                for child in value:check(child)
            elif type(value) in (b.Quotation,b.Path,b.Row,b.Decision):
                for field in fields(type(value)):check(getattr(value,field.name))
        check(quote)
        with self.assertRaises((TypeError,ValueError)):k._pack(quote)
    def test_reuse_paid_history_adversaries_zero_replay(self):
        state=PAID_STATES[0];sector=state.sector
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No replay')) as raw, \
             patch.object(l,'_Transaction',side_effect=AssertionError('No replay')) as tx:
            for stream in ('payments','trace'):
                report=replace(sector.last,**{stream:getattr(sector.last,stream)[::-1]})
                # Bypass constructors only to present a hostile immutable tree.
                forged=replace(state);bad=replace(sector)
                object.__setattr__(bad,'last',report);object.__setattr__(forged,'sector',bad)
                with self.assertRaises((TypeError,ValueError)):
                    modules().resolve_date(forged,date(iorb_rate_pct=-3))
            self.assertEqual((raw.call_count,tx.call_count),(0,0))


if __name__=='__main__':unittest.main()
