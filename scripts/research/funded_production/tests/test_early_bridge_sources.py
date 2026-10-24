"""Closed source binding; preparations are not adopted career commands."""
from dataclasses import replace
from pathlib import Path
import hashlib
import unittest
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k, macro as m, ledger as l
from scripts.research.funded_production import public_forecast as p


def inputs():
    root = m.initial(growth=0)
    root = replace(root, sector=l.enable_early_paydate_public(root.sector,
        l.public_income_terms(root.sector, cb_rates_pct=(0, 0))))
    book = root.sector.public_book
    rolls = tuple(row[0] for row in (book.treasuries, *book.private_treasuries))
    step = p.PublicStep(0, l.FundedPublicInstructions(treasury_rolls=rolls,
        treasury_issue_authorization=sum(rolls)), (100, 100))
    return root, m.Policy(3.5, 3.5), step


class EarlyBridgeSourceTests(unittest.TestCase):
    def test_module_is_bound_to_exact_current_source(self):
        self.assertIn('public_early_paydate', k._SOURCES)
        path = Path(k.__file__).with_name('public_early_paydate.py')
        self.assertEqual(k._SOURCES['public_early_paydate'],
                         hashlib.sha256(path.read_bytes()).hexdigest())
        k._check_sources()

    def test_loaded_module_alias_refuses_without_a_quarter(self):
        from scripts.research.funded_production import public_early_paydate as current
        with patch.object(current, '__file__', '/untrusted/public_early_paydate.py'), \
             patch.object(l, 'advance_given_orders', side_effect=AssertionError('No quarter')) as raw:
            with self.assertRaisesRegex(ValueError, 'module identity'):
                k._check_sources()
            self.assertEqual(raw.call_count, 0)

    def test_preparation_is_source_bound_and_not_a_saved_command(self):
        from scripts.research.funded_production import public_early_paydate as current
        root, policy, step = inputs()
        before = repr(root)
        with patch.object(l, 'advance_given_orders', side_effect=AssertionError('No quarter')) as raw:
            prepared = current.prepare(root, policy, step)
            with self.assertRaises((TypeError, ValueError)):
                k.encode_checkpoint(prepared)
            with patch.object(k, '_check_sources', side_effect=ValueError('source drift')):
                for operation in (lambda: current.quote_prefix(root, step),
                                  lambda: current.prepare(root, policy, step),
                                  lambda: current.controls(prepared)):
                    with self.assertRaisesRegex(ValueError, 'source drift'):
                        operation()
            self.assertEqual(raw.call_count, 0)
        self.assertEqual(repr(root), before)


if __name__ == '__main__':
    unittest.main()
