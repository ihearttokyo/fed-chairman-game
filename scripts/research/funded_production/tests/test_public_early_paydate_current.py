"""Bounded current-quarter early-credit bridge; not Q4/recovery qualification.

Pure tests forbid BOTH transactions and raw execution. Actual tests count raw
paid/refused/exceptions separately from positive paid macro closes. All stocks
are fresh synthetic Q0 fixtures, never converted paid strict-calendar books.
"""
from contextlib import contextmanager
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import hashlib
import inspect
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_early_paydate as q
from scripts.research.funded_production import public_paydate as old
from scripts.research.funded_production import public_forecast as p, coupled as c
from scripts.research.funded_production import checkpoint as k, macro as m, ledger as l
from scripts.research.funded_production import public_scenarios as scenarios
from scripts.research.funded_production import paydate_households as household
from scripts.research.funded_production.tests.test_public_paydate_journal import legacy, pools


POLICY = m.Policy(3.5, 3.5)
COUNTS = dict(attempts=0, paid=0, refused=0, raw_exceptions=0,
              macro_close_calls=0, macro_closes=0, macro_exceptions=0)


def opening(*, old_face=1, old_id='OLD:B', reserve=F(1, 10**6),
            cb_rates=(0, 4), early=True, **changes):
    values = dict(reserves=(5, reserve), mortgage_rates=(0, 0), cb_rates=cb_rates)
    values.update(changes)
    sector, terms = legacy(**values)
    if old_face:
        loan = l.CBLoan(old_id, 'B', F(old_face), 0, 1,
                        l._pledges(sector, 'B', F(old_face)))
        sector = replace(sector, cb_loans=(loan,), public_book=replace(sector.public_book,
            capital_other=sector.public_book.capital_other + old_face))
    factory = l.enable_early_paydate_public if early else l.enable_paydate_public
    a = m.initial(growth=0)
    return replace(a, sector=factory(sector, terms), macro=replace(a.macro,
        price_history=(100.,)*5, annualized_quarterly_inflation_pct=0,
        four_quarter_inflation_pct=0, expected_short_inflation_pct=0,
        expected_long_inflation_pct=0))


def step(a, *, iorb=0, limit=2, **changes):
    book = a.sector.public_book
    rolls = tuple(row[0] for row in (book.treasuries, *book.private_treasuries))
    values = dict(treasury_rolls=rolls, treasury_issue_authorization=sum(rolls))
    values.update(changes)
    return p.PublicStep(iorb, l.FundedPublicInstructions(**values), (100, limit))


@contextmanager
def pure():
    with patch.object(l, 'advance_given_orders', side_effect=AssertionError('Pure quote')) as raw, \
         patch.object(l, '_Transaction', side_effect=AssertionError('Pure quote')) as tx, \
         patch.object(m, '_close_paid', side_effect=AssertionError('Pure quote')) as close:
        yield
        assert (raw.call_count, tx.call_count, close.call_count) == (0, 0, 0)


