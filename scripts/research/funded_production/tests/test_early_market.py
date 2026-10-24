"""Pure explicit early-book Treasury resolver, plus ONE actual predecessor.

This does not qualify an early forecast, observation wrapper, four-quarter
aging diagnostic, endogenous recovery or native implementation. No paid book
is converted. All ordinary tests guard both raw execution and Transactions.
"""
from dataclasses import fields, replace
from fractions import Fraction as F
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_market as market
from scripts.research.funded_production import public_scenarios as s, public_forecast as p
from scripts.research.funded_production import public_early_paydate as current
from scripts.research.funded_production import public_funding as funding, public_income as income
from scripts.research.funded_production import checkpoint as k, macro as m, ledger as l, episodes as e
from scripts.research.funded_production.tests.test_public_paydate_journal import legacy, pools
from scripts.research.funded_production.tests.test_public_market import date
from scripts.research.funded_production.tests.test_public_scenarios import tampered


COUNTS = dict(attempts=0, paid=0, refused=0, raw_exceptions=0,
              transactions=0, macro_close_calls=0, macro_closes=0, macro_exceptions=0)


def opening(**changes):
    sector, terms = legacy(**changes)
    return replace(m.initial(growth=0), sector=l.enable_early_paydate_public(sector, terms))


class PureGuards(unittest.TestCase):
    def setUp(self):
        self.guards = []
        for target, name in ((l, 'advance_given_orders'), (l, '_Transaction'),
                (current, 'prepare'), (current, 'controls'), (current, 'execute'),
                (p, 'prepare'), (p, 'execute'), (m, '_close_paid')):
            guard = patch.object(target, name, side_effect=AssertionError('Pure Treasury resolver only'))
            self.guards.append(guard.start())
            self.addCleanup(guard.stop)

    def tearDown(self):
        for guard in self.guards:
            self.assertEqual(guard.call_count, 0)


