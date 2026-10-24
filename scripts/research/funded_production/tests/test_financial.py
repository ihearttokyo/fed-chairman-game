import unittest
from fractions import Fraction as F
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k
m=k.m
class FinancialTests(unittest.TestCase):
 def test_real_late_origination_refusal_preserves_actor_and_no_event(self):
  a=k.initial(growth=0);before=k.encode_checkpoint(a)
  with patch.object(m,'execute',wraps=m.execute) as run:
   z=k.adopt(a,m.Policy(3.5,3.5),additional_units=100)
   self.assertEqual(run.call_count,1)
  self.assertFalse(z.ok);self.assertEqual(z.state,a);self.assertIsNone(z.event)
  self.assertEqual(k.encode_checkpoint(z.state),before)
 def test_signed_fractional_coupon_and_scaled_program_roundtrip(self):
  for scale in (F(1,100),F(7,3)):
   a=k.initial(growth=0,scale=scale)
   z=k.adopt(a,m.Policy(3.5,3.5),additional_units=F(1,4),project_rate_pct=F(-1,3))
   self.assertTrue(z.ok,z.reason)
   self.assertTrue(all(l.rate_pct==F(-1,3) for l in z.state.economy.sector.loans if l.id in z.state.blocked_rollover_ids))
   b=k.decode_checkpoint(k.encode_checkpoint(z.state));self.assertEqual(b,z.state)
   event=k.decode_event(k.encode_event(z.event));self.assertEqual(event,z.event)
   self.assertEqual(k.replay(a,event).state,b)
if __name__=='__main__':unittest.main()
