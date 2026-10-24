"""Current vertical slice; no aging study, future table or recovery claim."""
from dataclasses import FrozenInstanceError, replace
from fractions import Fraction as F
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_household_paydate as q
from scripts.research.funded_production import public_early_paydate as early, public_paydate as old
from scripts.research.funded_production import public_market as market, public_forecast as p
from scripts.research.funded_production import checkpoint as k, macro as m, ledger as l
from scripts.research.funded_production.tests import test_household_paydate_journal as j
from scripts.research.funded_production.tests.test_public_market import date


POLICY = m.Policy(3.5, 3.5)


def opening(**changes):
    return replace(m.initial(growth=0), sector=j.fixture(**changes))


def step(a, **changes):
    finance = j.controls(a.sector, **changes)
    return p.PublicStep(finance.iorb_rate_pct, finance.public_instructions, finance.facility_limits)


class HouseholdCurrentPureTests(unittest.TestCase):
    def setUp(self):
        self.guards = []
        for target, name in ((l, 'advance_given_orders'), (l, '_Transaction'), (m, '_close_paid')):
            guard = patch.object(target, name, side_effect=AssertionError('Pure quote only'))
            self.guards.append(guard.start()); self.addCleanup(guard.stop)

    def tearDown(self):
        self.assertTrue(all(guard.call_count == 0 for guard in self.guards))

    def test_new_exact_api_conditional_not_approval_and_frozen_not_adoptable(self):
        a = opening(); before = repr(a)
        prefix = q.quote_prefix(a, step(a)); prepared = q.prepare(a, POLICY, step(a))
        self.assertIs(type(prefix), q.PublicPrefix); self.assertIs(type(prepared), q.Prepared)
        self.assertIsNot(q.Prepared, early.Prepared)
        self.assertEqual(prepared.household_liquidity_status, 'conditional_at_actual_payroll')
        self.assertFalse(hasattr(prepared, 'household_credit'))
        self.assertEqual(prepared.income_prefix.wallets[3], 2)
        self.assertEqual(prepared.observations[4].settled, F(1, 100))
        self.assertEqual(prepared.source.orders, prepared.orders)
        self.assertIs(prepared.source.opening, a)
        self.assertIs(type(q.controls(prepared)), l.PublicIncomeControls)
        with self.assertRaises(FrozenInstanceError): prepared.household_liquidity_status = 'approved'
        with self.assertRaises((TypeError, ValueError)): k._pack(prepared)
        self.assertEqual(repr(a), before)

    def test_old_apis_and_market_routes_reject_new_book_exactly(self):
        a = opening()
        for adapter in (old, early):
            with self.assertRaises((TypeError, NotImplementedError)): adapter.prepare(a, POLICY, step(a))
        for resolver in (market.resolve_date, market.resolve_paydate_date, market.resolve_early_paydate_date):
            with self.assertRaises(TypeError): resolver(a, date())
        resolved = market.resolve_household_paydate_date(a, date())
        self.assertIs(type(resolved), market.s.ResolvedDate)
        other = replace(a, sector=j.fixture(convention='early'))
        with self.assertRaises((TypeError, NotImplementedError)): q.prepare(other, POLICY, step(other))

    def test_no_anticipated_household_credit_changes_hiring_or_wallets(self):
        a = opening(old=0, reserve=5, rate=-4)
        b = replace(a, sector=j.fixture(old=0, reserve=5, rate=-4, convention='early'))
        left = q.prepare(a, POLICY, step(a), project_units=F(1, 4))
        right = early.prepare(b, POLICY, step(b), project_units=F(1, 4))
        for name in ('orders', 'household_budgets', 'forecast_payroll', 'forecast_income', 'previous_income'):
            self.assertEqual(getattr(left, name), getattr(right, name))
        self.assertEqual(left.orders.expected_dividends_nominal, (3, F(3, 20)))
        self.assertEqual(left.previous_income, (20, F(63, 20)))
        self.assertEqual(left.income_prefix.wallets[3], 2)

    def test_prepared_and_public_command_tamper_refuse_before_actual_attempt(self):
        a = opening(); prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
        for changed in (replace(prepared, household_liquidity_status='approved'),
            replace(prepared, step=replace(prepared.step, facility_limits=(100, 101))),
            replace(prepared, opening=replace(a, macro=replace(a.macro, public_support=69))),
            replace(prepared, household_budgets=(replace(prepared.household_budgets[0], desired=1), prepared.household_budgets[1]))):
            with self.assertRaises((TypeError, ValueError)): q.execute(changed, finance)
        for changed in (replace(finance, iorb_rate_pct=1), replace(finance, facility_limits=(100, 101)),
            replace(finance, public_instructions=replace(finance.public_instructions, treasury_issue_authorization=1))):
            with self.assertRaises(ValueError): q.execute(prepared, changed)

    def test_nested_metadata_aliases_and_source_failure_precede_construction(self):
        calls = []
        class Alias(float):
            def __eq__(self, other): calls.append('equality'); return True
        a = opening(); prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
        altered = replace(prepared, source=replace(prepared.source, price_index=Alias(100)))
        with self.assertRaises((TypeError, ValueError)): q.execute(altered, finance)
        object.__setattr__(prepared.early_plan, '__dataclass_fields__', {})
        with self.assertRaises((TypeError, ValueError)): q.controls(prepared)
        self.assertEqual(calls, [])
        with patch.object(k, '_check_sources', side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError, 'source drift'): q.prepare(a, POLICY, step(a))
        self.assertEqual(k._SOURCES['public_household_paydate'], hashlib.sha256(Path(q.__file__).read_bytes()).hexdigest())


