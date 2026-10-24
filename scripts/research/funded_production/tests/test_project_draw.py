"""Dated actual funding and resource delivery, not an endogenous growth pass."""
from dataclasses import replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import ledger as l, checkpoint as k


def fiscal(state):
    b = state.public_book
    r = (b.treasuries[0], b.private_treasuries[0][0], b.private_treasuries[1][0])
    return l.PublicInstructions(treasury_rolls=r, treasury_issue_authorization=sum(r))


class ProjectDrawTests(unittest.TestCase):
    def plan(self, ceiling=2, rate=4, lender='B'):
        return l.ProjectCommitment(lender, ceiling, rate)

    def advance(self, state=None, units=1, plan=True, loans=(), **changes):
        state = l.initial_depth_reference() if state is None else state
        orders = replace(l.depth_orders(), market_clearing=True, investment_units=units)
        inputs = dict(public_instructions=fiscal(state), household_mode='cash_stock_close_v1',
                      facility_limits=(100, 100), new_loans=loans,
                      project_commitment=self.plan() if plan is True else plan)
        inputs.update(changes)
        controls = l.Controls(**inputs)
        before = repr(state)
        out = l.advance_given_orders(state, orders, controls)
        self.assertEqual(repr(state), before)
        self.assertEqual(l.advance_given_orders(state, orders, controls), out)
        self.assertTrue(out.ok, out.reason)
        return out.state

    def projects(self, state):
        return [z for z in state.loans if isinstance(z, l.ProjectLoan)]

    def test_unused_reservation_creates_no_money_coupon_or_gdp(self):
        base = self.advance(units=0, plan=None)
        reserved = self.advance(units=0)
        self.assertEqual((reserved.banks, reserved.loans, reserved.last.payments),
                         (base.banks, base.loans, base.last.payments))
        self.assertEqual(reserved.last.real_output, base.last.real_output)
        self.assertEqual(reserved.wip_units, 0)
        self.assertTrue(any(t.kind == 'project_reservation' for t in reserved.last.trace))

    def test_internally_funded_full_invoice_has_zero_draw_and_whole_basis(self):
        state = self.advance(plan=self.plan(0))
        base = self.advance(plan=None)
        self.assertEqual((state.banks, state.loans), (base.banks, base.loans))
        self.assertEqual((state.wip_units, state.wip_basis, state.last.real_output), (1, F(37, 20), 25))
        self.assertEqual(self.projects(state), [])

    def test_mixed_draw_is_minimum_and_protected_dated_faces_sum_exactly(self):
        initial = l.initial_depth_reference()
        state = self.advance(initial, units=2)
        loans = self.projects(state)
        draw = sum((z.face for z in loans), F(0))
        self.assertEqual(draw, F(1818176, 10**6))
        self.assertEqual(sorted(z.maturity for z in loans), list(range(2, 18)))
        self.assertTrue(all(z.face == F(113636, 10**6) and z.last_coupon_paid == 1 for z in loans))
        ids = {z.id for z in loans}
        coupon = sum((p.amount for p in state.last.payments
                      if p.kind == 'private_coupon' and p.claim_id in ids), F(0))
        self.assertEqual(coupon, F(18176, 10**6))
        self.assertEqual((state.wip_units, state.wip_basis, state.last.investment), (2, F(37, 10), F(37, 10)))
        self.assertEqual(state.deposit('F'), 3)
        self.assertEqual(sum(state.deposit(a) - initial.deposit(a) for a in l.ACTORS), draw)
        self.assertEqual(state.last.real_output, 25)  # More I displaces paid consumption, not extra GDP.
        restored = k._unpack(k._pack(state), [k._MAX_NODES])
        self.assertEqual(restored, state)
        due = min(loans, key=lambda z: z.maturity)
        controls = l.Controls(public_instructions=fiscal(state), household_mode='cash_stock_close_v1',
                              renewals=(l.Renewal(due.id, due.face, 4, 3),))
        with self.assertRaises(ValueError):
            l.advance_given_orders(restored, replace(l.depth_orders(), market_clearing=True), controls)

    def test_tiny_draw_omits_zero_face_slots_without_losing_invoice_basis(self):
        state = self.advance(units=F(1027028, 10**6))
        loans = self.projects(state)
        self.assertEqual([(z.face, z.maturity) for z in loans], [(l.QUANTUM, 2), (l.QUANTUM, 3)])
        self.assertEqual(state.wip_basis, F(19000018, 10**7))
        self.assertGreater(state.wip_basis, sum(z.face for z in loans))

    def test_insufficient_resource_or_ceiling_cancels_without_partial_project(self):
        base = self.advance(units=0, plan=None)
        for units, plan in ((20, self.plan(50)), (2, self.plan(F(1, 2)))):
            with self.subTest(units=units):
                state = self.advance(units=units, plan=plan)
                self.assertEqual((state.banks, state.loans, state.next_private_id),
                                 (base.banks, base.loans, base.next_private_id))
                self.assertEqual((state.wip_units, state.wip_basis), (0, 0))
                self.assertEqual(state.last.payments, base.last.payments)
                reservation = next(t for t in state.last.trace if t.kind == 'project_reservation')
                self.assertTrue(dict(reservation.details)['approved'])

    def test_opening_aggregate_risk_cannot_use_later_coupon_income(self):
        initial = l.provision(l.initial_depth_reference(), 'L0', 8)
        state = self.advance(initial, units=2, plan=self.plan(1),
                             loans=(l.OperatingLoanOffer('B', 1, 4, 2),))
        note = next(t for t in state.last.trace if t.kind == 'project_reservation')
        self.assertEqual(note.amount, 0)
        self.assertFalse(dict(note.details)['approved'])
        self.assertEqual(state.wip_units, 0)
        self.assertEqual(self.projects(state), [])

    def test_current_signed_loss_can_invalidate_approved_draw_without_erasure(self):
        initial = l.provision(l.initial_depth_reference(), 'L0', F(79, 10))
        initial = replace(initial, loans=tuple(replace(z, rate_pct=-4) for z in initial.loans))
        state = self.advance(initial, units=2)
        reservation = next(t for t in state.last.trace if t.kind == 'project_reservation')
        self.assertTrue(dict(reservation.details)['approved'])
        self.assertEqual(self.projects(state), [])
        self.assertEqual(state.wip_units, 0)
        self.assertEqual(state.last.private_interest, -F(1, 10))
        self.assertEqual(state.bank_equity('B'), F(11, 10))
        self.assertEqual(state.next_private_id, initial.next_private_id)

    def test_stage_reserve_failure_discards_only_optional_project_effects(self):
        initial = l.initial_depth_reference()
        amount = initial.reserves('A')
        initial = l.settle_public(initial, l.PublicInstructions(
            treasury_subscriptions=(amount, 0), treasury_issue_authorization=amount))
        state = self.advance(initial, units=2, plan=self.plan(2, lender='A'),
                             facility_limits=(F(37, 20), 0), security_bids=(0, 0))
        base = self.advance(initial, units=0, plan=None,
                            facility_limits=(F(37, 20), 0), security_bids=(0, 0))
        self.assertEqual((state.banks, state.loans, state.cb_loans, state.next_private_id),
                         (base.banks, base.loans, base.cb_loans, base.next_private_id))
        self.assertEqual(state.last.payments, base.last.payments)
        self.assertEqual(state.wip_units, 0)
        self.assertEqual(state.last.cb_borrowed, F(37, 20))

    def test_minimum_draw_matches_independent_small_integer_enumeration(self):
        q = l.QUANTUM
        for rate in (-1000, -4, 0, 4, 399, 400, 500):
            for short in (F(1, 2), 2, 17):
                with self.subTest(rate=rate, short=short):
                    expected = None
                    for ticks in range(33):
                        whole, remainder = divmod(ticks, 16)
                        amounts = [whole + (i < remainder) for i in range(16)]
                        coupon = sum((-1 if rate < 0 else 1) * (F(a * abs(rate), 400) // 1)
                                     for a in amounts) * q
                        if ticks * q - coupon >= short * q:
                            expected = ticks * q
                            break
                    draw, probes = l._minimum_project_draw(0, short * q, 0, 32 * q, rate, 1)
                    self.assertEqual(draw, expected)
                    self.assertLessEqual(probes, (32).bit_length() + 1)

    def test_signed_project_coupon_has_real_bank_payer_and_high_quote_is_not_capped(self):
        state = self.advance(units=2, plan=self.plan(rate=-4))
        loans = self.projects(state)
        self.assertEqual(sum(z.face for z in loans), F(1782192, 10**6))
        ids = {z.id for z in loans}
        paid = [p for p in state.last.payments if p.kind == 'private_coupon' and p.claim_id in ids]
        self.assertTrue(all(p.payer == 'BankB' and p.payee == 'F' for p in paid))
        self.assertEqual(sum(p.amount for p in paid), F(17808, 10**6))
        self.assertEqual(state.last.private_interest, F(82192, 10**6))
        high = self.advance(units=2, plan=self.plan(rate=500))
        self.assertEqual((high.wip_units, self.projects(high)), (0, []))
        internal = self.advance(plan=self.plan(rate=500))
        self.assertEqual((internal.wip_units, self.projects(internal)), (1, []))

    def test_failed_stage_does_not_alias_any_live_journal_container(self):
        initial = l.initial_depth_reference()
        tx = l._Transaction(initial, l.Controls(facility_limits=(100, 100)), 1)
        before = repr(tx.__dict__)
        identities = {key: id(value) for key, value in tx.__dict__.items()}
        # Deliberately wrong draw: 3+1-.01-1=2.99, below the actual3 buffer.
        # The failure occurs after the cloned journal has originated, paid coupons
        # and delivered an invoice; none may escape into the live transaction.
        with self.assertRaisesRegex(ValueError, 'solver/delivery mismatch'):
            l._stage_project(tx, self.plan(), 1, 1, 3)
        self.assertEqual(repr(tx.__dict__), before)
        self.assertEqual({key: id(value) for key, value in tx.__dict__.items()}, identities)
        self.assertIs(tx.original, initial)

    def test_commitment_and_project_claim_admission(self):
        plan = self.plan()
        self.assertEqual(k._unpack(k._pack(plan), [k._MAX_NODES]), plan)
        with self.assertRaises(ValueError):
            l.Controls(project_commitment=plan)
        with self.assertRaises(TypeError):
            l.Controls(household_mode='cash_stock_close_v1', project_commitment=lambda: 1)
        for bad in (True, -1, float('nan')):
            with self.assertRaises((TypeError, ValueError)):
                self.plan(bad)
        with self.assertRaises(ValueError):
            l.ProjectLoan('bad', 'B', 1, 4, 1, 0, 0)


if __name__ == '__main__':
    unittest.main()
