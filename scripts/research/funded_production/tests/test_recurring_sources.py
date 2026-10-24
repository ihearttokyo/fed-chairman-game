"""Source custody for opt-in recurring forecasts, not planner adoption."""
from pathlib import Path
import hashlib
import unittest
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k
class RecurringSourceTests(unittest.TestCase):
 def test_module_is_in_closed_source_fingerprint_set(self):
  path=Path(k.__file__).with_name('public_recurring_branches.py')
  self.assertEqual(k._SOURCES['public_recurring_branches'],hashlib.sha256(path.read_bytes()).hexdigest())
 def test_source_drift_rejected_without_a_forecast(self):
  with patch.object(k.source_data,'check_sources',side_effect=ValueError('source drift')):
   with self.assertRaisesRegex(ValueError,'source drift'):k._check_sources()

 def test_new_forecast_source_drift_refuses_before_execution(self):
  from fractions import Fraction as F
  from scripts.research.funded_production import public_recurring_branches as q,ledger as l
  from scripts.research.funded_production.tests.test_paydate_bridge_sources import inputs
  root,descriptor,_=inputs()
  from scripts.research.funded_production import paydate_scenarios as sc
  cells=tuple(sc.ScenarioCell(sign,fulfilled,(descriptor,)*19)
              for sign in (-1,1) for fulfilled in (False,True))
  with patch.object(k,'_check_sources',side_effect=ValueError('source drift')),patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw:
   with self.assertRaisesRegex(ValueError,'source drift'):
    q.evaluate(root,cells,units=F(1,4),background_units=F(1),forward_gross=(F(1),)*18)
   self.assertEqual(raw.call_count,0)
 def test_recurring_quote_cannot_be_serialized_as_career_adoption(self):
  from fractions import Fraction as F
  from scripts.research.funded_production import public_recurring_branches as q,ledger as l,paydate_scenarios as sc
  from scripts.research.funded_production.tests.test_paydate_bridge_sources import inputs
  root,_,_=inputs()
  cells=tuple(sc.ScenarioCell(sign,fulfilled,(None,)*19)
              for sign in (-1,1) for fulfilled in (False,True))
  with patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw:
   quoted=q.evaluate(root,cells,units=F(1,4),background_units=F(1),forward_gross=(F(1),)*18)
   with self.assertRaises((TypeError,ValueError)):k.encode_checkpoint(quoted)
   self.assertEqual(raw.call_count,0)
if __name__=='__main__':unittest.main()
