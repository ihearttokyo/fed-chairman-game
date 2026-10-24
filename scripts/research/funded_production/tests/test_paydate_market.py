"""Pure own-book fiscal routing, not paid quarters or household qualification."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch
from scripts.research.funded_production import ledger as l, macro as m
from scripts.research.funded_production import public_market as market
from scripts.research.funded_production import public_forecast as p, public_scenarios as s
from scripts.research.funded_production.tests.test_public_paydate_journal import legacy,pools
from scripts.research.funded_production.tests.test_public_market import date


def opening(**kwargs):
    state,terms=legacy(**kwargs)
    return replace(m.initial(growth=0),sector=l.enable_paydate_public(state,terms))


class PaydateMarketTests(unittest.TestCase):
    def setUp(self):
        self.guards=[]
        for target,name in ((l,'advance_given_orders'),(l,'_Transaction'),(p,'prepare'),(p,'execute')):
            guard=patch.object(target,name,side_effect=AssertionError('Pure fiscal route only'))
            self.guards.append(guard.start());self.addCleanup(guard.stop)
    def tearDown(self):
        self.assertTrue(all(x.call_count==0 for x in self.guards))

    def test_explicit_route_accepts_new_book_old_route_stays_blocked(self):
        value=opening()
        with self.assertRaises((TypeError,NotImplementedError)):market.resolve_date(value,date())
        result=market.resolve_paydate_date(value,date())
        self.assertIs(type(result),s.ResolvedDate)
        self.assertIs(type(result.step),p.PublicStep)
        self.assertEqual(result.step.fiscal.treasury_subscriptions,(0,0))

    def test_identical_q0_fiscal_math_for_each_explicit_book(self):
        base,terms=legacy(faces=pools({0:2},{0:3},{0:4}),
                          masses=pools({0:F(2,5)},{0:F(4,5)},{0:F(6,5)}),tga=F(3,5)-F(1,10**6))
        a=replace(m.initial(growth=0),sector=l.enable_funded_public(base,terms))
        b=replace(a,sector=l.enable_paydate_public(base,terms));before=repr(b)
        for priority in (('A','B'),('B','A')):
            descriptor=date(allocation_priority=priority)
            self.assertEqual(market.resolve_date(a,descriptor),market.resolve_paydate_date(b,descriptor))
        self.assertEqual(repr(b),before)
        with self.assertRaises(TypeError):market.resolve_paydate_date(a,date())

    def test_no_implicit_treasury_subscription_or_household_affordability(self):
        value=opening(faces=pools({0:2},{0:3},{0:4}),
                      masses=pools({0:F(2,5)},{0:F(4,5)},{0:F(6,5)}),tga=F(3,5)-F(1,10**6))
        with self.assertRaises(p.FundingFailure):
            market.resolve_paydate_date(value,date(new_issue_authorization=0))
        result=market.resolve_paydate_date(value,date())
        self.assertEqual(sum(result.step.fiscal.treasury_subscriptions),F(1,10**6))
        # Mortgage expense exceeds HB opening cash, but this pure Treasury
        # program neither refuses it early nor pretends it has actually paid.
        self.assertLess(value.sector.deposit('HB'),F(3,10))
        self.assertEqual(value.sector.quarter,0)

    def test_nominal_policy_iorb_and_explicit_zero_are_distinct(self):
        value=opening()
        result=market.resolve_paydate_date(value,date(policy=m.Policy(-3,-3),iorb_rate_pct=s.PolicyIORB()))
        self.assertEqual(result.step.iorb_rate_pct,-3)
        result=market.resolve_paydate_date(value,date(policy=m.Policy(-3,-3),iorb_rate_pct=0))
        self.assertEqual(result.step.iorb_rate_pct,0)

    def test_missing_date_is_unknown_and_invalid_version_not_normalized(self):
        value=opening()
        with self.assertRaises(s.MissingCoverage):market.resolve_paydate_date(value,None)
        object.__setattr__(value,'version',2)
        with self.assertRaises((TypeError,ValueError)):market.resolve_paydate_date(value,date())

    def test_instance_metadata_never_runs_callbacks(self):
        value=opening();calls=[]
        class Schema(dict):
            def values(self):calls.append('metadata');return super().values()
        object.__setattr__(value.sector.public_book,'__dataclass_fields__',Schema())
        with self.assertRaises((TypeError,ValueError)):market.resolve_paydate_date(value,date())
        self.assertEqual(calls,[])

    def test_missing_existing_contract_is_invalid_but_explicit_zero_is_covered(self):
        for options in (dict(cb_a=1,cb_rates=(None,None)),
                        dict(rrp_a=1,rrp_rates=(None,None))):
            with self.subTest(options=options), self.assertRaises(ValueError):
                opening(**options)
        market.resolve_paydate_date(opening(cb_a=1,cb_rates=(0,None)),date())
        market.resolve_paydate_date(opening(rrp_a=1,rrp_rates=(0,None)),date())


if __name__=='__main__':unittest.main()
