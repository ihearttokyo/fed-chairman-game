"""Pure guards/accounting, then TWO shared actual paths (38 attempts maximum).

Synthetic scalar rows/claims below test bookkeeping, never replace settlement.
The actual fixture is an authored fixed schedule, not endogenous investment.
"""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import inspect
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_recurring_branches as r
from scripts.research.funded_production import public_branches as core
from scripts.research.funded_production import public_paydate as adapter
from scripts.research.funded_production import paydate_scenarios as scenarios
from scripts.research.funded_production.tests.test_paydate_branches import opening, cells


COUNTS = dict(attempts=0, paid=0, refused=0, raw_exceptions=0,
              macro_closes=0, macro_exceptions=0)


def scalar_row(date, cash=F(0)):
    """PURE invented scalars, not an asserted journal result."""
    return r.Row(date=date, quarter=date + 1, receipts=max(cash, F(0)),
        payroll=max(-cash, F(0)), construction_invoice=F(0), operating_cash=cash,
        discount_factor=F(1), pv=cash, gdp=F(0), jobs=F(0),
        background_requested_units=F(0), candidate_requested_units=F(0),
        requested_units=F(0), paid_units=F(0), shortfall_units=F(0), canceled_reason='')


def scalar_paths(now=F(2), wait=(4, -4, 4, -4), *, keys=None):
    """PURE reducer inputs. Counters describe synthetic records, not tool calls."""
    keys = (('same',),) * 4 if keys is None else keys
    result = []
    for i, (sign, fulfilled) in enumerate(((-1, False), (-1, True), (1, False), (1, True))):
        for action, value in (('NEVER', 0), ('NOW', now), ('WAIT', wait[i])):
            value = F(value)
            result.append(r.Path(demand_sign=sign, fulfilled=fulfilled, weight=F(1, 4),
                action=action, status='completed', reason='',
                rows=tuple(scalar_row(h, value if h == 0 else F(0)) for h in range(19)),
                prefix_pv=value, total_pv=value, incremental_pv=None,
                observation=keys[i] if action == 'WAIT' else None,
                units=F(0), background_units=F(0), claims=(), executor_calls=19,
                paid_closes=19, refused_closes=0, prefix_failures=0, unknown_coverage=0))
    return core._incrementals(tuple(result))