class EarlyMarketPureTests(PureGuards):
    def test_explicit_exact_route_and_old_routes_keep_rejecting_new_book(self):
        root = opening(); before = repr(root)
        result = market.resolve_early_paydate_date(root, date())
        self.assertIs(type(result), s.ResolvedDate)
        self.assertIs(type(result.step), p.PublicStep)
        self.assertIs(type(result.step.fiscal), l.FundedPublicInstructions)
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (0, 0))
        for resolver in (market.resolve_date, market.resolve_paydate_date):
            with self.assertRaises(TypeError): resolver(root, date())
        self.assertEqual(repr(root), before)

    def test_new_route_refuses_other_exact_books_and_subclasses(self):
        base, terms = legacy()
        root = m.initial(growth=0)
        for factory in (l.enable_funded_public, l.enable_paydate_public, l.enable_public_income):
            other = replace(root, sector=factory(base, terms))
            with self.assertRaises(TypeError): market.resolve_early_paydate_date(other, date())
        class EarlySubclass(l.EarlyPaydateBook):
            pass
        a = opening()
        altered = EarlySubclass(**{f.name:getattr(a.sector.public_book, f.name)
                                   for f in fields(l.EarlyPaydateBook)})
        other = tampered(a, sector=tampered(a.sector, public_book=altered))
        with self.assertRaises(TypeError): market.resolve_early_paydate_date(other, date())

    def test_private_selector_accepts_only_three_code_owned_type_identities(self):
        calls = []
        class Meta(type):
            def __eq__(self, other): calls.append('type equality'); return True
        class Foreign(metaclass=Meta):
            pass
        root = opening()
        for selector in (Foreign, True, 1, 'EarlyPaydateBook', object(), lambda: l.EarlyPaydateBook):
            with self.assertRaises(TypeError): market._opening(root, selector)
        self.assertEqual(calls, [])

    def test_identical_bounded_commands_for_all_three_fresh_zero_credit_routes(self):
        base, terms = legacy(faces=pools({0:2}, {0:3}, {0:4}),
            masses=pools({0:F(2,5)}, {0:F(4,5)}, {0:F(6,5)}), tga=F(3,5)-F(1,10**6))
        roots = tuple(replace(m.initial(growth=0), sector=factory(base, terms))
                      for factory in (l.enable_funded_public, l.enable_paydate_public,
                                      l.enable_early_paydate_public))
        resolvers = (market.resolve_date, market.resolve_paydate_date, market.resolve_early_paydate_date)
        before = tuple(map(repr, roots))
        for roll in (True, False):
            for priority in (('A', 'B'), ('B', 'A')):
                authored = date(full_roll=roll, allocation_priority=priority,
                    facility_limits=(0, 0), subscription_rates_pct=(-7, 0), replacement_maturity=F(3, 2))
                quoted = tuple(resolver(root, authored) for root, resolver in zip(roots, resolvers))
                self.assertEqual(quoted[0], quoted[1]); self.assertEqual(quoted[1], quoted[2])
                self.assertEqual(quoted[2].step.fiscal.treasury_rolls, (2, 3, 4) if roll else (0, 0, 0))
        self.assertEqual(tuple(map(repr, roots)), before)

    def test_same_treasury_bounds_never_spend_facilities_future_income_or_remittance(self):
        a = opening(masses=pools({5:4}), tga=0, reserves=(0, 0), firms=(0, 0),
                    mortgage_rates=(400, 400), cb_rates=(0, 0))
        for authored in (date(), date(iorb_rate_pct=10**6, facility_limits=(10**6, 10**6)),
                         date(subscription_rates_pct=(-10**6, -10**6))):
            with self.assertRaises(p.FundingFailure): market.resolve_early_paydate_date(a, authored)
        a = opening(faces=pools({5:1}, {0:3}, {5:1}), reserves=(0, 0), tga=0)
        result = market.resolve_early_paydate_date(a, date(full_roll=False, subscription_limits=(3, 0)))
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (3, 0))

    def test_explicit_nominal_iorb_and_policy_rules_are_current_own_branch_information(self):
        a = opening()
        b = replace(a, macro=replace(a.macro, output_gap_pct=-10))
        authored = date(policy=e.PolicyRule('staff'), iorb_rate_pct=s.PolicyIORB(), news=m.News(demand_shock_pct=-2))
        left = market.resolve_early_paydate_date(a, authored)
        right = market.resolve_early_paydate_date(b, authored)
        self.assertNotEqual(left.policy, right.policy)
        self.assertEqual(left.step.iorb_rate_pct, m.rational(left.policy.rate_pct))
        self.assertEqual(right.step.iorb_rate_pct, m.rational(right.policy.rate_pct))
        for iorb in (-7, 0, 4):
            result = market.resolve_early_paydate_date(a, date(policy=m.Policy(-3, -3), iorb_rate_pct=iorb))
            self.assertEqual(result.step.iorb_rate_pct, iorb)
            self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 0)
        with self.assertRaises(s.MissingCoverage):
            market.resolve_early_paydate_date(a, date(policy=e.PolicyRule('promise')))

    def test_missing_date_unknown_zero_declarations_explicit_and_contracts_not_invented(self):
        a = opening(cb_rates=(None, None))
        with self.assertRaises(s.MissingCoverage): market.resolve_early_paydate_date(a, None)
        with patch.object(income, 'quote', wraps=income.quote) as quote:
            result = market.resolve_early_paydate_date(a, date(new_issue_authorization=0,
                subscription_limits=(0, 0), subscription_rates_pct=(0, 0), facility_limits=(0, 0)))
            self.assertEqual(quote.call_args.args[0].cb_rates_pct, (None, None))
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (0, 0))
        a = opening(cb_a=1, cb_rates=(0, None), rrp_a=1, rrp_rates=(0, None))
        market.resolve_early_paydate_date(a, date())
        for name in ('cb_rates_pct', 'rrp_rates_pct'):
            b = opening(cb_a=1, cb_rates=(0, None), rrp_a=1, rrp_rates=(0, None))
            object.__setattr__(b.sector.public_book.terms, name, (None, None))
            with self.assertRaises(ValueError) as error: market.resolve_early_paydate_date(b, date())
            self.assertNotIsInstance(error.exception, p.FundingFailure)

    def test_source_binding_uses_existing_module_and_precedes_quote_reconstruction(self):
        a = opening()
        self.assertIn('public_market', k._SOURCES)
        self.assertEqual(k._SOURCES['public_market'], hashlib.sha256(Path(market.__file__).read_bytes()).hexdigest())
        with patch.object(k, '_check_sources', side_effect=ValueError('source drift')), \
             patch.object(market, '_reconstruct', side_effect=AssertionError('No stale reconstruction')) as rebuild, \
             patch.object(income, 'quote', side_effect=AssertionError('No stale quote')) as quote:
            with self.assertRaisesRegex(ValueError, 'source drift'):
                market.resolve_early_paydate_date(a, date())
            self.assertEqual((rebuild.call_count, quote.call_count), (0, 0))

    def test_nested_schema_and_scalar_proxies_never_execute_callbacks(self):
        calls = []
        class Alias(float):
            def __eq__(self, other): calls.append('equality'); return True
            def __float__(self): calls.append('float'); return 1.
        class Metadata(dict):
            def values(self): calls.append('schema'); return super().values()
        a = opening()
        for record in (a, a.macro, a.sector.public_book, a.sector.public_book.terms, a.sector.banks[0]):
            object.__setattr__(record, '__dataclass_fields__', Metadata(type(record).__dataclass_fields__))
            with patch.object(market, '_reconstruct', side_effect=AssertionError('Closed admission first')) as rebuild:
                with self.assertRaises((TypeError, ValueError)):
                    market.resolve_early_paydate_date(a, date())
                self.assertEqual(rebuild.call_count, 0)
            record.__dict__.pop('__dataclass_fields__')
        for root in (tampered(a, macro=tampered(a.macro, public_support=Alias(50))),
                     tampered(a, sector=tampered(a.sector, banks=(
                         tampered(a.sector.banks[0], reserves=Alias(5)), a.sector.banks[1])))):
            with patch.object(market, '_reconstruct', side_effect=AssertionError('Closed admission first')):
                with self.assertRaises((TypeError, ValueError)):
                    market.resolve_early_paydate_date(root, date())
        for authored in (tampered(date(), facility_limits=(Alias(1), 0)),
                         tampered(date(), policy=tampered(m.Policy(3.5, 3.5), rate_pct=Alias(3.5)))):
            with self.assertRaises((TypeError, ValueError)): market.resolve_early_paydate_date(a, authored)
        self.assertEqual(calls, [])

    def test_boolean_integer_metadata_versions_and_wrong_components_fail_closed(self):
        a = opening()
        for root in (tampered(a, version=True), tampered(a, version=2), tampered(a, sector=None),
            tampered(a, macro=tampered(a.macro, guidance_active=1)),
            tampered(a, sector=tampered(a.sector, scale=True))):
            with self.assertRaises((TypeError, ValueError)): market.resolve_early_paydate_date(root, date())
        for authored in (tampered(date(), full_roll=1), tampered(date(), new_issue_authorization=True),
            tampered(date(), iorb_rate_pct=True), tampered(date(), facility_limits=(True, 0)),
            tampered(date(), subscription_rates_pct=(False, 0))):
            with self.assertRaises((TypeError, ValueError)): market.resolve_early_paydate_date(a, authored)
        for record in (date(), date(policy=e.PolicyRule('staff'))):
            child = record.policy
            object.__setattr__(child, '__dataclass_fields__', {})
            with self.assertRaises((TypeError, ValueError)): market.resolve_early_paydate_date(a, record)


