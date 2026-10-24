from fractions import Fraction as F
from dataclasses import replace
import unittest
from scripts.research.funded_production.ledger import initial_depth_reference,depth_orders,ProductionOrders,Controls,PublicInstructions,LoanOffer,Renewal,advance_given_orders

def fiscal(a):
 b=a.public_book;r=(b.treasuries[0],b.private_treasuries[0][0],b.private_treasuries[1][0])
 return PublicInstructions(treasury_rolls=r,treasury_issue_authorization=sum(r))
class Clearing(unittest.TestCase):
 def run_ok(self,a,o,mode='fixed',loans=(),renewals=()):
  c=Controls(public_instructions=fiscal(a),household_mode=mode,facility_limits=(100,100),new_loans=loans,renewals=renewals)
  before=repr(a);out=advance_given_orders(a,o,c);self.assertTrue(out.ok,out.reason)
  self.assertEqual(repr(a),before);self.assertEqual(advance_given_orders(a,o,c),out)
  return out.state
 def test_stationary64q_owned_income_not_duplicated(self):
  a=initial_depth_reference();o=replace(depth_orders(),market_clearing=True)
  for q in range(1,65):
   renew=(Renewal('L0',10,4,96),) if q==48 else ()
   a=self.run_ok(a,o,renewals=renew)
   self.assertEqual(a.last.real_output,25);self.assertEqual(a.wip_units,1);self.assertEqual(a.capital_units,16)
   self.assertEqual([a.deposit(x) for x in ('R','F','HA','HB')],[17,3,3,F(3,20)])
   self.assertEqual(a.last.dividend_focal,F(1,20));self.assertEqual(a.last.dividend_residual,3)
 def test_current_profit_funds_unfilled_desired_orders_at_higher_prices(self):
  a=initial_depth_reference();o=replace(depth_orders(),price_factor=F(6,5),market_clearing=True)
  # All new cash is matched corporate debt, not a rebase of old deposits.
  offers=(LoanOffer('A',F(17,5),4,8,borrower='R'),LoanOffer('B',F(3,5),4,8,borrower='F'))
  b=self.run_ok(a,o,loans=offers)
  self.assertEqual(b.last.real_output,25);self.assertEqual(b.wip_units,1)
  self.assertEqual(next(l.face for l in b.loans if l.id=='L0'),10)
  self.assertEqual(b.last.services,5)
  self.assertGreater(len([p for p in b.last.payments if p.kind=='services']),2)
 def test_wealth_variant_never_pays_forecasts(self):
  a=initial_depth_reference();o=replace(depth_orders(),market_clearing=True,expected_dividends_nominal=(10**6,10**6))
  b=self.run_ok(a,o,'liquidity')
  self.assertTrue(all(b.deposit(x)>=0 for x in ('R','F','HA','HB')))
  self.assertEqual(sum(b.deposit(x) for x in ('R','F','HA','HB')),F(463,20))
  self.assertLessEqual(b.last.residual_consumption+b.last.investment,20)
  self.assertLessEqual(b.last.services,5)
 def test_round_limit_reports_partial_trading_without_fake_clearing(self):
  a=initial_depth_reference();o=replace(depth_orders(),market_clearing=True,max_clearing_rounds=1,price_factor=F(6,5))
  loans=(LoanOffer('A',F(17,5),4,8,borrower='R'),LoanOffer('B',F(3,5),4,8,borrower='F'))
  b=self.run_ok(a,o,loans=loans)
  notes=[t for t in b.last.trace if t.kind=='market_clearing'];self.assertEqual(len(notes),1)
  self.assertEqual(dict(notes[0].details)['rounds'],1)
  self.assertLessEqual(b.last.real_output,25)
 def test_unfunded_maturity_still_rejects_original_whole_state(self):
  from scripts.research.funded_production.ledger import originate
  a=originate(initial_depth_reference(),LoanOffer('A',30,4,1,borrower='R'))
  a=replace(a,banks=(replace(a.banks[0],deposits=(17,33)),a.banks[1]))
  c=Controls(public_instructions=fiscal(a),household_mode='fixed',facility_limits=(100,100))
  out=advance_given_orders(a,replace(depth_orders(),market_clearing=True),c)
  self.assertFalse(out.ok);self.assertEqual(out.status,'credit_default');self.assertEqual(out.state,a)
 def test_zero_production_cannot_distribute_unearned_profit(self):
  a=initial_depth_reference();o=replace(depth_orders(),market_clearing=True,residual_workers=0,focal_workers=0,investment_units=0)
  b=self.run_ok(a,o)
  self.assertEqual(b.last.real_output,0);self.assertEqual(b.last.dividend_residual,0);self.assertEqual(b.last.dividend_focal,0)
 def test_each_actual_unit_is_produced_only_once(self):
  a=initial_depth_reference();o=replace(depth_orders(),market_clearing=True,residual_consumption=100,service_a=100,service_b=100,investment_units=100)
  b=self.run_ok(a,o)
  self.assertLessEqual(b.last.residual_consumption+b.last.investment,20)
  self.assertLessEqual(b.last.services,5)
  self.assertEqual(b.last.real_output,b.last.residual_consumption+b.last.investment+b.last.services)
 def test_clearing_options_reject_invalid_types(self):
  for kwargs in ({'market_clearing':1},{'max_clearing_rounds':0},{'max_clearing_rounds':True}):
   with self.assertRaises((ValueError,TypeError)):ProductionOrders(**kwargs)
if __name__=='__main__':unittest.main()
