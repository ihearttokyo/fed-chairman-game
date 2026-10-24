"""Source-bound household forecasts never become saved commands."""
from pathlib import Path
from fractions import Fraction as F
import hashlib
import unittest
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k,ledger as l,macro as m
from scripts.research.funded_production import public_household_branches as q
from scripts.research.funded_production.tests import test_household_scenarios as fixtures


class HouseholdFutureSourceTests(unittest.TestCase):
    def test_exact_module_is_bound_without_adopted_forecast_tags(self):
        self.assertIn('public_household_branches',k._SOURCES)
        self.assertEqual(k._SOURCES['public_household_branches'],
            hashlib.sha256(Path(q.__file__).read_bytes()).hexdigest())
        for cls in (q.ScenarioCell,q.Quotation,q.RecurringQuotation):
            self.assertNotIn(cls,k._TAGS)

    def test_source_failure_precedes_any_forecast_execution(self):
        root=fixtures.opening();cells=tuple(q.ScenarioCell(sign,fulfilled,(None,)*19)
            for sign in (-1,1) for fulfilled in (False,True))
        with patch.object(k,'_check_sources',side_effect=ValueError('source drift')), \
             patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw, \
             patch.object(l,'_Transaction',side_effect=AssertionError('No transaction')) as tx:
            for operation in (lambda:q.evaluate(root,cells,units=0,forward_gross=(F(1),)*18),
                              lambda:q.evaluate_recurring(root,cells,units=0,background_units=1,forward_gross=(F(1),)*18)):
                with self.assertRaisesRegex(ValueError,'source drift'):operation()
            self.assertEqual((raw.call_count,tx.call_count),(0,0))

    def test_unknown_future_quotation_is_not_adoptable(self):
        root=fixtures.opening();before=repr(root)
        cells=tuple(q.ScenarioCell(sign,fulfilled,(None,)*19)
            for sign in (-1,1) for fulfilled in (False,True))
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw:
            for quote in (q.evaluate(root,cells,units=0,forward_gross=(F(1),)*18),
                          q.evaluate_recurring(root,cells,units=0,background_units=1,forward_gross=(F(1),)*18)):
                self.assertEqual(quote.status,'admission_incomplete')
                self.assertIsNone(quote.action)
                with self.assertRaises((TypeError,ValueError)):k.encode_checkpoint(quote)
            self.assertEqual(raw.call_count,0)
        self.assertEqual(repr(root),before)

    def test_signed_zero_cannot_split_equivalent_public_wait_information(self):
        root=fixtures.opening();before=repr(root)
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw, \
             patch.object(l,'_Transaction',side_effect=AssertionError('No transaction')) as tx:
            left=q.resolve_date(root,fixtures.date(news=m.News(demand_shock_pct=0.0)))
            right=q.resolve_date(root,fixtures.date(news=m.News(demand_shock_pct=-0.0)))
            self.assertEqual(left,right)
            self.assertEqual(q.wait_observation(root,left),q.wait_observation(root,right))
            self.assertEqual((raw.call_count,tx.call_count),(0,0))
        self.assertEqual(repr(root),before)

    def test_loaded_module_alias_refused_without_forecast(self):
        with patch.object(q,'__file__','/untrusted/public_household_branches.py'):
            with self.assertRaisesRegex(ValueError,'module identity'):k._check_sources()


if __name__=='__main__':unittest.main()
