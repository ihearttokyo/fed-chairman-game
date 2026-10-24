"""Phase559: finite actual forecasts, plus explicitly PURE reducer/math cases.

No production settlement is replaced. The full-table fixture is one 228-attempt
maximum simulated quotation, not 228 real career adoptions or pure quotes.
"""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import importlib
import unittest
from unittest.mock import patch


PACKAGE = 'scripts.research.funded_production'


def modules(scenarios=True):
    # Do not import until the parent supplies SCENARIOS-READY.json.
    b = importlib.import_module(PACKAGE + '.public_branches')
    s = importlib.import_module(PACKAGE + '.public_scenarios') if scenarios else None
    return b, s


def opening():
    from scripts.research.funded_production.tests.test_public_forecast_current import opening as make
    return make(cb_rates_pct=(0, 0))


def cells(*, missing=None):
    b, s = modules()
    date = s.FullRollDate(b.m.Policy(3.5, 3.5), b.m.News(), F(0), (F(100), F(100)))
    dates = tuple(None if h == missing else date for h in range(19))
    return tuple(s.ScenarioCell(sign, fulfilled, dates)
                 for sign in (-1, 1) for fulfilled in (False, True))


class PublicBranchesBoundaryTests(unittest.TestCase):
    def test_exact_evaluate_api_and_required_explicit_curve(self):
        import inspect
        b, _ = modules()
        self.assertEqual(str(inspect.signature(b.evaluate)),
                         '(opening, cells, *, units, forward_gross, tolerance=1e-06) -> '
                         "'Quotation'")
        with self.assertRaises(TypeError):
            b.evaluate(opening(), cells(), units=0)

    def test_bad_root_curve_units_tolerance_and_structural_path_zero_executor(self):
        b, s = modules(); root = opening(); paths = cells()

        class EqualFloat(float):
            def __eq__(self, other): return True

        class FalseInt(int):
            @property
            def numerator(self): return self
            def __bool__(self): return False

        proxy = F(FalseInt(1))
        malformed_root = replace(root, macro=replace(root.macro))
        object.__setattr__(malformed_root.macro, 'credibility', EqualFloat(.85))
        malformed_book = replace(root, sector=replace(root.sector,
            public_book=replace(root.sector.public_book)))
        object.__setattr__(malformed_book.sector.public_book, 'tga', proxy)
        bad = [dict(opening=malformed_root), dict(opening=malformed_book),
               dict(units=True), dict(units=proxy), dict(units=F(-1)),
               dict(units=F(1, 10**7)), dict(forward_gross=[F(1)] * 18),
               dict(forward_gross=(F(1),) * 17),
               dict(forward_gross=(F(1),) * 17 + (F(0),)),
               dict(forward_gross=(F(1),) * 17 + (proxy,)),
               dict(tolerance=True), dict(tolerance=float('nan')),
               dict(tolerance=proxy), dict(tolerance=-1)]
        dates = list(paths[0].dates)
        dates[18] = replace(dates[18], news=b.m.News(structural_unemployment_change_pct=-100))
        bad.append(dict(cells=(replace(paths[0], dates=tuple(dates)),) + paths[1:]))
        dates = list(paths[0].dates)
        dates[18] = replace(dates[18], facility_limits=(F(1, 10**7), F(100)))
        bad.append(dict(cells=(replace(paths[0], dates=tuple(dates)),) + paths[1:]))
        with patch.object(b.p, 'execute', wraps=b.p.execute) as execute:
            for changed in bad:
                kwargs = dict(opening=root, cells=paths, units=F(0), forward_gross=(F(1),) * 18)
                kwargs.update(changed)
                with self.subTest(changed=tuple(changed)), self.assertRaises((TypeError, ValueError)):
                    b.evaluate(**kwargs)
            self.assertEqual(execute.call_count, 0)

    def test_different_resolved_current_information_refused_before_executor(self):
        b, _ = modules(); paths = cells()
        date = replace(paths[0].dates[0], news=b.m.News(demand_shock_pct=1))
        paths = (replace(paths[0], dates=(date,) + paths[0].dates[1:]),) + paths[1:]
        with patch.object(b.p, 'execute', wraps=b.p.execute) as execute:
            with self.assertRaisesRegex(ValueError, '[Cc]urrent'):
                b.evaluate(opening(), paths, units=0, forward_gross=(F(1),) * 18)
            self.assertEqual(execute.call_count, 0)

    def test_missing_current_coverage_retained_for_all_actions_without_calls(self):
        b, _ = modules()
        with patch.object(b.p, 'execute', wraps=b.p.execute) as execute:
            q = b.evaluate(opening(), cells(missing=0), units=1, forward_gross=(F(1),) * 18)
        self.assertEqual(execute.call_count, 0)
        self.assertEqual((q.status, q.action), ('admission_incomplete', None))
        self.assertEqual(len(q.paths), 12)
        self.assertEqual(q.unknown_coverage, 12)
        self.assertTrue(all(path.status == 'unknown' and not path.rows for path in q.paths))

    def test_unexpected_programming_error_propagates_not_good_forecast(self):
        b, _ = modules()
        with patch.object(b.p, 'prepare', side_effect=AssertionError('programmer defect')):
            with self.assertRaisesRegex(AssertionError, 'programmer defect'):
                b.evaluate(opening(), cells(), units=0, forward_gross=(F(1),) * 18)


