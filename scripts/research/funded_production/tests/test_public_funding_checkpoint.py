"""Funded research-book restoration, not native saves or adapter qualification."""
from dataclasses import replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import checkpoint as k
from scripts.research.funded_production import public_funding as funding

l = k.m.ledger


class PublicFundingCheckpointTests(unittest.TestCase):
    def paid_fixture(self):
        original = l.initial_depth_reference()
        state = l.enable_funded_public(original, l.public_income_terms(original,
            treasury_rates_pct=(4, 4, 4), mortgage_rates_pct=(4, 4),
            iorb_rate_pct=1, cb_rates_pct=(0, 0)))
        book = state.public_book
        rolls = (book.treasuries[0], *(row[0] for row in book.private_treasuries))
        instructions = l.FundedPublicInstructions(
            treasury_rolls=rolls,
            treasury_subscriptions=(F(1, 5), 0),
            subscription_coupon_mass=(F(1, 125), None),
            treasury_issue_authorization=sum(rolls)+F(1, 5),
            mortgage_repayments=(F(1, 10), 0))
        result = l.advance_given_orders(state, l.depth_orders(), l.Controls(
            public_instructions=instructions, facility_limits=(10, 10),
            asset_purchase_request=F(1, 2), asset_offers=(F(1, 2), 0)))
        self.assertTrue(result.ok, result.reason)
        sector = result.state
        report = sector.last
        # Hand codec envelope only: no public macro adapter is executed.
        macro = replace(k.m.initial(growth=0).macro, quarter=sector.quarter,
            actual_output_index=4*float(report.real_output),
            unemployment_rate_pct=100*(1-float(
                report.paid_residual_workers+report.paid_focal_workers)/(4000/191)))
        return k.CandidateState(k.m.Envelope(macro, sector))

    def test_public_funding_source_is_bound(self):
        self.assertIn('public_funding', k._SOURCES)

    def test_fresh_book_and_instruction_identities_roundtrip(self):
        original = k.m.initial(growth=0)
        sector = l.enable_funded_public(original.sector,
            l.public_income_terms(original.sector, iorb_rate_pct=-1))
        state = k.CandidateState(replace(original, sector=sector))
        encoded = k.encode_checkpoint(state)
        restored = k.decode_checkpoint(encoded)
        self.assertEqual(restored, state)
        self.assertIs(type(restored.economy.sector.public_book), l.FundedPublicBook)
        self.assertEqual(k.encode_checkpoint(restored), encoded)
        instruction = l.FundedPublicInstructions(
            treasury_subscriptions=(F(1, 5), 0),
            treasury_issue_authorization=F(1, 5),
            subscription_coupon_mass=(F(-1, 125), None))
        self.assertEqual(k._unpack(k._pack(instruction), [k._MAX_NODES]), instruction)
        with self.assertRaisesRegex(NotImplementedError, '[Pp]ublic'):
            k.m.prepare(restored.economy, k.m.Policy(3.5, 3.5))

    def test_opening_batch_and_transfer_have_strict_registered_identities(self):
        rows = ((F(0),) * 120,) * 3
        opening = funding.FundingOpening(1, F(1), l.PublicIncomeTerms(rows), rows)
        batch = funding.FundingBatch(subscriptions=(1, 0), authorization=1,
                                     subscription_coupon_mass=(0, None))
        transfer = funding.TreasuryTransfer('A', 'CB', 1, F(-1, 25))
        for value in (opening, batch, transfer):
            with self.subTest(type=type(value).__name__):
                packed = k._pack(value)
                self.assertEqual(k._unpack(packed, [k._MAX_NODES]), value)
                changed = dict(packed, fields={**packed['fields'], 'future_field': 0})
                with self.assertRaisesRegex(ValueError, '[Uu]nknown|missing'):
                    k._unpack(changed, [k._MAX_NODES])

    def test_paid_book_roundtrip_preserves_opening_contract_and_trade_order(self):
        state = self.paid_fixture()
        text = k.encode_checkpoint(state)
        restored = k.decode_checkpoint(text)
        self.assertEqual(restored, state)
        self.assertEqual(k.encode_checkpoint(restored), text)
        book = restored.economy.sector.public_book
        self.assertIs(type(book.opening), funding.FundingOpening)
        self.assertIs(type(book.funding), funding.FundingBatch)
        self.assertTrue(book.transfers)
        self.assertTrue(all(type(event) is funding.TreasuryTransfer
                            for event in book.transfers))
        self.assertEqual(book.opening.quarter, restored.economy.sector.quarter)

    def test_two_paid_quarters_preserve_history_when_administered_rate_changes(self):
        first = self.paid_fixture()
        before = k.encode_checkpoint(first)
        sector = first.economy.sector
        old = sector.public_book
        rolls = (old.treasuries[0], *(row[0] for row in old.private_treasuries))
        result = l.advance_given_orders(sector, l.depth_orders(), l.PublicIncomeControls(
            iorb_rate_pct=2, facility_limits=(10, 10),
            public_instructions=l.FundedPublicInstructions(
                treasury_rolls=rolls, treasury_issue_authorization=sum(rolls))))
        self.assertTrue(result.ok, result.reason)
        book = result.state.public_book
        self.assertEqual(book.opening.quarter, 2)
        self.assertEqual(book.opening.terms.annual_treasury, old.terms.annual_treasury)
        self.assertEqual(book.opening.mortgages, old.mortgages)
        self.assertEqual(book.opening.reserves, tuple(b.reserves for b in sector.banks))
        self.assertEqual(book.opening.terms.iorb_rate_pct, 2)
        self.assertEqual(old.terms.iorb_rate_pct, 1)
        self.assertEqual(k.encode_checkpoint(first), before)
        l.validate_funded_public(book, result.state.scale, 2, result.state.last.payments)
        # The second paid sector restores directly without invoking a macro adapter.
        self.assertEqual(k._unpack(k._pack(result.state), [k._MAX_NODES]), result.state)

    def test_missing_invented_or_misattributed_quantity_receipts_refuse(self):
        state = self.paid_fixture()
        sector = state.economy.sector
        payments = sector.last.payments
        cases = (
            tuple(p for p in payments if p.kind != 'treasury_net_cash'),
            tuple(p for p in payments if p.kind not in (
                'household_mortgage_principal', 'pass_through_mbs_principal')),
            payments + (l.Payment('CB', 'A', F(1), 'public_par_purchase', 'Treasury:A'),),
            tuple(replace(p, claim_id='Treasury:B') if p.kind == 'public_par_purchase'
                  else p for p in payments),
        )
        before = k.encode_checkpoint(state)
        for changed in cases:
            with self.subTest(receipt_count=len(changed)), self.assertRaises(ValueError):
                forged = replace(sector, last=replace(sector.last, payments=changed))
                k.encode_checkpoint(replace(state,
                    economy=replace(state.economy, sector=forged)))
        self.assertEqual(k.encode_checkpoint(state), before)


if __name__ == '__main__':
    unittest.main()