class EarlyCurrentPureTests(unittest.TestCase):
    def test_distinct_exact_api_frozen_records_and_zero_transactions(self):
        a = opening(); before = repr(a)
        with pure():
            prefix = q.quote_prefix(a, step(a))
            prepared = q.prepare(a, POLICY, step(a))
            finance = q.controls(prepared)
            self.assertIs(type(prefix), q.PublicPrefix)
            self.assertIs(type(prepared), q.Prepared)
            self.assertIsNot(q.Prepared, old.Prepared)
            self.assertIsNot(q.PublicPrefix, old.PublicPrefix)
            self.assertIs(q.PublicStep, p.PublicStep)
            self.assertIs(q.FundingFailure, p.FundingFailure)
            self.assertEqual(str(inspect.signature(q.prepare)),
                str(inspect.signature(old.prepare)))
            for name in ('opening', 'policy', 'step', 'news', 'source', 'orders'):
                self.assertTrue(hasattr(prepared, name))
            self.assertIs(prepared.opening, a)
            self.assertIs(prepared.source.opening, a)
            self.assertIs(type(finance), l.PublicIncomeControls)
            with self.assertRaises(FrozenInstanceError): prepared.orders = l.depth_orders()
            with self.assertRaises((TypeError, ValueError)): k._pack(prepared)
        self.assertEqual(repr(a), before)

    def test_original_bases_and_gross_net_are_separate(self):
        a = opening()
        with pure():
            prefix = q.quote_prefix(a, step(a))
            plan = prefix.early_plan
            self.assertEqual(len(prefix.observations), 11)
            self.assertEqual(prefix.observations[8].basis, 1)
            self.assertEqual(prefix.observations[8].settled, F(1, 100))
            self.assertEqual(prefix.observations[6].basis, a.sector.reserves('B'))
            self.assertEqual(plan.refinanced, (0, 1))
            self.assertEqual(plan.advances[1], F(9999, 10**6))
            self.assertEqual(plan.gross_used[1], 1 + plan.advances[1])
            self.assertEqual(prefix.credit_prefix.reserves[1], F(1, 100))
            self.assertEqual(prefix.credit_prefix.cb_faces, plan.replacement_faces)
            self.assertEqual(prefix.income_prefix.reserves, plan.coupon_reserves)
            self.assertEqual(prefix.credit_prefix.wallets, prefix.principal_snapshot.wallets)
            self.assertEqual(prefix.credit_prefix.tga, prefix.principal_snapshot.tga)
            self.assertEqual(prefix.income_prefix.wallets, prefix.principal_snapshot.wallets)
            self.assertEqual(prefix.income_prefix.deferred, a.sector.public_book.deferred_asset)

    def test_collateral_and_equity_use_postprincipal_not_opening_stocks(self):
        a = opening(faces=pools({0:1}, {0:2, 5:16}, {0:2, 5:8}))
        with pure():
            base = q.quote_prefix(a, step(a))
            issued = q.quote_prefix(a, step(a, treasury_subscriptions=(1, 0),
                subscription_coupon_mass=(F(1, 10), None),
                treasury_issue_authorization=sum(step(a).fiscal.treasury_rolls) + 1))
            redeemed = q.quote_prefix(a, step(a, treasury_rolls=(0, 0, 0),
                treasury_issue_authorization=0))
            self.assertEqual(issued.early_plan.capacities[0] - base.early_plan.capacities[0], l.HAIRCUT_VALUE)
            self.assertEqual(base.early_plan.capacities[1] - redeemed.early_plan.capacities[1], 2*l.HAIRCUT_VALUE)
            self.assertEqual(issued.early_plan.equities, base.early_plan.equities)
            self.assertEqual(redeemed.early_plan.equities, base.early_plan.equities)
            self.assertEqual(issued.observations, base.observations)
            self.assertEqual(redeemed.observations, base.observations)
            self.assertEqual(issued.principal_snapshot.treasuries, issued.principal_prefix.treasuries)

    def test_full_and_partial_refinance_exact_cash_repayment(self):
        a = opening(reserve=2)
        with pure():
            prefix = q.quote_prefix(a, step(a, limit=F(1, 2)))
            self.assertEqual(prefix.early_plan.refinanced[1], F(1, 2))
            self.assertEqual(prefix.early_plan.cash_repayments[1], F(1, 2))
            self.assertEqual(prefix.early_plan.gross_used[1], F(1, 2))
            self.assertEqual(prefix.credit_prefix.reserves[1], F(3, 2))

    def test_true_prefix_shortage_is_not_missing_coverage(self):
        with pure():
            a = opening()
            with self.assertRaises(p.FundingFailure): q.prepare(a, POLICY, step(a, limit=1))
            a = opening(old_face=0, tga=0, masses=pools({5:1}))
            with self.assertRaises(p.FundingFailure): q.prepare(a, POLICY, step(a))
            a = opening(firms=(17, 30), masses=pools(b={5:100}))
            # Current negative equity cannot be repaired by anticipated public earnings.
            with self.assertRaises(p.FundingFailure):
                q.prepare(a, POLICY, step(a, iorb=-4), m.News(), project_units=1)

    def test_missing_new_credit_contract_unknown_but_explicit_zero_valid(self):
        changes = dict(old_face=0, reserve=0, masses=pools(b={5:-4}))
        with pure():
            a = opening(cb_rates=(0, None), **changes)
            with self.assertRaises(scenarios.MissingCoverage): q.quote_prefix(a, step(a))
            a = opening(cb_rates=(0, 0), **changes)
            prefix = q.quote_prefix(a, step(a))
            self.assertEqual(prefix.early_plan.advances[1], 1)
            self.assertEqual(prefix.early_plan.cb_rates_pct[1], 0)
            self.assertEqual(prefix.observations[8].basis, 0)

    def test_signed_rates_and_household_income_enter_intentions_once(self):
        with pure():
            for rate in (-4, 0, 4):
                a = opening(reserve=5, cb_rates=(0, rate), mortgage_rates=(4, -4))
                prefix = q.prepare(a, m.Policy(-3, -3), step(a, iorb=rate,
                    mortgage_repayments=(F(1, 10), 0)))
                self.assertEqual(prefix.observations[6].basis, 5)
                self.assertEqual(prefix.observations[8].basis, 1)
                self.assertEqual(prefix.observations[3].basis, 1)
                self.assertEqual(prefix.income_prefix.wallets[2], F(29, 10))
                self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 0)
                for i, ratio in enumerate((F(3, 20), F(1, 21))):
                    signed = -prefix.observations[3+i].settled
                    self.assertEqual(prefix.forecast_income[i], prefix.forecast_payroll[i]
                        + prefix.orders.expected_dividends_nominal[i] + signed)
                    actual = household.cash_stock_budget(opening_cash=prefix.principal_prefix.household_deposits[i],
                        paid_wages=prefix.forecast_payroll[i], settled_income=signed,
                        previous_income=prefix.previous_income[i], forecast_income=prefix.forecast_income[i],
                        cash_ratio=ratio)
                    conditional = prefix.household_budgets[i]
                    self.assertEqual((conditional.desired, conditional.conditional_wallet, conditional.spending_intention),
                                     (actual.desired, actual.wallet, actual.funded))

    def test_negative_conditional_wallet_does_not_refuse_or_invent_cash(self):
        a = opening(old_face=0, reserve=5, households=(3, 0), mortgage_rates=(0, 4000))
        with pure():
            prepared = q.prepare(a, POLICY, step(a))
            budget = prepared.household_budgets[1]
            self.assertLess(budget.conditional_wallet, 0)
            self.assertEqual(budget.spending_intention, 0)
            self.assertEqual(budget.predicted_shortfall, -budget.conditional_wallet)
            self.assertEqual(prepared.income_prefix.wallets[3], 0)

    def test_adaptive_hiring_and_source_technology_match_strict_quoter(self):
        a = opening(old_face=0, reserve=5, early=False, mortgage_rates=(4, -4))
        b = opening(old_face=0, reserve=5, mortgage_rates=(4, -4))
        with pure():
            strict = old.prepare(a, POLICY, step(a), project_units=F(1, 4))
            early = q.prepare(b, POLICY, step(b), project_units=F(1, 4))
            for name in ('orders', 'household_budgets', 'forecast_payroll', 'previous_income', 'forecast_income'):
                self.assertEqual(getattr(early, name), getattr(strict, name))
            self.assertEqual(early.forecast_payroll, (17, 3))
            self.assertEqual(early.previous_income, (20, F(63, 20)))
            self.assertEqual(early.orders.expected_dividends_nominal, (3, F(3, 20)))
            self.assertEqual(early.orders.service_productivity, F(5, 3))
            self.assertLessEqual(early.orders.focal_workers * early.orders.service_productivity,
                (sum(v.units for v in b.sector.vintages if v.age < 15) + b.sector.wip_units)*F(5, 16))

    def test_early_earnings_only_inform_private_capital_quote_not_eligibility_or_cash(self):
        a = opening(old_face=0, reserve=5)
        with pure():
            low = q.prepare(a, POLICY, step(a), project_units=1)
            high = q.prepare(a, POLICY, step(a, iorb=40), project_units=1)
            self.assertGreater(high.early_bank_earnings[1], low.early_bank_earnings[1])
            self.assertEqual(high.early_plan.equities, low.early_plan.equities)
            self.assertEqual(high.early_plan.capacities, low.early_plan.capacities)
            self.assertEqual(high.income_prefix.wallets, low.income_prefix.wallets)
            self.assertEqual(high.orders, low.orders)
            self.assertGreater(q.controls(high).project_commitment.face_ceiling,
                               q.controls(low).project_commitment.face_ceiling)

    def test_old_strict_golden_refusal_and_both_exact_route_guards(self):
        a = opening(); b = opening(early=False)
        with pure():
            with self.assertRaises(p.FundingFailure): old.prepare(b, POLICY, step(b))
            for operation in (lambda:old.prepare(a, POLICY, step(a)),
                              lambda:p.prepare(a, POLICY, step(a)),
                              lambda:c.prepare(a, POLICY), lambda:m.prepare(a, POLICY),
                              lambda:q.prepare(b, POLICY, step(b))):
                with self.assertRaises((TypeError, NotImplementedError)): operation()
            prepared = q.prepare(a, POLICY, step(a))
            for operation in (lambda:old.controls(prepared), lambda:old.execute(prepared, q.controls(prepared))):
                with self.assertRaises(ValueError): operation()

    def test_changed_preparation_and_finance_commands_reject_before_execution(self):
        a = opening()
        with pure():
            prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
            variants = (
                replace(prepared, step=replace(prepared.step, iorb_rate_pct=1)),
                replace(prepared, step=replace(prepared.step, facility_limits=(100, 3))),
                replace(prepared, step=replace(prepared.step, fiscal=replace(prepared.step.fiscal,
                    treasury_issue_authorization=1))),
                replace(prepared, opening=replace(a, macro=replace(a.macro, public_support=69))),
                replace(prepared, early_plan=replace(prepared.early_plan, gross_used=(0, 1))),
                replace(prepared, credit_prefix=replace(prepared.credit_prefix, reserves=(5, 1))),
                replace(prepared, principal_snapshot=replace(prepared.principal_snapshot, tga=21)),
                replace(prepared, orders=replace(prepared.orders, residual_workers=0)),
                replace(prepared, household_budgets=(replace(prepared.household_budgets[0],
                    desired=prepared.household_budgets[0].desired+1), prepared.household_budgets[1])))
            for changed in variants:
                with self.assertRaises((ValueError, TypeError)): q.execute(changed, finance)
                with self.assertRaises((ValueError, TypeError)): q.controls(changed)
            for changed in (replace(finance, iorb_rate_pct=1), replace(finance, facility_limits=(100, 3)),
                replace(finance, public_instructions=replace(finance.public_instructions, treasury_issue_authorization=1))):
                with self.assertRaises(ValueError): q.execute(prepared, changed)

    def test_nested_metadata_numeric_aliases_and_invalid_roots_fail_before_callbacks(self):
        calls = []
        class Alias(float):
            def __eq__(self, other): calls.append('equality'); return True
            def __float__(self): calls.append('float'); return 1.
        class Schema(dict):
            def values(self): calls.append('schema'); return super().values()
        with pure():
            a = opening(); prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
            for name, value in (('source', replace(prepared.source, price_index=Alias(1))),
                    ('early_plan', replace(prepared.early_plan, gross_used=(0, Alias(1)))),
                    ('household_budgets', (replace(prepared.household_budgets[0], desired=Alias(1)), prepared.household_budgets[1]))):
                with self.assertRaises((ValueError, TypeError)): q.execute(replace(prepared, **{name:value}), finance)
            for record in (prepared, prepared.early_plan, prepared.credit_prefix,
                           prepared.source, prepared.household_budgets[0]):
                object.__setattr__(record, '__dataclass_fields__', Schema(type(record).__dataclass_fields__))
                with self.assertRaises((ValueError, TypeError)): q.execute(prepared, finance)
                record.__dict__.pop('__dataclass_fields__')
            for record, name, value in ((a, 'version', 2), (a.sector.banks[0], 'reserves', True)):
                original = getattr(record, name)
                object.__setattr__(record, name, value)
                with patch.object(m, '_quote_source', side_effect=AssertionError('Reject before source quote')):
                    with self.assertRaises((ValueError, TypeError)): q.prepare(a, POLICY, step(a))
                object.__setattr__(record, name, original)
            self.assertEqual(calls, [])

    def test_source_guard_precedes_quote_controls_and_execution(self):
        a = opening()
        with pure():
            prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
            with patch.object(k, '_check_sources', side_effect=ValueError('source drift')), \
                 patch.object(m, '_quote_source', side_effect=AssertionError('No stale quote')):
                for operation in (lambda:q.quote_prefix(a, step(a)),
                    lambda:q.prepare(a, POLICY, step(a)), lambda:q.controls(prepared),
                    lambda:q.execute(prepared, finance)):
                    with self.assertRaisesRegex(ValueError, 'source drift'): operation()
            self.assertEqual(k._SOURCES['public_early_paydate'],
                hashlib.sha256(Path(q.__file__).read_bytes()).hexdigest())

    def test_unsupported_routes_and_demand_stock_migration_stay_blocked(self):
        a = opening()
        with pure():
            for changes in (dict(currency_to_deposits=(1, 0)), dict(rrp_request=1),
                            dict(rrp_offers=(1, 0)), dict(treasury_redemption=1)):
                with self.assertRaises(NotImplementedError): q.prepare(a, POLICY, step(a, **changes))
            prepared = q.prepare(a, POLICY, step(a)); finance = q.controls(prepared)
            for changed in (replace(finance, asset_purchase_request=1), replace(finance, asset_offers=(1, 0)),
                            replace(finance, security_bids=(0, 0))):
                with self.assertRaises(NotImplementedError): q.execute(prepared, changed)
            for field in ('consumption_state_pct', 'deferred_consumption_units'):
                changed = replace(a, macro=replace(a.macro, **{field:1}))
                with self.assertRaises(ValueError): q.prepare(changed, POLICY, step(changed))


