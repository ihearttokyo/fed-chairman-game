"""Current paid-observation guard; no synthesized history or q0 seed reuse."""
from dataclasses import replace
import unittest
from scripts.research.funded_production import coupled as c, macro as m
from scripts.research.funded_production.tests.test_coupled_quarter import opening


class CoupledObservationTests(unittest.TestCase):
    def paid(self):
        p=c.prepare(opening(),m.Policy(3.5,3.5),project_units=1)
        out=c.execute(p,c.controls(p))
        self.assertTrue(out.ok,out.reason)
        return out.envelope

    def test_nonzero_quarter_requires_actual_report_not_initial_income_seeds(self):
        a=opening()
        missing=replace(a,macro=replace(a.macro,quarter=1),sector=replace(a.sector,quarter=1))
        with self.assertRaises(ValueError):c.prepare(missing,m.Policy(3.5,3.5))

    def test_opening_gdp_must_match_current_paid_report(self):
        a=self.paid();bad=replace(a,macro=replace(a.macro,actual_output_index=101))
        with self.assertRaises(ValueError):c.prepare(bad,m.Policy(3.5,3.5))

    def test_opening_employment_must_match_current_paid_report(self):
        a=self.paid();bad=replace(a,macro=replace(a.macro,unemployment_rate_pct=10))
        with self.assertRaises(ValueError):c.prepare(bad,m.Policy(3.5,3.5))

    def test_opening_prices_cannot_revalue_the_actual_paid_invoices(self):
        a=self.paid()
        bad=replace(a,macro=replace(a.macro,price_index=101,
                                  price_history=(*a.macro.price_history[:-1],101)))
        with self.assertRaises(ValueError):c.prepare(bad,m.Policy(3.5,3.5))

    def test_opening_productivity_quote_cannot_revalue_actual_paid_wages(self):
        a=self.paid();bad=replace(a,macro=replace(a.macro,productivity_trend=1.01))
        with self.assertRaises(ValueError):c.prepare(bad,m.Policy(3.5,3.5))


if __name__=='__main__':unittest.main()