class PublicBranchesPureTests(unittest.TestCase):
    """PURE scalar arithmetic and selection; no simulated ledger closes."""

    def test_date_zero_and_every_one_of_eighteen_forward_factors(self):
        b, _ = modules(False)
        forwards = tuple(F(h + 2, h + 1) for h in range(18))
        discounts = b._discount_factors(forwards)
        self.assertEqual(discounts, tuple(F(1, h + 1) for h in range(19)))
        for h in range(18):
            changed = forwards[:h] + (2 * forwards[h],) + forwards[h + 1:]
            actual = b._discount_factors(changed)
            self.assertEqual(actual[:h + 1], discounts[:h + 1])
            self.assertEqual(actual[h + 1:], tuple(x / 2 for x in discounts[h + 1:]))

    def test_operating_cash_whole_invoice_once_without_financial_flows(self):
        b, _ = modules(False); root = opening(); l = b.l
        # Pure Report arithmetic. Financial fields deliberately dwarf operations.
        report = l.Report(1, F(13), F(7), F(2), F(4), F(1), F(2),
            F(3), F(5), F(999), F(-999), F(888), F(777), F(666),
            F(555), F(444), F(0), F(0), (), ())
        row = b._cash_row(0, report, F(3), F(2), F(1, 4), F(1, 8),
                          F(0), F(0), F(0))
        self.assertEqual((row.receipts, row.payroll, row.construction_invoice), (42, 5, 12))
        self.assertEqual((row.operating_cash, row.discount_factor, row.pv), (25, 1, 25))
        later = b._cash_row(1, report, F(3), F(2), F(0), F(0),
                            F(0), F(0), F(0), discount=F(1, 2))
        self.assertEqual(later.pv, F(25, 2))

    def pure_paths(self, now=(0, 0, 0, 0), wait=(0, 0, 0, 0), *, keys=None):
        b, _ = modules(False); result = []
        keys = (('same',),) * 4 if keys is None else keys
        for i, (sign, fulfilled) in enumerate(((-1, False), (-1, True), (1, False), (1, True))):
            for action, value in (('NEVER', 0), ('NOW', now[i]), ('WAIT', wait[i])):
                result.append(b.Path(sign, fulfilled, F(1, 4), action, 'completed', '', (),
                    F(value), F(value), None, keys[i] if action == 'WAIT' else None,
                    F(0), F(0), None, '', (), F(0), F(0), F(0), 0, 0, 0, 0, 0))
        return b._incrementals(tuple(result))

    def test_wait_cannot_choose_clairvoyantly_by_hidden_cell(self):
        b, _ = modules(False)
        paths = self.pure_paths(now=(-1,) * 4, wait=(4, -4, 4, -4))
        status, action, expected_now, wait_value, admissible, choices = b._select(paths, F(0))
        self.assertEqual((status, action, expected_now, wait_value, admissible),
                         ('completed', 'NEVER', -1, 0, True))
        self.assertEqual(len(choices), 1)
        self.assertEqual((choices[0].weight, choices[0].conditional_delta, choices[0].action),
                         (1, 0, 'NEVER'))

    def test_current_observations_permit_grouping_and_ties_favor_wait(self):
        b, _ = modules(False)
        paths = self.pure_paths(now=(2,) * 4, wait=(4, -4, 4, -4),
            keys=(('a',), ('b',), ('a',), ('b',)))
        result = b._select(paths, F(0))
        self.assertEqual((result[1], result[2], result[3]), ('WAIT', 2, 2))
        self.assertEqual(tuple(x.action for x in result[5]), ('WAIT', 'NEVER'))

    def test_failed_positive_weight_baseline_is_not_filtered(self):
        b, _ = modules(False); paths = self.pure_paths(now=(20,) * 4, wait=(10,) * 4)
        paths = tuple(replace(x, status='failed', reason='credit_constraint', total_pv=None,
                              incremental_pv=None) if x.action == 'NEVER' and x.demand_sign == -1
                      else x for x in paths)
        result = b._select(paths, F(0))
        self.assertEqual(result[:2], ('baseline_incomplete', None))
        self.assertIsNone(result[2]); self.assertIsNone(result[3])

    def test_positive_unknown_stops_admission_but_known_now_failure_can_wait(self):
        b, _ = modules(False); paths = self.pure_paths(now=(20,) * 4, wait=(10,) * 4)
        for status, expected in (('unknown', 'admission_incomplete'), ('failed', 'completed')):
            changed = tuple(replace(x, status=status, reason='not_complete', total_pv=None,
                                    incremental_pv=None) if x.action == 'NOW' else x for x in paths)
            result = b._select(changed, F(0))
            self.assertEqual(result[0], expected)
            self.assertEqual(result[1], None if status == 'unknown' else 'WAIT')
            self.assertFalse(result[4])

    def test_failed_wait_member_blocks_whole_observation_group(self):
        b, _ = modules(False); paths = self.pure_paths(now=(-1,) * 4, wait=(100,) * 4)
        changed = tuple(replace(x, status='failed', reason='cancelled', total_pv=None,
                                incremental_pv=None) if x.action == 'WAIT' and x.fulfilled
                        else x for x in paths)
        result = b._select(changed, F(0))
        self.assertEqual((result[1], result[3]), ('NEVER', 0))
        self.assertFalse(result[5][0].admissible)

    def test_zero_weight_unknown_is_retained_but_does_not_block(self):
        b, _ = modules(False); paths = self.pure_paths(now=(1,) * 4)
        changed = tuple(replace(x, weight=F(0) if x.fulfilled else F(1, 2),
                                status='unknown' if x.fulfilled else 'completed',
                                total_pv=None if x.fulfilled else x.total_pv,
                                incremental_pv=None if x.fulfilled else x.incremental_pv)
                        for x in paths)
        self.assertEqual(len(changed), 12)
        self.assertEqual(b._select(changed, F(0))[:2], ('completed', 'NOW'))

    def test_output_records_reject_scalar_proxies_and_mutable_observations(self):
        b, _ = modules(False); path = self.pure_paths()[0]

        class FalseInt(int):
            @property
            def numerator(self): return self
            def __bool__(self): return False

        for changed in (dict(weight=True), dict(weight=F(FalseInt(1))),
                        dict(executor_calls=True), dict(observation=['mutable']),
                        dict(observation=(object(),)), dict(demand_sign=True)):
            with self.subTest(changed=tuple(changed)), self.assertRaises((TypeError, ValueError)):
                replace(path, **changed)

    def test_known_fraction_type_tags_in_module1_canonical_observation(self):
        b, _ = modules(False)
        # Fraction uses ABCMeta, not the exact built-in type metaclass.
        b._observation(b.p._canonical_value(('known nominal cash', F(1))))


