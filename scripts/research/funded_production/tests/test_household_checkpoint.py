"""New reference codec convention, never native-save migration."""
from dataclasses import replace
from pathlib import Path
from fractions import Fraction as F
import hashlib
import unittest
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k,macro as m,ledger as l
from scripts.research.funded_production import early_liquidity as e,public_household_paydate as current
from scripts.research.funded_production.tests import test_public_household_paydate_current as fixtures
from scripts.research.funded_production.tests.test_household_liquidity import inputs as plan_inputs


def fresh():
    root=m.initial(growth=0)
    return replace(root,sector=l.enable_household_liquidity_public(root.sector,
        l.public_income_terms(root.sector,cb_rates_pct=(0,0))))


class HouseholdCheckpointPureTests(unittest.TestCase):
    def setUp(self):
        raw_guard=patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter'))
        tx_guard=patch.object(l,'_Transaction',side_effect=AssertionError('No transaction'))
        self.raw=raw_guard.start();self.addCleanup(raw_guard.stop)
        self.tx=tx_guard.start();self.addCleanup(tx_guard.stop)

    def tearDown(self):
        self.assertEqual((self.raw.call_count,self.tx.call_count),(0,0))

    def test_closed_tags_and_exact_module_fingerprint(self):
        for cls in (l.HouseholdLiquidityBook,l.HouseholdLiquidityPhase,
                    l.HouseholdLiquidityWitness,e.HouseholdLiquidityPlan):
            self.assertIn(cls,k._TAGS)
        self.assertNotIn(current.Prepared,k._TAGS)
        self.assertEqual(k._SOURCES['public_household_paydate'],
            hashlib.sha256(Path(current.__file__).read_bytes()).hexdigest())

    def test_fresh_roundtrip_preserves_exact_convention(self):
        state=k.CandidateState(fresh());restored=k.decode_checkpoint(k.encode_checkpoint(state))
        self.assertEqual(restored,state)
        self.assertIs(type(restored.economy.sector.public_book),l.HouseholdLiquidityBook)
        self.assertIsNone(restored.economy.sector.public_book.household_credit)

    def test_fresh_book_cannot_invent_validly_typed_credit_history(self):
        root=fresh();witness=l.HouseholdLiquidityWitness(e.household_plan(**plan_inputs()),())
        object.__setattr__(root.sector.public_book,'household_credit',witness)
        with self.assertRaises((TypeError,ValueError)):
            k.encode_checkpoint(k.CandidateState(root))

    def test_fresh_numeric_components_cannot_bypass_canonical_constructors(self):
        for target in ('bank','macro'):
            root=fresh()
            object.__setattr__(root.sector.banks[0] if target=='bank' else root.macro,
                               'reserves' if target=='bank' else 'growth_pct',True)
            with self.assertRaises((TypeError,ValueError)):
                k.encode_checkpoint(k.CandidateState(root))

    def test_fresh_paid_wages_are_not_legal_history(self):
        root=fresh();object.__setattr__(root.sector.public_book,'paid_wages',(F(1),F(0)))
        with self.assertRaises((TypeError,ValueError)):
            k.encode_checkpoint(k.CandidateState(root))

    def test_current_preparation_cannot_be_adopted_or_serialized(self):
        root=fixtures.opening();prepared=current.prepare(root,fixtures.POLICY,fixtures.step(root))
        with self.assertRaises((TypeError,ValueError)):
            k.encode_checkpoint(prepared)

    def test_source_failure_precedes_codec_or_preparation(self):
        state=k.CandidateState(fresh())
        with patch.object(k,'_check_sources',side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError,'source drift'):k.encode_checkpoint(state)
            with self.assertRaisesRegex(ValueError,'source drift'):
                current.prepare(state.economy,fixtures.POLICY,fixtures.step(state.economy))

    def test_loaded_adapter_alias_rejected(self):
        with patch.object(current,'__file__','/untrusted/public_household_paydate.py'):
            with self.assertRaisesRegex(ValueError,'module identity'):k._check_sources()


class HouseholdCheckpointActualTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root=fixtures.opening();prepared=current.prepare(root,fixtures.POLICY,fixtures.step(root))
        finance=current.controls(prepared)
        with patch.object(l,'advance_given_orders',wraps=l.advance_given_orders) as raw:
            out=current.execute(prepared,finance)
            if raw.call_count!=1:raise AssertionError('Codec fixture must make one raw attempt.')
        if not out.ok:raise AssertionError('Retain codec fixture failure: '+out.status+': '+out.reason)
        if out.envelope.sector.last.real_output<=0:raise AssertionError('No positive paid GDP.')
        cls.state=k.CandidateState(out.envelope);cls.root=root

    def test_paid_roundtrip_binds_actual_household_draw(self):
        book=self.state.economy.sector.public_book
        self.assertGreater(book.household_credit.plan.advances[1],0)
        self.assertEqual(k.decode_checkpoint(k.encode_checkpoint(self.state)),self.state)
        self.assertEqual(self.root.sector.quarter,0)

    def test_paid_witness_tamper_rejects_without_another_quarter(self):
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No extra quarter')) as raw:
            root=k.decode_checkpoint(k.encode_checkpoint(self.state)).economy
            plan=root.sector.public_book.household_credit.plan
            object.__setattr__(plan,'gross_after',(plan.gross_after[0],plan.gross_after[1]+F(1)))
            with self.assertRaises((TypeError,ValueError)):
                k.encode_checkpoint(k.CandidateState(root))
            self.assertEqual(raw.call_count,0)


if __name__=='__main__':unittest.main()
