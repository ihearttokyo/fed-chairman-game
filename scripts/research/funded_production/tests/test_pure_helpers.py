import unittest
from fractions import Fraction as F
from scripts.research.funded_production import numerics as n, households as h, pricing as p
class PureHelpersTests(unittest.TestCase):
 def test_exact_ration_and_signed_coupon(self):
  self.assertEqual(n.ration(F(1),F(1),F(1)),(F(1,2),F(1,2)))
  self.assertEqual(n.coupon(F(3,100),F(1,3),F(1))[1],F(25,10**6))
  self.assertEqual(n.coupon(F(3,100),F(-1,3),F(1))[1],F(-25,10**6))
 def test_forecast_not_cash(self):
  z=h.allocate(F(1),F(100),h.Preferences(19,1,3))
  self.assertEqual(z.residual+z.services+z.saving,1)
  self.assertLessEqual(z.residual+z.services,1)
 def test_exact_forward_curve(self):
  self.assertEqual(p.price_cashflows((F(1),F(1)),(F(1),F(2))),F(3,2))
  with self.assertRaises((ValueError,TypeError)):p.price_cashflows((F(1),),(F(0),))
if __name__=='__main__':unittest.main()
