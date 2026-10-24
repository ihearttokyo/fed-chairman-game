import unittest
from fractions import Fraction as F
from scripts.research.funded_production import numerics, households, pricing, ledger, macro, episodes, choice, checkpoint


class PortableReferenceTests(unittest.TestCase):
    def test_largest_remainder_and_signed_contractual_coupon(self):
        self.assertEqual(numerics.ration(F(1), F(1), F(1)), (F(1, 2), F(1, 2)))
        self.assertEqual(numerics.coupon(F(3, 100), F(1, 3), F(1))[1], F(25, 10**6))
        self.assertEqual(numerics.coupon(F(3, 100), F(-1, 3), F(1))[1], F(-25, 10**6))

    def test_preferences_forecast_is_not_owned_cash(self):
        z = households.allocate(F(1), F(100), households.Preferences(19, 1, 3))
        self.assertEqual(z.residual + z.services + z.saving, 1)
        self.assertLessEqual(z.residual + z.services, 1)

    def test_every_forward_discount_factor_matters(self):
        self.assertEqual(pricing.price_cashflows((F(1), F(1)), (F(1), F(2))), F(3, 2))

    def test_funded_macro_actor_and_exact_saved_program(self):
        a = checkpoint.initial(growth=0)
        out = checkpoint.adopt(a, macro.Policy(3.5, 3.5), additional_units=F(1, 4))
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(len(out.state.blocked_rollover_ids), 16)
        restored = checkpoint.decode_checkpoint(checkpoint.encode_checkpoint(out.state))
        self.assertEqual(restored, out.state)
        next_ = checkpoint.adopt(restored, macro.Policy(3.5, 3.5))
        self.assertTrue(next_.ok, next_.reason)
        self.assertEqual(len(next_.state.blocked_rollover_ids), 15)

    def test_complete_source_staff_family(self):
        p = episodes.PolicyRule('staff').resolve(macro.initial(growth=0))
        self.assertEqual(p, macro.Policy(3.5, 3.5, 1.5, .5))


if __name__ == '__main__':
    unittest.main()
