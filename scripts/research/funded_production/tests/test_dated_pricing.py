"""Independent dated-valuation checks, not empirical curve calibration."""
from fractions import Fraction as F
from dataclasses import replace
import unittest

from scripts.research.funded_production import pricing as p, ledger as l


class DatedPricingTests(unittest.TestCase):
    def test_flat_project_curve_current_coupon_and_no_current_coupon(self):
        principal = (F(1, 16),) * 16
        curve = (1 + F(435, 100) / 400,) * 16
        future_only = p.par_coupon(principal, curve, coupon_at_issue=False)
        current = p.par_coupon(principal, curve, coupon_at_issue=True)
        self.assertEqual(future_only, F(435, 100))
        self.assertLess(abs(current - F('3.8652028185')), F(1, 10**10))
        self.assertEqual(p.loan_present_value(principal, current, curve, coupon_at_issue=True), 1)

    def test_opening_operating_loan_has_two_future_dates(self):
        curve = (1 + F(385, 100) / 400,) * 2
        rate = p.par_coupon((0, 10), curve)
        self.assertEqual(rate, F(385, 100))
        self.assertEqual(p.loan_present_value((0, 10), rate, curve), 10)
        self.assertNotEqual(p.par_coupon((0, 10), curve, coupon_at_issue=True), rate)

    def test_signed_quotes_and_exact_par_identity_scale(self):
        for gross in (F(399, 400), F(1), F(401, 400)):
            for current in (False, True):
                with self.subTest(gross=gross, current=current):
                    principal = (F(1, 3), F(2, 3))
                    curve = (gross, gross)
                    rate = p.par_coupon(principal, curve, coupon_at_issue=current)
                    self.assertEqual(p.loan_present_value(principal, rate, curve,
                                                         coupon_at_issue=current), 1)
                    self.assertEqual(p.par_coupon(tuple(7*x for x in principal), curve,
                                                  coupon_at_issue=current), rate)
                    self.assertEqual(rate < 0, gross < 1)

    def test_curve_completion_uses_nearest_rational_root_and_reports_residual(self):
        short, long = F(385, 100), F(435, 100)
        curve = p.policy_curve(short, long)
        self.assertIs(type(curve), tuple)
        self.assertEqual((len(curve), curve[0]), (16, 1 + short / 400))
        self.assertEqual(len(set(curve[1:])), 1)
        target = (1 + long / 400) ** 16 / curve[0]
        half_grid = F(1, 2 * 10**18)
        self.assertLessEqual((curve[1] - half_grid)**15, target)
        self.assertGreaterEqual((curve[1] + half_grid)**15, target)
        product = F(1)
        for gross in curve:
            product *= gross
        self.assertEqual(p.curve_anchor_residual(curve, long), product - (1 + long / 400)**16)
        self.assertNotEqual(p.curve_anchor_residual(curve, long), 0)
        self.assertEqual(p.policy_curve(4, 4), (F(101, 100),) * 16)

    def test_extreme_positive_curve_preserves_anchor_instead_of_grid_amplification(self):
        grid = 10**18
        # On a fixed absolute grid the positive true root is exactly half a tick;
        # rounding up would turn the requested compound1 into32768.
        short = 400 * ((2 * grid)**15 - 1)
        curve = p.policy_curve(short, 0)
        self.assertTrue(all(x > 0 for x in curve))
        self.assertLessEqual(abs(p.curve_anchor_residual(curve, 0)),
                             (1 + F(1, 2**60))**15 - 1)

    def test_current_target_and_path_quotes_do_not_collapse_to_one_scalar(self):
        first = p.policy_curve(F(385, 100), F(435, 100))
        other = p.policy_curve(F(334, 100), F(435, 100))
        operating = p.operating_offer('A', 1, 1, 'R', first)
        operating_other = p.operating_offer('A', 1, 1, 'R', other)
        project = p.project_commitment('B', 2, first)
        project_other = p.project_commitment('B', 2, other)
        self.assertLess(operating_other.rate_pct, operating.rate_pct)
        self.assertGreater(project_other.rate_pct, project.rate_pct)
        self.assertIs(type(operating), l.OperatingLoanOffer)
        self.assertEqual((operating.maturity, operating.borrower), (2, 'R'))
        # Project draws at closing: skip the opening-to-current-closing interval.
        self.assertEqual(p.project_forward_gross(first), (first[1],) * 16)
        self.assertEqual(p.loan_present_value((F(1, 16),) * 16, project.rate_pct,
                         p.project_forward_gross(first), coupon_at_issue=True), 1)

    def test_settled_coupon_residual_is_reported_not_added_to_cash(self):
        principal = (F(185, 100) / 16,) * 16
        rate = F(435, 100)
        curve = (1 + rate / 400,) * 16
        actual = p.settled_loan_present_value(principal, rate, curve,
                                             coupon_at_issue=True)
        # Independent per-claim truncation, not aggregate-coupon rounding.
        per_claim = F(1257, 10**6)
        expected = 16 * per_claim
        discount = F(1)
        for h, gross in enumerate(curve):
            discount /= gross
            expected += (principal[h] + (16-h)*per_claim) * discount
        self.assertEqual(actual, expected)
        theoretical = p.loan_present_value(principal, rate, curve, coupon_at_issue=True)
        self.assertLess(actual, theoretical)
        bound = 16 * l.QUANTUM
        discount = F(1)
        for h, gross in enumerate(curve):
            discount /= gross
            bound += (16-h) * l.QUANTUM * discount
        self.assertLess(theoretical - actual, bound)

    def test_factories_execute_actual_contracts_without_changing_legacy_pricing(self):
        initial = l.initial_depth_reference()
        curve = p.policy_curve(F(385, 100), F(435, 100))
        b = initial.public_book
        rolls = (b.treasuries[0], b.private_treasuries[0][0], b.private_treasuries[1][0])
        controls = l.Controls(household_mode='cash_stock_close_v1', facility_limits=(100, 100),
            public_instructions=l.PublicInstructions(treasury_rolls=rolls, treasury_issue_authorization=sum(rolls)),
            new_loans=(p.operating_offer('A', 1, 1, 'R', curve),),
            project_commitment=p.project_commitment('B', 2, curve))
        before = repr(initial)
        out = l.advance_given_orders(initial, replace(l.depth_orders(), market_clearing=True,
                                                      investment_units=2), controls)
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(repr(initial), before)
        self.assertTrue(any(isinstance(z, l.ProjectLoan) for z in out.state.loans))
        self.assertTrue(all(z.rate_pct == controls.project_commitment.rate_pct
                            for z in out.state.loans if isinstance(z, l.ProjectLoan)))
        self.assertEqual(next(z.rate_pct for z in out.state.loans if z.id == 'L0'), 4)

    def test_invalid_vectors_flags_and_nonpositive_discounts_rejected(self):
        for principal, curve in (((), ()), ((0,), (1,)), ((1,), (0,)),
                                 ((1, -1), (1, 1)), ((1,), (True,)), ((1,), (float('nan'),)),
                                 ((1, 2), (1,))):
            with self.subTest(principal=principal, curve=curve):
                with self.assertRaises((TypeError, ValueError)):
                    p.par_coupon(principal, curve)
        with self.assertRaises(TypeError):
            p.par_coupon((1,), (1,), coupon_at_issue=1)
        for short, long in ((-400, 0), (0, -400), (True, 1), (0, float('inf'))):
            with self.assertRaises((TypeError, ValueError)):
                p.policy_curve(short, long)
    def test_tiny_positive_root_remains_positive_with_bounded_relative_anchor_error(self):
        anchor_rate = -400 + F(1, 10**100)
        curve = p.policy_curve(0, anchor_rate)
        self.assertTrue(all(x > 0 for x in curve))
        target = (1 + anchor_rate / 400)**16
        self.assertLessEqual(abs(p.curve_anchor_residual(curve, anchor_rate)) / target,
                             (1 + F(1, 2**60))**15 - 1)


if __name__ == '__main__':
    unittest.main()
