"""Source-bound quotes are neither saved commands nor paid career adoption."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k, macro as m, ledger as l
from scripts.research.funded_production import public_paydate as current
from scripts.research.funded_production import public_paydate_branches as branches
from scripts.research.funded_production import paydate_scenarios as scenarios,public_market as market


def inputs():
    a=m.initial(growth=0)
    a=replace(a,sector=l.enable_paydate_public(a.sector,
        l.public_income_terms(a.sector,cb_rates_pct=(0,0))))
    descriptor=market.MarketFundingDate(m.Policy(3.5,3.5),m.News(),0,(100,100),
        True,0,(0,0),(4,4),F(118,5),('A','B'))
    resolved=scenarios.resolve_date(a,descriptor)
    return a,descriptor,resolved


class PaydateBridgeSourceTests(unittest.TestCase):
    def test_all_three_new_modules_are_bound_to_current_source(self):
        for name in ('public_paydate','paydate_scenarios','public_paydate_branches'):
            self.assertIn(name,k._SOURCES)
        k._check_sources()

    def test_changed_source_refuses_before_preparation_or_execution(self):
        root,descriptor,resolved=inputs()
        cells=tuple(scenarios.ScenarioCell(sign,fulfilled,(descriptor,)*19)
                    for sign in (-1,1) for fulfilled in (False,True))
        before=repr(root)
        with patch.object(k,'_check_sources',side_effect=ValueError('Changed source')) as check, \
             patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as advance:
            for operation in (lambda:current.prepare(root,resolved.policy,resolved.step,resolved.news),
                              lambda:branches.evaluate(root,cells,units=0,forward_gross=(F(1),)*18),
                              lambda:scenarios.resolve_date(root,descriptor)):
                with self.assertRaisesRegex(ValueError,'Changed source'):operation()
            self.assertEqual(check.call_count,3)
            self.assertEqual(advance.call_count,0)
        self.assertEqual(repr(root),before)

    def test_preparation_and_unknown_future_quote_are_not_serialized_adoptions(self):
        root,_,resolved=inputs()
        cells=tuple(scenarios.ScenarioCell(sign,fulfilled,(None,)*19)
                    for sign in (-1,1) for fulfilled in (False,True))
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as advance:
            prepared=current.prepare(root,resolved.policy,resolved.step,resolved.news)
            quote=branches.evaluate(root,cells,units=0,forward_gross=(F(1),)*18)
            self.assertEqual((quote.status,quote.action,quote.executor_calls),('admission_incomplete',None,0))
            for record in (prepared,quote):
                with self.assertRaises(TypeError):k.encode_checkpoint(record)
            self.assertEqual(advance.call_count,0)


if __name__=='__main__':unittest.main()
