"""Current-information private plan: value is not a credit or welfare approval."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch
from scripts.research.funded_production import investment as i, coupled as c, macro as m, ledger as l
from scripts.research.funded_production.tests.test_coupled_quarter import opening


def missing_pipeline(scale=1):
    a=m.initial(growth=0,scale=scale)
    return replace(a,sector=replace(a.sector,wip_units=0,wip_basis=0))


def financing(out,action='NOW',sign=-1,fulfilled=False):
    return next(z for z in out.financing if (z.action,z.demand_sign,z.fulfilled)==(action,sign,fulfilled))


class PrivateInvestmentTests(unittest.TestCase):
    def test_forecasts_use_declared_current_information_and_known_dates(self):
        a=m.initial(growth=2);f=i.forecast(a,m.Policy(3.5,3.5,1.5,.5))
        self.assertEqual(len(f.cells),4)
        base=c.prepare(a,m.Policy(3.5,3.5,1.5,.5))
        grow=m.rational((1+a.macro.growth_pct/100)**.25)
        prices=m.rational((1+a.macro.expected_long_inflation_pct/100)**.25)
        for cell in f.cells:
            self.assertEqual(cell.known_capital,c.known_capital(a.sector))
            self.assertEqual(cell.demand[0],base.forecast_services)
            for h in (1,2,18):
                self.assertEqual(cell.demand[h],base.forecast_services*grow**h*
                    (1+F(cell.demand_sign,100)*F(18,25)**(h-1)))
                self.assertEqual(cell.service_price[h],a.sector.scale*base.orders.price_factor*prices**h)
        self.assertEqual({(z.demand_sign,z.fulfilled) for z in f.cells},
                         {(-1,False),(-1,True),(1,False),(1,True)})
        self.assertTrue(all(z.baseline_ok is z.now_ok is z.wait_ok is None for z in f.cells))

    def test_first_delivery_deficit_is_quantized_and_bounded_once(self):
        f=i.forecast(opening(),m.Policy(3.5,3.5))
        self.assertEqual((f.proposed_units,f.units),(1,1))
        small=missing_pipeline();small=replace(small,macro=replace(small.macro,workforce=1))
        f=i.forecast(small,m.Policy(3.5,3.5))
        self.assertGreater(f.proposed_units,0)
        self.assertEqual(f.units,0)
        self.assertEqual(f.units%l.QUANTUM,0)

    def test_next_guidance_uses_rolling_price_history_and_current_anchors(self):
        a=m.initial(growth=0);policy=m.Policy(3.5,2,1.5,.5)
        f=i.forecast(a,policy)
        node_price=f.cells[0].service_price[1]/a.sector.scale*100
        node_inflation=100*(float(node_price)/a.macro.price_history[2]-1)
        predicted_gap=.72*a.macro.output_gap_pct
        rate=m.round_quote(policy.guidance_pct+policy.inflation_sensitivity*(node_inflation-a.macro.four_quarter_inflation_pct)
                           +policy.gap_sensitivity*(predicted_gap-a.macro.output_gap_pct))
        self.assertEqual(f.fulfilled_policy,m.Policy(rate,rate,1.5,.5))
        self.assertEqual(f.fallback_policy,i.PolicyRule('staff').resolve(a))

    def test_next_policy_uses_observed_current_close_not_unseen_next_close(self):
        a=opening()
        a=replace(a,macro=replace(a.macro,price_index=102,price_history=(98,99,100,101,102),
            annualized_quarterly_inflation_pct=100*((102/101)**4-1),
            four_quarter_inflation_pct=100*(102/98-1),
            expected_short_inflation_pct=2,expected_long_inflation_pct=2))
        policy=m.Policy(3.5,2,1.5,0)
        f=i.forecast(a,policy)
        prepared=c.prepare(a,policy)
        actual=c.execute(prepared,c.controls(prepared));self.assertTrue(actual.ok,actual.reason)
        self.assertEqual(f.fulfilled_policy,i.PolicyRule('promise').resolve(actual.envelope))

    def test_signed_same_date_coupons_do_not_depend_on_loan_storage_order(self):
        a=opening()
        a=replace(a,sector=replace(a.sector,
            banks=(a.sector.banks[0],replace(a.sector.banks[1],deposits=(F(3,100),F(3,20)))),
            vintages=(l.Vintage(0,F(1,10),F(37,200)),),wip_units=0,wip_basis=0,
            loans=(a.sector.loans[0],l.Loan('negative-fixed','B',10,-4,48,0,0))))
        cases=[]
        for loans in (a.sector.loans,tuple(reversed(a.sector.loans))):
            state=replace(a,sector=replace(a.sector,loans=loans))
            case=financing(i.evaluate(state,m.Policy(3.5,3.5)),'NEVER')
            self.assertTrue(case.complete,case.reason)
            cases.append(case)
        self.assertEqual([r.cash for r in cases[0].dates],[r.cash for r in cases[1].dates])
        self.assertEqual(cases[0].dates[0].cash,F(17,400))

    def test_actual_project_waits_for_fundable_same_date_debt_closure(self):
        a=opening()
        loans=(l.Loan('positive','B',10,240,50,0,0),l.Loan('negative','B',10,-240,50,0,0))
        for ordered in (loans,tuple(reversed(loans))):
            with self.subTest(order=tuple(z.id for z in ordered)):
                state=replace(a,sector=replace(a.sector,loans=ordered))
                plan=i.evaluate(state,m.Policy(3.5,3.5))
                case=financing(plan)
                self.assertTrue(case.complete,case.reason)
                p=c.prepare(state,m.Policy(3.5,3.5),project_units=1)
                actual=c.execute(p,c.controls(p));self.assertTrue(actual.ok,actual.reason)
                self.assertEqual(actual.envelope.sector.wip_units,1)
                self.assertEqual(actual.envelope.sector.deposit('F'),case.dates[0].cash)

    def test_exact_flat_hand_current_finance_matches_paid_ledger(self):
        a=opening();out=i.evaluate(a,m.Policy(3.5,3.5));case=financing(out)
        self.assertTrue(case.complete,case.reason)
        row=case.dates[0]
        self.assertEqual((row.project_draw,row.project_coupon,row.cash,row.bank_equity),
                         (0,0,3,F(91,10)))
        self.assertEqual((row.receipts,row.payroll,row.principal_paid),(5,3,0))
        p=c.prepare(a,m.Policy(3.5,3.5),project_units=out.forecast.units)
        actual=c.execute(p,c.controls(p));self.assertTrue(actual.ok,actual.reason)
        self.assertEqual(row.cash,actual.envelope.sector.deposit('F'))
        self.assertEqual(row.bank_equity,actual.envelope.sector.bank_equity('B'))

    def test_operating_value_excludes_finance_and_each_positive_baseline_is_retained(self):
        a=m.initial(growth=0);out=i.evaluate(a,m.Policy(3.5,3.5))
        self.assertEqual((len(out.quotation.rows),out.quotation.scalar_rows),(228,228))
        self.assertEqual(out.executor_calls,0)
        self.assertLessEqual(out.financing_dates,228)
        self.assertTrue(all(z.baseline_ok is not None for z in out.cells))
        for cell in out.quotation.cells:
            def pv(action):return sum(r.present_value for r in out.quotation.rows
                if (r.action,r.demand_sign,r.fulfilled)==(action,cell.demand_sign,cell.fulfilled))
            self.assertEqual(cell.now_value,pv('NOW')-pv('NEVER'))

    def test_no_executor_or_recursive_choice_inside_quotation(self):
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No paid forecast')):
            out=i.evaluate(m.initial(growth=0),m.Policy(3.5,3.5))
        self.assertEqual(out.executor_calls,0)

    def test_physical_table_is_built_once_not_counted_twice_as_228(self):
        with patch.object(i.p,'evaluate',wraps=i.p.evaluate) as quote:
            out=i.evaluate(m.initial(growth=0),m.Policy(3.5,3.5))
        self.assertEqual(quote.call_count,1)
        self.assertEqual(out.quotation.scalar_rows,228)

    def test_conditional_draw_coupon_and_principal_reconcile_without_zero_claims(self):
        out=i.evaluate(missing_pipeline(),m.Policy(3.5,3.5));case=financing(out)
        self.assertTrue(case.complete,case.reason)
        draw=case.dates[0].project_draw
        self.assertGreater(draw,0)
        self.assertEqual(sum(r.project_principal_paid for r in case.dates),draw)
        self.assertEqual(case.dates[-1].project_outstanding,0)
        self.assertEqual(case.dates[0].project_outstanding,draw)
        self.assertGreater(case.draw_probes,0)

    def test_negative_coupons_use_bank_payer_and_reduce_earned_income(self):
        out=i.evaluate(missing_pipeline(),m.Policy(-3,-3));case=financing(out)
        self.assertTrue(case.complete,case.reason)
        row=case.dates[0]
        self.assertLess(row.project_coupon,0)
        self.assertEqual(row.bank_interest,F(1,10)+row.operating_coupon+row.project_coupon)
        self.assertLessEqual(row.bank_equity,F(91,10))
        self.assertEqual(next(z.rate_pct for z in out.forecast.base.opening.sector.loans if z.id=='L0'),4)

    def test_bank_reservation_counts_old_maturing_face_at_open(self):
        a=missing_pipeline();loan=replace(a.sector.loans[0],maturity=1)
        a=replace(a,sector=replace(a.sector,loans=(loan,)))
        out=i.evaluate(a,m.Policy(3.5,3.5));row=financing(out).dates[0]
        self.assertEqual(row.opening_risk,10)
        self.assertGreaterEqual(row.project_ceiling,0)

    def test_protected_project_maturity_never_becomes_legacy_roll(self):
        a=opening();z=a.sector.loans[0]
        protected=l.ProjectLoan(z.id,z.lender,z.face,z.rate_pct,2,z.start,
                                last_coupon_paid=z.last_coupon_paid,allowance=z.allowance,borrower=z.borrower)
        a=replace(a,sector=replace(a.sector,loans=(protected,)))
        out=i.evaluate(a,m.Policy(3.5,3.5))
        self.assertFalse(financing(out,'NEVER').complete)
        self.assertEqual(out.quotation.decision.status,'baseline_incomplete')

    def test_unsupported_bank_ownership_is_unknown_not_approved(self):
        a=opening();z=replace(a.sector.loans[0],lender='A')
        a=replace(a,sector=replace(a.sector,loans=(z,)))
        out=i.evaluate(a,m.Policy(3.5,3.5))
        self.assertTrue(all(z.complete is None for z in out.financing))
        self.assertEqual(out.quotation.decision.status,'admission_incomplete')

    def test_actual_missing_pipeline_adoption_is_funded_and_recomputed_once(self):
        a=missing_pipeline();before=repr(a)
        real=l.advance_given_orders
        with patch.object(l,'advance_given_orders',wraps=real) as execute:
            out=i.adopt(a,m.Policy(3.5,3.5))
        self.assertEqual(execute.call_count,1)
        self.assertTrue(out.transition.ok,out.transition.reason)
        self.assertEqual(out.plan.quotation.decision.action,'NOW')
        self.assertGreater(out.transition.envelope.sector.wip_units,0)
        self.assertEqual(repr(a),before)
        self.assertEqual(out.error.requested_units,out.plan.forecast.units)
        self.assertEqual(out.error.paid_units,out.transition.envelope.sector.wip_units)

    def test_monetary_scale_does_not_change_physical_choice(self):
        a=i.evaluate(missing_pipeline(),m.Policy(3.5,3.5))
        b=i.evaluate(missing_pipeline(7),m.Policy(3.5,3.5))
        self.assertEqual(a.forecast.units,b.forecast.units)
        self.assertEqual(a.quotation.decision.action,b.quotation.decision.action)
        self.assertEqual(b.quotation.cells[0].now_value,7*a.quotation.cells[0].now_value)
        for x,y in zip(financing(a).dates,financing(b).dates):
            self.assertEqual((y.cash,y.bank_equity),(7*x.cash,7*x.bank_equity))

    def test_failed_bank_capital_does_not_approve_unfunded_now_draw(self):
        a=missing_pipeline();z=replace(a.sector.loans[0],allowance=F(17,2))
        a=replace(a,sector=replace(a.sector,loans=(z,)))
        out=i.evaluate(a,m.Policy(3.5,3.5));case=financing(out)
        self.assertFalse(case.complete)
        self.assertEqual(case.reason,'project_funding')


if __name__=='__main__':unittest.main()
