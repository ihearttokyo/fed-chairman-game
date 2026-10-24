"""Paid income must reconcile to identified actual payout records."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from scripts.research.funded_production import coupled as c, macro as m, checkpoint as k
from scripts.research.funded_production.tests.test_coupled_quarter import opening


class DividendObservationTests(unittest.TestCase):
    def setUp(self):
        p=c.prepare(opening(),m.Policy(3.5,3.5),project_units=1)
        out=c.execute(p,c.controls(p));self.assertTrue(out.ok,out.reason)
        self.a=out.envelope

    def reject(self,report):
        bad=replace(self.a,sector=replace(self.a.sector,last=report))
        with self.assertRaises(ValueError):k._paid_economy(bad)
        with self.assertRaises(ValueError):c.prepare(bad,m.Policy(3.5,3.5))

    def test_dividend_fields_match_actual_firm_and_bank_payouts(self):
        for field in ('dividend_residual','dividend_focal','dividend_bank'):
            with self.subTest(field=field):
                self.assertGreater(getattr(self.a.sector.last,field),0)
                self.reject(replace(self.a.sector.last,**{field:F(0)}))

    def test_identified_firm_and_bank_dividend_routes_cannot_be_swapped(self):
        for kind in ('residual_dividend','focal_dividend','bank_dividend'):
            with self.subTest(kind=kind):
                report=self.a.sector.last
                target=next(z for z in report.payments if z.kind==kind)
                wrong=replace(target,payee='HA' if target.payee=='HB' else 'HB')
                payments=tuple(wrong if z is target else z for z in report.payments)
                self.reject(replace(report,payments=payments))

    def test_report_fields_cannot_hide_a_different_actual_payout_amount(self):
        for kind in ('residual_dividend','focal_dividend','bank_dividend'):
            with self.subTest(kind=kind):
                report=self.a.sector.last
                target=next(z for z in report.payments if z.kind==kind)
                wrong=replace(target,amount=target.amount/2)
                payments=tuple(wrong if z is target else z for z in report.payments)
                self.reject(replace(report,payments=payments))


if __name__=='__main__':unittest.main()
