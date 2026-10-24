"""Observation groups describe visible commands, not latent scenario labels."""
import unittest
from scripts.research.funded_production import investment as i,macro as m


class InvestmentObservabilityTests(unittest.TestCase):
    def test_equal_observed_commands_merge_fulfilled_and_fallback_branches(self):
        f=i.forecast(m.initial(growth=0),m.Policy(3.5,3.5))
        self.assertEqual(f.fulfilled_policy,f.fallback_policy)
        self.assertEqual(len({z.observable_node for z in f.cells}),2)
        for sign in (-1,1):
            same_signal=[z for z in f.cells if z.demand_sign==sign]
            self.assertEqual(same_signal[0].observable_node,same_signal[1].observable_node)

    def test_distinct_public_commands_remain_distinguishable(self):
        f=i.forecast(m.initial(growth=0),m.Policy(3.5,2))
        self.assertNotEqual(f.fulfilled_policy,f.fallback_policy)
        self.assertEqual(len({z.observable_node for z in f.cells}),4)


if __name__=='__main__':unittest.main()
