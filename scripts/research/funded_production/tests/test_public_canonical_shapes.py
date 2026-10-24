"""Shared immutable-record boundary: no instance-defined schemas or callbacks."""
from dataclasses import replace
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_forecast as p
from scripts.research.funded_production import macro as m, ledger as l


def root():
    initial = m.initial(growth=0)
    return replace(initial, sector=l.enable_funded_public(initial.sector,
        l.public_income_terms(initial.sector, cb_rates_pct=(0,0))))


class PublicCanonicalShapeTests(unittest.TestCase):
    def test_root_schema_callback_cannot_mutate_root(self):
        value = root(); calls = []
        class Schema(dict):
            def values(self):
                calls.append('schema callback')
                object.__setattr__(value.macro,'public_support',1)
                return super().values()
        object.__setattr__(value,'__dataclass_fields__',Schema(type(value).__dataclass_fields__))
        before = repr(value)
        with self.assertRaises((TypeError, ValueError)):
            p._canonical_value(value)
        self.assertEqual(calls, [])
        self.assertEqual(repr(value), before)

    def test_hidden_version_cannot_reach_public_prefix(self):
        value = root()
        object.__setattr__(value,'version',2)
        schema = dict(type(value).__dataclass_fields__); schema.pop('version')
        object.__setattr__(value,'__dataclass_fields__',schema)
        step = p.PublicStep(0,l.FundedPublicInstructions(),(100,100))
        with patch.object(p.funding,'project_batch') as project:
            with self.assertRaises((TypeError, ValueError)):
                p.quote_prefix(value,step)
            self.assertEqual(project.call_count,0)

    def test_nested_record_metadata_is_not_a_field_schema(self):
        value = root()
        for record in (value.macro, value.sector.banks[0], m.Policy(3.5,3.5), m.News()):
            object.__setattr__(record,'__dataclass_fields__',{})
            with self.subTest(record=type(record).__name__), self.assertRaises((TypeError, ValueError)):
                p._canonical_value(record)

    def test_extra_instance_attributes_and_nonplain_keys_reject_without_equality(self):
        calls = []
        class Key(str):
            def __eq__(self,other): calls.append('key equality'); return True
            __hash__ = str.__hash__
        for key in ('undeclared_field', Key('undeclared_field')):
            value = root()
            value.__dict__[key] = 0
            calls.clear()
            with self.assertRaises((TypeError, ValueError)):
                p._canonical_value(value)
            self.assertEqual(calls,[])

    def test_valid_records_retain_canonical_value_without_mutation(self):
        value = root(); before = repr(value)
        self.assertEqual(p._canonical_value(value),p._canonical_value(replace(value)))
        self.assertEqual(repr(value),before)


if __name__ == '__main__': unittest.main()