class RecurringPureTests(unittest.TestCase):
    def test_explicit_new_api_distinct_frozen_records_and_no_adoption_codec(self):
        self.assertEqual(str(inspect.signature(r.evaluate)),
            '(opening, cells, *, units, background_units, forward_gross, tolerance=1e-06) -> '\
            "'Quotation'")
        for name in ('Row', 'Path', 'Decision', 'Quotation'):
            self.assertIsNot(getattr(r, name), getattr(core, name))
        row = scalar_row(0)
        with self.assertRaises(FrozenInstanceError): row.date = 1
        with self.assertRaises((TypeError, ValueError)): core.checkpoint._pack(row)

    def test_current_information_reducer_not_hidden_labels_and_near_tie_wait(self):
        result = r._select(scalar_paths(now=F(-1)), F(0))
        self.assertEqual(result[:5], ('completed', 'NEVER', -1, 0, True))
        self.assertEqual(len(result[5]), 1)
        self.assertIs(type(result[5][0]), r.Decision)
        split = scalar_paths(now=F(2), keys=(('a',), ('b',), ('a',), ('b',)))
        result = r._select(split, F(0))
        self.assertEqual(result[1:4], ('WAIT', 2, 2))

    def test_failed_and_unknown_positive_cells_veto_but_zero_weight_retained(self):
        paths = scalar_paths()
        for action, status, expected in (('NEVER', 'failed', 'baseline_incomplete'),
                                          ('NOW', 'unknown', 'admission_incomplete')):
            changed = tuple(replace(p, status=status, total_pv=None, incremental_pv=None)
                if p.action == action and p.fulfilled else p for p in paths)
            self.assertEqual(r._select(changed, F(0))[:2], (expected, None))
        zero = tuple(replace(p, weight=F(0) if p.fulfilled else F(1, 2),
            status='unknown' if p.fulfilled else 'completed',
            total_pv=None if p.fulfilled else p.total_pv,
            incremental_pv=None if p.fulfilled else p.incremental_pv)
            for p in scalar_paths(wait=(0,) * 4))
        self.assertEqual((len(zero), r._select(zero, F(0))[1]), (12, 'NOW'))

    def test_background_known_shortfall_continues_but_joint_partial_is_not_candidate_delivery(self):
        for candidate, reason, expected in ((F(0), 'credit_constraint', None),
                (F(0), 'unsupported_public_income', 'unknown'),
                (F(1), 'credit_constraint', 'failed'),
                (F(1), 'unsupported_public_income', 'unknown')):
            self.assertEqual(r._delivery_failure(candidate, F(2), F(1), reason)[0], expected)
        self.assertEqual(r._delivery_failure(F(1), F(2), F(2), ''), (None, ''))
        with self.assertRaises(AssertionError): r._delivery_failure(F(0), F(0), F(1), '')

    def test_whole_invoice_cash_excludes_financing_and_discount_date_zero(self):
        report = core.l.Report(1, F(13), F(7), F(2), F(4), F(1), F(2),
            F(3), F(5), F(999), F(-999), F(888), F(777), F(666),
            F(555), F(444), F(0), F(0), (), ())
        row = r._cash_row(0, report, F(3), F(2), background=F(1), candidate=F(1),
            paid=F(1), canceled='known_shortfall', previous_claims=(), claims=(), discount=F(1))
        self.assertEqual((row.receipts, row.payroll, row.construction_invoice,
                          row.operating_cash, row.pv), (42, 5, 12, 25, 25))
        self.assertEqual((row.requested_units, row.paid_units, row.shortfall_units), (2, 1, 1))
        self.assertFalse(row.candidate_fully_delivered)
        forwards = tuple(F(h + 2, h + 1) for h in range(18))
        self.assertEqual(core._discount_factors(forwards), tuple(F(1, h + 1) for h in range(19)))

    def test_joint_claims_actual_receipts_and_background_tracking_without_root_relabel(self):
        root = core.l.ProjectLoan('root', 'B', F(5), F(4), 17, 0, 0)
        joint = core.l.ProjectLoan('joint', 'B', F(3), F(4), 17, 0, 1)
        claims = r._track_claims((), (root,), (root, joint), (),
                                 construction_date=0, quarter=1, decision_date=0)
        self.assertEqual(tuple(c.id for c in claims), ('joint',))
        self.assertEqual((claims[0].role, claims[0].origin_face), ('decision_date_joint', 3))
        background = core.l.ProjectLoan('background', 'B', F(2), F(4), 18, 1, 2)
        claims = r._track_claims(claims, (root, joint), (root, joint, background), (),
                                 construction_date=1, quarter=2, decision_date=0)
        self.assertEqual(claims[1].role, 'background')
        paid = core.l.Payment('F', 'BankB', F(3), 'private_principal', 'joint')
        done = r._track_claims(claims, (root, joint, background), (root, background), (paid,),
                               construction_date=2, quarter=3, decision_date=0)
        self.assertEqual((done[0].retired_principal, done[0].outstanding_face,
                          done[1].outstanding_face), (3, 0, 2))
        for changed in (replace(background, rate_pct=F(5)), replace(background, lender='A'),
                        replace(background, maturity=17), replace(background, start=2)):
            with self.subTest(change=changed), self.assertRaises(AssertionError):
                r._track_claims(claims, (root, joint, background), (root, joint, changed), (),
                                construction_date=2, quarter=3, decision_date=0)
        wrong = replace(paid, payee='BankA')
        with self.assertRaises(AssertionError):
            r._track_claims(claims, (root, joint, background), (root, background), (wrong,),
                            construction_date=2, quarter=3, decision_date=0)
        with self.assertRaises(AssertionError):
            r._track_claims(claims, (root, joint, background), (root, background), (),
                            construction_date=2, quarter=3, decision_date=0)
        with self.assertRaises(AssertionError):
            r._track_claims(done, (root, background), (root, background, joint), (),
                            construction_date=3, quarter=4, decision_date=0)
        reused_root = replace(root, start=3, maturity=20, last_coupon_paid=4)
        with self.assertRaises(AssertionError):
            r._track_claims((), (), (reused_root,), (), construction_date=3,
                            quarter=4, decision_date=None, root_ids=('root',))

    def test_exact_output_scalars_schemas_and_candidate_zero_no_decision_cohort(self):
        row = scalar_row(0)
        for change in (dict(date=True), dict(receipts=True), dict(canceled_reason=[]),
                       dict(shortfall_units=F(1))):
            with self.subTest(change=change), self.assertRaises((TypeError, ValueError)):
                replace(row, **change)
        path = scalar_paths()[0]
        self.assertEqual(path.decision_date_cohort, ())
        self.assertFalse(path.candidate_fully_delivered)
        self.assertEqual(path.background_policy, 'authored_fixed_schedule_counterfactual')
        for change in (dict(rows=list(path.rows)), dict(claims=[object()]),
                       dict(background_units=True), dict(observation=(object(),))):
            with self.subTest(change=change), self.assertRaises((TypeError, ValueError)):
                replace(path, **change)
        forged = replace(row)
        object.__setattr__(forged, '__dataclass_fields__', {})
        with self.assertRaises((TypeError, ValueError)):
            replace(path, rows=(forged,) + path.rows[1:])


