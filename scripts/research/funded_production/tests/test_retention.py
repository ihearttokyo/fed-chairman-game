"""Actual earned retention is not a grant, reserve creation or covenant waiver."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from scripts.research.funded_production import ledger as l


def advance(a, targets, clearing, offers=()):
    b=a.public_book;rolls=(b.treasuries[0],b.private_treasuries[0][0],b.private_treasuries[1][0])
    controls=l.Controls(public_instructions=l.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls)),facility_limits=(100,100),bank_capital_targets=targets,new_loans=offers)
    return l.advance_given_orders(a,replace(l.depth_orders(),market_clearing=clearing),controls)


class RetentionTests(unittest.TestCase):
    def test_actual_earnings_move_from_owner_cash_to_bank_equity_only(self):
        for clearing in (False,True):
            a=l.initial_depth_reference();before=repr(a)
            base=advance(a,None,clearing);held=advance(a,(0,a.bank_equity('B')+F(1,20)),clearing)
            self.assertTrue(base.ok,base.reason);self.assertTrue(held.ok,held.reason)
            self.assertEqual(held.state.bank_equity('B')-base.state.bank_equity('B'),F(1,20))
            self.assertEqual(base.state.deposit('HB')-held.state.deposit('HB'),F(1,20))
            self.assertEqual(held.state.private_wealth,base.state.private_wealth)
            self.assertEqual(held.state.last.real_output,base.state.last.real_output)
            self.assertEqual(held.state.loans,base.state.loans)
            self.assertEqual([held.state.reserves(b) for b in ('A','B')],[base.state.reserves(b) for b in ('A','B')])
            self.assertEqual(repr(a),before)
    def test_target_above_income_does_not_grant_equity(self):
        a=l.initial_depth_reference();out=advance(a,(100,100),True)
        self.assertTrue(out.ok,out.reason)
        self.assertEqual(out.state.bank_equity('B'),a.bank_equity('B')+F(1,10))
        self.assertEqual(out.state.last.bank_dividend_to('HB'),0)
        self.assertEqual(out.state.loan_face,a.loan_face)
    def test_negative_coupons_still_reduce_capital(self):
        a=l.initial_depth_reference();a=replace(a,loans=tuple(replace(z,rate_pct=F(-4)) for z in a.loans))
        out=advance(a,(100,100),True);self.assertTrue(out.ok,out.reason)
        self.assertEqual(out.state.bank_equity('B'),a.bank_equity('B')-F(1,10))
        self.assertEqual(out.state.last.bank_dividend_to('HB'),0)
    def test_current_income_and_target_do_not_waive_opening_covenant(self):
        a=l.initial_depth_reference();before=repr(a)
        available=a.bank_equity('B')/l.COVENANT-a.loan_face
        exact=advance(a,(100,100),True,(l.LoanOffer('B',available,4,8),))
        self.assertTrue(exact.ok,exact.reason)
        over=advance(a,(100,100),True,(l.LoanOffer('B',available+l.QUANTUM,4,8),))
        self.assertFalse(over.ok);self.assertEqual(over.status,'credit_constraint')
        self.assertEqual(over.state,a);self.assertEqual(repr(a),before)

    def test_target_inputs_are_immutable_finite_nonnegative_pairs(self):
        original=[1,2];c=l.Controls(bank_capital_targets=original);original[0]=99
        self.assertEqual(c.bank_capital_targets,(1,2))
        for bad in ((1,),(-1,0),(True,1),(float('nan'),0)):
            with self.assertRaises((ValueError,TypeError)):l.Controls(bank_capital_targets=bad)


if __name__=='__main__':unittest.main()
