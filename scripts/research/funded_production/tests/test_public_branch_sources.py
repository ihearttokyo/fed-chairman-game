"""Source-bound research quotations are not adopted investment or saved commands."""
from dataclasses import replace
from fractions import Fraction as F
import importlib
import unittest
from unittest.mock import patch

from scripts.research.funded_production import checkpoint as k


class PublicBranchSourceTests(unittest.TestCase):
    def test_tampered_fraction_components_are_not_canonical_amounts(self):
        funding = importlib.import_module('scripts.research.funded_production.public_funding')
        for numerator, denominator in ((1, 0), (2, 4), (1, -2)):
            value = F(1, 2)
            object.__setattr__(value, '_numerator', numerator)
            object.__setattr__(value, '_denominator', denominator)
            with self.subTest(components=(numerator, denominator)), self.assertRaises((TypeError, ValueError)):
                funding._number(value)

    def test_numeric_metaclasses_never_run_callbacks_or_mutate_the_root(self):
        branches = importlib.import_module('scripts.research.funded_production.public_branches')
        scenarios = importlib.import_module('scripts.research.funded_production.public_scenarios')
        p = importlib.import_module('scripts.research.funded_production.public_forecast')
        funding = importlib.import_module('scripts.research.funded_production.public_funding')
        l = k.m.ledger
        for operation in ('number', 'vector', 'date', 'units', 'int_alias'):
            original = k.m.initial(growth=0)
            root = replace(original, sector=l.enable_funded_public(original.sector,
                l.public_income_terms(original.sector)))
            before = branches._digest(root)
            calls = []

            class TrapMeta(type):
                def __eq__(self, other):
                    calls.append('equality')
                    object.__setattr__(root.macro, 'public_support', 1.)
                    return False

            class Trap(metaclass=TrapMeta):
                pass

            class AliasMeta(type):
                def __eq__(self, other):
                    calls.append('alias_equality')
                    object.__setattr__(root.macro, 'public_support', 1.)
                    return True

            class IntAlias(int, metaclass=AliasMeta):
                @property
                def numerator(self):
                    calls.append('numerator')
                    return 1

            cells = tuple(scenarios.ScenarioCell(sign, fulfilled, (None,)*19)
                          for sign in (-1, 1) for fulfilled in (False, True))
            with self.subTest(operation=operation), patch.object(p, 'prepare', wraps=p.prepare) as prepare, \
                    patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
                with self.assertRaises(TypeError):
                    if operation == 'number':
                        funding._number(Trap())
                    elif operation == 'vector':
                        funding._vector((0, Trap()), 2, 'probe')
                    elif operation == 'date':
                        scenarios.FullRollDate(k.m.Policy(3.5, 3.5), k.m.News(), Trap(), (100, 100))
                    else:
                        branches.evaluate(root, cells, units=IntAlias(1) if operation == 'int_alias' else Trap(),
                                          forward_gross=(F(1),)*18)
                self.assertEqual((calls, branches._digest(root)), ([], before))
                self.assertEqual((prepare.call_count, advance.call_count), (0, 0))

    def test_unsupported_envelope_versions_reject_before_preparation(self):
        branches = importlib.import_module('scripts.research.funded_production.public_branches')
        scenarios = importlib.import_module('scripts.research.funded_production.public_scenarios')
        p = importlib.import_module('scripts.research.funded_production.public_forecast')
        l = k.m.ledger
        original = k.m.initial(growth=0)
        original = replace(original, sector=l.enable_funded_public(original.sector,
            l.public_income_terms(original.sector)))
        descriptor = scenarios.FullRollDate(k.m.Policy(3.5, 3.5), k.m.News(), 0, (100, 100))
        step = scenarios.resolve_date(original, descriptor).step
        cells = tuple(scenarios.ScenarioCell(sign, fulfilled, (descriptor,)+(None,)*18)
                      for sign in (-1, 1) for fulfilled in (False, True))
        for version in (2, True):
            root = replace(original)
            object.__setattr__(root, 'version', version)
            with self.subTest(version=version), patch.object(p, 'prepare', wraps=p.prepare) as prepare, \
                    patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
                for operation in (lambda: branches.evaluate(root, cells, units=0, forward_gross=(F(1),)*18),
                                  lambda: scenarios.resolve_date(root, descriptor),
                                  lambda: p.quote_prefix(root, step), lambda: k.CandidateState(root)):
                    with self.assertRaises(ValueError):
                        operation()
                self.assertEqual((prepare.call_count, advance.call_count), (0, 0))

    def test_observation_rejects_metaclass_equality_without_callbacks(self):
        branches = importlib.import_module('scripts.research.funded_production.public_branches')
        calls = []

        class TrapMeta(type):
            def __eq__(self, other):
                calls.append('equality')
                return True

        class Trap(metaclass=TrapMeta):
            pass

        with self.assertRaises(TypeError):
            branches._observation((Trap(),))
        self.assertEqual(calls, [])

    def test_both_new_source_files_are_bound(self):
        self.assertIn('public_scenarios', k._SOURCES)
        self.assertIn('public_branches', k._SOURCES)

    def test_missing_future_coverage_is_not_an_adopted_or_serialized_decision(self):
        scenarios = importlib.import_module('scripts.research.funded_production.public_scenarios')
        branches = importlib.import_module('scripts.research.funded_production.public_branches')
        l = k.m.ledger
        original = k.m.initial(growth=0)
        opening = replace(original, sector=l.enable_funded_public(original.sector,
            l.public_income_terms(original.sector, cb_rates_pct=(0, 0))))
        before = k.encode_checkpoint(k.CandidateState(opening))
        cells = tuple(scenarios.ScenarioCell(signal, fulfilled, (None,)*19)
                      for signal in (-1, 1) for fulfilled in (False, True))
        with patch.object(l, 'advance_given_orders', wraps=l.advance_given_orders) as advance:
            quote = branches.evaluate(opening, cells, units=F(1), forward_gross=(F(1),)*18)
            self.assertEqual(advance.call_count, 0)
            self.assertEqual(quote.executor_calls, 0)
        self.assertEqual(quote.status, 'admission_incomplete')
        self.assertIsNone(quote.action)
        self.assertEqual(k.encode_checkpoint(k.CandidateState(opening)), before)
        for value in (cells[0], quote):
            with self.subTest(type=type(value).__name__), self.assertRaises(TypeError):
                k._pack(value)

    def test_actual_credit_refusal_and_missing_cb_contract_are_distinct(self):
        scenarios = importlib.import_module('scripts.research.funded_production.public_scenarios')
        branches = importlib.import_module('scripts.research.funded_production.public_branches')
        l = k.m.ledger
        original = k.m.initial(growth=0)
        root = replace(original, sector=l.enable_funded_public(original.sector,
            l.public_income_terms(original.sector)))
        sector = root.sector
        # Authored initial redistribution, not a grant: retain bank liabilities
        # and move F's cash to HB, then suppress trading so its coupon is unpaid.
        b = sector.banks[1]
        poor = replace(root, sector=replace(sector, banks=(sector.banks[0],
            replace(b, deposits=(F(1, 100), sum(b.deposits)-F(1, 100))))))
        crash = scenarios.FullRollDate(k.m.Policy(3.5, 3.5),
            k.m.News(demand_shock_pct=-10000), F(0), (F(100), F(100)))
        failed_cells = tuple(scenarios.ScenarioCell(sign, fulfilled, (crash,)*19)
                             for sign in (-1, 1) for fulfilled in (False, True))
        failed = branches.evaluate(poor, failed_cells, units=0, forward_gross=(F(1),)*18)
        self.assertEqual((failed.status, failed.action), ('baseline_incomplete', None))
        self.assertEqual((failed.executor_calls, failed.paid_closes, failed.refused_closes), (12, 0, 12))
        self.assertTrue(all(path.status == 'failed' and path.reason.startswith('credit_default:')
                            for path in failed.paths))

        # Preserve aggregate reserves and deposits. A remains solvent, but its
        # cross-bank settlement needs a CB contract that was never declared.
        a, b = sector.banks
        no_contract = replace(root, sector=replace(sector, banks=(
            replace(a, reserves=F(0), deposits=(a.deposits[0], F(0))),
            replace(b, reserves=a.reserves+b.reserves,
                    deposits=(b.deposits[0], b.deposits[1]+a.deposits[1])))))
        self.assertGreater(no_contract.sector.bank_equity('A'), 0)
        normal = replace(crash, news=k.m.News())
        unknown_cells = tuple(scenarios.ScenarioCell(sign, fulfilled, (normal,)*19)
                              for sign in (-1, 1) for fulfilled in (False, True))
        unknown = branches.evaluate(no_contract, unknown_cells, units=0, forward_gross=(F(1),)*18)
        self.assertEqual((unknown.status, unknown.action), ('admission_incomplete', None))
        self.assertEqual((unknown.executor_calls, unknown.refused_closes, unknown.unknown_coverage), (12, 12, 12))
        self.assertTrue(all(path.status == 'unknown' and path.reason.startswith('unsupported_public_income:')
                            for path in unknown.paths))

    def test_optional_project_missing_cb_contract_is_unknown_not_rejected(self):
        scenarios = importlib.import_module('scripts.research.funded_production.public_scenarios')
        branches = importlib.import_module('scripts.research.funded_production.public_branches')
        l = k.m.ledger
        original = k.m.initial(growth=0)
        sector = l.enable_funded_public(original.sector, l.public_income_terms(original.sector))
        a, b = sector.banks
        root = replace(original, sector=replace(sector, banks=(
            replace(a, reserves=a.reserves+b.reserves), replace(b, reserves=F(0)))))
        current = scenarios.FullRollDate(k.m.Policy(3.5, 3.5), k.m.News(), F(0), (F(100), F(100)))
        cells = tuple(scenarios.ScenarioCell(sign, fulfilled, (current,)+(None,)*18)
                      for sign in (-1, 1) for fulfilled in (False, True))
        quote = branches.evaluate(root, cells, units=2, forward_gross=(F(1),)*18)
        now = tuple(path for path in quote.paths if path.action == 'NOW')
        self.assertEqual(len(now), 4)
        for path in now:
            self.assertEqual(path.canceled_reason, 'unsupported_public_income')
            self.assertEqual((path.status, path.paid_closes, path.refused_closes, path.unknown_coverage),
                             ('unknown', 1, 0, 1))
            self.assertIsNone(path.total_pv)


if __name__ == '__main__':
    unittest.main()