class RecurringBoundaryTests(unittest.TestCase):
    """Pure evaluator preflight: no raw executor or monetary transaction."""
    def setUp(self):
        self.raw = patch.object(core.l, 'advance_given_orders',
            side_effect=AssertionError('No actual call in pure tests')).start()
        self.transaction = patch.object(core.l, '_Transaction',
            side_effect=AssertionError('No shadow ledger')).start()
        self.addCleanup(patch.stopall)

    def tearDown(self):
        self.assertEqual(self.raw.call_count, 0)
        self.assertEqual(self.transaction.call_count, 0)

    def quote(self, **changes):
        args = dict(opening=opening(), cells=cells(missing=0), units=F(1, 2),
                    background_units=F(1), forward_gross=(F(1),) * 18)
        args.update(changes)
        return r.evaluate(**args)

    def test_missing_current_zero_attempts_and_zero_background_parity(self):
        quote = self.quote(background_units=F(0))
        from scripts.research.funded_production import public_paydate_branches as old
        root = opening(); paths = cells(missing=0)
        prior = old.evaluate(root, paths, units=F(1, 2), forward_gross=(F(1),) * 18)
        for name in ('status', 'action', 'expected_now', 'wait_value', 'opening_digest',
                     'executor_calls', 'paid_closes', 'refused_closes', 'prefix_failures', 'unknown_coverage'):
            self.assertEqual(getattr(quote, name), getattr(prior, name))
        self.assertEqual((len(quote.paths), quote.unknown_coverage), (12, 12))
        self.assertTrue(all(p.total_pv is None for p in quote.paths))
        with self.assertRaises((TypeError, ValueError)): core.checkpoint._pack(quote)

    def test_bad_background_and_future_program_grid_refused_before_execution(self):
        class BadInt(int):
            @property
            def numerator(self): return self
        for value in (True, BadInt(1), F(BadInt(1)), F(-1), F(1, 10**7), float('nan'), [1]):
            with self.subTest(value=type(value)), self.assertRaises((TypeError, ValueError)):
                self.quote(background_units=value)
        paths = cells()
        for changes in (dict(facility_limits=(F(1, 10**7), F(100))),
                        dict(new_issue_authorization=F(1, 10**7)),
                        dict(subscription_limits=(F(1, 10**7), F(0))),
                        dict(news=core.m.News(structural_unemployment_change_pct=-100))):
            future = replace(paths[0].dates[18], **changes)
            altered = (replace(paths[0], dates=paths[0].dates[:18] + (future,)),) + paths[1:]
            with self.subTest(changes=changes), self.assertRaises((TypeError, ValueError)):
                self.quote(cells=altered)

    def test_book_current_information_and_sources_cannot_be_bypassed(self):
        from scripts.research.funded_production.tests.test_public_branches import opening as old_opening
        with self.assertRaises((TypeError, ValueError)): self.quote(opening=old_opening())
        root = opening(); object.__setattr__(root, 'version', 2)
        with self.assertRaises((TypeError, ValueError)): self.quote(opening=root)
        paths = cells(); current = replace(paths[0].dates[0], new_issue_authorization=F(1))
        altered = (replace(paths[0], dates=(current,) + paths[0].dates[1:]),) + paths[1:]
        with self.assertRaisesRegex(ValueError, '[Cc]urrent'): self.quote(cells=altered)
        with patch.object(core.checkpoint, '_check_sources', side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError, 'source drift'): self.quote()
        with patch.object(adapter, 'prepare', side_effect=AssertionError('programmer error')):
            with self.assertRaisesRegex(AssertionError, 'programmer error'): self.quote(cells=cells())

    def test_programmer_exception_still_checks_root_and_predecessor_immutability(self):
        root = opening()
        def defect(state, *args, **kwargs):
            object.__setattr__(state.macro, 'public_support', state.macro.public_support + 1)
            raise AssertionError('injected mutation and error; no monetary call')
        with patch.object(adapter, 'prepare', side_effect=defect):
            with self.assertRaisesRegex(ValueError, 'mutated'):
                self.quote(opening=root, cells=cells())


