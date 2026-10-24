"""Shared recurring accounting and ONE cached NEVER/WAIT pair (38 calls)."""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import inspect
import unittest
from unittest.mock import patch
from scripts.research.funded_production import public_branches as b, public_recurring_branches as r
from scripts.research.funded_production import public_household_paydate as current
from scripts.research.funded_production.tests.test_household_scenarios import (
    modules,opening,date,cells,counted,COUNTS,PAID_STATES,l,m,k)
from scripts.research.funded_production.tests.test_public_recurring_branches import scalar_paths


class HouseholdRecurringPureTests(unittest.TestCase):
    def setUp(self):
        self.q=modules();self.guards=[]
        for obj,name in ((l,'advance_given_orders'),(l,'_Transaction'),(m,'_close_paid')):
            guard=patch.object(obj,name,side_effect=AssertionError('No actual future'))
            self.guards.append(guard.start());self.addCleanup(guard.stop)
    def tearDown(self):self.assertTrue(all(g.call_count==0 for g in self.guards))
    def quote(self,**changes):
        args=dict(opening=opening(),cells=cells(missing=0),units=F(1,2),background_units=F(1),forward_gross=(F(1),)*18)
        args.update(changes);return self.q.evaluate_recurring(**args)
    def test_shared_records_signature_missing_prefix_and_zero_background_parity(self):
        self.assertEqual(str(inspect.signature(self.q.evaluate_recurring)),
            '(opening, cells, *, units, background_units, forward_gross, tolerance=1e-06) -> '\
            "'RecurringQuotation'")
        quote=self.quote(background_units=0);single=self.q.evaluate(opening(),cells(missing=0),units=F(1,2),forward_gross=(F(1),)*18)
        self.assertIs(type(quote),r.Quotation)
        for name in ('status','action','expected_now','wait_value','executor_calls','unknown_coverage'):
            self.assertEqual(getattr(quote,name),getattr(single,name))
        with self.assertRaises((TypeError,ValueError)):k._pack(quote)
        with self.assertRaises(TypeError):r.evaluate(opening(),cells(),units=0,background_units=0,forward_gross=(F(1),)*18)
    def test_invalid_background_selector_and_exceptional_immutability(self):
        for value in (True,F(-1),F(1,10**7),float('nan'),[1]):
            with self.assertRaises((TypeError,ValueError)):self.quote(background_units=value)
        for flag in (1,None,lambda:True):
            with self.assertRaises(TypeError):r._evaluate(opening(),cells(),units=0,background_units=0,forward_gross=(F(1),)*18,household=flag)
        root=opening()
        def broken(state,*args,**kwargs):
            object.__setattr__(state.macro,'public_support',state.macro.public_support+1)
            raise AssertionError('original error')
        with patch.object(current,'prepare',side_effect=broken):
            with self.assertRaisesRegex(ValueError,'mutated'):self.quote(opening=root,cells=cells())
    def test_whole_invoice_signed_finance_is_not_operating_DCF_and_all_discounts(self):
        report=l.Report(1,F(13),F(7),F(2),F(4),F(1),F(2),F(3),F(5),
            F(999),F(-999),F(888),F(777),F(666),F(555),F(444),F(0),F(0),(),())
        row=r._cash_row(0,report,F(3),F(2),background=F(1),candidate=F(1),paid=F(1),
            canceled='known_shortfall',previous_claims=(),claims=(),discount=F(1))
        self.assertEqual((row.receipts,row.payroll,row.construction_invoice,row.operating_cash,row.pv),(42,5,12,25,25))
        self.assertFalse(row.candidate_fully_delivered)
        self.assertEqual(b._discount_factors(tuple(F(h+2,h+1) for h in range(18))),tuple(F(1,h+1) for h in range(19)))
        self.assertFalse(hasattr(row,'candidate_paid_units'))
    def test_same_background_incrementals_cancellation_baseline_veto_and_WAIT_grouping(self):
        paths=scalar_paths(now=-1)
        self.assertEqual(r._select(paths,F(0))[:4],('completed','NEVER',-1,0))
        for action,status in (('NEVER','failed'),('NOW','unknown')):
            changed=tuple(replace(p,status=status,total_pv=None,incremental_pv=None)
                if p.action==action and p.fulfilled else p for p in paths)
            self.assertIsNone(r._select(changed,F(0))[1])
        self.assertEqual(r._delivery_failure(F(0),F(2),F(1),'credit_constraint'),(None,''))
        self.assertEqual(r._delivery_failure(F(1),F(2),F(1),'credit_constraint')[0],'failed')
        self.assertEqual(r._delivery_failure(F(0),F(2),F(1),'unsupported_public_income')[0],'unknown')
        zero=tuple(replace(p,weight=F(0) if p.fulfilled else F(1,2),status='unknown' if p.fulfilled else p.status,
            total_pv=None if p.fulfilled else p.total_pv,incremental_pv=None if p.fulfilled else p.incremental_pv) for p in scalar_paths(wait=(0,)*4))
        self.assertEqual(r._select(zero,F(0))[1],'NOW')
    def test_project_identity_tracking_is_actual_joint_not_root_relabel_or_ratio(self):
        root=l.Loan('ROOT','B',10,4,48,0,0,borrower='F')
        project=l.ProjectLoan('NEW','B',2,-4,2,0,0,borrower='F')
        claims=r._track_claims((),(root,),(root,project),(),construction_date=0,quarter=1,decision_date=0,root_ids=('ROOT',))
        self.assertEqual([(x.id,x.role,x.origin_face) for x in claims],[('NEW','decision_date_joint',2)])
        self.assertNotIn('ROOT',[x.id for x in claims])
        with self.assertRaises(AssertionError):r._track_claims(claims,(root,project),(root,replace(project,rate_pct=0)),(),construction_date=1,quarter=2,decision_date=0)
        retired=r._track_claims(claims,(root,project),(root,),
            (l.Payment('F','BankB',2,'private_principal','NEW'),),construction_date=1,quarter=2,decision_date=0)
        self.assertEqual((retired[0].origin_face,retired[0].retired_principal,retired[0].outstanding_face),(2,2,0))


class HouseholdRecurringActualPairTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root=opening(debt=True);cls.before=repr(cls.root);cls.units=F(1,2);cls.background=F(3,2)
        checked,units,_,_,discounts,_=b._validated_inputs(cls.root,cells(),units=cls.units,
            forward_gross=(F(1),)*18,paydate=True,household=True)
        before=dict(COUNTS)
        with counted():
            cls.baseline=r._run_path(cls.root,checked[0],'NEVER',units,cls.background,discounts,F(1,4),household=True)
            if cls.baseline.status!='completed':raise AssertionError('Retain baseline failure, not tune/retry: '+cls.baseline.reason)
            cls.wait=r._run_path(cls.root,checked[0],'WAIT',units,cls.background,discounts,F(1,4),household=True)
        cls.counts={name:COUNTS[name]-before[name] for name in COUNTS}
    def test_actual_joint_WAIT_delivery_retirement_and_background_right_censoring(self):
        self.assertEqual(self.counts,dict(attempts=38,paid=38,refused=0,raw_exceptions=0,
            transactions=38,macro_calls=38,macro_closes=38,macro_exceptions=0))
        self.assertEqual((self.baseline.status,self.wait.status),('completed','completed'))
        self.assertEqual(self.baseline.decision_date_cohort,())
        self.assertTrue(self.wait.candidate_fully_delivered)
        self.assertGreater(self.wait.decision_date_origin_face,0)
        self.assertEqual(self.wait.decision_date_origin_face,self.wait.decision_date_retired_principal)
        self.assertEqual(self.wait.decision_date_outstanding_face,0)
        for path in (self.baseline,self.wait):
            self.assertTrue(path.background_right_censored)
            self.assertTrue(all(c.origin_face==c.retired_principal+c.outstanding_face for c in path.claims))
        self.assertEqual(repr(self.root),self.before)
    def test_actual_same_background_whole_invoice_incremental_and_primitive_WAIT(self):
        baseline,wait=b._incrementals((self.baseline,self.wait))
        self.assertEqual(wait.incremental_pv,wait.total_pv-baseline.total_pv)
        self.assertEqual(baseline.incremental_pv,0)
        self.assertEqual([row.date for row in wait.rows if row.candidate_requested_units],[1])
        self.assertEqual(wait.rows[1].requested_units,2)
        for path in (baseline,wait):
            self.assertEqual([row.background_requested_units for row in path.rows],[self.background]*19)
            self.assertEqual(path.total_pv,sum((row.pv for row in path.rows),F(0)))
            for row in path.rows:self.assertEqual(row.operating_cash,row.receipts-row.payroll-row.construction_invoice)
        def check(value):
            self.assertNotIsInstance(value,(m.Envelope,l.Report,current.Prepared,type))
            if type(value) is tuple:
                for child in value:check(child)
            elif type(value) in (r.Path,r.Row,r.ProjectClaim):
                for field in fields(type(value)):check(getattr(value,field.name))
        check(wait)
        for value in (wait,wait.rows[0],wait.claims[0]):
            with self.assertRaises((TypeError,ValueError)):k._pack(value)
            with self.assertRaises(FrozenInstanceError):setattr(value,fields(type(value))[0].name,None)


if __name__=='__main__':unittest.main()