class EarlyMarketActualPredecessorTests(PureGuards):
    @classmethod
    def setUpClass(cls):
        # ONE fresh synthetic actual journal, not the retained aging/Q3 career.
        from scripts.research.funded_production.tests.test_public_early_paydate_current import opening as credit_opening
        root = credit_opening()
        resolved = market.resolve_early_paydate_date(root, date(facility_limits=(100, 2)))
        prepared = current.prepare(root, resolved.policy, resolved.step, resolved.news)
        finance = current.controls(prepared)
        raw = l.advance_given_orders; transaction = l._Transaction; close = m._close_paid
        def counted(*args, **kwargs):
            if COUNTS['attempts']: raise AssertionError('Only ONE actual predecessor is authorized in this test wave.')
            COUNTS['attempts'] += 1
            try: out = raw(*args, **kwargs)
            except Exception:
                COUNTS['raw_exceptions'] += 1
                raise
            COUNTS['paid' if out.ok else 'refused'] += 1
            return out
        def constructed(*args, **kwargs):
            COUNTS['transactions'] += 1
            return transaction(*args, **kwargs)
        def closed(*args, **kwargs):
            COUNTS['macro_close_calls'] += 1
            try: out = close(*args, **kwargs)
            except Exception:
                COUNTS['macro_exceptions'] += 1
                raise
            COUNTS['macro_closes'] += int(out.ok)
            return out
        with patch.object(l, 'advance_given_orders', side_effect=counted), \
             patch.object(l, '_Transaction', side_effect=constructed), \
             patch.object(m, '_close_paid', side_effect=closed):
            out = current.execute(prepared, finance)
        if not out.ok: raise AssertionError('Retain actual fixture failure, no retry: '+out.status+': '+out.reason)
        cls.root = root; cls.paid = out.envelope

    def test_actual_paid_book_resolves_with_explicit_full_payment_and_trace_validator(self):
        a = self.paid; before = repr(a)
        with patch.object(l, 'validate_early_paydate_public', wraps=l.validate_early_paydate_public) as validate, \
             patch.object(p, '_paid_economy', wraps=p._paid_economy) as paid:
            result = market.resolve_early_paydate_date(a, date(iorb_rate_pct=-4))
            self.assertGreaterEqual(paid.call_count, 1)
            self.assertGreaterEqual(validate.call_count, 1)
            self.assertEqual(validate.call_args.args[3:], (a.sector.last.payments, a.sector.last.trace))
        self.assertEqual(result.step.iorb_rate_pct, -4)
        self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 0)
        self.assertEqual(repr(a), before)
        self.assertEqual(COUNTS, dict(attempts=1, paid=1, refused=0, raw_exceptions=0,
            transactions=1, macro_close_calls=1, macro_closes=1, macro_exceptions=0))

    def test_altered_or_missing_paid_streams_reject_before_any_new_iorb_quote(self):
        a = self.paid
        original_quote = income.quote
        def prior_only(terms, **kwargs):
            if terms.iorb_rate_pct == -4: raise AssertionError('Prior witness must precede new IORB')
            return original_quote(terms, **kwargs)
        for name in ('payments', 'trace'):
            values = getattr(a.sector.last, name)
            for altered in ((), values[1:], values[::-1]):
                root = tampered(a, sector=tampered(a.sector,
                    last=tampered(a.sector.last, **{name:altered})))
                with patch.object(income, 'quote', side_effect=prior_only):
                    with self.assertRaises((TypeError, ValueError)):
                        market.resolve_early_paydate_date(root, date(iorb_rate_pct=-4))

    def test_altered_credit_metadata_or_closing_identity_reject_before_new_iorb(self):
        a = self.paid; b = a.sector.public_book
        altered_plan = replace(b.early_credit.plan, gross_used=(F(0), F(1)))
        altered_credit = tampered(b.early_credit, plan=altered_plan)
        self.assertTrue(b.closing_cb_loans)
        closing = tuple(replace(loan, id='not-the-witnessed-cohort') for loan in b.closing_cb_loans)
        for book in (tampered(b, early_credit=altered_credit), tampered(b, closing_cb_loans=closing)):
            root = tampered(a, sector=tampered(a.sector, public_book=book))
            with self.assertRaises((TypeError, ValueError)):
                market.resolve_early_paydate_date(root, date(iorb_rate_pct=-4))

    def test_paid_boolean_positions_and_nested_plan_metadata_cannot_normalize_into_valid_history(self):
        a = self.paid; b = a.sector.public_book
        phase = tampered(b.phases[2], payment_end=True)
        boolean_plan = tampered(b.early_credit.plan,
            gross_used=(False, b.early_credit.plan.gross_used[1]))
        for book in (tampered(b, phases=(*b.phases[:2], phase, *b.phases[3:])),
                     tampered(b, early_credit=tampered(b.early_credit, plan=boolean_plan))):
            root = tampered(a, sector=tampered(a.sector, public_book=book))
            with self.assertRaises((TypeError, ValueError)):
                market.resolve_early_paydate_date(root, date(iorb_rate_pct=-4))
        plan = replace(b.early_credit.plan)
        object.__setattr__(plan, '__dataclass_fields__', {})
        root = tampered(a, sector=tampered(a.sector,
            public_book=tampered(b, early_credit=tampered(b.early_credit, plan=plan))))
        with patch.object(market, '_reconstruct', side_effect=AssertionError('Reject instance schema first')) as rebuild:
            with self.assertRaises((TypeError, ValueError)):
                market.resolve_early_paydate_date(root, date(iorb_rate_pct=-4))
            self.assertEqual(rebuild.call_count, 0)


if __name__ == '__main__': unittest.main()
