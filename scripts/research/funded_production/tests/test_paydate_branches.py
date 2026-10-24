"""Bounded paydate quotations: pure guards, short prefixes, ONE shared table.

The executor is only instrumented, never replaced by fake settlement. The Q0
table is an authored zero-public-coupon fixture, not a recovery experiment.
"""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import importlib
import inspect
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_branches as b
from scripts.research.funded_production import public_scenarios as old_s


PACKAGE = 'scripts.research.funded_production'
COUNTS = dict(raw_attempts=0, raw_paid=0, raw_refused=0, raw_exceptions=0,
              macro_closes=0)


def modules():
    # Run dependent classes only after the parent supplies its ready receipt.
    return (importlib.import_module(PACKAGE + '.public_paydate_branches'),
            importlib.import_module(PACKAGE + '.paydate_scenarios'),
            importlib.import_module(PACKAGE + '.public_paydate'))


def opening(*, debt=False, **rates):
    root = b.m.initial(growth=0)
    root = replace(root, macro=replace(root.macro, price_history=(100.,) * 5,
        annualized_quarterly_inflation_pct=0, four_quarter_inflation_pct=0,
        expected_short_inflation_pct=0, expected_long_inflation_pct=0))
    sector = root.sector
    if debt:
        # Explicit fresh stock allocation at the SAME bank, not a forecast
        # transfer or migration. Force actual project borrowing by emptying F.
        banks = sector.banks
        focal = replace(banks[1], deposits=(F(0), sum(banks[1].deposits, F(0))))
        sector = replace(sector, banks=(banks[0], focal))
    rates.setdefault('cb_rates_pct', (0, 0))
    return replace(root, sector=b.l.enable_paydate_public(sector,
        b.l.public_income_terms(sector, **rates)))


def date(**changes):
    from scripts.research.funded_production.public_market import MarketFundingDate
    values = dict(policy=b.m.Policy(3.5, 3.5), news=b.m.News(), iorb_rate_pct=F(0),
        facility_limits=(F(100), F(100)), full_roll=True,
        new_issue_authorization=F(0), subscription_limits=(F(0), F(0)),
        subscription_rates_pct=(F(0), F(0)), replacement_maturity=F(118, 5),
        allocation_priority=('A', 'B'))
    values.update(changes)
    return MarketFundingDate(**values)


def cells(*, missing=None, descriptor=None):
    _, s, _ = modules()
    descriptor = date() if descriptor is None else descriptor
    dates = tuple(None if h == missing else descriptor for h in range(19))
    return tuple(s.ScenarioCell(sign, fulfilled, dates)
                 for sign in (-1, 1) for fulfilled in (False, True))


def pure_paths(*, now=2, wait=(4, -4, 4, -4)):
    result = []
    for i, (sign, fulfilled) in enumerate(((-1, False), (-1, True), (1, False), (1, True))):
        for action, value in (('NEVER', 0), ('NOW', now), ('WAIT', wait[i])):
            result.append(b.Path(sign, fulfilled, F(1, 4), action, 'completed', '', (),
                F(value), F(value), None, ('same',) if action == 'WAIT' else None,
                F(0), F(0), None, '', (), F(0), F(0), F(0), 0, 0, 0, 0, 0))
    return b._incrementals(tuple(result))


