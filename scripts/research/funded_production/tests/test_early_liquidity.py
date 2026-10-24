"""Conditional arithmetic only: no monetary executor, loan or cash approval."""
from dataclasses import replace
from fractions import Fraction as F
import ast
from pathlib import Path
import unittest

from scripts.research.funded_production import early_liquidity as e, public_income as income


def observations(cb=(0,1), rates=(0,4), reserves=(1,F(1,10**6)), iorb=0):
    zeros = (F(0),)*120
    terms = income.PublicIncomeTerms((zeros,)*3,iorb_rate_pct=iorb,cb_rates_pct=rates)
    return income.quote(terms,treasuries=(zeros,)*3,mortgages=(0,0),reserves=reserves,
                        cb_faces=cb,rrp_faces=(0,0),scale=1)


def plan(**changes):
    values=dict(scale=1,reserves=(1,F(1,10**6)),old_faces=(0,1),equities=(1,1),
                capacities=(8,8),facility_limits=(2,2),cb_rates_pct=(0,4),tga=1,
                observations=observations())
    values.update(changes)
    return e.plan(**values)


class EarlyLiquidityTests(unittest.TestCase):
    def test_full_novation_then_only_net_peak_coupon_advance(self):
        result=plan()
        self.assertEqual(result.refinanced,(0,1))
        self.assertEqual(result.cash_repayments,(0,0))
        self.assertEqual(result.advances,(0,F(9999,10**6)))
        self.assertEqual(result.gross_used,(0,F(1009999,10**6)))
        self.assertEqual(result.replacement_faces,result.gross_used)
        self.assertEqual(result.credit_reserves,(1,F(1,100)))
        self.assertEqual(result.coupon_reserves,(1,0))
        self.assertEqual(result.observations,observations())
        e.validate_plan(result)

    def test_partial_novation_residual_actual_cash_not_gross_cash_recirculation(self):
        result=plan(reserves=(1,F(3,5)),facility_limits=(0,F(1,2)))
        self.assertEqual(result.refinanced,(0,F(1,2)))
        self.assertEqual(result.cash_repayments,(0,F(1,2)))
        self.assertEqual(result.credit_reserves,(1,F(1,10)))
        self.assertEqual(result.advances,(0,0))
        self.assertEqual(result.coupon_reserves,(1,F(9,100)))

    def test_shared_gross_limit_collateral_equity_and_repayment_failures(self):
        for changes in (dict(facility_limits=(2,1)),dict(capacities=(8,1)),
                        dict(equities=(1,0)),dict(facility_limits=(2,F(1,2)))):
            with self.subTest(changes=changes),self.assertRaises(e.PlanFailure) as caught:
                plan(**changes)
            self.assertEqual(caught.exception.status,'funding_failure')

    def test_missing_new_credit_contract_is_not_invented_zero(self):
        lines=observations(cb=(0,0),rates=(None,None),reserves=(0,0),iorb=0)
        # Negative Treasury coupon can require reserves even without opening CB debt.
        lines=list(lines);lines[2]=income.CouponLine('treasury','B',1,F(-1,100),F(-1,100))
        with self.assertRaises(e.PlanFailure) as caught:
            plan(old_faces=(0,0),reserves=(0,0),cb_rates_pct=(None,None),observations=tuple(lines))
        self.assertEqual(caught.exception.status,'unsupported_public_income')
        result=plan(old_faces=(0,0),reserves=(0,0),cb_rates_pct=(0,0),observations=tuple(lines))
        self.assertEqual(result.advances,(0,F(1,100)))

    def test_positive_zero_negative_original_coupons_and_round_up(self):
        for rate in (4,0,-4):
            result=plan(cb_rates_pct=(0,rate),observations=observations(rates=(0,rate)))
            self.assertEqual(result.advances[1],F(9999,10**6) if rate>0 else 0)
        result=plan(reserves=(1,F(1,10**7)))
        self.assertEqual(result.advances[1],F(1,100))
        self.assertEqual(result.coupon_reserves[1],F(1,10**7))

    def test_peak_early_debit_not_netted_with_later_positive_coupon(self):
        lines=list(observations(cb=(0,0),rates=(0,0),reserves=(1,1),iorb=8))
        lines[2]=income.CouponLine('treasury','B',1,F(-1,100),F(-1,100))
        result=plan(old_faces=(0,0),reserves=(1,0),cb_rates_pct=(0,0),observations=tuple(lines))
        self.assertEqual(result.peak_needs[1],F(1,100))
        self.assertEqual(result.advances[1],F(1,100))
        self.assertEqual(result.coupon_reserves[1],F(1,50))

    def test_tga_not_funded_by_new_bank_credit_or_future_remittance(self):
        lines=list(observations());lines[0]=income.CouponLine('treasury','CB',1,F(2),F(2))
        with self.assertRaises(e.PlanFailure):plan(observations=tuple(lines))

    def test_invalid_shapes_scalars_and_metadata_never_invoke_callbacks(self):
        calls=[]
        class Alias(int):
            def __eq__(self,other):calls.append('equality');return True
            def __float__(self):calls.append('float');return 1.
        class Schema(dict):
            def values(self):calls.append('schema');return super().values()
        for bad in (True,Alias(1),float('inf'),F(-1)):
            with self.assertRaises((TypeError,ValueError)):plan(scale=bad)
        for key,value in (('reserves',[1,1]),('facility_limits',(1,)),('equities',(1,Alias(1)))):
            with self.assertRaises((TypeError,ValueError)):plan(**{key:value})
        result=plan()
        object.__setattr__(result,'__dataclass_fields__',Schema(type(result).__dataclass_fields__))
        with self.assertRaises((TypeError,ValueError)):e.validate_plan(result)
        self.assertEqual(calls,[])

    def test_stale_plan_and_module_import_boundary(self):
        result=plan()
        with self.assertRaises(ValueError):e.validate_plan(replace(result,advances=(0,0)))
        with self.assertRaises(ValueError):e.validate_plan(replace(result,gross_used=(False,result.gross_used[1])))
        tree=ast.parse(Path(e.__file__).read_text())
        for node in ast.walk(tree):
            if isinstance(node,(ast.Import,ast.ImportFrom)):
                names=[a.name for a in node.names]
                self.assertFalse(any(n in ('ledger','checkpoint') for n in names))


if __name__=='__main__':unittest.main()
