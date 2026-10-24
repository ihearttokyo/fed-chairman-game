"""Actual closing facts and conditional gross quotes, not forecast certainty."""
from dataclasses import replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import ledger as l, checkpoint as k


def fiscal(state):
    b = state.public_book
    rolls = (b.treasuries[0], b.private_treasuries[0][0], b.private_treasuries[1][0])
    return l.PublicInstructions(treasury_rolls=rolls, treasury_issue_authorization=sum(rolls))


class ClosingCreditQuoteTests(unittest.TestCase):
    def forecast(self, payroll=(17, 3), project=(0, 0)):
        return l.ClosingCreditForecast(payroll, project)

    def advance(self, state, forecast=None, orders=None, loans=(), renewals=()):
        controls = l.Controls(public_instructions=fiscal(state), facility_limits=(100, 100),
                              household_mode='cash_stock_close_v1', new_loans=loans,
                              renewals=renewals, closing_credit_forecast=forecast)
        before = repr(state)
        out = l.advance_given_orders(state,
                orders or replace(l.depth_orders(), market_clearing=True), controls)
        self.assertEqual(repr(state), before)
        self.assertEqual(l.advance_given_orders(state,
                orders or replace(l.depth_orders(), market_clearing=True), controls), out)
        return out

    def paid(self, *args, **kwargs):
        out = self.advance(*args, **kwargs)
        self.assertTrue(out.ok, out.reason)
        return out.state

    def quote(self, state, bank):
        notes = [t for t in state.last.trace if t.kind == 'closing_credit_quote' and t.actor == bank]
        self.assertEqual(len(notes), 1)
        return dict(notes[0].details)

    def test_nonbinding_quote_changes_no_balances_or_paid_goods(self):
        initial = l.initial_depth_reference()
        base = self.paid(initial)
        quoted = self.paid(initial, forecast=self.forecast())
        self.assertEqual(base.banks, quoted.banks)
        self.assertEqual(base.loans, quoted.loans)
        self.assertEqual(base.last.payments, quoted.last.payments)
        self.assertEqual(base.last.real_output, quoted.last.real_output)
        self.assertEqual(self.quote(quoted, 'B')['gross_request'], 0)

    def test_binding_retention_supports_specified_next_offer_without_grant(self):
        initial = l.provision(l.initial_depth_reference(), 'L0', 8)
        base = self.paid(initial)
        held = self.paid(initial, forecast=self.forecast((F(51, 2), F(9, 2))))
        self.assertEqual(held.bank_equity('B'), F(23, 20))
        self.assertEqual(held.bank_equity('B') - base.bank_equity('B'), F(1, 20))
        self.assertEqual(base.deposit('HB') - held.deposit('HB'), F(1, 20))
        self.assertEqual(held.private_wealth, base.private_wealth)
        self.assertEqual(held.loan_face, base.loan_face)
        self.assertEqual([held.reserves(b) for b in l.BANKS], [base.reserves(b) for b in l.BANKS])
        self.assertEqual(held.last.real_output, base.last.real_output)
        q = self.quote(held, 'B')
        self.assertEqual((q['firm_cash'], q['wage_request'], q['target']),
                         (3, F(3, 2), F(23, 20)))
        # A declared 50% price rise needs owned 8.5/1.5 wage credit, not a grant.
        loans = (l.LoanOffer('A', F(17, 2), 4, 8, borrower='R'),
                 l.LoanOffer('B', F(3, 2), 4, 8, borrower='F'))
        orders = replace(l.depth_orders(), market_clearing=True, price_factor=F(3, 2))
        rejected = self.advance(base, orders=orders, loans=loans)
        self.assertFalse(rejected.ok)
        self.assertEqual(rejected.status, 'credit_constraint')
        self.assertEqual(rejected.state, base)
        next_state = self.paid(held, orders=orders, loans=loans)
        observed = [dict(t.details) for t in next_state.last.trace
                    if t.kind == 'closing_credit_forecast_observed']
        self.assertEqual(len(observed), 2)
        self.assertEqual([d['payroll_error'] for d in observed], [0, 0])
        self.assertEqual([d['offer_error'] for d in observed], [0, 0])

    def test_actual_cash_above_floor_is_not_replaced_by_floor_proxy(self):
        initial = l.originate(l.initial_depth_reference(),
                               l.LoanOffer('A', F(95, 2), 4, 8, borrower='R'))
        # Authored same-bank ownership transfer, total deposits unchanged.
        initial = replace(initial, banks=(replace(initial.banks[0], deposits=(17, F(101, 2))),
                                          initial.banks[1]))
        self.assertLess(initial.residual_equity, 0)
        state = self.paid(initial, forecast=self.forecast((F(1717, 100), 3)))
        q = self.quote(state, 'A')
        self.assertGreater(q['firm_cash'], F(1717, 100))
        self.assertEqual(q['wage_request'], 0)
        self.assertEqual(state.last.dividend_residual, 0)
        self.assertEqual(F(1717, 100) - 17, F(17, 100))  # rejected floor proxy

    def test_current_next_and_later_legal_principal_chronology(self):
        for due in (1, 2, 8):
            with self.subTest(due=due):
                state = l.originate(l.initial_depth_reference(),
                                     l.LoanOffer('A', F(1, 2), 4, due, borrower='R'))
                after = self.paid(state, forecast=self.forecast())
                self.assertEqual(self.quote(after, 'A')['closing_risk'], 0 if due == 1 else F(1, 2))
                self.assertEqual(self.quote(after, 'B')['closing_risk'], 10)

    def test_quotes_round_up_and_targets_cannot_create_earnings(self):
        state = self.paid(l.initial_depth_reference(),
                         forecast=self.forecast((17, 3 + F(1, 10**7)), (0, F(1, 10**7))))
        q = self.quote(state, 'B')
        self.assertEqual((q['wage_request'], q['project_request'], q['gross_request']),
                         (l.QUANTUM, l.QUANTUM, 2 * l.QUANTUM))
        initial = l.provision(l.initial_depth_reference(), 'L0', 8)
        state = self.paid(initial, forecast=self.forecast((17, 200)))
        self.assertEqual(state.bank_equity('B'), initial.bank_equity('B') + F(1, 10))
        self.assertEqual(state.last.bank_dividend_to('HB'), 0)
        self.assertGreater(self.quote(state, 'B')['unfunded_target'], 0)

    def test_negative_coupon_remains_loss_not_negative_retention(self):
        initial = l.initial_depth_reference()
        initial = replace(initial, loans=tuple(replace(z, rate_pct=-4) for z in initial.loans))
        state = self.paid(initial, forecast=self.forecast((200, 200)))
        self.assertEqual(state.bank_equity('B'), initial.bank_equity('B') - F(1, 10))
        self.assertEqual(state.last.bank_dividend_to('HB'), 0)
        self.assertEqual(state.loan_face, initial.loan_face)

    def test_immutable_forecast_record_and_exact_typed_payload(self):
        payroll, project = [17, 3], [0, 1]
        f = self.forecast(payroll, project)
        payroll[0], project[1] = 999, 999
        self.assertEqual((f.payroll_nominal, f.project_gross_nominal), ((17, 3), (0, 1)))
        controls = l.Controls(household_mode='cash_stock_close_v1', closing_credit_forecast=f)
        self.assertEqual(k._unpack(k._pack(controls), [k._MAX_NODES]), controls)
        with self.assertRaises(ValueError):
            l.Controls(closing_credit_forecast=f)
        with self.assertRaises(TypeError):
            l.Controls(household_mode='cash_stock_close_v1', closing_credit_forecast=lambda: 1)
        for bad in ((1,), (-1, 0), (True, 1), (float('nan'), 1)):
            with self.assertRaises((TypeError, ValueError)):
                self.forecast(bad)

    def test_malformed_previous_quote_metadata_is_explicitly_refused(self):
        state = self.paid(l.initial_depth_reference(), forecast=self.forecast())
        quote = next(t for t in state.last.trace if t.kind == 'closing_credit_quote')
        missing = replace(quote, details=tuple((a, b) for a, b in quote.details
                                               if a != 'forecast_payroll'))
        for trace in (tuple(missing if t is quote else t for t in state.last.trace),
                      state.last.trace + (quote,)):
            bad = replace(state, last=replace(state.last, trace=trace))
            before = repr(bad)
            with self.assertRaises((ValueError, TypeError)):
                self.advance(bad)
            self.assertEqual(repr(bad), before)


if __name__ == '__main__':
    unittest.main()