class PaydateBranchesPureTests(unittest.TestCase):
    """No new adapter/scenario dependency or actual monetary attempt."""

    def test_new_entry_is_thin_and_old_signature_is_exactly_unchanged(self):
        q = importlib.import_module(PACKAGE + '.public_paydate_branches')
        expected = '(opening, cells, *, units, forward_gross, tolerance=1e-06) -> '\
                   "'Quotation'"
        self.assertEqual(str(inspect.signature(b.evaluate)), expected)
        self.assertEqual(str(inspect.signature(q.evaluate)), expected)
        self.assertIs(q.Quotation, b.Quotation)

    def test_old_entry_still_refuses_exact_paydate_book_before_executor(self):
        descriptor = old_s.FullRollDate(b.m.Policy(3.5, 3.5), b.m.News(), F(0), (F(100), F(100)))
        old_cells = tuple(old_s.ScenarioCell(sign, fulfilled, (descriptor,) * 19)
                          for sign in (-1, 1) for fulfilled in (False, True))
        with patch.object(b.l, 'advance_given_orders', wraps=b.l.advance_given_orders) as raw:
            with self.assertRaises(TypeError):
                b.evaluate(opening(), old_cells, units=0, forward_gross=(F(1),) * 18)
            self.assertEqual(raw.call_count, 0)

    def test_private_pair_selector_refuses_callback_or_module(self):
        for selector in (b.p, lambda: b.p, 'public_paydate', 1, None):
            with self.subTest(selector=type(selector).__name__), self.assertRaises(TypeError):
                b._evaluate(None, (), units=0, forward_gross=(F(1),) * 18,
                            paydate=selector)

    def test_common_reducer_never_uses_hidden_cell_for_wait(self):
        result = b._select(pure_paths(now=-1), F(0))
        self.assertEqual(result[:5], ('completed', 'NEVER', -1, 0, True))
        self.assertEqual(len(result[5]), 1)
        self.assertEqual(result[5][0].conditional_delta, 0)

    def test_positive_failed_baseline_and_unknown_admission_are_not_zero(self):
        for action, status, expected in (('NEVER', 'failed', 'baseline_incomplete'),
                                          ('NOW', 'unknown', 'admission_incomplete')):
            changed = tuple(replace(path, status=status, total_pv=None, incremental_pv=None)
                if path.action == action and path.fulfilled else path for path in pure_paths())
            result = b._select(changed, F(0))
            self.assertEqual(result[:2], (expected, None))
            self.assertIsNone(result[3])

    def test_exact_eighteen_factors_and_whole_invoice_accounting(self):
        forwards = tuple(F(h + 2, h + 1) for h in range(18))
        self.assertEqual(b._discount_factors(forwards), tuple(F(1, h + 1) for h in range(19)))
        report = b.l.Report(1, F(13), F(7), F(2), F(4), F(1), F(2),
            F(3), F(5), F(999), F(-999), F(888), F(777), F(666),
            F(555), F(444), F(0), F(0), (), ())
        row = b._cash_row(0, report, F(3), F(2), F(1), F(1), F(0), F(0), F(0))
        self.assertEqual((row.receipts, row.payroll, row.construction_invoice,
                          row.operating_cash, row.discount_factor, row.pv), (42, 5, 12, 25, 1, 25))


