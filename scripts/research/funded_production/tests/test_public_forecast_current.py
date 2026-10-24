"""Current-only public bridge contracts; no future planner/recovery acceptance."""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_forecast as p
from scripts.research.funded_production import coupled as c, macro as m, ledger as l
from scripts.research.funded_production import households as h, checkpoint as k
from scripts.research.funded_production import public_income as income
from scripts.research.funded_production.tests.test_public_funding import fixture, pools, with_rrp


POLICY = m.Policy(3.5, 3.5)


def opening(scale=1, **rates):
    a = m.initial(scale=scale, growth=0)
    a = replace(a, macro=replace(a.macro, price_history=(100.,) * 5,
        annualized_quarterly_inflation_pct=0, four_quarter_inflation_pct=0,
        expected_short_inflation_pct=0, expected_long_inflation_pct=0))
    terms = l.public_income_terms(a.sector, **rates)
    return replace(a, sector=l.enable_funded_public(a.sector, terms))


def step(a, *, iorb=0, limits=None, **instructions):
    book = a.sector.public_book
    rolls = tuple(row[0] for row in (book.treasuries, *book.private_treasuries))
    fiscal = l.FundedPublicInstructions(treasury_rolls=rolls,
        treasury_issue_authorization=sum(rolls), **instructions)
    return p.PublicStep(iorb, fiscal,
        (100 * a.sector.scale,) * 2 if limits is None else limits)


