"""Actual public-bridge state restoration, not a qualified decision replay."""
from dataclasses import replace
from fractions import Fraction as F
import importlib
import unittest

from scripts.research.funded_production import checkpoint as k

l = k.m.ledger


class PublicForecastCheckpointTests(unittest.TestCase):
    def test_current_public_forecast_source_is_bound(self):
        self.assertIn('public_forecast', k._SOURCES)

    def test_actual_public_bridge_state_roundtrips_without_claiming_command_replay(self):
        public = importlib.import_module('scripts.research.funded_production.public_forecast')
        original = k.m.initial(growth=0)
        macro = replace(original.macro, price_history=(100.,)*5,
            annualized_quarterly_inflation_pct=0, four_quarter_inflation_pct=0,
            expected_short_inflation_pct=0, expected_long_inflation_pct=0)
        sector = l.enable_funded_public(original.sector,
            l.public_income_terms(original.sector, treasury_rates_pct=(4, 4, 4),
                mortgage_rates_pct=(4, 4), cb_rates_pct=(0, 0)))
        opening = replace(original, macro=macro, sector=sector)
        book = sector.public_book
        rolls = (book.treasuries[0], *(row[0] for row in book.private_treasuries))
        step = public.PublicStep(iorb_rate_pct=F(1), facility_limits=(100, 100),
            fiscal=l.FundedPublicInstructions(treasury_rolls=rolls,
                                             treasury_issue_authorization=sum(rolls)))
        prepared = public.prepare(opening, k.m.Policy(3.5, 3.5), step)
        outcome = public.execute(prepared, public.controls(prepared))
        self.assertTrue(outcome.ok, outcome.reason)
        state = k.CandidateState(outcome.envelope)
        text = k.encode_checkpoint(state)
        restored = k.decode_checkpoint(text)
        self.assertEqual(restored, state)
        self.assertEqual(k.encode_checkpoint(restored), text)
        self.assertIs(type(restored.economy.sector.public_book), l.FundedPublicBook)
        # A state checkpoint is not a registered public decision/scenario format.
        for value in (step, prepared):
            with self.subTest(type=type(value).__name__), self.assertRaises(TypeError):
                k._pack(value)
        with self.assertRaisesRegex(NotImplementedError, '[Pp]ublic'):
            k.m.prepare(restored.economy, k.m.Policy(3.5, 3.5))


if __name__ == '__main__':
    unittest.main()