class PaydateBranchesBoundaryTests(unittest.TestCase):
    """Dependent pure admission checks; all must make ZERO actual attempts."""

    def setUp(self):
        self.q, self.s, self.adapter = modules()
        self.raw = patch.object(b.l, 'advance_given_orders', wraps=b.l.advance_given_orders).start()
        self.addCleanup(patch.stopall)

    def tearDown(self):
        self.assertEqual(self.raw.call_count, 0)

    def evaluate(self, root=None, paths=None, **changes):
        args = dict(opening=opening() if root is None else root,
                    cells=cells() if paths is None else paths,
                    units=F(0), forward_gross=(F(1),) * 18)
        args.update(changes)
        return self.q.evaluate(**args)

    def test_known_pair_cannot_cross_new_or_old_books_and_cells(self):
        from scripts.research.funded_production.tests.test_public_branches import opening as old_opening, cells as old_cells
        for call in (lambda: self.evaluate(root=old_opening()),
                     lambda: self.evaluate(paths=old_cells()),
                     lambda: b.evaluate(old_opening(), cells(), units=0, forward_gross=(F(1),) * 18)):
            with self.assertRaises((TypeError, ValueError)): call()

    def test_missing_current_coverage_has_twelve_unknown_paths_no_fake_zero(self):
        quote = self.evaluate(paths=cells(missing=0), units=1)
        self.assertEqual((quote.status, quote.action, quote.executor_calls, quote.unknown_coverage),
                         ('admission_incomplete', None, 0, 12))
        self.assertTrue(all(x.status == 'unknown' and x.total_pv is None and not x.rows
                            for x in quote.paths))

    def test_invalid_root_units_curve_tolerance_and_future_dates(self):
        root = opening(); paths = cells()
        malformed = replace(root)
        object.__setattr__(malformed, 'version', 2)
        future = replace(paths[0].dates[18], facility_limits=(F(1, 10**7), F(100)))
        invalid_paths = (replace(paths[0], dates=paths[0].dates[:18] + (future,)),) + paths[1:]
        bad_authorization = replace(paths[0].dates[18], new_issue_authorization=F(1, 10**7))
        invalid_authorization = (replace(paths[0], dates=paths[0].dates[:18] +
                                        (bad_authorization,)),) + paths[1:]
        bad_bid = replace(paths[0].dates[18], subscription_limits=(F(1, 10**7), F(0)))
        invalid_bid = (replace(paths[0], dates=paths[0].dates[:18] + (bad_bid,)),) + paths[1:]
        structural = replace(paths[0].dates[18], news=b.m.News(structural_unemployment_change_pct=-100))
        invalid_u = (replace(paths[0], dates=paths[0].dates[:18] + (structural,)),) + paths[1:]
        bad = (dict(root=malformed), dict(units=True), dict(units=F(1, 10**7)),
               dict(forward_gross=[F(1)] * 18), dict(forward_gross=(F(1),) * 17),
               dict(forward_gross=(F(1),) * 17 + (F(0),)), dict(tolerance=True),
               dict(tolerance=float('nan')), dict(paths=invalid_paths), dict(paths=invalid_u),
               dict(paths=invalid_authorization), dict(paths=invalid_bid))
        for changes in bad:
            with self.subTest(changes=tuple(changes)), self.assertRaises((TypeError, ValueError)):
                self.evaluate(**changes)

    def test_current_published_program_common_even_when_no_subscription_needed(self):
        for field, value in (('new_issue_authorization', F(1)),
                             ('subscription_limits', (F(1), F(0))),
                             ('subscription_rates_pct', (F(1), F(0))),
                             ('allocation_priority', ('B', 'A')),
                             ('news', b.m.News(demand_shock_pct=1))):
            paths = cells(); first = replace(paths[0].dates[0], **{field: value})
            paths = (replace(paths[0], dates=(first,) + paths[0].dates[1:]),) + paths[1:]
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, '[Cc]urrent'):
                self.evaluate(paths=paths)

    def test_source_check_failure_and_programmer_error_propagate(self):
        with patch.object(b.checkpoint, '_check_sources', side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError, 'source drift'): self.evaluate()
        with patch.object(self.adapter, 'prepare', side_effect=AssertionError('programmer defect')):
            with self.assertRaisesRegex(AssertionError, 'programmer defect'): self.evaluate()

    def test_known_treasury_prefix_failure_is_failed_baseline_not_unknown(self):
        from scripts.research.funded_production.tests.test_public_paydate_journal import fixture, pools
        root = replace(opening(), sector=fixture(faces=pools({1: 1}, {1: 1}),
            masses=pools({1: F(3, 10)}, {1: F(2, 5)}), tga=0, mortgage_rates=(0, 0)))
        quote = self.evaluate(root=root)
        self.assertEqual((quote.status, quote.action, quote.executor_calls,
                          quote.prefix_failures, quote.unknown_coverage),
                         ('baseline_incomplete', None, 0, 12, 0))


def actual_quote(root, paths, units):
    """Instrumentation retains raw-vs-macro distinctions without substitution."""
    q, _, _ = modules()
    raw = b.l.advance_given_orders; close = b.m._close_paid
    def counted(*args, **kwargs):
        COUNTS['raw_attempts'] += 1
        try:
            out = raw(*args, **kwargs)
        except Exception:
            COUNTS['raw_exceptions'] += 1
            raise
        COUNTS['raw_paid' if out.ok else 'raw_refused'] += 1
        return out
    def closed(*args, **kwargs):
        COUNTS['macro_closes'] += 1
        return close(*args, **kwargs)
    with patch.object(b.l, 'advance_given_orders', side_effect=counted) as attempts, \
         patch.object(b.m, '_close_paid', side_effect=closed) as closes:
        quote = q.evaluate(root, paths, units=units, forward_gross=(F(1),) * 18)
        return quote, attempts.call_count, closes.call_count