class PublicCurrentTests(unittest.TestCase):
    def test_equality_spoofing_source_records_refuse_before_executor(self):
        class EqualFloat(float):
            def __eq__(self, other):
                return True

        a = opening()
        quote = p.prepare(a, POLICY, step(a))
        finance = p.controls(quote)

        class EqualSource:
            def __eq__(self, other):
                return True

            def __getattr__(self, name):
                return getattr(quote.source, name)

        for source in (replace(quote.source, price_index=EqualFloat(101)), EqualSource()):
            with self.subTest(source=type(source).__name__), patch.object(
                    l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
                with self.assertRaises((ValueError, TypeError)):
                    p.execute(replace(quote, source=source), finance)
                self.assertEqual(advance.call_count, 0)

    def test_callback_backed_fraction_cannot_hide_unsupported_qe(self):
        class FalseInt(int):
            @property
            def numerator(self):
                return self

            def __bool__(self):
                return False

        a = opening()
        quote = p.prepare(a, POLICY, step(a))
        one = F(FalseInt(1))
        self.assertIs(type(one.numerator), FalseInt)
        finance = replace(p.controls(quote), asset_purchase_request=one,
                          asset_offers=(one, 0))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            with self.assertRaises((ValueError, TypeError)):
                p.execute(quote, finance)
            self.assertEqual(advance.call_count, 0)

    def test_explicit_exact_immutable_step_and_api(self):
        a = opening(); command = step(a)
        self.assertEqual([f.name for f in fields(p.PublicStep)],
                         ['iorb_rate_pct', 'fiscal', 'facility_limits'])
        with self.assertRaises(FrozenInstanceError):
            command.iorb_rate_pct = 1
        for args in ((), (0,), (0, command.fiscal)):
            with self.assertRaises(TypeError): p.PublicStep(*args)
        self.assertIs(type(p.prepare(a, POLICY, command)), p.Prepared)

    def test_strict_scalar_callback_and_nonfinite_boundaries(self):
        class Callback(int):
            def __float__(self): raise AssertionError('callback executed')
        a = opening(); command = step(a)
        for value in (True, Callback(1), object(), float('nan'), float('inf')):
            with self.subTest(value=type(value)), self.assertRaises((TypeError, ValueError)):
                p.PublicStep(value, command.fiscal, (1, 1))
            with self.subTest(limits=type(value)), self.assertRaises((TypeError, ValueError)):
                p.PublicStep(0, command.fiscal, (value, 1))
            with self.subTest(project=type(value)), self.assertRaises((TypeError, ValueError)):
                p.prepare(a, POLICY, command, project_units=value)
        for limits in ([1, 1], (1,), (1, -1)):
            with self.assertRaises((TypeError, ValueError)):
                p.PublicStep(0, command.fiscal, limits)
        for fiscal in (None, l.PublicInstructions(), lambda: command.fiscal):
            with self.assertRaises(TypeError): p.PublicStep(0, fiscal, (1, 1))
        with self.assertRaises(ValueError):
            p.prepare(a, POLICY, command, project_units=F(1, 10**7))

    def test_funded_tga_subscription_chronology_and_typed_failure(self):
        s = fixture(faces=pools({1: 1}, {1: 1}),
            masses=pools({1: F(3, 10)}, {1: F(2, 5)}),
            reserves=(1, 1), deposits=(1, 1), tga=F(1, 20),
            mortgage_rates=(4, 4), iorb=10)
        a = replace(opening(), sector=s); before = repr(a)
        def command(sub):
            return p.PublicStep(10, l.FundedPublicInstructions(
                treasury_subscriptions=(sub, 0), subscription_coupon_mass=(0, None),
                treasury_issue_authorization=sub), (100, 100))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            quote = p.prepare(a, POLICY, command(F(1, 5)))
            self.assertEqual(quote.income_prefix.tga, F(3, 25))
            self.assertEqual(quote.income_prefix.reserves, (F(183, 200), F(203, 200)))
            with self.assertRaises(p.FundingFailure) as error:
                p.prepare(a, POLICY, command(F(1, 10)))
            self.assertEqual(error.exception.status, 'funding_failure')
            self.assertEqual(advance.call_count, 0)
        self.assertEqual(repr(a), before)

    def test_changed_iorb_uses_original_stocks_and_fixed_contracts(self):
        a = opening(treasury_rates_pct=(2, -1, 0), mortgage_rates_pct=(1, -1),
                    iorb_rate_pct=1)
        q = p.prepare(a, m.Policy(-3, -3), step(a, iorb=-4))
        s = a.sector; b = s.public_book
        self.assertIs(q.opening, a)
        self.assertIs(q.source.opening, a)
        self.assertIs(type(q.source.opening.sector.public_book), l.FundedPublicBook)
        self.assertEqual(q.projected_opening.terms.annual_treasury, b.terms.annual_treasury)
        self.assertEqual(q.projected_opening.terms.mortgage_rates_pct, b.terms.mortgage_rates_pct)
        self.assertEqual(q.projected_opening.terms.iorb_rate_pct, -4)
        self.assertEqual(tuple(z.basis for z in q.observations[5:7]),
                         tuple(bank.reserves for bank in s.banks))
        self.assertEqual(q.observations, income.quote(q.projected_opening.terms,
            treasuries=(b.treasuries, *b.private_treasuries), mortgages=b.mortgages,
            reserves=tuple(bank.reserves for bank in s.banks), cb_faces=(0, 0),
            rrp_faces=(0, 0), scale=s.scale))
        self.assertEqual(b.terms.iorb_rate_pct, 1)

    def test_returned_rrp_does_not_enlarge_current_iorb_basis(self):
        a = m.initial(growth=0); s = with_rrp(a.sector)
        s = l.enable_funded_public(s, l.public_income_terms(s, rrp_rates_pct=(4, None)))
        a = replace(a, sector=s)
        quote = p.prepare(a, POLICY, step(a, iorb=4))
        self.assertEqual(quote.projected_opening.rrp_faces, (1, 0))
        self.assertEqual(quote.observations[5].basis, s.reserves('A'))
        self.assertEqual(quote.observations[9].settled, F(1, 100))
        finance = p.controls(quote)
        tx = l._Transaction(s, finance, 1)
        tx.settle_funded_public(finance.public_instructions)
        self.assertEqual(tuple(tx.r.values()), quote.income_prefix.reserves)
        self.assertEqual((tx.d['HA'], tx.d['HB']), quote.income_prefix.household_deposits)

    def test_fractional_partial_roll_subscription_and_principal_prefix_parity(self):
        s = fixture(faces=pools({0: 2}, {0: 3}, {0: 4}),
            masses=pools({0: F(2, 5)}, {0: F(-4, 5)}, {0: F(6, 5)}))
        a = replace(opening(), sector=s)
        fiscal = l.FundedPublicInstructions(treasury_rolls=(1, 1, 0),
            treasury_subscriptions=(F(1, 5), 0), subscription_coupon_mass=(F(-1, 7), None),
            treasury_issue_authorization=F(11, 5), replacement_maturity=F(118, 5),
            mortgage_repayments=(F(1, 10), 0))
        q = p.prepare(a, POLICY, p.PublicStep(1, fiscal, (100, 100)))
        tx = l._Transaction(s, p.controls(q), 1)
        tx.settle_funded_public(fiscal)
        self.assertEqual(tx.public_book.terms, q.principal_prefix.terms)
        self.assertEqual(tuple(tx.r.values()), q.income_prefix.reserves)
        self.assertEqual(tuple(z.settled for z in q.observations[:3]),
                         (F(1, 10), F(-1, 5), F(3, 10)))
        self.assertEqual(sum(q.principal_prefix.terms.annual_treasury[1]),
                         F(-4, 15) - F(1, 7))

    def test_signed_household_income_wallet_and_forecast_once(self):
        a = opening(mortgage_rates_pct=(4, -4)); q = p.prepare(a, POLICY, step(a))
        current = tuple(-z.settled for z in q.observations[3:5])
        self.assertLess(current[0], 0); self.assertGreater(current[1], 0)
        previous = (20, F(63, 20)); divs = (3, F(3, 20))
        for i, owner in enumerate(('HA', 'HB')):
            expected_cash = a.sector.deposit(owner) + current[i]
            self.assertEqual(q.income_prefix.household_deposits[i], expected_cash)
            expected = h.net_cash_stock_budget(opening_cash=expected_cash,
                paid_wages=q.forecast_payroll[i], previous_income=previous[i],
                forecast_income=q.forecast_payroll[i] + divs[i] + current[i],
                cash_ratio=(F(3, 20), F(1, 21))[i])
            self.assertEqual(q.household_budgets[i], expected)
            self.assertEqual(expected.wallet, expected_cash + q.forecast_payroll[i])
            self.assertLessEqual(expected.funded, expected.wallet)
        self.assertEqual(q.orders.expected_dividends_nominal, divs)

    def test_public_bank_earnings_are_not_forecast_household_deposits(self):
        a = opening(); high = p.prepare(a, POLICY, step(a, iorb=40), project_units=1)
        zero = p.prepare(a, POLICY, step(a), project_units=1)
        self.assertGreater(high.income_prefix.earnings[1], zero.income_prefix.earnings[1])
        self.assertEqual(high.income_prefix.household_deposits,
                         zero.income_prefix.household_deposits)
        self.assertEqual(high.orders, zero.orders)
        self.assertEqual(high.household_budgets, zero.household_budgets)
        self.assertGreater(p.controls(high).project_commitment.face_ceiling,
                           p.controls(zero).project_commitment.face_ceiling)

    def test_paid_budget_reconciles_post_principal_signed_coupon_cash_once(self):
        a = opening(mortgage_rates_pct=(4, -4), cb_rates_pct=(0, 0))
        command = step(a, mortgage_repayments=(F(1, 10), 0))
        q = p.prepare(a, POLICY, command, m.News(demand_shock_pct=-5))
        out = p.execute(q, p.controls(q)); self.assertTrue(out.ok, out.reason)
        notes = {z.actor: dict(z.details) for z in out.envelope.sector.last.trace
                 if z.kind == 'household_budget'}
        for i, owner in enumerate(('HA', 'HB')):
            data = notes[owner]
            self.assertEqual(data['opening_cash'], q.income_prefix.household_deposits[i])
            current = -q.observations[3 + i].settled
            self.assertEqual(data['income_forecast'], data['paid_wages']
                             + q.orders.expected_dividends_nominal[i] + current)
            budget = h.net_cash_stock_budget(opening_cash=data['opening_cash'],
                paid_wages=data['paid_wages'], previous_income=data['income_previous'],
                forecast_income=data['income_forecast'], cash_ratio=data['cash_ratio'],
                demand_multiplier=q.orders.demand_multiplier)
            self.assertEqual((data['desired'], data['funded']), (budget.desired, budget.funded))
            self.assertLessEqual(data['funded'], q.income_prefix.household_deposits[i]
                                 + data['paid_wages'])
        self.assertEqual(out.envelope.sector.public_book.mortgages[0],
                         a.sector.public_book.mortgages[0] - F(1, 10))

    def test_negative_actual_disposable_income_is_not_erased_on_continuation(self):
        a = opening(mortgage_rates_pct=(4, 0), cb_rates_pct=(0, 0))
        q = p.prepare(a, POLICY, step(a), m.News(demand_shock_pct=-1000))
        out = p.execute(q, p.controls(q)); self.assertTrue(out.ok, out.reason)
        a = out.envelope
        self.assertLess(a.sector.last.disposable_income('HA'), 0)
        q = p.prepare(a, POLICY, step(a))
        self.assertEqual(q.previous_income[0], a.sector.last.disposable_income('HA'))
        self.assertLess(q.forecast_income[0], 0)
        self.assertEqual(q.household_budgets[0], h.net_cash_stock_budget(
            opening_cash=q.income_prefix.household_deposits[0],
            paid_wages=q.forecast_payroll[0], previous_income=q.previous_income[0],
            forecast_income=q.forecast_income[0], cash_ratio=F(3, 20)))

    def test_explicit_finance_and_authored_curve_not_iorb_mapping(self):
        a = opening(); q = p.prepare(a, m.Policy(-3, -3), step(a, iorb=4, limits=(0, 7)),
                                   project_units=1)
        finance = p.controls(q)
        self.assertIs(type(finance), l.PublicIncomeControls)
        self.assertEqual(finance.facility_limits, (0, 7))
        self.assertEqual(finance.iorb_rate_pct, 4)
        self.assertEqual(finance.public_instructions, q.step.fiscal)
        self.assertLess(finance.project_commitment.rate_pct, 0)
        self.assertEqual(next(z.rate_pct for z in a.sector.loans if z.id == 'L0'), 4)

    def test_preparation_is_zero_calls_and_execution_is_one_paid_call(self):
        a = opening(); before = repr(a)
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            q = p.prepare(a, POLICY, step(a), project_units=1)
            finance = p.controls(q)
            self.assertEqual(advance.call_count, 0)
            out = p.execute(q, finance)
            self.assertEqual(advance.call_count, 1)
            self.assertTrue(out.ok, out.reason)
            self.assertEqual(out.committed_calls, 1)
            self.assertIs(advance.call_args.args[0], a.sector)
            self.assertEqual(advance.call_args.args[1:], (q.orders, finance))
        self.assertEqual(repr(a), before)
        self.assertEqual(out.envelope.macro.actual_output_index,
                         4 * float(out.envelope.sector.last.real_output))
        k._paid_economy(out.envelope)

    def test_prepared_command_orders_opening_and_facility_tampering_zero_calls(self):
        a = opening(); q = p.prepare(a, POLICY, step(a)); finance = p.controls(q)
        changed_step = replace(q.step, fiscal=replace(q.step.fiscal,
            treasury_issue_authorization=q.step.fiscal.treasury_issue_authorization + 1))
        variants = (replace(q, step=changed_step),
            replace(q, step=replace(q.step, iorb_rate_pct=1)),
            replace(q, step=replace(q.step, facility_limits=(0, 0))),
            replace(q, opening=replace(a, macro=replace(a.macro, public_support=69))),
            replace(q, orders=replace(q.orders, residual_workers=q.orders.residual_workers + 1)),
            replace(q, income_prefix=replace(q.income_prefix, tga=q.income_prefix.tga + 1)))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            for changed in variants:
                with self.subTest(changed=changed), self.assertRaises(ValueError):
                    p.execute(changed, finance)
                with self.assertRaises(ValueError): p.controls(changed)
            self.assertEqual(advance.call_count, 0)

    def test_content_binding_detects_even_in_place_command_tampering(self):
        a = opening(); q = p.prepare(a, POLICY, step(a)); finance = p.controls(q)
        object.__setattr__(q.step, 'facility_limits', (F(0), F(0)))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            with self.assertRaises(ValueError): p.execute(q, finance)
            with self.assertRaises(ValueError): p.controls(q)
            self.assertEqual(advance.call_count, 0)

    def test_submitted_public_command_iorb_facilities_modes_and_qe_bound(self):
        a = opening(); q = p.prepare(a, POLICY, step(a)); finance = p.controls(q)
        changed_fiscal = replace(finance.public_instructions,
            treasury_issue_authorization=finance.public_instructions.treasury_issue_authorization + 1)
        variants = (replace(finance, public_instructions=changed_fiscal),
            replace(finance, iorb_rate_pct=1), replace(finance, facility_limits=(0, 0)),
            replace(finance, household_mode='fixed'), replace(finance, asset_purchase_request=1),
            replace(finance, asset_offers=(1, 0)), replace(finance, security_bids=(0, 0)),
            l.Controls(household_mode='cash_stock_close_v1'))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            for changed in variants:
                with self.subTest(changed=changed), self.assertRaises((ValueError, NotImplementedError)):
                    p.execute(q, changed)
            self.assertEqual(advance.call_count, 0)

    def test_actual_credit_refusal_returns_exact_predecessor_once(self):
        a = opening(); q = p.prepare(a, POLICY, step(a)); before = repr(a)
        finance = replace(p.controls(q), new_loans=(
            l.OperatingLoanOffer('A', 10**6, 4, 2, borrower='R'),))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            out = p.execute(q, finance)
            self.assertEqual(advance.call_count, 1)
            self.assertFalse(out.ok)
            self.assertIs(out.envelope, a)
            self.assertEqual(out.status, 'credit_constraint')
        self.assertEqual(repr(a), before)

    def test_zero_public_matches_legacy_coupled_actual_economic_path(self):
        a = opening(); legacy = replace(a, sector=m.initial(growth=0).sector)
        for units in (0, 1):
            q = p.prepare(a, POLICY, step(a), project_units=units)
            old = c.prepare(legacy, POLICY, project_units=units)
            self.assertEqual(q.orders, old.orders)
            public_out = p.execute(q, p.controls(q)); old_out = c.execute(old, c.controls(old))
            self.assertTrue(public_out.ok, public_out.reason)
            self.assertTrue(old_out.ok, old_out.reason)
            self.assertEqual(public_out.envelope.macro, old_out.envelope.macro)
            for name in ('banks', 'loans', 'cb_loans', 'vintages', 'wip_units', 'wip_basis', 'last'):
                self.assertEqual(getattr(public_out.envelope.sector, name),
                                 getattr(old_out.envelope.sector, name))

    def test_paid_previous_disposable_income_and_two_quarter_reexecution(self):
        a = opening(mortgage_rates_pct=(4, -4), cb_rates_pct=(0, 0))
        for date in range(2):
            q = p.prepare(a, POLICY, step(a, iorb=date + 1), m.News(demand_shock_pct=-5))
            if date:
                last = a.sector.last
                self.assertEqual(q.previous_income,
                    tuple(last.disposable_income(owner) for owner in ('HA', 'HB')))
                wage = a.sector.scale * q.orders.price_factor * q.orders.real_wage
                self.assertEqual(q.forecast_payroll,
                    (last.paid_residual_workers * wage, last.paid_focal_workers * wage))
                self.assertEqual(q.orders.expected_dividends_nominal,
                    (last.dividend_residual + last.bank_dividend_to('HA'),
                     last.dividend_focal + last.bank_dividend_to('HB')))
            out = p.execute(q, p.controls(q)); self.assertTrue(out.ok, out.reason)
            self.assertEqual(out, p.execute(q, p.controls(q)))
            k._paid_economy(out.envelope)
            a = out.envelope

    def test_forged_paid_report_rejected_before_quotation_and_execution(self):
        a = opening(mortgage_rates_pct=(4, 0))
        q = p.prepare(a, POLICY, step(a)); out = p.execute(q, p.controls(q))
        self.assertTrue(out.ok, out.reason)
        a = out.envelope
        bad_report = replace(a.sector.last, payments=tuple(z for z in a.sector.last.payments
                                                       if z.kind != 'mortgage_coupon'))
        forged = replace(a, sector=replace(a.sector, last=bad_report))
        with patch.object(m, '_quote_source', wraps=m._quote_source) as quote:
            with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
                with self.assertRaises(ValueError): p.prepare(forged, POLICY, step(forged))
                self.assertEqual((quote.call_count, advance.call_count), (0, 0))

    def test_nominal_scaling_preserves_real_path_and_paid_source_identity(self):
        outcomes = []
        for scale in (1, 7):
            a = opening(scale, mortgage_rates_pct=(4, -4), cb_rates_pct=(0, 0))
            q = p.prepare(a, POLICY, step(a, iorb=2), project_units=1)
            out = p.execute(q, p.controls(q)); self.assertTrue(out.ok, out.reason)
            k._paid_economy(out.envelope)
            outcomes.append(out.envelope)
        self.assertEqual(outcomes[0].macro, outcomes[1].macro)
        self.assertEqual(outcomes[1].sector.deposit('HA'), 7 * outcomes[0].sector.deposit('HA'))
        self.assertEqual(outcomes[1].sector.last.real_output, outcomes[0].sector.last.real_output)

    def test_no_discarded_is_no_demand_stock_deletion_and_legacy_guards(self):
        a = opening(); huge = replace(a, macro=replace(a.macro, financial_restraint_pct=-10**9))
        with patch.object(m, 'prepare', side_effect=AssertionError('guard bypass')):
            self.assertEqual(p.prepare(huge, POLICY, step(huge)).orders,
                             p.prepare(a, POLICY, step(a)).orders)
        for name in ('consumption_state_pct', 'deferred_consumption_units'):
            changed = replace(a, macro=replace(a.macro, **{name: 1}))
            with self.assertRaises(ValueError): p.prepare(changed, POLICY, step(changed))
        with self.assertRaises(NotImplementedError): m.prepare(a, POLICY)
        with self.assertRaises(NotImplementedError): c.prepare(a, POLICY)
        legacy = replace(a, sector=m.initial(growth=0).sector)
        with self.assertRaises(NotImplementedError): p.prepare(legacy, POLICY, step(a))

    def test_no_new_rrp_currency_redemption_or_implicit_cb_contracts(self):
        a = opening(); command = step(a)
        for changes in (dict(rrp_request=1), dict(rrp_offers=(1, 0)),
                        dict(currency_to_deposits=(1, 0)), dict(treasury_redemption=1)):
            with self.subTest(changes=changes), self.assertRaises(NotImplementedError):
                p.prepare(a, POLICY, replace(command, fiscal=replace(command.fiscal, **changes)))
        q = p.prepare(a, POLICY, command)
        self.assertEqual(q.projected_opening.terms.cb_rates_pct, (None, None))
        self.assertEqual(p.controls(q).iorb_rate_pct, 0)
        self.assertEqual(q.private_planner_status, 'unqualified_no_project')
        self.assertEqual(p.prepare(a, POLICY, command, project_units=1).private_planner_status,
                         'supplied_research_project')


if __name__ == '__main__': unittest.main()