class EarlyCurrentActualTests(unittest.TestCase):
    def setUp(self):
        raw = l.advance_given_orders; close = m._close_paid
        def counted(*args, **kwargs):
            path = os.environ.get('FED567_BUDGET_FILE')
            totals = json.loads(Path(path).read_text()) if path and Path(path).exists() else dict(COUNTS)
            if totals['attempts'] >= 40: raise AssertionError('Bounded worker wave exhausted; retain results.')
            COUNTS['attempts'] += 1; totals['attempts'] += 1
            try:
                result = raw(*args, **kwargs)
            except Exception:
                COUNTS['raw_exceptions'] += 1; totals['raw_exceptions'] += 1
                if path: Path(path).write_text(json.dumps(totals))
                raise
            key = 'paid' if result.ok else 'refused'
            COUNTS[key] += 1; totals[key] += 1
            if path: Path(path).write_text(json.dumps(totals))
            return result
        def closed(*args, **kwargs):
            def increment(key):
                COUNTS[key] += 1
                path = os.environ.get('FED567_BUDGET_FILE')
                if path:
                    totals = json.loads(Path(path).read_text())
                    totals[key] += 1
                    Path(path).write_text(json.dumps(totals))
            increment('macro_close_calls')
            try: result = close(*args, **kwargs)
            except Exception:
                increment('macro_exceptions')
                raise
            if result.ok: increment('macro_closes')
            return result
        self.raw = patch.object(l, 'advance_given_orders', side_effect=counted).start()
        self.close = patch.object(m, '_close_paid', side_effect=closed).start()
        self.addCleanup(patch.stopall)

    def pay(self, a, *, command=None, news=m.News(), units=0, finance_changes=None):
        prepared = q.prepare(a, POLICY, command or step(a), news, project_units=units)
        finance = q.controls(prepared)
        if finance_changes: finance = replace(finance, **finance_changes)
        return prepared, q.execute(prepared, finance)

    def test_actual_early_credit_macro_close_and_quote_boundaries_match_once(self):
        a = opening(old_id='CB1:B'); before = repr(a)
        prepared, out = self.pay(a)
        self.assertTrue(out.ok, out.reason)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 1))
        b = out.envelope.sector; book = b.public_book
        self.assertEqual(book.phases[1].snapshot, prepared.principal_snapshot)
        self.assertEqual(book.phases[2].snapshot, prepared.credit_prefix)
        self.assertEqual(book.phases[3].snapshot, prepared.income_prefix)
        self.assertEqual(book.early_credit.plan, prepared.early_plan)
        self.assertEqual(book.observations, prepared.observations)
        self.assertEqual(book.early_credit.replacement_loans[0].id, 'CB1:B:new')
        self.assertEqual(out.envelope.macro.actual_output_index, 4*float(b.last.real_output))
        self.assertEqual(out.envelope.macro.price_index, prepared.source.price_index)
        self.assertEqual(self.raw.call_args.args[1], prepared.source.orders)
        l.validate_early_paydate_public(book, b.scale, b.quarter, b.last.payments, b.last.trace)
        self.assertEqual(repr(a), before)

    def test_custom_actual_underwriting_refuses_atomically_once(self):
        a = opening(); before = repr(a)
        _, out = self.pay(a, finance_changes=dict(new_loans=(
            l.OperatingLoanOffer('A', 10**6, 4, 2, borrower='R'),)))
        self.assertFalse(out.ok); self.assertEqual(out.status, 'credit_constraint')
        self.assertIs(out.envelope, a)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 0))
        self.assertEqual(repr(a), before)

    def test_actual_later_draw_uses_remaining_shared_gross_limit(self):
        for limit, paid in ((2, False), (4, True)):
            a = opening()
            prepared, out = self.pay(a, command=step(a, limit=limit),
                finance_changes=dict(new_loans=(l.LoanOffer('B', 2, 0, 2, borrower='R'),)))
            self.assertEqual(out.ok, paid, out.reason)
            if paid:
                book = out.envelope.sector.public_book
                self.assertTrue(book.later_credit)
                self.assertEqual(book.later_credit[0].gross_before, prepared.early_plan.gross_used[1])
                self.assertLessEqual(book.later_credit[-1].gross_before + book.later_credit[-1].advance, limit)
            else:
                self.assertEqual(out.status, 'funding_failure'); self.assertIs(out.envelope, a)
        self.assertEqual((self.raw.call_count, self.close.call_count), (2, 1))

    def test_no_early_credit_old_actual_golden_is_unchanged(self):
        a = opening(old_face=0, reserve=5, early=False)
        b = opening(old_face=0, reserve=5)
        strict = old.prepare(a, POLICY, step(a), project_units=F(1, 4))
        strict_out = old.execute(strict, old.controls(strict))
        early, early_out = self.pay(b, units=F(1, 4))
        self.assertTrue(strict_out.ok, strict_out.reason)
        self.assertTrue(early_out.ok, early_out.reason)
        self.assertEqual(early.early_plan.gross_used, (0, 0))
        self.assertEqual(early_out.envelope.macro, strict_out.envelope.macro)
        before, after = strict_out.envelope.sector, early_out.envelope.sector
        for name in ('banks', 'loans', 'cb_loans', 'vintages', 'wip_units', 'wip_basis',
                     'public_securities', 'gov_debt_face', 'next_private_id'):
            self.assertEqual(getattr(after, name), getattr(before, name))
        for field in fields(l.Report):
            if field.name != 'trace':
                self.assertEqual(getattr(after.last, field.name), getattr(before.last, field.name))
        self.assertEqual((self.raw.call_count, self.close.call_count), (2, 2))

    def test_actual_signed_zero_and_positive_coupon_prefixes_match(self):
        for rate in (-4, 0, 4):
            a = opening(reserve=5, cb_rates=(0, rate), mortgage_rates=(4, -4))
            prepared, out = self.pay(a, command=step(a, iorb=rate,
                mortgage_repayments=(F(1, 10), 0)))
            self.assertTrue(out.ok, out.reason)
            self.assertEqual(out.envelope.sector.public_book.phases[3].snapshot, prepared.income_prefix)
            self.assertEqual(out.envelope.sector.public_book.observations, prepared.observations)
        self.assertEqual((self.raw.call_count, self.close.call_count), (3, 3))

    def test_explicit_zero_contract_funds_new_credit_without_retroactive_interest(self):
        a = opening(old_face=0, reserve=0, cb_rates=(0, 0), masses=pools(b={5:-4}))
        prepared, out = self.pay(a, command=step(a, iorb=-4))
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(prepared.early_plan.advances[1], 1)
        self.assertEqual(prepared.credit_prefix.cb_faces[1], 1)
        self.assertEqual(prepared.observations[6].basis, 0)
        self.assertEqual(prepared.observations[8].basis, 0)
        self.assertEqual(prepared.observations[6].settled, 0)
        self.assertEqual(prepared.observations[8].settled, 0)
        self.assertEqual(out.envelope.sector.public_book.phases[3].snapshot, prepared.income_prefix)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 1))

    def test_paid_history_validated_before_new_iorb_and_next_original_bases(self):
        a = opening(); first, out = self.pay(a)
        self.assertTrue(out.ok, out.reason)
        a = out.envelope; before = repr(a); last = a.sector.last
        with pure():
            prepared = q.prepare(a, POLICY, step(a, iorb=-4, limit=100))
            self.assertEqual(prepared.observations[8].basis, a.sector.cb_debt('B'))
            self.assertEqual(prepared.previous_income, tuple(last.disposable_income(h) for h in ('HA', 'HB')))
            divs = (last.dividend_residual+last.bank_dividend_to('HA'),
                    last.dividend_focal+last.bank_dividend_to('HB'))
            self.assertEqual(prepared.income_prefix.previous_dividends, divs)
            self.assertEqual(prepared.orders.expected_dividends_nominal, divs)
            self.assertEqual(prepared.forecast_payroll,
                tuple(j*a.sector.scale*prepared.orders.price_factor*prepared.orders.real_wage
                    for j in (last.paid_residual_workers, last.paid_focal_workers)))
            self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 0)
            for name in ('payments', 'trace'):
                report = replace(last); sector = replace(a.sector); forged = replace(a)
                object.__setattr__(report, name, getattr(report, name)[1:])
                object.__setattr__(sector, 'last', report); object.__setattr__(forged, 'sector', sector)
                original_quote = l.public_income.quote
                def prior_only(terms, **kwargs):
                    if terms.iorb_rate_pct == 4:
                        raise AssertionError('Prior history must reject BEFORE new IORB quotation')
                    return original_quote(terms, **kwargs)
                with patch.object(l.public_income, 'quote', side_effect=prior_only):
                    with self.assertRaises((TypeError, ValueError)): q.prepare(forged, POLICY, step(forged, iorb=4))
            self.assertEqual(repr(a), before)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 1))

    def test_later_missing_new_cb_terms_keep_actual_unsupported_status(self):
        a = opening(old_face=0, reserve=0, reserves=(0, 0), cb_rates=(None, None))
        prepared, out = self.pay(a)
        self.assertEqual(prepared.early_plan.gross_used, (0, 0))
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'unsupported_public_income')
        self.assertIs(out.envelope, a)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 0))

    def test_optional_project_missing_credit_terms_remains_visible_after_paid_close(self):
        a = opening(old_face=0, reserve=0, cb_rates=(0, None), firms=(17, 0))
        prepared, out = self.pay(a, units=F(3, 2))
        self.assertEqual(prepared.early_plan.gross_used, (0, 0))
        self.assertTrue(out.ok, out.reason)
        report = out.envelope.sector.last
        canceled = [dict(note.details)['reason'] for note in report.trace if note.kind == 'project_cancelled']
        self.assertEqual(canceled, ['unsupported_public_income'])
        self.assertEqual(report.investment, 0)
        self.assertFalse(any(type(loan) is l.ProjectLoan for loan in out.envelope.sector.loans))
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 1))

    def test_negative_conditional_wallet_leaves_actual_mandatory_failure_to_journal(self):
        a = opening(old_face=0, reserve=5, households=(3, 0), mortgage_rates=(0, 4000))
        prepared, out = self.pay(a)
        self.assertLess(prepared.household_budgets[1].conditional_wallet, 0)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'funding_failure')
        self.assertIs(out.envelope, a)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 0))

    def test_zero_paid_output_never_calls_macro_close(self):
        a = opening(old_face=0, reserve=5, cb_rates=(0, 0))
        _, out = self.pay(a, news=m.News(demand_shock_pct=-100000))
        self.assertTrue(self.raw.call_args is not None)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'terminal_crisis')
        self.assertIs(out.envelope, a)
        self.assertEqual((self.raw.call_count, self.close.call_count), (1, 0))


if __name__ == '__main__': unittest.main()
