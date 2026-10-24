"""Hand cases for the shared existing principal-allocation convention."""
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import numerics


class PoolDistributionTests(unittest.TestCase):
    def test_ties_keep_lower_index_priority(self):
        self.assertEqual(numerics.distribute(F(3), (F(1), F(1)), F(1)),
                         (F(2), F(1)))

    def test_larger_remainder_not_larger_weight_wins(self):
        self.assertEqual(numerics.distribute(F(4), (F(2), F(3)), F(1)),
                         (F(2), F(2)))

    def test_inherited_dust_is_not_destroyed(self):
        self.assertEqual(numerics.distribute(F(7, 2), (F(1), F(1)), F(1)),
                         (F(5, 2), F(1)))

    def test_zero_and_single_weight_preserve_face(self):
        self.assertEqual(numerics.distribute(F(0), (F(1), F(2)), F(1, 100)),
                         (F(0), F(0)))
        self.assertEqual(numerics.distribute(F(1, 3), (F(0), F(7)), F(1, 100)),
                         (F(0), F(1, 3)))

    def test_grid_and_off_grid_face_conserved_across_pool_shapes(self):
        for quantum in (F(1), F(1, 100), F(7, 3000000)):
            for face in (F(0), quantum/3, 3*quantum, 25*quantum/7):
                for weights in ((F(1),), (F(0), F(1)),
                                (F(1), F(1)), (F(1), F(2), F(3))):
                    with self.subTest(quantum=quantum, face=face, weights=weights):
                        result = numerics.distribute(face, weights, quantum)
                        self.assertEqual(sum(result), face)
                        self.assertTrue(all(value >= 0 for value in result))


if __name__ == '__main__':
    unittest.main()
