"""Pure wallet-budget arithmetic; no paid wages or journal execution here."""
from fractions import Fraction as F
from dataclasses import FrozenInstanceError
from itertools import product
import unittest
from unittest.mock import patch

from scripts.research.funded_production import paydate_households as q
from scripts.research.funded_production import households as old
from scripts.research.funded_production import ledger as l


def quote(**changes):
    values = dict(opening_cash=F(3,20), paid_wages=3, settled_income=F(-3,10),
                  previous_income=F(63,20), forecast_income=F(27,10), cash_ratio=F(1,21))
    values.update(changes)
    return q.cash_stock_budget(**values)


class PaydateHouseholdsTests(unittest.TestCase):
    def setUp(self):
        guard = patch.object(l, 'advance_given_orders', side_effect=AssertionError('Pure quotation only.'))
        self.advance = guard.start()
        self.addCleanup(guard.stop)

    def tearDown(self):
        self.assertEqual(self.advance.call_count, 0)

    def test_paid_wages_can_fund_coupon_without_negative_owned_opening_cash(self):
        result = quote()
        self.assertEqual(result, old.CashStockBudget(F(741,280), F(57,20),
                                                    F(741,280), F(57,280)))
        with self.assertRaises(ValueError):
            old.net_cash_stock_budget(opening_cash=F(-3,20), paid_wages=3,
                previous_income=F(63,20), forecast_income=F(27,10), cash_ratio=F(1,21))

    def test_intended_income_cannot_fund_unpaid_wage_shortage(self):
        with self.assertRaises(ValueError):
            quote(paid_wages=0, forecast_income=1000)

    def test_forecast_is_neither_cash_nor_credited_twice(self):
        result = quote(forecast_income=1000)
        self.assertEqual((result.wallet, result.funded, result.unspent_wallet),
                         (F(57,20), F(57,20), 0))
        # Settled income affects the wallet once; forecast already includes it.
        result = quote(opening_cash=1, paid_wages=2, settled_income=3,
                       previous_income=0, forecast_income=0, cash_ratio=0, adjustment=0)
        self.assertEqual((result.wallet, result.desired, result.funded), (6, 0, 0))

    def test_exact_parity_with_old_rule_when_adjustment_cash_nonnegative(self):
        for cash, wages, income, prior, forecast in product(
                (F(0), F(3,20), F(3)), (F(0), F(3)),
                (F(-1,10), F(0), F(1,10)), (F(-2), F(0), F(4)),
                (F(-3), F(0), F(5))):
            if cash + income < 0:
                continue
            result = quote(opening_cash=cash, paid_wages=wages, settled_income=income,
                           previous_income=prior, forecast_income=forecast)
            expected = old.net_cash_stock_budget(opening_cash=cash+income, paid_wages=wages,
                previous_income=prior, forecast_income=forecast, cash_ratio=F(1,21))
            self.assertEqual(result, expected)

    def test_signed_income_zero_wallet_and_nonnegative_targets(self):
        result = quote(opening_cash=0, paid_wages=1, settled_income=-1,
                       previous_income=-5, forecast_income=-2)
        self.assertEqual(result, old.CashStockBudget(0,0,0,0))
        result = quote(opening_cash=0, paid_wages=0, settled_income=2,
                       previous_income=-5, forecast_income=-2)
        self.assertGreaterEqual(result.desired, 0)
        self.assertEqual(result.wallet, 2)

    def test_impulse_changes_desire_not_owned_wallet(self):
        for impulse in (F(0), F(1), F(5)):
            result = quote(demand_multiplier=impulse)
            self.assertEqual(result.wallet, F(57,20))
            self.assertEqual(result.desired, impulse*F(741,280))
            self.assertEqual(result.funded, min(result.wallet,result.desired))
            self.assertEqual(result.unspent_wallet, result.wallet-result.funded)

    def test_nonnegative_inputs_and_adjustment_range(self):
        for field in ('opening_cash','paid_wages','cash_ratio','adjustment','demand_multiplier'):
            with self.subTest(field=field), self.assertRaises(ValueError):
                quote(**{field:-1})
        with self.assertRaises(ValueError):
            quote(adjustment=F(1001,1000))
        quote(adjustment=0); quote(adjustment=1)

    def test_invalid_numeric_proxies_rejected_before_callbacks(self):
        calls = []
        class Meta(type):
            def __eq__(self, other): calls.append('metaclass equality'); return True
        class Proxy(metaclass=Meta):
            def __float__(self): calls.append('float'); return 1.0
        class IntProxy(int):
            def __eq__(self, other): calls.append('integer equality'); return True
        forged = F(1,2)
        object.__setattr__(forged,'_denominator',0)
        for value in (True, Proxy(), IntProxy(1), forged, float('nan'), float('inf')):
            for field in ('opening_cash','paid_wages','settled_income','previous_income',
                          'forecast_income','cash_ratio','adjustment','demand_multiplier'):
                with self.subTest(field=field,value=type(value).__name__), self.assertRaises((TypeError,ValueError)):
                    quote(**{field:value})
        self.assertEqual(calls, [])

    def test_scale_covariance_and_immutable_output(self):
        baseline = quote()
        for scale in (F(1,1000), F(1), F(1000)):
            result = quote(opening_cash=F(3,20)*scale, paid_wages=3*scale,
                settled_income=F(-3,10)*scale, previous_income=F(63,20)*scale,
                forecast_income=F(27,10)*scale)
            self.assertEqual(result, old.CashStockBudget(*(x*scale for x in (
                baseline.desired, baseline.wallet, baseline.funded, baseline.unspent_wallet))))
            with self.assertRaises(FrozenInstanceError):
                result.wallet = 0


if __name__ == '__main__':
    unittest.main()
