"""Public-income accounting hand cases; not recovery or game qualification."""
from dataclasses import replace
from fractions import Fraction as F
import unittest
from scripts.research.funded_production import ledger as l, households as h, macro as m, coupled as c
from scripts.research.funded_production import checkpoint as k

def enabled(state=None, **rates):
    state=state or l.initial_depth_reference()
    return l.enable_public_income(state,l.public_income_terms(state,**rates))

def journal(state,controls=None):
    tx=l._Transaction(state,controls or l.Controls(),state.quarter+1)
    before=repr(state)
    tx.settle_public_income()
    result=tx.finish()
    assert repr(state)==before
    return tx,result

def cash_case(private,central,mortgage,iorb):
    a=l.initial_depth_reference();b=a.public_book
    return enabled(a,treasury_rates_pct=(400*central/sum(b.treasuries),
        400*private/a.securities('A'),0),
        mortgage_rates_pct=tuple(400*(mortgage/2)/x for x in b.mortgages),
        iorb_rate_pct=400*iorb/sum(z.reserves for z in a.banks))

class PublicIncomeTests(unittest.TestCase):
    def fiscal(self,state,maturity=120):
        b=state.public_book
        rolls=(b.treasuries[0],*(x[0] for x in b.private_treasuries))
        return l.PublicInstructions(treasury_rolls=rolls,
            treasury_issue_authorization=sum(rolls),replacement_maturity=maturity)

    def test_positive_funded_income_and_owner_payout_are_not_gdp(self):
        a=cash_case(F(1,10),F(3,40),F(1,50),F(1,20));tx,b=journal(a)
        self.assertEqual(b.public_book.tga,F(287,100))
        self.assertEqual(b.public_book.deferred_asset,0)
        self.assertEqual(sum(b.deposit(z) for z in l.ACTORS),F(2313,100))
        self.assertEqual(sum(b.bank_equity(z) for z in l.BANKS),F(14))
        self.assertEqual(sum(tx.earnings.values()),F(3,20))
        self.assertEqual(sum(p.amount for p in tx.payments if p.kind=='cb_remittance'),F(9,200))
        self.assertFalse(any(p.kind in ('services','investment','residual_consumption') for p in tx.payments))
        # Distribute only this actually earned income; no direct grant to owners.
        for bank,owner in zip(l.BANKS,('HA','HB')):
            tx.d[owner]+=tx.earnings[bank];tx.record('Bank'+bank,owner,tx.earnings[bank],'bank_dividend')
        b=tx.finish()
        self.assertEqual(sum(b.deposit(z) for z in l.ACTORS),F(582,25))
        self.assertEqual(sum(b.bank_equity(z) for z in l.BANKS),F(277,20))

    def test_loss_deferred_asset_is_not_cash_or_capital_grant(self):
        a=cash_case(F(3,100),F(1,50),F(1,100),F(2,25));tx,b=journal(a)
        self.assertEqual(b.public_book.deferred_asset,F(1,20))
        self.assertEqual(b.public_book.capital_other,a.public_book.capital_other)
        self.assertEqual(b.public_book.tga,F(59,20))
        self.assertFalse(any(p.kind=='cb_remittance' for p in tx.payments))
        self.assertEqual(sum(tx.earnings.values()),F(11,100))

    def test_deferred_waterfall_covers_old_losses_before_remittance(self):
        a=cash_case(F(3,100),F(1,50),F(1,100),F(2,25));_,b=journal(a)
        # New administered rate changes expense; fixed security terms stay fixed.
        _,d=journal(b,l.PublicIncomeControls(iorb_rate_pct=0))
        self.assertEqual(d.public_book.deferred_asset,F(1,50))
        self.assertEqual(d.public_book.tga,F(29,10))
        self.assertEqual(l.public_income.earnings_close(F(1,50),F(1,25)),(0,F(1,50)))

    def test_zero_program_preserves_legacy_economic_flows(self):
        a=l.initial_depth_reference();e=enabled(a)
        book=a.public_book;rolls=(book.treasuries[0],*(x[0] for x in book.private_treasuries))
        controls=l.Controls(public_instructions=l.PublicInstructions(treasury_rolls=rolls,treasury_issue_authorization=sum(rolls)))
        old=l.advance_given_orders(a,l.depth_orders(),controls)
        new=l.advance_given_orders(e,l.depth_orders(),controls)
        self.assertTrue(old.ok,old.reason);self.assertTrue(new.ok,new.reason)
        self.assertEqual(old.state.banks,new.state.banks)
        self.assertEqual(old.state.loans,new.state.loans)
        self.assertEqual(old.state.last,new.state.last)
        self.assertEqual(new.state.public_book.income_paid_through,1)

    def test_insufficient_tga_fails_atomic_quarter(self):
        a=enabled(treasury_rates_pct=(100000,100000,100000))
        before=repr(a)
        out=l.advance_given_orders(a,l.depth_orders())
        self.assertFalse(out.ok);self.assertEqual(out.state,a);self.assertEqual(repr(a),before)
        self.assertEqual(out.status,'funding_failure')

    def test_negative_reserve_coupon_has_bank_as_payer(self):
        a=enabled(iorb_rate_pct=-4);tx,b=journal(a)
        self.assertEqual(sum(tx.earnings.values()),-F(9,100))
        self.assertEqual(sum(p.amount for p in tx.payments if p.kind=='iorb_coupon'),F(9,100))
        self.assertTrue(all(p.payer in ('BankA','BankB') and p.payee=='CB' for p in tx.payments if p.kind=='iorb_coupon'))
        self.assertEqual(b.public_book.tga,F(309,100))

    def test_negative_mortgage_coupon_is_paid_once_to_owner(self):
        a=enabled(mortgage_rates_pct=(-4,-4));tx,b=journal(a)
        amount=sum(p.amount for p in tx.payments if p.kind=='mortgage_coupon')
        self.assertGreater(amount,0)
        self.assertEqual(sum(b.deposit(z)-a.deposit(z) for z in ('HA','HB')),amount)
        self.assertEqual(b.public_book.mortgages,a.public_book.mortgages)
        self.assertEqual(b.public_book.mbs,a.public_book.mbs)
        self.assertTrue(all(p.payer=='MortgagePool' for p in tx.payments if p.kind=='mortgage_coupon'))

    def test_coupon_bases_exclude_returned_rrp_principal(self):
        a=l.settle_public(l.initial_depth_reference(),l.PublicInstructions())
        # A public RRP fixture is constructed with matched held collateral.
        left=F(1);collateral=[]
        for index,face in enumerate(a.public_book.treasuries[1:],1):
            take=min(left,face)
            if take:collateral.append((index,take));left-=take
            if not left:break
        self.assertEqual(left,0)
        a=replace(a,banks=(replace(a.banks[0],reserves=a.reserves('A')-1),a.banks[1]),
            public_book=replace(a.public_book,rrp_claims=(l.RRPClaim('A',1,0,1,tuple(collateral)),)))
        a=enabled(a,iorb_rate_pct=4,rrp_rates_pct=(4,None))
        tx,b=journal(a)
        self.assertEqual(sum(p.amount for p in tx.payments if p.kind=='iorb_coupon'),F(8,100))
        self.assertEqual(sum(p.amount for p in tx.payments if p.kind=='rrp_coupon'),F(1,100))
        self.assertEqual(b.public_book.rrp_claims,())

    def test_duplicate_income_phase_refused(self):
        a=enabled();tx=l._Transaction(a,l.Controls(),1);tx.settle_public_income()
        with self.assertRaises(l._Failure):tx.settle_public_income()

    def test_enable_is_fresh_only_and_missing_claim_terms_are_not_zero(self):
        a=enabled()
        with self.assertRaises(ValueError):l.enable_public_income(a,a.public_book.terms)
        tx,b=journal(a)
        with self.assertRaises(ValueError):l.enable_public_income(b,l.public_income_terms(b))
        # Explicit zero is a contract. None does not silently authorize a loan.
        self.assertEqual(a.public_book.terms.cb_rates_pct,(None,None))

    def test_unknown_quantity_operations_refused_without_migration(self):
        a=enabled();out=l.advance_given_orders(a,l.depth_orders(),l.Controls(asset_purchase_request=1,asset_offers=(1,0)))
        self.assertFalse(out.ok);self.assertEqual(out.state,a)
        self.assertEqual(out.status,'unsupported_public_income')

    def test_public_income_cannot_enter_unqualified_private_forecast(self):
        a=m.initial(growth=0);a=replace(a,sector=enabled(a.sector))
        with self.assertRaisesRegex(NotImplementedError,'[Pp]ublic'):c.prepare(a,m.Policy(3.5,3.5))

    def test_signed_net_income_has_owned_wallet_and_nonnegative_cash_target(self):
        b=h.net_cash_stock_budget(opening_cash=2,paid_wages=0,previous_income=-1,forecast_income=-2,cash_ratio=F(1,5))
        self.assertEqual(b.desired,0);self.assertEqual(b.wallet,2);self.assertEqual(b.funded,0)
        for prior,future in [(100,104),(0,0),(3,2)]:
            args=dict(opening_cash=22,paid_wages=4,previous_income=prior,forecast_income=future,cash_ratio=F(1,5))
            self.assertEqual(h.net_cash_stock_budget(**args),h.cash_stock_budget(**args))

    def test_paid_public_income_in_current_budget_and_history_is_not_double_cash(self):
        a=cash_case(F(1,10),F(3,40),F(1,50),F(1,20))
        controls=l.Controls(public_instructions=self.fiscal(a),household_mode='cash_stock_close_v1',
                            facility_limits=(100,100))
        out=l.advance_given_orders(a,replace(l.depth_orders(),market_clearing=True),controls)
        self.assertTrue(out.ok,out.reason)
        r=out.state.last
        self.assertEqual((r.public_income_to('HA'),r.public_income_to('HB')),(-F(1,100),)*2)
        budgets={n.actor:dict(n.details) for n in r.trace if n.kind=='household_budget'}
        self.assertEqual(budgets['HA']['opening_cash'],F(299,100))
        self.assertEqual(budgets['HA']['income_forecast'],F(1999,100))
        self.assertEqual(r.disposable_income('HA'),r.payroll_residual+r.dividend_residual+r.bank_dividend_to('HA')-F(1,100))

    def test_same_face_roll_preserves_actual_annual_coupon_mass(self):
        a=enabled(treasury_rates_pct=(4,3,2))
        before=tuple(sum(v,F(0)) for v in a.public_book.terms.annual_treasury)
        out=l.advance_given_orders(a,l.depth_orders(),l.Controls(public_instructions=self.fiscal(a,F(3,2))))
        self.assertTrue(out.ok,out.reason)
        book=out.state.public_book
        self.assertEqual(tuple(sum(v,F(0)) for v in book.terms.annual_treasury),before)
        for faces,masses in zip((book.treasuries,*book.private_treasuries),book.terms.annual_treasury):
            self.assertTrue(all(face or not mass for face,mass in zip(faces,masses)))

    def test_missing_cb_contract_is_refused_and_explicit_zero_is_coverage(self):
        tx=l._Transaction(l.initial_depth_reference(),l.Controls(facility_limits=(10,0)),0)
        tx._draw('A',1);old=tx.finish()
        with self.assertRaisesRegex(ValueError,'Missing contractual'):enabled(old)
        a=enabled(old,cb_rates_pct=(40,None));tx,b=journal(a)
        self.assertEqual(sum(p.amount for p in tx.payments if p.kind=='cb_loan_coupon'),F(1,10))
        self.assertEqual(b.cb_debt('A'),1)
        self.assertEqual(tx.earnings['A'],-F(1,10))
        explicit=enabled(old,cb_rates_pct=(0,None))
        self.assertEqual(explicit.public_book.terms.cb_rates_pct,(0,None))

    def test_new_cb_funding_cannot_drop_unknown_coupon_terms(self):
        a=enabled();tx=l._Transaction(a,l.Controls(facility_limits=(10,0)),1)
        with self.assertRaises(l._Failure) as error:tx._draw('A',1)
        self.assertEqual(error.exception.status,'unsupported_public_income')
        self.assertEqual(tx.cb,{})

    def test_unfunded_borrower_interest_rolls_back_whole_quarter(self):
        a=enabled(mortgage_rates_pct=(100000,100000))
        before=repr(a);out=l.advance_given_orders(a,l.depth_orders(),l.Controls(public_instructions=self.fiscal(a)))
        self.assertFalse(out.ok);self.assertEqual(out.status,'funding_failure')
        self.assertEqual(out.state,a);self.assertEqual(repr(a),before)

    def test_strict_contracts_clock_and_orphan_coupon_mass(self):
        a=enabled();book=a.public_book
        for value in (True,float('inf'),float('nan'),'4'):
            with self.subTest(value=value),self.assertRaises((ValueError,TypeError)):
                replace(book.terms,iorb_rate_pct=value)
        with self.assertRaises(ValueError):replace(a,public_book=replace(book,income_paid_through=1))
        rows=[list(v) for v in book.terms.annual_treasury];rows[2][0]=1
        with self.assertRaises(ValueError):replace(book,terms=replace(book.terms,annual_treasury=tuple(map(tuple,rows))))

    def test_strict_checkpoint_type_roundtrip_and_private_adapter_refusal(self):
        a=m.initial(growth=0);a=replace(a,sector=enabled(a.sector,iorb_rate_pct=-1))
        state=k.CandidateState(a)
        text=k.encode_checkpoint(state);restored=k.decode_checkpoint(text)
        self.assertEqual(restored,state);self.assertEqual(k.encode_checkpoint(restored),text)
        with self.assertRaisesRegex(NotImplementedError,'[Pp]ublic'):m.prepare(a,m.Policy(3.5,3.5))

    def test_treasury_secondary_sale_cannot_reassign_coupon_terms(self):
        a=enabled();tx=l._Transaction(a,l.Controls(),1)
        with self.assertRaises(l._Failure):tx.transfer_treasuries('A','B',1)
        self.assertEqual(tx.s,dict(zip(l.BANKS,(18,0))))

    def test_consolidated_public_claim_identity_includes_deferred_asset(self):
        for args in ((F(1,10),F(3,40),F(1,50),F(1,20)),
                     (F(3,100),F(1,50),F(1,100),F(2,25))):
            a=cash_case(*args);_,b=journal(a);book=b.public_book
            owned=(sum(z.reserves+z.securities for z in b.banks)
                   +sum(book.currency)+sum(z.face for z in book.rrp_claims)
                   -sum(z.face for z in b.cb_loans)-book.mbs)
            self.assertEqual(owned,b.gov_debt_face-book.tga-book.capital_other+book.deferred_asset)
            self.assertEqual(b.private_wealth-a.private_wealth,args[0]+args[3]-args[2])

    def test_paid_report_cannot_drop_or_misattribute_mortgage_pass_through(self):
        a=cash_case(F(1,10),F(3,40),F(1,50),F(1,20))
        out=l.advance_given_orders(a,l.depth_orders(),l.Controls(public_instructions=self.fiscal(a)))
        self.assertTrue(out.ok,out.reason);s=out.state;r=s.last
        # Codec hand fixture only: this is not a qualified public macro adapter.
        macro=replace(m.initial(growth=0).macro,quarter=s.quarter,
            actual_output_index=4*float(r.real_output),
            unemployment_rate_pct=100*(1-float(r.paid_residual_workers+r.paid_focal_workers)/(4000/191)))
        env=m.Envelope(macro,s);k._paid_economy(env)
        missing=replace(r,payments=tuple(p for p in r.payments if p.kind!='mbs_coupon'))
        with self.assertRaisesRegex(ValueError,'pass-through'):
            k._paid_economy(replace(env,sector=replace(s,last=missing)))
        forged=tuple(replace(p,claim_id='mortgage:HB') if p.kind=='mortgage_coupon' and p.payer=='HA' else p for p in r.payments)
        with self.assertRaisesRegex(ValueError,'another owner'):
            k._paid_economy(replace(env,sector=replace(s,last=replace(r,payments=forged))))
        deleted=tuple(p for p in r.payments if p.kind not in ('mortgage_coupon','mbs_coupon'))
        invented=r.payments+(l.Payment('HA','MortgagePool',1,'mortgage_coupon','mortgage:HA'),
                             l.Payment('MortgagePool','CB',1,'mbs_coupon','mortgage:HA'))
        wrong_claim=tuple(replace(p,claim_id='Treasury:B') if p.kind=='treasury_coupon' and p.payee=='BankA' else p for p in r.payments)
        for changed in (deleted,invented,wrong_claim):
            with self.subTest(receipt_case=len(changed)),self.assertRaisesRegex(ValueError,'[Pp]ublic.*receipt|obligation'):
                k._paid_economy(replace(env,sector=replace(s,last=replace(r,payments=changed))))
            forged_state=replace(s,last=replace(r,payments=changed))
            with self.subTest(raw_ledger_case=len(changed)),self.assertRaisesRegex(ValueError,'[Pp]ublic.*receipt|obligation'):
                l.advance_given_orders(forged_state,replace(l.depth_orders(),market_clearing=True),l.Controls(public_instructions=self.fiscal(s),household_mode='cash_stock_close_v1'))

    def test_treasury_first_is_conservative_order_not_insolvency_theorem(self):
        a=enabled(treasury_rates_pct=(0,-F(1400,9),0),iorb_rate_pct=F(1600,9))
        before=repr(a)
        with self.assertRaises(l._Failure) as error:journal(a)
        self.assertEqual(error.exception.status,'funding_failure')
        self.assertEqual(repr(a),before)
        # CB-first would have paid A3, allowing its7 coupon. V1 does not net it.
        self.assertEqual(a.reserves('A')+3-7,F(11,4))
        self.assertEqual(a.bank_equity('A')+3-7,F(3,4))

    def test_administered_rate_requires_enabled_book_without_rewriting_old_history(self):
        with self.assertRaises(ValueError):
            l._Transaction(l.initial_depth_reference(),l.PublicIncomeControls(iorb_rate_pct=0),1)
        a=enabled(iorb_rate_pct=1);_,b=journal(a)
        with self.assertRaises(ValueError):replace(b,public_book=replace(b.public_book,terms=replace(b.public_book.terms,iorb_rate_pct=2)))
        before=repr(b);_,d=journal(b,l.PublicIncomeControls(iorb_rate_pct=2))
        self.assertEqual(repr(b),before)
        self.assertEqual(d.public_book.terms.iorb_rate_pct,2)
        self.assertEqual(b.public_book.terms.iorb_rate_pct,1)

if __name__=='__main__':unittest.main()
