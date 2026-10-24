import unittest,json
from fractions import Fraction as F
from dataclasses import replace
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k
m=k.m
class CheckpointTests(unittest.TestCase):
 def project(self):
  a=k.initial(growth=0);z=k.adopt(a,m.Policy(3.5,3.5),additional_units=F(1,4));self.assertTrue(z.ok,z.reason);return a,z
 def test_initial_and_post_project_exact_roundtrip(self):
  a,z=self.project()
  for s in (a,z.state):
   text=k.encode_checkpoint(s);t=k.decode_checkpoint(text)
   self.assertEqual(s,t);self.assertEqual(k.state_digest(s),k.state_digest(t));self.assertEqual(text,k.encode_checkpoint(t))
 def test_event_roundtrip_and_exact_replay_single_call(self):
  a,z=self.project();event=k.decode_event(k.encode_event(z.event))
  with patch.object(m,'execute',wraps=m.execute) as run:
   replay=k.replay(a,event);self.assertEqual(run.call_count,1)
  self.assertTrue(replay.ok);self.assertEqual(z.state,replay.state);self.assertEqual(z.event,replay.event)
 def test_restored_project_principal_not_refinanced(self):
  _,z=self.project();a=k.decode_checkpoint(k.encode_checkpoint(z.state));old=set(a.blocked_rollover_ids)
  b=k.adopt(a,m.Policy(3.5,3.5));self.assertTrue(b.ok,b.reason)
  self.assertGreater(b.state.project_paid,0);self.assertEqual(len(b.state.blocked_rollover_ids),15)
  self.assertTrue(all(r.loan_id not in old for r in b.event.controls.renewals))
 def test_failure_or_tamper_does_not_change_predecessor(self):
  a,z=self.project();before=repr(a)
  bad=replace(z.event,before_digest='0'*64)
  with patch.object(m,'execute',wraps=m.execute) as run:
   with self.assertRaises(ValueError):k.replay(a,bad)
   self.assertEqual(run.call_count,0)
  self.assertEqual(repr(a),before)
 def test_tampered_controls_rejected_before_execution(self):
  a,z=self.project();bad=replace(z.event,controls=replace(z.event.controls,facility_limits=(F(0),F(0))))
  with patch.object(m,'execute',wraps=m.execute) as run:
   with self.assertRaises(ValueError):k.replay(a,bad)
   self.assertEqual(run.call_count,0)
 def test_unknown_schema_class_duplicate_or_nonfinite_rejected(self):
  a=k.initial(growth=0);text=k.encode_checkpoint(a)
  for bad in ('{"schema":1,"schema":2}','NaN','{"$type":"os.system","fields":{}}',text.replace('"schema"','"unexpected_schema"',1)):
   with self.assertRaises((ValueError,TypeError)):k.decode_checkpoint(bad)
 def test_unknown_project_identity_and_flow_mismatch_rejected(self):
  a=k.initial(growth=0)
  with self.assertRaises((ValueError,TypeError)):replace(a,blocked_rollover_ids=('unknown',))
  with self.assertRaises((ValueError,TypeError)):replace(a,project_origin=F(1))
 def test_quarter_paid_GDP_not_independent_mutable_book(self):
  _,z=self.project();bad=replace(z.state.economy,macro=replace(z.state.economy.macro,actual_output_index=999))
  with self.assertRaises(ValueError):replace(z.state,economy=bad)
 def test_existing_actual_project_program_can_finish_after_restore(self):
  _,z=self.project();a=k.decode_checkpoint(k.encode_checkpoint(z.state))
  for _ in range(17):
   out=k.adopt(a,m.Policy(3.5,3.5));self.assertTrue(out.ok,out.reason);a=out.state
  self.assertEqual(a.blocked_rollover_ids,());self.assertEqual(a.project_origin,a.project_paid)
if __name__=='__main__':unittest.main()
