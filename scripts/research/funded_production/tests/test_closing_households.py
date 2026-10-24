"""Paid closing-dividend hand cases, not an endogenous reference qualification."""
from dataclasses import replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import ledger as l, macro as m

MODE = 'cash_stock_close_v1'


def fiscal(state):
    book = state.public_book
    rolls = (book.treasuries[0], book.private_treasuries[0][0],
             book.private_treasuries[1][0])
    return l.PublicInstructions(treasury_rolls=rolls,
                                treasury_issue_authorization=sum(rolls))


class ClosingHouseholdsTests(unittest.TestCase):
    def advance(self, state, mode=MODE, targets=None, orders=None, loans=()):
        orders = orders or replace(l.depth_orders(), market_clearing=True)
        controls = l.Controls(public_instructions=fiscal(state),
                              household_mode=mode, facility_limits=(100, 100),
                              bank_capital_targets=targets, new_loans=loans)
        before = repr(state)
        result = l.advance_given_orders(state, orders, controls)
        self.assertEqual(repr(state), before)
        self.assertEqual(l.advance_given_orders(state, orders, controls), result)
        return result

    def paid(self, state, **kwargs):
        result = self.advance(state, **kwargs)
        self.assertTrue(result.ok, result.reason)
        return result.state

    def test_two_quarter_neutral_owned_cash_and_capital(self):
        state = l.initial_depth_reference()
        for _ in range(2):
            state = self.paid(state)
            self.assertEqual(state.last.real_output, 25)
            self.assertEqual((state.capital_units, state.wip_units), (16, 1))
            self.assertEqual([state.deposit(a) for a in l.ACTORS],
                             [17, 3, 3, F(3, 20)])
            self.assertEqual((state.last.dividend_residual,
                              state.last.dividend_focal,
                              state.last.bank_dividend_to('HB')),
                             (3, F(1, 20), F(1, 10)))

    def test_goods_close_before_any_distribution_and_budget_uses_paid_history(self):
        state = self.paid(self.paid(l.initial_depth_reference()))
        payments = state.last.payments
        goods = [i for i, p in enumerate(payments) if p.kind in
                 ('services', 'residual_consumption', 'investment')]
        distributions = [i for i, p in enumerate(payments)
                         if p.kind.endswith('dividend')]
        self.assertTrue(goods and distributions)
        self.assertLess(max(goods), min(distributions))
        notes = [t for t in state.last.trace if t.kind == 'household_budget']
        self.assertEqual(len(notes), 2)
        a, b = (dict(t.details) for t in notes)
        self.assertEqual((a['income_previous'], b['income_previous']), (20, F(63, 20)))
        self.assertEqual((a['opening_cash'], b['opening_cash']), (3, F(3, 20)))
        self.assertEqual((a['funded'], b['funded']), (20, F(63, 20)))

    def test_retention_changes_next_spending_not_just_bank_survival(self):
        initial = l.initial_depth_reference()
        targets = (0, 100)
        legacy = self.paid(self.paid(initial, mode='fixed', targets=targets),
                           mode='fixed', targets=targets)
        self.assertEqual((legacy.last.services, legacy.wip_units, legacy.last.real_output),
                         (F(49, 10), F(972972, 10**6), F(248499982, 10**7)))
        first = self.paid(initial, targets=targets)
        self.assertEqual(first.last.real_output, 25)
        self.assertEqual(first.deposit('HB'), F(1, 20))
        self.assertEqual(first.bank_equity('B'), initial.bank_equity('B') + F(1, 10))
        second = self.paid(first, targets=targets)
        # Yprev=Yhat=3.05, M=.05, theta=1/21, lambda=1/4:
        # HB planned services=3.05+(.05-3.05/21)/4=1271/420.
        desired_b = F(1271, 420)
        paid_b = (desired_b // l.QUANTUM) * l.QUANTUM
        services = F(37, 20) + paid_b
        investment = ((services - F(1, 10) - 3) / F(37, 20)
                      // l.QUANTUM) * l.QUANTUM
        self.assertEqual(second.last.services, services)
        self.assertEqual(second.wip_units, investment)
        self.assertEqual(second.last.real_output,
                         F(363, 20) + services + F(37, 20) * investment)
        self.assertLess(second.last.real_output, 25)
        self.assertEqual(second.loan_face, initial.loan_face)

    def test_unpaid_forecast_never_creates_current_purchasing_power(self):
        orders = replace(l.depth_orders(), market_clearing=True,
                         expected_dividends_nominal=(10**6, 10**6))
        state = self.paid(l.initial_depth_reference(), orders=orders)
        for note in (t for t in state.last.trace if t.kind == 'household_budget'):
            data = dict(note.details)
            self.assertGreater(data['desired'], data['funded'])
            self.assertEqual(data['funded'], data['opening_cash'] + data['paid_wages'])
        self.assertEqual(sum(state.deposit(a) for a in l.ACTORS), F(463, 20))
        self.assertEqual(state.loan_face, 10)

    def test_negative_coupon_payer_and_loss_not_fabricated_retention(self):
        state = l.initial_depth_reference()
        state = replace(state, loans=tuple(replace(z, rate_pct=-4) for z in state.loans))
        after = self.paid(state, targets=(100, 100))
        self.assertEqual(after.bank_equity('B'), state.bank_equity('B') - F(1, 10))
        self.assertEqual(after.last.bank_dividend_to('HB'), 0)
        self.assertEqual(after.last.dividend_focal, F(1, 4))
        self.assertEqual(after.loan_face, state.loan_face)
        self.assertEqual(after.last.private_interest, -F(1, 10))

    def test_nominal_scale_and_changed_price_do_not_rebase_old_claims(self):
        results = []
        for scale in (1, 10):
            initial = l.initial_depth_reference(scale=scale)
            loans = (l.LoanOffer('A', F(17, 5) * scale, 4, 8, borrower='R'),
                     l.LoanOffer('B', F(3, 5) * scale, 4, 8, borrower='F'))
            orders = replace(l.depth_orders(), market_clearing=True, price_factor=F(6, 5))
            state = self.paid(initial, orders=orders, loans=loans)
            self.assertEqual(next(z.face for z in state.loans if z.id == 'L0'), 10 * scale)
            for note in (t for t in state.last.trace if t.kind == 'household_budget'):
                data = dict(note.details)
                self.assertLessEqual(data['funded'], data['opening_cash'] + data['paid_wages'])
            results.append(state)
        small, large = results
        self.assertEqual((small.last.real_output, small.last.services, small.wip_units),
                         (large.last.real_output, large.last.services, large.wip_units))
        self.assertEqual([small.deposit(a) * 10 for a in l.ACTORS],
                         [large.deposit(a) for a in l.ACTORS])
        self.assertEqual([small.bank_equity(b) * 10 for b in l.BANKS],
                         [large.bank_equity(b) for b in l.BANKS])

    def test_unfunded_mandatory_maturity_refuses_whole_attempt(self):
        state = l.originate(l.initial_depth_reference(),
                            l.LoanOffer('A', 30, 4, 1, borrower='R'))
        state = replace(state, banks=(replace(state.banks[0], deposits=(17, 33)),
                                      state.banks[1]))
        result = self.advance(state)
        self.assertFalse(result.ok)
        self.assertEqual(result.status, 'credit_default')
        self.assertEqual(result.state, state)

    def test_requires_explicit_clearing_and_old_macro_rejects_new_mode(self):
        state = l.initial_depth_reference()
        with self.assertRaises(ValueError):
            self.advance(state, orders=l.depth_orders())
        envelope = m.initial(growth=0)
        prepared = m.prepare(envelope, m.Policy(3.5, 3.5))
        controls = replace(m.stationary_controls(envelope, prepared), household_mode=MODE)
        with self.assertRaises(NotImplementedError):
            m.execute(prepared, controls)


if __name__ == '__main__':
    unittest.main()
