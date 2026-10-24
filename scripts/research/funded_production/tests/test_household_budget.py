"""Independent cash-stock oracles; no paid executor or future state access."""
import unittest
from fractions import Fraction as F

from scripts.research.funded_production import households as h


class HouseholdBudgetTests(unittest.TestCase):
    def quote(self, **changes):
        inputs = dict(opening_cash=3, paid_wages=F(1717, 100),
                      previous_income=20, forecast_income=F(202, 10),
                      cash_ratio=F(3, 20), adjustment=F(1, 4))
        inputs.update(changes)
        return h.cash_stock_budget(**inputs)

    def test_one_percent_growth_two_owners(self):
        a = self.quote()
        b = self.quote(opening_cash=F(15, 100), paid_wages=F(303, 100),
                       previous_income=F(315, 100),
                       forecast_income=F(31815, 10000), cash_ratio=F(1, 21))
        self.assertEqual((a.desired, a.funded), (F(2017, 100),) * 2)
        self.assertEqual((b.desired, b.funded), (F(318, 100),) * 2)
        closing = a.wallet - a.funded + F(303, 100)
        closing_b = b.wallet - b.funded + F(1515, 10000)
        self.assertEqual((closing, closing_b), (F(303, 100), F(1515, 10000)))
        self.assertEqual(closing + closing_b - F(315, 100), F(315, 10000))

    def test_forecast_dividend_is_not_cash(self):
        z = self.quote(opening_cash=0, paid_wages=1, forecast_income=100)
        self.assertGreater(z.desired, z.wallet)
        self.assertEqual((z.wallet, z.funded), (F(1), F(1)))
        self.assertEqual(z.unspent_wallet, 0)

    def test_forecast_error_not_credited(self):
        z = self.quote()
        actual_dividend = F(302, 100)  # forecast was3.03; no missing cent grant
        closing = z.wallet - z.funded + actual_dividend
        actual_income = F(1717, 100) + actual_dividend
        # Forecast error changes both actual income target and actual cash.
        self.assertEqual(closing, F(302, 100))
        self.assertEqual(closing - F(3, 20) * actual_income, -F(17, 2000))

    def test_target_error_contraction_if_funded_and_fulfilled(self):
        for previous, forecast, cash, ratio, speed in (
            (20, 20, 4, F(3, 20), F(1, 4)),
            (20, 22, 3, F(3, 20), F(1)),
            (20, 18, 2, F(1, 10), F(0)),
            (0, 2, 1, F(0), F(1, 2)),
        ):
            with self.subTest(previous=previous, speed=speed):
                z = self.quote(opening_cash=cash, paid_wages=forecast,
                               previous_income=previous, forecast_income=forecast,
                               cash_ratio=ratio, adjustment=speed)
                self.assertEqual(z.desired, z.funded)
                self.assertEqual(z.wallet - z.funded - ratio * forecast,
                                 (1 - speed) * (cash - ratio * previous))

    def test_zero_floor_and_owned_unspent_cash(self):
        z = self.quote(opening_cash=1, paid_wages=0, previous_income=100,
                       forecast_income=0, cash_ratio=F(1, 2), adjustment=1)
        self.assertEqual(z.desired, 1)  # 0-(-50)+(1-50)=1
        z = self.quote(opening_cash=0, paid_wages=2, previous_income=100,
                       forecast_income=0, cash_ratio=1, adjustment=1)
        self.assertEqual((z.desired, z.funded, z.unspent_wallet), (0, 0, 2))
        # Strictly negative raw plan: 2-2*(2-0)+0=-2, floored to zero.
        z = self.quote(opening_cash=1, paid_wages=1, previous_income=0,
                       forecast_income=2, cash_ratio=2, adjustment=0)
        self.assertEqual((z.desired, z.funded, z.unspent_wallet), (0, 0, 2))

    def test_unfilled_purchases_leave_more_cash_than_budget_residual(self):
        z = self.quote()
        purchases = z.funded - F(1, 10)
        self.assertEqual(z.wallet - purchases, z.unspent_wallet + F(1, 10))
        self.assertEqual(z.wallet, purchases + (z.wallet - purchases))

    def test_invalid_inputs_fail_before_quote(self):
        for key in ('opening_cash', 'paid_wages', 'previous_income',
                    'forecast_income', 'cash_ratio', 'adjustment'):
            for bad in (True, '1', None, float('nan'), float('inf'), -1):
                with self.subTest(key=key, bad=bad):
                    with self.assertRaises((TypeError, ValueError)):
                        self.quote(**{key: bad})
        with self.assertRaises(ValueError):
            self.quote(adjustment=F(1001, 1000))

    def test_float_inputs_use_existing_decimal_boundary(self):
        self.assertEqual(self.quote(opening_cash=0.1).wallet, F(1727, 100))

    def test_legacy_allocation_unchanged(self):
        self.assertEqual(h.allocate(1, 100, h.Preferences(19, 1, 3)),
                         h.Allocation(F(19, 20), F(1, 20), F(0)))


if __name__ == '__main__':
    unittest.main()
