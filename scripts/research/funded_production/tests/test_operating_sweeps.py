"""Contractual surplus repayment; reference hand cases, not a growth model."""
from dataclasses import replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import ledger as l, checkpoint as k, households


def fiscal(state):
    b = state.public_book
    rolls = (b.treasuries[0], b.private_treasuries[0][0], b.private_treasuries[1][0])
    return l.PublicInstructions(treasury_rolls=rolls, treasury_issue_authorization=sum(rolls))


class OperatingSweepTests(unittest.TestCase):
    def advance(self, state, orders=None, offers=(), renewals=(), forecast=None):
        controls = l.Controls(public_instructions=fiscal(state), facility_limits=(100, 100),
                              household_mode='cash_stock_close_v1', new_loans=offers,
                              renewals=renewals, closing_credit_forecast=forecast)
        orders = orders or replace(l.depth_orders(), market_clearing=True)
        before = repr(state)
        result = l.advance_given_orders(state, orders, controls)
        self.assertEqual(repr(state), before)
        self.assertEqual(l.advance_given_orders(state, orders, controls), result)
        self.assertTrue(result.ok, result.reason)
        return result.state

    def seeded(self, loan_type, faces=(10,), rate=4):
        state = l.initial_depth_reference()
        for face in faces:
            state = l.originate(state, loan_type('A', face, rate, 2, borrower='R'))
        total = sum(faces)
        # Authored funded R-to-HA transfer; same bank, no aggregate deposit change.
        state = replace(state, banks=(replace(state.banks[0], deposits=(17, 3 + total)),
                                      state.banks[1]))
        return state

    def test_new_loan_fully_sweeps_but_legacy_reference_is_unchanged(self):
        initial = l.initial_depth_reference()
        base = self.advance(initial)
        state = self.advance(initial, offers=(l.OperatingLoanOffer('A', 1, 0, 2, borrower='R'),))
        self.assertEqual(state.banks, base.banks)
        self.assertEqual(state.loans, base.loans)
        self.assertEqual(state.last.real_output, 25)
        notes = [t for t in state.last.trace if t.kind == 'operating_cash_sweep']
        self.assertEqual([t.amount for t in notes], [1])
        kinds = [p.kind for p in state.last.payments]
        self.assertLess(kinds.index('private_principal'), kinds.index('residual_dividend'))

    def test_cross_bank_sweep_has_actual_reserve_settlement(self):
        initial = l.initial_depth_reference()
        base = self.advance(initial)
        state = self.advance(initial, offers=(l.OperatingLoanOffer('A', 1, 0, 2, borrower='F'),))
        self.assertEqual(state.banks, base.banks)
        self.assertEqual(state.loans, base.loans)
        legs = [t for t in state.last.trace if t.kind == 'reserve_settlement'
                and dict(t.details).get('purpose') == 'private_principal']
        self.assertEqual([(t.actor, t.counterparty, t.amount) for t in legs], [('B', 'A', 1)])

    def test_starved_cross_bank_sweep_requires_actual_facility_liability(self):
        initial = l.initial_depth_reference()
        state = l.settle_public(initial, l.PublicInstructions(
            treasury_subscriptions=(0, F(9, 4)), treasury_issue_authorization=F(9, 4)))
        self.assertEqual(state.reserves('B'), 0)
        self.assertEqual(state.bank_equity('B'), initial.bank_equity('B'))
        orders = replace(l.depth_orders(), market_clearing=True)
        controls = l.Controls(household_mode='cash_stock_close_v1',
            public_instructions=fiscal(state), facility_limits=(0, 0), security_bids=(0, 0),
            new_loans=(l.OperatingLoanOffer('A', 1, 4, 2, borrower='F'),))
        failed = l.advance_given_orders(state, orders, controls)
        self.assertFalse(failed.ok)
        self.assertEqual((failed.status, failed.state), ('funding_failure', state))
        funded = l.advance_given_orders(state, orders,
                                       replace(controls, facility_limits=(0, F(1, 100))))
        self.assertTrue(funded.ok, funded.reason)
        self.assertEqual(funded.state.last.cb_borrowed, F(1, 100))
        self.assertEqual(funded.state.cb_debt('B'), F(1, 100))
        ordinary = l.advance_given_orders(state, orders, replace(controls,
            new_loans=(l.LoanOffer('A', 1, 4, 2, borrower='F'),)))
        self.assertTrue(ordinary.ok, ordinary.reason)
        self.assertEqual(next(z.face for z in ordinary.state.loans if z.id == 'L1'), 1)

    def test_pledged_private_principal_release_needs_owned_reserve_cash(self):
        initial = l.originate(l.initial_depth_reference(),
                               l.OperatingLoanOffer('A', 10, 4, 2, borrower='R'))
        tx = l._Transaction(initial, l.Controls(facility_limits=(F(112, 5), 0),
                                               security_bids=(0, 0)), 0)
        tx._draw('A', F(112, 5))
        tx.pay('R', 'HB', F(132, 5), 'funded_test_transfer')
        tx.pay('HA', 'HB', F(11, 4), 'funded_test_transfer')
        state = tx.finish()
        self.assertEqual((state.reserves('A'), state.cb_debt('A'), state.deposit('R')),
                         (0, F(112, 5), F(3, 5)))
        orders = replace(l.depth_orders(), market_clearing=True, investment_units=0,
                         preferences_a=households.Preferences(20, 0, 3))
        controls = l.Controls(household_mode='cash_stock_close_v1',
            public_instructions=fiscal(state), facility_limits=(F(112, 5), 0), security_bids=(0, 0))
        failed = l.advance_given_orders(state, orders, controls)
        self.assertFalse(failed.ok)
        self.assertEqual((failed.status, failed.state), ('funding_failure', state))
        transfer = l._Transaction(state, l.Controls(), 0)
        transfer.pay('HB', 'HA', F(1, 100), 'funded_test_transfer')
        liquid = transfer.finish()
        funded = l.advance_given_orders(liquid, orders, controls)
        self.assertTrue(funded.ok, funded.reason)
        sweep = next(t for t in funded.state.last.trace if t.kind == 'operating_cash_sweep')
        self.assertEqual((sweep.amount, dict(sweep.details)['buffer']),
                         (F(2941, 500000), F(3, 5)))
        self.assertEqual(liquid.cb_debt('A') - funded.state.cb_debt('A'), sweep.amount * F(4, 5))

    def test_partial_sweep_remaining_coupon_and_principal_conserve(self):
        orders = replace(l.depth_orders(), market_clearing=True, investment_units=0)
        initial = self.seeded(l.OperatingLoanOffer)
        first = self.advance(initial, orders,
                forecast=l.ClosingCreditForecast((F(1717, 100), 3)))
        loan = next(z for z in first.loans if isinstance(z, l.OperatingLoan))
        self.assertEqual((loan.face, loan.maturity, loan.start, loan.last_coupon_paid),
                         (F(71, 10), 2, 0, 1))
        self.assertEqual(first.deposit('R'), 17)
        principal = [p.amount for p in first.last.payments
                     if p.kind == 'private_principal' and p.claim_id == loan.id]
        self.assertEqual(principal, [F(29, 10)])
        q = next(dict(t.details) for t in first.last.trace
                 if t.kind == 'closing_credit_quote' and t.actor == 'A')
        self.assertEqual((q['firm_cash'], q['closing_risk'], q['wage_request']),
                         (17, F(71, 10), F(17, 100)))
        restored = k._unpack(k._pack(first), [k._MAX_NODES])
        self.assertEqual(restored, first)
        second = self.advance(restored, orders)
        self.assertEqual(second, self.advance(first, orders))
        coupon = [p.amount for p in second.last.payments
                  if p.kind == 'private_coupon' and p.claim_id == loan.id]
        self.assertEqual(coupon, [F(71, 1000)])
        paid = sum((p.amount for p in second.last.payments
                    if p.kind == 'private_principal' and p.claim_id == loan.id), F(0))
        self.assertEqual(principal[0] + paid, 10)
        self.assertFalse(any(z.id == loan.id for z in second.loans))

    def test_base_claim_never_swept_and_matching_deposit_destruction(self):
        orders = replace(l.depth_orders(), market_clearing=True, investment_units=0)
        base = self.advance(self.seeded(l.LoanOffer), orders)
        state = self.advance(self.seeded(l.OperatingLoanOffer), orders)
        self.assertEqual(next(z.face for z in base.loans if z.id == 'L1'), 10)
        self.assertEqual(base.loan_face - state.loan_face, F(29, 10))
        self.assertEqual(sum(base.deposit(a) - state.deposit(a) for a in l.ACTORS), F(29, 10))
        self.assertEqual(base.private_wealth, state.private_wealth)
        self.assertEqual([base.bank_equity(b) for b in l.BANKS],
                         [state.bank_equity(b) for b in l.BANKS])
        self.assertEqual(base.last.real_output, state.last.real_output)

    def test_only_identified_contracts_in_stable_claim_order(self):
        state = self.seeded(l.OperatingLoanOffer, faces=(6, 6), rate=0)
        state = l.originate(state, l.LoanOffer('A', 6, 0, 8, borrower='R'))
        state = replace(state, banks=(replace(state.banks[0], deposits=(17, 21)), state.banks[1]))
        after = self.advance(state, replace(l.depth_orders(), market_clearing=True, investment_units=0))
        self.assertEqual([(z.id, z.face) for z in sorted(after.loans, key=lambda z: z.id)
                          if z.borrower == 'R'], [('L1', 3), ('L2', 6), ('L3', 6)])
        self.assertIs(type(next(z for z in after.loans if z.id == 'L3')), l.Loan)

    def test_no_surplus_and_signed_coupon_loss(self):
        initial = l.initial_depth_reference()
        orders = replace(l.depth_orders(), market_clearing=True,
                         residual_workers=0, focal_workers=0, investment_units=0)
        owed = self.seeded(l.OperatingLoanOffer, rate=0)
        owed = replace(owed, banks=(replace(owed.banks[0], deposits=(0, 30)), owed.banks[1]))
        empty = self.advance(owed, orders)
        self.assertTrue(any(isinstance(z, l.OperatingLoan) for z in empty.loans))
        self.assertFalse(any(t.kind == 'operating_cash_sweep' for t in empty.last.trace))
        controls = l.Controls(public_instructions=fiscal(empty),
                              household_mode='cash_stock_close_v1', facility_limits=(100, 100))
        refused = l.advance_given_orders(empty, orders, controls)
        self.assertFalse(refused.ok)
        self.assertEqual(refused.status, 'credit_default')
        self.assertEqual(refused.state, empty)
        state = self.advance(initial,
                offers=(l.OperatingLoanOffer('A', 1, -4, 2, borrower='R'),))
        self.assertEqual(state.bank_equity('A'), initial.bank_equity('A') - F(1, 100))
        self.assertEqual(state.last.bank_dividend_to('HA'), 0)
        self.assertFalse(any(isinstance(z, l.OperatingLoan) for z in state.loans))

    def test_contract_dates_legacy_mode_and_trusted_offer_roundtrip(self):
        initial = l.initial_depth_reference()
        offer = l.OperatingLoanOffer('A', 1, 0, 2, borrower='R')
        self.assertEqual(k._unpack(k._pack(offer), [k._MAX_NODES]), offer)
        with self.assertRaises(ValueError):
            self.advance(initial, offers=(replace(offer, maturity=3),))
        with self.assertRaises(ValueError):
            l.originate(initial, replace(offer, maturity=1))
        state = l.originate(initial, offer)
        with self.assertRaises(ValueError):
            l.advance_given_orders(state, l.depth_orders(), l.Controls())
        with self.assertRaises(ValueError):
            l.OperatingLoan('bad', 'A', 1, 0, 3, 0, 0, borrower='R')

    def test_consented_renewal_preserves_contract_and_no_current_double_coupon(self):
        initial = self.seeded(l.OperatingLoanOffer, rate=0)
        initial = replace(initial, banks=(replace(initial.banks[0], deposits=(0, 30)), initial.banks[1]))
        zero = replace(l.depth_orders(), market_clearing=True, residual_workers=0,
                       focal_workers=0, investment_units=0)
        first = self.advance(initial, zero)
        loan = next(z for z in first.loans if isinstance(z, l.OperatingLoan))
        second = self.advance(first, zero, renewals=(l.Renewal(loan.id, 10, 4, 4),))
        renewed = next(z for z in second.loans if isinstance(z, l.OperatingLoan))
        self.assertEqual((renewed.start, renewed.maturity, renewed.last_coupon_paid), (2, 4, 2))
        coupons = [p.amount for p in second.last.payments
                   if p.kind == 'private_coupon' and p.payer == 'R']
        self.assertEqual(coupons, [])  # Old coupon0; new4% accrues starting next date.
        with self.assertRaises(ValueError):
            self.advance(first, zero, renewals=(l.Renewal(loan.id, 10, 4, 3),))


if __name__ == '__main__':
    unittest.main()
