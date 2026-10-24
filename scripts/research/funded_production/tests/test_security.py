"""Adversarial file-format checks, not signatures/authentication claims."""
import unittest,json,hashlib
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k
class SecurityTests(unittest.TestCase):
 def root(self):return json.loads(k.encode_checkpoint(k.initial(growth=0)))
 def seal(self,r):
  body={a:b for a,b in r.items() if a!='digest'}
  r['digest']=hashlib.sha256(json.dumps(body,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('ascii')).hexdigest()
  return json.dumps(r)
 def test_unknown_class_rejected_even_with_valid_content_digest(self):
  r=self.root();r['payload']['$type']='os.system'
  with self.assertRaises(ValueError):k.decode_checkpoint(self.seal(r))
 def test_missing_project_policy_not_defaulted_to_empty(self):
  r=self.root();del r['payload']['fields']['blocked_rollover_ids']
  with self.assertRaises(ValueError):k.decode_checkpoint(self.seal(r))
 def test_changed_trusted_source_rejected_even_after_checksum_reseal(self):
  r=self.root();name=next(iter(r['sources']));r['sources'][name]='0'*64
  with self.assertRaises(ValueError):k.decode_checkpoint(self.seal(r))
 def test_scalar_type_not_silently_coerced(self):
  r=self.root();r['payload']['fields']['project_origin']=0
  with self.assertRaises(ValueError):k.decode_checkpoint(self.seal(r))
 def test_writer_does_not_emit_a_checkpoint_its_own_reader_rejects(self):
  a=k.initial(growth=0)
  # Deterministic parser-admission boundary injection, not a mocked economy.
  with patch.object(k,'_MAX_NODES',2):
   with self.assertRaises(ValueError):k.encode_checkpoint(a)
if __name__=='__main__':unittest.main()
