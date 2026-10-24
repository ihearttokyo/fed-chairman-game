"""Pure post-payroll reserve arithmetic; no ledger approval or recovery claim."""
from dataclasses import FrozenInstanceError, replace
from fractions import Fraction as F
import ast
from pathlib import Path
import unittest

from scripts.research.funded_production import early_liquidity as e, public_income as income
from scripts.research.funded_production.tests.test_public_paydate_journal import pools


Q = F(1, 10**6)


def inputs(**changes):
    terms = income.PublicIncomeTerms(pools(), (F(0), F(4)), F(0), (F(0), F(4)), (None, None))
    observations = income.quote(terms, treasuries=pools(), mortgages=(F(1), F(1)),
        reserves=(F(1), Q), cb_faces=(F(0), F(1)), rrp_faces=(F(0), F(0)), scale=F(1))
    values = dict(scale=F(1), reserves=(F(5), Q), household_deposits=(F(3), F(2)),
        cb_faces=(F(0), F(1)), equities=(F(5), F(5)), capacities=(F(10), F(10)),
        facility_limits=(F(10), F(2)), gross_used=(F(0), F(1)),
        cb_rates_pct=(F(0), F(4)), observations=observations)
    values.update(changes)
    return values


class HouseholdLiquidityTests(unittest.TestCase):
    def test_minimum_grid_credit_is_bank_debt_not_household_cash(self):
        p = e.household_plan(**inputs())
        self.assertIs(type(p), e.HouseholdLiquidityPlan)
        self.assertEqual(p.advances, (0, F(9999, 10**6)))
        self.assertEqual(p.credit_faces[1], 1+p.advances[1])
        self.assertEqual(p.gross_after[1], 1+p.advances[1])
        self.assertEqual(p.credit_reserves[1], F(1, 100))
        self.assertEqual(p.coupon_reserves[1], 0)
        self.assertEqual(p.coupon_deposits[1], F(199, 100))
        self.assertEqual(p.household_deposits, (3, 2))
        with self.assertRaises(FrozenInstanceError): p.advances = (0, 0)
        e.validate_household_plan(p)

    def test_household_shortfall_is_funding_failure_even_with_unlimited_reserve_offer(self):
        with self.assertRaises(e.PlanFailure) as error:
            e.household_plan(**inputs(household_deposits=(3, 0),
                facility_limits=(10**6, 10**6), cb_rates_pct=(None, None)))
        self.assertEqual(error.exception.status, 'funding_failure')

    def test_missing_needed_contract_is_unsupported_explicit_zero_valid(self):
        with self.assertRaises(e.PlanFailure) as error:
            e.household_plan(**inputs(cb_rates_pct=(0, None)))
        self.assertEqual(error.exception.status, 'unsupported_public_income')
        p = e.household_plan(**inputs(cb_rates_pct=(0, 0)))
        self.assertGreater(p.advances[1], 0)
        p = e.household_plan(**inputs(reserves=(5, 5), cb_rates_pct=(None, None)))
        self.assertEqual(p.advances, (0, 0))
        self.assertEqual(p.cb_rates_pct, (None, None))

    def test_current_equity_collateral_and_used_gross_cannot_be_guessed_or_reset(self):
        for change in (dict(equities=(5, 0)), dict(capacities=(10, 1)),
                       dict(gross_used=(0, 2)), dict(facility_limits=(10, 1))):
            with self.assertRaises(e.PlanFailure) as error: e.household_plan(**inputs(**change))
            self.assertEqual(error.exception.status, 'funding_failure')
        # Cash repayment can lower current debt; it does not replenish gross room.
        with self.assertRaises(e.PlanFailure):
            e.household_plan(**inputs(cb_faces=(0, 0), gross_used=(0, 2)))

    def test_signed_zero_coupons_and_current_bases_are_not_requoted(self):
        values = inputs()
        for coupon in (F(-1, 100), F(0), F(1, 100)):
            lines = list(values['observations'])
            lines[4] = income.CouponLine('mortgage', 'HB', F(1), coupon, coupon)
            p = e.household_plan(**inputs(observations=tuple(lines)))
            self.assertEqual(p.coupon_deposits[1], 2-coupon)
            self.assertEqual(p.observations, tuple(lines))
            if coupon <= 0:
                self.assertEqual(p.advances[1], 0)
                self.assertEqual(p.coupon_reserves[1], Q-coupon)
            self.assertEqual(p.observations[8].basis, 1)

    def test_round_up_need_without_rounding_owned_reserve_dust(self):
        dust = Q/3
        p = e.household_plan(**inputs(reserves=(5, dust)))
        self.assertEqual(p.advances[1], F(1, 100))
        self.assertEqual(p.coupon_reserves[1], dust)
        self.assertEqual(p.reserves[1], dust)

    def test_metadata_aliases_shapes_and_stale_outputs_reject_before_callbacks(self):
        calls = []
        class Alias(float):
            def __eq__(self, other): calls.append('equality'); return True
        for change in (dict(scale=True), dict(reserves=[5, 1]), dict(gross_used=(0, Alias(1))),
                       dict(observations=inputs()['observations'][1:])):
            with self.assertRaises((TypeError, ValueError)): e.household_plan(**inputs(**change))
        p = e.household_plan(**inputs())
        for altered in (replace(p, advances=(0, 0)), replace(p, gross_after=(0, Alias(1))),
                        replace(p, coupon_deposits=(3, 2)), replace(p, gross_used=(False, F(1)))):
            with self.assertRaises((TypeError, ValueError)): e.validate_household_plan(altered)
        object.__setattr__(p, '__dataclass_fields__', {})
        with self.assertRaises((TypeError, ValueError)): e.validate_household_plan(p)
        self.assertEqual(calls, [])

    def test_planner_module_stays_independent_of_ledger_checkpoint_and_transactions(self):
        tree = ast.parse(Path(e.__file__).read_text())
        imports = [ast.unparse(n) for n in ast.walk(tree) if isinstance(n, (ast.Import, ast.ImportFrom))]
        self.assertFalse(any('ledger' in name or 'checkpoint' in name for name in imports))
        self.assertNotIn('_Transaction', Path(e.__file__).read_text())


if __name__ == '__main__': unittest.main()
