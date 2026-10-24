"""Integration hand case: same stocks, different explicit payment convention."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import macro as m, ledger as l
from scripts.research.funded_production import checkpoint as k


def source():
    sector = m.initial(growth=0).sector
    bank = sector.banks[1]
    # Q0 fixture reallocation inside the same bank: no new deposits/equity.
    bank = replace(bank, deposits=(sum(bank.deposits,F(0)),F(0)))
    return replace(sector,banks=(sector.banks[0],bank))


def controls(sector):
    book=sector.public_book
    rolls=(book.treasuries[0],book.private_treasuries[0][0],book.private_treasuries[1][0])
    return l.PublicIncomeControls(iorb_rate_pct=0,household_mode='cash_stock_close_v1',
        public_instructions=l.FundedPublicInstructions(treasury_rolls=rolls,
            treasury_issue_authorization=sum(rolls)),facility_limits=(100,100))


class PublicPaydateIntegrationTests(unittest.TestCase):
    def test_same_stocks_wage_funded_coupon_not_forecast_money(self):
        base=source()
        terms=l.public_income_terms(base,mortgage_rates_pct=(0,4),cb_rates_pct=(0,0))
        legacy=l.enable_funded_public(base,terms)
        candidate=l.enable_paydate_public(base,terms)
        orders=replace(l.depth_orders(),market_clearing=True,residual_workers=0,
                       focal_workers=1,investment_units=0)
        before=(repr(legacy),repr(candidate))
        with patch.object(l,'advance_given_orders',wraps=l.advance_given_orders) as advance:
            old=l.advance_given_orders(legacy,orders,controls(legacy))
            new=l.advance_given_orders(candidate,orders,controls(candidate))
            self.assertEqual(advance.call_count,2)
        self.assertFalse(old.ok)
        self.assertEqual(old.status,'funding_failure')
        self.assertIs(old.state,legacy)
        self.assertTrue(new.ok,new.reason)
        self.assertEqual((repr(legacy),repr(candidate)),before)
        paid=new.state.last
        self.assertGreater(paid.payroll_focal,0)
        wage=[i for i,payment in enumerate(paid.payments) if payment.kind=='focal_payroll']
        coupons=[i for i,payment in enumerate(paid.payments)
                 if payment.kind=='mortgage_coupon' and payment.claim_id=='mortgage:HB']
        self.assertEqual(len(wage),1);self.assertEqual(len(coupons),1)
        self.assertLess(wage[0],coupons[0])
        goods=[i for i,payment in enumerate(paid.payments)
               if payment.kind in ('services','residual_consumption')]
        self.assertTrue(goods)
        self.assertLess(coupons[0],min(goods))

    def test_fresh_opt_in_codec_has_explicit_types_and_source(self):
        base=source()
        terms=l.public_income_terms(base,cb_rates_pct=(0,0))
        sector=l.enable_paydate_public(base,terms)
        economy=replace(m.initial(growth=0),sector=sector)
        candidate=k.CandidateState(economy)
        restored=k.decode_checkpoint(k.encode_checkpoint(candidate))
        self.assertIs(type(restored.economy.sector.public_book),l.PaydatePublicBook)
        self.assertEqual(restored,candidate)
        self.assertIn('paydate_households',k._SOURCES)
        for cls in (l.PaydatePublicBook,l.PaydateSnapshot,l.PaydatePhase):
            self.assertIn(cls,k._TAGS)

    def test_older_adapters_refuse_new_calendar_without_executor_calls(self):
        from scripts.research.funded_production import public_forecast as p, coupled as c
        base=source();terms=l.public_income_terms(base,cb_rates_pct=(0,0))
        economy=replace(m.initial(growth=0),sector=l.enable_paydate_public(base,terms))
        policy=m.Policy(3.5,3.5)
        step=p.PublicStep(0,controls(economy.sector).public_instructions,(100,100))
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No adoption')) as advance:
            for operation in (lambda:m.prepare(economy,policy),lambda:c.prepare(economy,policy),
                              lambda:p.prepare(economy,policy,step)):
                with self.assertRaises((TypeError,NotImplementedError)):
                    operation()
            self.assertEqual(advance.call_count,0)

    def test_paid_macro_checkpoint_keeps_actual_timing_witnesses(self):
        base=source()
        terms=l.public_income_terms(base,mortgage_rates_pct=(0,4),cb_rates_pct=(0,0))
        economy=replace(m.initial(growth=0),sector=l.enable_paydate_public(base,terms))
        prepared=m._quote_source(economy,m.Policy(3.5,3.5))
        orders=replace(l.depth_orders(),market_clearing=True,residual_workers=0,
            focal_workers=1,investment_units=0,
            price_factor=m.rational(prepared.price_index/100),
            real_wage=m.rational(prepared.trend),available_workers=m.rational(economy.macro.workforce))
        raw=l.advance_given_orders(economy.sector,orders,controls(economy.sector))
        self.assertTrue(raw.ok,raw.reason)
        closed=m._close_paid(replace(prepared,orders=orders),raw.state,closing_households=True)
        self.assertTrue(closed.ok,closed.reason)
        candidate=k.CandidateState(closed.envelope)
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No validation replay')) as advance:
            restored=k.decode_checkpoint(k.encode_checkpoint(candidate))
            self.assertEqual(advance.call_count,0)
        self.assertEqual(restored,candidate)
        self.assertEqual(restored.economy.sector.public_book.phases,
                         raw.state.public_book.phases)


if __name__=='__main__':unittest.main()