class HouseholdCurrentActualTests(unittest.TestCase):
    def test_one_actual_paid_macro_close_source_price_orders_and_prior_validation(self):
        a = opening(); before = repr(a)
        prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
        counters = dict(j.COUNTS)
        with j.counted_actual(): out = q.execute(prepared, finance)
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(j.COUNTS['attempts']-counters['attempts'], 1)
        self.assertEqual(j.COUNTS['macro_closes']-counters['macro_closes'], 1)
        self.assertEqual(out.envelope.macro.actual_output_index, 4*float(out.envelope.sector.last.real_output))
        self.assertEqual(out.envelope.macro.price_index, prepared.source.price_index)
        self.assertEqual(repr(a), before)
        a = out.envelope
        with patch.object(l, 'advance_given_orders', side_effect=AssertionError('No replay')) as raw, \
             patch.object(l, '_Transaction', side_effect=AssertionError('No replay')) as tx:
            next_quote = q.prepare(a, POLICY, step(a, iorb_rate_pct=-4))
            self.assertEqual(next_quote.previous_income, tuple(a.sector.last.disposable_income(h) for h in ('HA', 'HB')))
            self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 0)
            for field in ('payments', 'trace'):
                report = replace(a.sector.last); sector = replace(a.sector); root = replace(a)
                object.__setattr__(report, field, getattr(report, field)[1:])
                object.__setattr__(sector, 'last', report); object.__setattr__(root, 'sector', sector)
                with self.assertRaises((TypeError, ValueError)): q.prepare(root, POLICY, step(root, iorb_rate_pct=4))
            self.assertEqual((raw.call_count, tx.call_count), (0, 0))

    def test_one_actual_custom_credit_refusal_keeps_exact_predecessor(self):
        a = opening(); prepared = q.prepare(a, POLICY, step(a)); before = repr(a)
        finance = replace(q.controls(prepared), new_loans=(l.OperatingLoanOffer('A', 10**6, 4, 2, borrower='R'),))
        counters = dict(j.COUNTS)
        with j.counted_actual(): out = q.execute(prepared, finance)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'credit_constraint')
        self.assertIs(out.envelope, a); self.assertEqual(repr(a), before)
        self.assertEqual(j.COUNTS['attempts']-counters['attempts'], 1)
        self.assertEqual(j.COUNTS['macro_closes']-counters['macro_closes'], 0)


if __name__ == '__main__': unittest.main()