class RecurringActualPairTests(unittest.TestCase):
    """Two cached one-cell paths only: NEVER19 + NOW19, maximum38 attempts."""
    @classmethod
    def setUpClass(cls):
        cls.root = opening(debt=True); cls.before = repr(cls.root)
        cls.units = F(1, 2); cls.background = F(3, 2)
        checked, units, _, _, discounts, _ = core._validated_inputs(cls.root, cells(),
            units=cls.units, forward_gross=(F(1),) * 18, paydate=True)
        cls.cell = checked[0]
        raw = core.l.advance_given_orders; close = core.m._close_paid
        def counted(*args, **kwargs):
            COUNTS['attempts'] += 1
            if COUNTS['attempts'] > 38: raise AssertionError('Actual budget exceeded')
            try: out = raw(*args, **kwargs)
            except Exception:
                COUNTS['raw_exceptions'] += 1
                raise
            COUNTS['paid' if out.ok else 'refused'] += 1
            return out
        def closed(*args, **kwargs):
            try: out = close(*args, **kwargs)
            except Exception:
                COUNTS['macro_exceptions'] += 1
                raise
            COUNTS['macro_closes'] += 1
            return out
        with patch.object(core.l, 'advance_given_orders', side_effect=counted), \
             patch.object(core.m, '_close_paid', side_effect=closed):
            cls.baseline = r._run_path(cls.root, cls.cell, 'NEVER', units,
                                       cls.background, discounts, F(1, 4))
            if cls.baseline.status != 'completed':
                raise AssertionError('Retain baseline fixture failure before another actual batch: '
                                     + cls.baseline.reason)
            cls.now = r._run_path(cls.root, cls.cell, 'NOW', units,
                                  cls.background, discounts, F(1, 4))

    def test_real_joint_cohort_retires_and_later_background_is_right_censored(self):
        self.assertEqual(COUNTS, dict(attempts=38, paid=38, refused=0, raw_exceptions=0,
                                      macro_closes=38, macro_exceptions=0))
        self.assertEqual(repr(self.root), self.before)
        self.assertEqual((self.baseline.status, self.now.status), ('completed', 'completed'))
        self.assertEqual(self.baseline.decision_date_cohort, ())
        self.assertTrue(self.now.candidate_fully_delivered)
        self.assertGreater(self.now.decision_date_origin_face, 0)
        self.assertEqual(self.now.decision_date_origin_face, self.now.decision_date_retired_principal)
        self.assertEqual(self.now.decision_date_outstanding_face, 0)
        self.assertTrue(any(c.construction_date > 1 for c in self.now.background_claims))
        self.assertGreater(self.now.background_outstanding_face, 0)
        self.assertTrue(self.now.background_right_censored)
        for path in (self.baseline, self.now):
            for claim in path.claims:
                self.assertEqual(claim.origin_face, claim.retired_principal + claim.outstanding_face)

    def test_common_schedule_whole_invoice_incrementals_and_no_physical_split(self):
        baseline, now = core._incrementals((self.baseline, self.now))
        self.assertEqual(now.incremental_pv, now.total_pv - baseline.total_pv)
        self.assertEqual(baseline.incremental_pv, 0)
        for path in (baseline, now):
            self.assertEqual([z.background_requested_units for z in path.rows], [self.background] * 19)
            self.assertEqual([z.date for z in path.rows if z.candidate_requested_units],
                             [] if path.action == 'NEVER' else [0])
            for row in path.rows:
                self.assertEqual(row.operating_cash, row.receipts-row.payroll-row.construction_invoice)
            self.assertEqual(path.total_pv, sum((z.pv for z in path.rows), F(0)))
        self.assertEqual((now.rows[0].requested_units, now.rows[0].paid_units), (2, 2))
        self.assertFalse(hasattr(now.rows[0], 'candidate_paid_units'))
        self.assertFalse(hasattr(now, 'project_origin_face'))

    def test_cached_actual_records_are_frozen_scalar_only_unadoptable(self):
        def visit(value):
            self.assertNotIsInstance(value, (core.m.Envelope, core.l.Report, adapter.Prepared))
            if type(value) is tuple:
                for child in value: visit(child)
            elif type(value) in (r.Path, r.Row, r.ProjectClaim):
                for field in fields(value): visit(getattr(value, field.name))
        visit(self.now)
        for value in (self.now, self.now.rows[0], self.now.claims[0]):
            with self.assertRaises(FrozenInstanceError): setattr(value, fields(value)[0].name, None)
            with self.assertRaises((TypeError, ValueError)): core.checkpoint._pack(value)


if __name__ == '__main__':
    unittest.main()
