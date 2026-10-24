"""Paid sales-driven quarter contract, not autonomous-reference acceptance."""
from dataclasses import replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import coupled as c, macro as m, ledger as l
from scripts.research.funded_production import households as h, checkpoint as k


def opening(scale=1):
    a=m.initial(scale=scale,growth=0)
    return replace(a,macro=replace(a.macro,price_history=(100.,)*5,
        annualized_quarterly_inflation_pct=0,four_quarter_inflation_pct=0,
        expected_short_inflation_pct=0,expected_long_inflation_pct=0))


class CoupledQuarterTests(unittest.TestCase):
    def test_explicit_reference_project_hiring_and_paid_macro(self):
        a=opening();p=c.prepare(a,m.Policy(3.5,3.5),project_units=1)
        self.assertEqual((p.orders.residual_workers,p.orders.focal_workers),(17,3))
        self.assertEqual((p.forecast_residual,p.forecast_services),(F(363,20),5))
        out=c.execute(p,c.controls(p))
        self.assertTrue(out.ok,out.reason)
        self.assertEqual(out.envelope.sector.last.real_output,25)
        self.assertEqual(out.envelope.macro.actual_output_index,100)
        self.assertEqual(out.envelope.macro.unemployment_rate_pct,
                         100*(1-20/a.macro.workforce))
        self.assertEqual(c.execute(p,c.controls(p)),out)
        k._paid_economy(out.envelope)

    def test_default_has_no_forced_replacement_and_no_unqualified_investment(self):
        p=c.prepare(opening(),m.Policy(3.5,3.5))
        self.assertEqual(p.orders.investment_units,0)
        self.assertEqual(p.private_planner_status,'unqualified_no_project')
        out=c.execute(p,c.controls(p))
        self.assertTrue(out.ok,out.reason)
        self.assertEqual(out.envelope.sector.wip_units,0)
        self.assertFalse(any(isinstance(z,l.ProjectLoan) for z in out.envelope.sector.loans))

    def test_aggregate_is_does_not_generate_consumption_or_employment(self):
        a=opening();other=replace(a,macro=replace(a.macro,financial_restraint_pct=50))
        p=c.prepare(a,m.Policy(3.5,3.5));q=c.prepare(other,m.Policy(3.5,3.5))
        self.assertEqual(p.orders,q.orders)
        first=c.execute(p,c.controls(p));second=c.execute(q,c.controls(q))
        self.assertEqual(first.envelope.sector,second.envelope.sector)
        self.assertEqual((first.envelope.macro.consumption_state_pct,
                          first.envelope.macro.deferred_consumption_units),(0,0))

    def test_legacy_demand_stocks_are_not_silently_deleted(self):
        for field in ('consumption_state_pct','deferred_consumption_units'):
            a=opening();a=replace(a,macro=replace(a.macro,**{field:1}))
            with self.assertRaises(ValueError):c.prepare(a,m.Policy(3.5,3.5))

    def test_preference_impulse_once_before_wallet_cap(self):
        z=h.cash_stock_budget(opening_cash=1,paid_wages=1,previous_income=10,
            forecast_income=10,cash_ratio=0,demand_multiplier=F(1,10))
        self.assertEqual((z.desired,z.wallet,z.funded),(F(41,40),2,F(41,40)))
        a=opening();p=c.prepare(a,m.Policy(3.5,3.5),m.News(demand_shock_pct=-10))
        self.assertLess(p.forecast_residual,F(363,20))
        out=c.execute(p,c.controls(p));self.assertTrue(out.ok,out.reason)
        for note in (t for t in out.envelope.sector.last.trace if t.kind=='household_budget'):
            d=dict(note.details)
            q=h.cash_stock_budget(opening_cash=d['opening_cash'],paid_wages=d['paid_wages'],
                previous_income=d['income_previous'],forecast_income=d['income_forecast'],
                cash_ratio=d['cash_ratio'],demand_multiplier=p.orders.demand_multiplier)
            self.assertEqual((d['desired'],d['funded']),(q.desired,q.funded))

    def test_simultaneous_workforce_not_funded_by_future_dividends(self):
        a=opening();a=replace(a,macro=replace(a.macro,workforce=10))
        p=c.prepare(a,m.Policy(3.5,3.5),project_units=1)
        self.assertEqual(p.orders.residual_workers+p.orders.focal_workers,10)
        self.assertEqual((p.orders.residual_workers,p.orders.focal_workers),(F(17,2),F(3,2)))
        out=c.execute(p,c.controls(p));self.assertTrue(out.ok,out.reason)
        r=out.envelope.sector.last
        self.assertLessEqual(r.paid_residual_workers+r.paid_focal_workers,10)
        for t in (z for z in r.trace if z.kind=='household_budget'):
            d=dict(t.details)
            self.assertLessEqual(d['funded'],d['opening_cash']+d['paid_wages'])

    def test_current_vintage_calendar_includes_only_committed_wip(self):
        s=l.initial_depth_reference()
        self.assertEqual(c.known_capital(s),tuple(map(F,range(16,0,-1)))+(F(0),)*3)
        s=replace(s,vintages=(l.Vintage(14,2,1),l.Vintage(15,3,1)),wip_units=5)
        self.assertEqual(c.known_capital(s),(F(7),)+(F(5),)*15+(F(0),)*3)

    def test_calendar_matches_actual_paid_opening_aging(self):
        a=opening();calendar=c.known_capital(a.sector)
        for date in range(3):
            p=c.prepare(a,m.Policy(3.5,3.5));out=c.execute(p,c.controls(p))
            self.assertTrue(out.ok,out.reason)
            self.assertEqual(out.envelope.sector.capital_units,calendar[date])
            a=out.envelope

    def test_failed_finance_returns_identical_opening_and_no_partial_report(self):
        a=opening();p=c.prepare(a,m.Policy(3.5,3.5));before=repr(a)
        finance=replace(c.controls(p),new_loans=(l.OperatingLoanOffer('A',10**6,4,2,borrower='R'),))
        out=c.execute(p,finance)
        self.assertFalse(out.ok)
        self.assertIs(out.envelope,a)
        self.assertEqual(repr(a),before)
        self.assertEqual(out.committed_calls,1)

    def test_next_payroll_and_income_forecast_uses_only_last_paid_report(self):
        p=c.prepare(opening(),m.Policy(3.5,3.5),m.News(demand_shock_pct=-10))
        out=c.execute(p,c.controls(p));self.assertTrue(out.ok,out.reason)
        q=c.prepare(out.envelope,m.Policy(3.5,3.5));last=out.envelope.sector.last
        wage=q.opening.sector.scale*q.orders.price_factor*q.orders.real_wage
        self.assertEqual(q.forecast_payroll,(last.paid_residual_workers*wage,last.paid_focal_workers*wage))
        self.assertEqual(q.orders.expected_dividends_nominal,
            (last.dividend_residual+last.bank_dividend_to('HA'),
             last.dividend_focal+last.bank_dividend_to('HB')))

    def test_quote_only_does_not_evaluate_discarded_is_and_cannot_execute_legacy(self):
        a=opening();a=replace(a,macro=replace(a.macro,financial_restraint_pct=-10**9))
        p=c.prepare(a,m.Policy(3.5,3.5))
        self.assertEqual(p.orders,c.prepare(opening(),m.Policy(3.5,3.5)).orders)
        public=m.prepare(opening(),m.Policy(3.5,3.5),_quotes_only=True)
        with self.assertRaises(ValueError):m.execute(public,l.Controls())

    def test_closing_dividend_buffer_uses_actual_paid_payroll_not_detached_floor(self):
        s=l.initial_depth_reference();book=s.public_book
        rolls=(book.treasuries[0],book.private_treasuries[0][0],book.private_treasuries[1][0])
        controls=l.Controls(household_mode='cash_stock_close_v1',facility_limits=(100,100),
            public_instructions=l.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls)))
        orders=replace(l.depth_orders(),market_clearing=True,cash_floor_r=10**6,cash_floor_f=10**6)
        out=l.advance_given_orders(s,orders,controls);self.assertTrue(out.ok,out.reason)
        self.assertEqual((out.state.last.dividend_residual,out.state.last.dividend_focal),(3,F(1,20)))

    def test_negative_policy_quotes_fixed_legacy_claim_and_no_project_renewal(self):
        p=c.prepare(opening(),m.Policy(-3,-3),project_units=1)
        controls=c.controls(p)
        self.assertLess(controls.project_commitment.rate_pct,0)
        self.assertEqual(next(z.rate_pct for z in p.opening.sector.loans if z.id=='L0'),4)
        out=c.execute(p,controls);self.assertTrue(out.ok,out.reason)
        self.assertTrue(all(not isinstance(z,l.ProjectLoan) for z in out.envelope.sector.loans))

    def test_preparation_is_verified_and_wrong_modes_or_public_programs_rejected(self):
        p=c.prepare(opening(),m.Policy(3.5,3.5))
        with self.assertRaises(ValueError):c.execute(replace(p,orders=l.depth_orders()),c.controls(p))
        with self.assertRaises(ValueError):c.execute(p,replace(c.controls(p),household_mode='fixed'))
        with self.assertRaises(NotImplementedError):
            c.execute(p,replace(c.controls(p),asset_purchase_request=1))
        for kwargs in (dict(project_units=F(1,10**7)),dict(project_units=True)):
            with self.assertRaises((ValueError,TypeError)):c.prepare(opening(),m.Policy(3.5,3.5),**kwargs)

    def test_nominal_scale_preserves_real_paid_path_and_deterministic_reexecution(self):
        outcomes=[]
        for scale in (1,7):
            a=opening(scale);p=c.prepare(a,m.Policy(3.5,3.5),project_units=1)
            out=c.execute(p,c.controls(p));self.assertTrue(out.ok,out.reason)
            outcomes.append(out.envelope)
        self.assertEqual(outcomes[0].macro,outcomes[1].macro)
        self.assertEqual(outcomes[1].sector.last.real_output,outcomes[0].sector.last.real_output)
        self.assertEqual(outcomes[1].sector.deposit('HA'),7*outcomes[0].sector.deposit('HA'))

    def test_multiplier_cannot_silently_change_legacy_household_modes(self):
        orders=replace(l.depth_orders(),market_clearing=True,demand_multiplier=F(1,2))
        with self.assertRaises(ValueError):l.advance_given_orders(l.initial_depth_reference(),orders)
        for value in (True,-1,float('inf')):
            with self.assertRaises((ValueError,TypeError)):
                h.cash_stock_budget(opening_cash=1,paid_wages=1,previous_income=1,
                    forecast_income=1,cash_ratio=0,demand_multiplier=value)


if __name__=='__main__':unittest.main()