class PaydateBranchesActualPrefixTests(unittest.TestCase):
    """One twelve-attempt actual table with date-one coverage deliberately absent."""

    @classmethod
    def setUpClass(cls):
        # No opening CB debt means absent terms are initially valid. The optional
        # candidate's cross-bank invoice needs NEW CB credit, which is unknown
        # without its contract; cancellation must not relabel it known failure.
        # Invoice 37/8 exceeds B's 9/4 reserves plus HA's maximum services
        # transfer even if HA received ALL workforce wages. The first RED used
        # 3/2 units, whose 111/40 invoice did NOT need CB credit; retain that log.
        cls.root = opening(cb_rates_pct=(None, None)); cls.before = repr(cls.root)
        cls.quote, cls.attempts, cls.closes = actual_quote(cls.root, cells(missing=1), F(5, 2))

    def test_missing_is_not_zero_and_cancellation_is_paid_close_not_valid_total(self):
        quote = self.quote
        self.assertEqual((self.attempts, self.closes, quote.executor_calls,
                          quote.paid_closes, quote.refused_closes), (12, 12, 12, 12, 0))
        self.assertEqual((quote.status, quote.action), ('admission_incomplete', None))
        self.assertEqual(quote.unknown_coverage, 12)
        self.assertEqual(repr(self.root), self.before)
        for path in quote.paths:
            self.assertEqual((len(path.rows), path.rows[0].date), (1, 0))
            self.assertIsNone(path.total_pv); self.assertIsNone(path.incremental_pv)
            self.assertEqual(path.prefix_pv, path.rows[0].pv)
            if path.action == 'NOW':
                self.assertEqual((path.status, path.paid_units, path.project_origin_face), ('unknown', 0, 0))
                self.assertEqual(path.canceled_reason, 'unsupported_public_income')
                self.assertEqual(path.rows[0].construction_invoice, 0)
            else:
                self.assertEqual(path.status, 'unknown')


class PaydateBranchesActualTableTests(unittest.TestCase):
    """ONE shared 228-attempt maximum full table; never a second actual table."""

    @classmethod
    def setUpClass(cls):
        cls.root = opening(debt=True); cls.before = repr(cls.root)
        cls.quote, cls.attempts, cls.closes = actual_quote(cls.root, cells(), F(3, 2))

    def test_counts_completion_and_opening_source_immutability(self):
        quote = self.quote
        self.assertEqual((self.attempts, self.closes, quote.executor_calls,
                          quote.paid_closes, quote.refused_closes, quote.prefix_failures,
                          quote.unknown_coverage), (228, 228, 228, 228, 0, 0, 0))
        self.assertEqual(quote.status, 'completed')
        self.assertEqual(repr(self.root), self.before)
        self.assertEqual(quote.opening_digest, b._digest(self.root))
        self.assertIs(type(quote), b.Quotation)
        # All four hidden labels have the SAME current history and disclosures.
        # Their full-table WAIT decision must still use one coarse observation.
        self.assertEqual(len(quote.exercise_choices), 1)
        self.assertEqual(quote.exercise_choices[0].weight, 1)
        self.assertEqual(set(quote.exercise_choices[0].cells),
                         {(-1, False), (-1, True), (1, False), (1, True)})

    def test_single_tranche_and_actual_project_principal_origin_retirement(self):
        self.assertTrue(any(x.project_origin_face > 0 for x in self.quote.paths))
        for path in self.quote.paths:
            with self.subTest(action=path.action, sign=path.demand_sign, fulfilled=path.fulfilled):
                date_index = {'NOW': 0, 'WAIT': 1, 'NEVER': None}[path.action]
                self.assertEqual([x.date for x in path.rows], list(range(19)))
                for field in ('requested_units', 'paid_units'):
                    self.assertEqual([x.date for x in path.rows if getattr(x, field)],
                                     [] if date_index is None else [date_index])
                self.assertEqual(path.project_origin_face, path.project_retired_principal)
                self.assertEqual(path.project_outstanding_face, 0)
                self.assertEqual(path.total_pv, sum((x.pv for x in path.rows), F(0)))
                self.assertEqual(path.project_origin_face,
                                 sum((x.project_origin_face for x in path.rows), F(0)))
                self.assertEqual(path.project_retired_principal,
                                 sum((x.project_retired_principal for x in path.rows), F(0)))

    def test_frozen_scalar_receipts_do_not_retain_future_states(self):
        _, _, adapter = modules()
        def check(value):
            self.assertNotIsInstance(value, (b.m.Envelope, b.l.Report, b.p.Prepared, adapter.Prepared))
            if type(value) is tuple:
                for child in value: check(child)
            elif type(value) in (b.Quotation, b.Path, b.Row, b.Decision):
                for field in fields(value): check(getattr(value, field.name))
        check(self.quote)
        for value in (self.quote, self.quote.paths[0], self.quote.paths[0].rows[0]):
            with self.assertRaises(FrozenInstanceError): setattr(value, fields(value)[0].name, None)


if __name__ == '__main__':
    unittest.main()