class PublicBranchesActualTableTests(unittest.TestCase):
    """One shared actual, finite 4 x 3 x 19 quotation; no mocked executor."""

    @classmethod
    def setUpClass(cls):
        cls.b, _ = modules(); cls.root = opening()
        # A declared coherent Q0 fixture, not a transfer executed by the
        # forecast: move F's initial cash to its household at the same bank.
        # This preserves every bank balance sheet and forces this larger
        # candidate tranche to test ACTUAL new principal, not vacuous 0 == 0.
        banks = cls.root.sector.banks
        focal = banks[1]
        focal = replace(focal, deposits=(F(0), sum(focal.deposits, F(0))))
        cls.root = replace(cls.root, sector=replace(cls.root.sector, banks=(banks[0], focal)))
        cls.before = repr(cls.root)
        cls.ledger_attempts = 0
        with patch.object(cls.b.l, 'advance_given_orders', wraps=cls.b.l.advance_given_orders) as advance:
            cls.quote = cls.b.evaluate(cls.root, cells(), units=F(3, 2), forward_gross=(F(1),) * 18)
            cls.ledger_attempts = advance.call_count

    def test_actual_counts_complete_table_and_root_immutability(self):
        q = self.quote
        self.assertEqual(repr(self.root), self.before)
        self.assertEqual((len(q.paths), q.executor_calls), (12, self.ledger_attempts))
        self.assertLessEqual(q.executor_calls, 228)
        self.assertEqual((q.executor_calls, q.paid_closes, q.refused_closes,
                          q.prefix_failures, q.unknown_coverage), (228, 228, 0, 0, 0))
        self.assertEqual(q.status, 'completed')
        self.assertTrue(all(len(path.rows) == 19 for path in q.paths))
        self.assertEqual(sum(path.weight for path in q.paths if path.action == 'NEVER'), 1)

    def test_single_tranche_chronology_and_actual_project_principal_retirement(self):
        self.assertTrue(any(path.project_origin_face > 0 for path in self.quote.paths),
                        'The actual debt-retirement fixture must exercise project origination.')
        for path in self.quote.paths:
            with self.subTest(action=path.action, sign=path.demand_sign, fulfilled=path.fulfilled):
                date = {'NOW': 0, 'WAIT': 1, 'NEVER': None}[path.action]
                self.assertEqual([row.date for row in path.rows], list(range(19)))
                self.assertEqual([row.date for row in path.rows if row.requested_units],
                                 [] if date is None else [date])
                self.assertEqual([row.date for row in path.rows if row.paid_units],
                                 [] if date is None else [date])
                self.assertEqual(path.paid_quarter, None if date is None else date + 1)
                self.assertEqual(path.project_origin_face, path.project_retired_principal)
                self.assertEqual(path.project_outstanding_face, 0)
                self.assertEqual(path.total_pv, sum((row.pv for row in path.rows), F(0)))
                self.assertTrue(all(row.operating_cash == row.receipts - row.payroll
                                    - row.construction_invoice for row in path.rows))

    def test_outputs_are_frozen_and_do_not_retain_full_states(self):
        b = self.b; q = self.quote
        for value in (q, q.paths[0], q.paths[0].rows[0], *q.exercise_choices):
            with self.assertRaises(FrozenInstanceError):
                setattr(value, fields(value)[0].name, None)
        def no_states(value):
            self.assertNotIsInstance(value, (b.m.Envelope, b.l.Report, b.p.Prepared))
            if type(value) is tuple:
                for child in value: no_states(child)
            elif type(value) in (b.Quotation, b.Path, b.Row, b.Decision):
                for field in fields(value): no_states(getattr(value, field.name))
        no_states(q)


