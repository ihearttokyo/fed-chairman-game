"""Source binding only; this program is not adopted or checkpoint-serializable."""
import unittest
from unittest.mock import patch

from scripts.research.funded_production import checkpoint as k
from scripts.research.funded_production import public_market as market
from scripts.research.funded_production import public_income as income
from scripts.research.funded_production.tests.test_public_market import opening, date


class PublicMarketSourceTests(unittest.TestCase):
    def test_shadowed_metadata_cannot_run_callbacks_or_change_root(self):
        root = opening()
        calls = []

        class Metadata(dict):
            def values(self):
                calls.append('metadata callback')
                object.__setattr__(root.macro, 'public_support', 1)
                return super().values()

        object.__setattr__(root, '__dataclass_fields__',
                           Metadata(type(root).__dataclass_fields__))
        before = repr(root)
        with self.assertRaises((TypeError, ValueError)):
            market.resolve_date(root, date())
        self.assertEqual(calls, [])
        self.assertEqual(repr(root), before)

    def test_instance_metadata_cannot_conceal_unsupported_version(self):
        root = opening()
        object.__setattr__(root, 'version', 2)
        metadata = dict(type(root).__dataclass_fields__)
        metadata.pop('version')
        object.__setattr__(root, '__dataclass_fields__', metadata)
        with self.assertRaises((TypeError, ValueError)):
            market.resolve_date(root, date())

    def test_descriptor_constructor_rejects_nested_metadata_before_callbacks(self):
        from dataclasses import replace
        calls = []

        class Metadata(dict):
            def values(self):
                calls.append('metadata callback')
                return super().values()

        for name in ('policy', 'news'):
            descriptor = date()
            child = getattr(descriptor, name)
            object.__setattr__(child, '__dataclass_fields__',
                               Metadata(type(child).__dataclass_fields__))
            with self.subTest(field=name), self.assertRaises((TypeError, ValueError)):
                replace(descriptor)
        self.assertEqual(calls, [])

    def test_new_module_has_bound_current_source(self):
        self.assertIn('public_market', k._SOURCES)
        k._check_sources()

    def test_changed_source_stops_before_public_quote_or_executor(self):
        root = opening()
        before = repr(root)
        with patch.object(k, '_check_sources', side_effect=ValueError('Changed source')), \
                patch.object(income, 'quote') as quote, \
                patch.object(market.l, 'advance_given_orders') as advance:
            with self.assertRaisesRegex(ValueError, 'Changed source'):
                market.resolve_date(root, date())
            self.assertEqual((quote.call_count, advance.call_count), (0, 0))
        self.assertEqual(repr(root), before)

    def test_descriptor_is_not_a_saved_command_or_adopted_economy(self):
        with self.assertRaises((TypeError, ValueError)):
            k.encode_checkpoint(date())
        descriptor = date()
        with self.assertRaises((TypeError, ValueError)):
            k.CandidateState(descriptor)
        # The old four-cell program refuses the new independent declaration.
        with self.assertRaises(TypeError):
            market.s.ScenarioCell(-1, False, (descriptor,) * 19)
