"""Exact local oracle parity, not native-game or cross-platform qualification."""
from pathlib import Path
from fractions import Fraction as F
import json
import unittest
from scripts.research.funded_production import checkpoint as k

FIXTURE = Path(__file__).parent / 'fixtures' / 'committed_golden.json'


class CommittedGoldenTests(unittest.TestCase):
    def test_all_retained_fields_and_event_controls_match_frozen_reference(self):
        golden = json.loads(FIXTURE.read_text())
        a = k.initial(growth=2)
        for expected in golden['events']:
            macro = a.economy.macro
            target = k.m.round_quote(macro.r_star_pct + macro.expected_short_inflation_pct
                                    + 1.5 * (macro.four_quarter_inflation_pct - 2)
                                    + .5 * macro.output_gap_pct)
            fields = expected['fields']
            fraction = fields['additional_units']['$fraction']
            extra = F(int(fraction[0]), int(fraction[1]))
            out = k.adopt(a, k.m.Policy(target, target, 1.5, .5), additional_units=extra)
            self.assertTrue(out.ok, out.reason)
            actual = json.loads(k.encode_event(out.event))['payload']
            actual['fields'].pop('before_digest')
            actual['fields'].pop('after_digest')
            # New optional payout instruction is explicitly disabled; retain
            # strict equality of every pre-existing frozen command field.
            self.assertIsNone(actual['fields']['controls']['fields'].pop('bank_capital_targets'))
            self.assertIsNone(actual['fields']['controls']['fields'].pop('closing_credit_forecast'))
            self.assertEqual(actual, expected)
            a = out.state
        expected = next(s for s in golden['states'] if s['case'] == 'q16')
        self.assertEqual(json.loads(k.encode_checkpoint(a))['payload'], expected['payload'])
        saved = k.decode_checkpoint(k.encode_checkpoint(a))
        macro = saved.economy.macro
        target = k.m.round_quote(macro.r_star_pct + macro.expected_short_inflation_pct
                                + 1.5 * (macro.four_quarter_inflation_pct - 2)
                                + .5 * macro.output_gap_pct)
        out = k.adopt(saved, k.m.Policy(target, target, 1.5, .5))
        self.assertTrue(out.ok, out.reason)
        expected = next(s for s in golden['states'] if s['case'] == 'q17_resume_test')
        self.assertEqual(json.loads(k.encode_checkpoint(out.state))['payload'], expected['payload'])


if __name__ == '__main__':
    unittest.main()