class PublicBranchesActualShortTests(unittest.TestCase):
    """Bounded actual prefixes and refusals, never a second full career."""

    def test_zero_units_actions_have_identical_paid_prefixes_missing_is_not_zero(self):
        b, _ = modules(); root = opening()
        with patch.object(b.l, 'advance_given_orders', wraps=b.l.advance_given_orders) as advance:
            q = b.evaluate(root, cells(missing=1), units=0, forward_gross=(F(1),) * 18)
        self.assertEqual((advance.call_count, q.executor_calls, q.paid_closes,
                          q.refused_closes, q.unknown_coverage), (12, 12, 12, 0, 12))
        self.assertEqual((q.status, q.action), ('admission_incomplete', None))
        for sign in (-1, 1):
            for fulfilled in (False, True):
                group = [x for x in q.paths if (x.demand_sign, x.fulfilled) == (sign, fulfilled)]
                self.assertEqual(group[0].rows, group[1].rows)
                self.assertEqual(group[1].rows, group[2].rows)
                self.assertTrue(all(x.incremental_pv is None and x.total_pv is None for x in group))

    def test_cancelled_actual_quarter_is_a_paid_close_but_failed_investment(self):
        b, _ = modules()
        with patch.object(b.l, 'advance_given_orders', wraps=b.l.advance_given_orders) as advance:
            q = b.evaluate(opening(), cells(missing=1), units=F(10**6),
                           forward_gross=(F(1),) * 18)
        self.assertEqual((advance.call_count, q.executor_calls, q.paid_closes,
                          q.refused_closes), (12, 12, 12, 0))
        for path in q.paths:
            if path.action == 'NOW':
                self.assertEqual(path.status, 'failed')
                self.assertEqual(path.paid_units, 0)
                self.assertIsNone(path.paid_quarter)
                self.assertTrue(path.canceled_reason)
                self.assertEqual((len(path.rows), path.rows[0].construction_invoice), (1, 0))
                self.assertIsNone(path.incremental_pv)

    def test_known_public_funding_prefix_failure_is_not_missing_coverage_or_executor_refusal(self):
        from scripts.research.funded_production.tests.test_public_funding import fixture, pools
        b, _ = modules()
        sector = fixture(faces=pools({1: 1}, {1: 1}),
            masses=pools({1: F(3, 10)}, {1: F(2, 5)}),
            reserves=(1, 1), deposits=(1, 1), tga=0)
        root = replace(opening(), sector=sector)
        with patch.object(b.l, 'advance_given_orders', wraps=b.l.advance_given_orders) as advance:
            q = b.evaluate(root, cells(), units=0, forward_gross=(F(1),) * 18)
        self.assertEqual((advance.call_count, q.executor_calls, q.paid_closes,
                          q.refused_closes, q.prefix_failures, q.unknown_coverage), (0, 0, 0, 0, 12, 0))
        self.assertEqual((q.status, q.action), ('baseline_incomplete', None))
        self.assertTrue(all(path.status == 'failed' and 'funding_failure' in path.reason for path in q.paths))


if __name__ == '__main__':
    unittest.main()
