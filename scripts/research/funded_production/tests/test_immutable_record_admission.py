"""Pure closed-tree admission checks; no ledger or forecast executions."""
from dataclasses import dataclass
from fractions import Fraction as F
import unittest
from scripts.research.funded_production import public_funding as f, checkpoint as k
from scripts.research.funded_production.tests.test_public_canonical_shapes import root


@dataclass(frozen=True)
class Leaf:
    value: object


class ImmutableAdmissionTests(unittest.TestCase):
    def test_shared_subtrees_are_valid_but_cycles_are_not(self):
        leaf=Leaf(F(1,2))
        f.validate_records((leaf,leaf), (Leaf,))
        object.__setattr__(leaf,'value',leaf)
        with self.assertRaises(ValueError):f.validate_records(leaf,(Leaf,))

    def test_class_identity_not_metaclass_equality_or_hash(self):
        calls=[]
        class Meta(type):
            def __eq__(self,other):calls.append('equality');return True
            def __hash__(self):calls.append('hash');return 0
        class Proxy(metaclass=Meta):pass
        for operation in (lambda:f.validate_records(Proxy(),tuple(k._TAGS)),
                          lambda:k._pack(Proxy())):
            with self.assertRaises((TypeError,ValueError)):operation()
        self.assertEqual(calls,[])

    def test_unknown_attributes_and_noncanonical_fraction_are_rejected(self):
        leaf=Leaf(F(1,2));object.__setattr__(leaf,'__dataclass_fields__',{})
        with self.assertRaises((TypeError,ValueError)):f.validate_records(leaf,(Leaf,))
        bad=F(1,2);object.__setattr__(bad,'_denominator',0)
        with self.assertRaises((TypeError,ValueError)):f.validate_records(Leaf(bad),(Leaf,))
        with self.assertRaises((TypeError,ValueError)):k._pack(bad)

    def test_candidate_constructor_rejects_hidden_version_before_replace(self):
        value=root();object.__setattr__(value,'version',2)
        schema=dict(type(value).__dataclass_fields__);schema.pop('version')
        object.__setattr__(value,'__dataclass_fields__',schema)
        with self.assertRaises((TypeError,ValueError)):k.CandidateState(value)

    def test_normal_checkpoint_pack_is_unchanged(self):
        value=k.CandidateState(root())
        a=k._pack(value)
        self.assertEqual(a,k._pack_checked(value))
        restored=k.decode_checkpoint(k.encode_checkpoint(value))
        self.assertEqual(restored,value)


if __name__=='__main__':unittest.main()
