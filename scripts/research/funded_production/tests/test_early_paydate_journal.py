"""Bounded fresh-stock raw journal tests, not codec/macro/native adoption."""
from dataclasses import fields, replace
from fractions import Fraction as F
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts.research.funded_production import ledger as l, paydate_households
from scripts.research.funded_production.tests.test_public_paydate_journal import legacy, fiscal

COUNTS=dict(attempts=0,paid=0,refused=0,exceptions=0)


def fixture(*, old=1,old_id="OLD:B",reserve=F(1,10**6),rate=4,early=True,**changes):
    # Fresh Q0 matched legal stocks. Near-zero B reserves, private collateral,
    # positive current equity and an original CB claim due Q1, never migrated Q3.
    state,terms=legacy(reserves=(5,reserve),mortgage_rates=(0,0),cb_rates=(0,rate),**changes)
    if old:
        loan=l.CBLoan(old_id,'B',F(old),0,1,l._pledges(state,'B',F(old)))
        state=replace(state,cb_loans=(loan,),public_book=replace(state.public_book,
            capital_other=state.public_book.capital_other+old))
    factory=l.enable_early_paydate_public if early else l.enable_paydate_public
    return factory(state,terms)


def controls(state,limit=2,**changes):
    values=dict(iorb_rate_pct=0,household_mode='cash_stock_close_v1',
                public_instructions=fiscal(state),facility_limits=(100,limit),security_bids=(0,0))
    values.update(changes)
    return l.PublicIncomeControls(**values)


def attempt(state,finance=None,orders=None):
    path=os.environ.get('FED566_BUDGET_FILE')
    total=json.loads(Path(path).read_text()) if path and Path(path).exists() else dict(COUNTS)
    if total['attempts']>=40:raise AssertionError('Initial 40-attempt raw budget exhausted; preserve evidence.')
    total['attempts']+=1;COUNTS['attempts']+=1
    try:
        out=l.advance_given_orders(state,orders or replace(l.depth_orders(),market_clearing=True,
            investment_units=0),finance or controls(state))
    except Exception:
        total['exceptions']+=1;COUNTS['exceptions']+=1
        if path:Path(path).write_text(json.dumps(total))
        raise
    key='paid' if out.ok else 'refused';total[key]+=1;COUNTS[key]+=1
    if path:Path(path).write_text(json.dumps(total))
    return out


def validate(state,**changes):
    values=dict(book=state.public_book,scale=state.scale,quarter=state.quarter,
                payments=state.last.payments,trace=state.last.trace)
    values.update(changes)
    return l.validate_early_paydate_public(**values)


def synthetic_identity_book(old_id='OLD:B', *, reserve=F(1, 10 ** 6), replacement_id='CB1:B'):
    """Pure complete synthetic monetary stream from the review probes; never an executed quarter."""
    s = fixture(old_id=old_id, reserve=reserve)
    b = s.public_book
    original = l.PaydateSnapshot(reserves=tuple((s.reserves(x) for x in l.BANKS)), wallets=tuple((s.deposit(x) for x in l.ACTORS)), cb_faces=tuple((s.cb_debt(x) for x in l.BANKS)), treasuries=(b.treasuries, *b.private_treasuries), terms=b.terms, mortgages=b.mortgages, rrp_faces=(F(0), F(0)), currency=b.currency, capital_other=b.capital_other, tga=b.tga, deferred=F(0), previous_income=(F(20), F(63, 20)), previous_dividends=(None, None))
    opening = l.FundingOpening(quarter=1, scale=s.scale, terms=original.terms, treasuries=original.treasuries, mortgages=original.mortgages, reserves=original.reserves, household_deposits=original.wallets[2:], cb_faces=original.cb_faces, rrp_faces=original.rrp_faces, tga=original.tga, deferred=original.deferred)
    batch = l.FundingBatch()
    projection = l.public_funding.project_batch(opening, batch)
    principal = replace(original, reserves=projection.reserves, wallets=(*original.wallets[:2], *projection.household_deposits), treasuries=projection.treasuries, terms=projection.terms, mortgages=projection.mortgages, rrp_faces=(F(0), F(0)), tga=projection.tga)
    lines = l.public_income.quote(opening.terms, treasuries=opening.treasuries, mortgages=opening.mortgages, reserves=opening.reserves, cb_faces=opening.cb_faces, rrp_faces=opening.rrp_faces, scale=s.scale)
    assets, equities, capacities = l._early_conditions(principal, s.loans)
    plan = l.early_liquidity.plan(scale=s.scale, reserves=principal.reserves, old_faces=principal.cb_faces, equities=equities, capacities=capacities, facility_limits=(F(100), F(2)), cb_rates_pct=principal.terms.cb_rates_pct, tga=principal.tga, observations=lines)
    new = tuple((l.CBLoan(replacement_id if bank == 'B' else 'CB1:' + bank, bank, face, 1, 2, l._pledges(assets, bank, face)) for bank, face in zip(l.BANKS, plan.replacement_faces) if face))
    witness = l.EarlyCreditWitness(plan, s.cb_loans, s.loans, new)
    payments = []
    trace = []
    phases = []

    def pay(p):
        position = len(payments)
        payments.append(p)
        trace.append(l.Trace(p.kind, p.payer, p.payee, p.amount, p.claim_id))
        trace.append(l.Trace('paydate_payment', p.payer, p.payee, p.amount, p.claim_id, (('payment_kind', p.kind), ('position', position))))

    def phase(name, snap):
        trace.append(l.Trace('paydate_phase', 'journal', name, F(0), details=(('payment_end', len(payments)),)))
        phases.append(l.EarlyPhase(name, len(payments), len(trace), snap))
    phase('opening', original)
    for p in projection.payments:
        pay(l.Payment(*p))
    phase('principal', principal)
    for x in l._early_credit_events(witness, 1, assets.securities_faces):
        if type(x) is l.Payment:
            pay(x)
        else:
            trace.append(x)
    current = replace(principal, reserves=plan.credit_reserves, cb_faces=plan.replacement_faces)
    phase('early_credit', current)
    early = l._paydate_ordered_lines(lines)
    for x in l._paydate_coupon_receipts(early):
        pay(l.Payment(*x))
    current = l._paydate_income_snapshot(current, early)
    phase('early_income', current)
    phase('funded_payroll', current)
    delayed = l._paydate_ordered_lines(lines, household_phase=True)
    for x in l._paydate_coupon_receipts(delayed):
        pay(l.Payment(*x))
    current = l._paydate_income_snapshot(current, delayed)
    phase('household_income', current)
    deferred, remit = l.public_income.earnings_close(opening.deferred, l.public_income.cb_profit(lines))
    if remit:
        pay(l.Payment('CB', 'Treasury', remit, 'cb_remittance'))
    current = replace(current, tga=current.tga + remit, deferred=deferred)
    phase('income_close', current)
    orders = replace(l.depth_orders(), market_clearing=True, residual_workers=0, focal_workers=0, investment_units=0, residual_consumption=0, service_a=0, service_b=0, available_workers=0, cash_floor_r=0, cash_floor_f=0)
    direct = ('price_factor', 'real_wage', 'residual_workers', 'focal_workers', 'investment_units', 'residual_consumption', 'service_a', 'service_b', 'available_workers', 'residual_productivity', 'service_productivity', 'capital_productivity', 'capital_resource_cost', 'cash_floor_r', 'cash_floor_f', 'market_clearing', 'max_clearing_rounds', 'demand_multiplier')
    details = [(n, getattr(orders, n)) for n in direct]
    for owner, prefs in (('a', orders.preferences_a), ('b', orders.preferences_b)):
        details.extend((('preference_' + owner + '_' + n, getattr(prefs, n)) for n in ('residual', 'services', 'cash')))
    details.extend((('expected_a_nominal', None), ('expected_b_nominal', None), ('initial_dividend_a_real', orders.initial_dividends_real[0]), ('initial_dividend_b_real', orders.initial_dividends_real[1])))
    trace.append(l.Trace('production_orders', 'production', 'goods', F(0), details=tuple(details)))
    for i, owner in enumerate(('HA', 'HB')):
        cash = principal.wallets[i + 2]
        prior = original.previous_income[i]
        forecast = orders.initial_dividends_real[i] * s.scale
        ratio = (F(3, 20), F(1, 21))[i]
        budget = paydate_households.cash_stock_budget(opening_cash=cash, paid_wages=0, settled_income=0, previous_income=prior, forecast_income=forecast, cash_ratio=ratio)
        trace.append(l.Trace('household_budget', owner, 'goods', budget.wallet, details=(('mode', 'cash_stock_close_v1'), ('opening_cash', cash), ('paid_wages', F(0)), ('settled_income', F(0)), ('income_previous', prior), ('income_forecast', forecast), ('forecast', forecast), ('forecast_source', 'initial_reference'), ('cash_ratio', ratio), ('adjustment', F(1, 4)), ('desired', budget.desired), ('funded', budget.funded))))
    phase('trading_close', current)
    b = replace(b, treasuries=current.treasuries[0], private_treasuries=current.treasuries[1:], terms=current.terms, tga=current.tga, deferred_asset=current.deferred, income_paid_through=1, opening_deferred_asset=opening.deferred, observations=lines, opening=opening, funding=batch, phases=tuple(phases), early_credit=witness, paid_wages=(F(0), F(0)), household_income=(F(0), F(0)), closing_cb_loans=new, closing_private_loans=s.loans, later_credit=())
    return (s, b, tuple(payments), tuple(trace))

class EarlyPaydateJournalTests(unittest.TestCase):
    def test_exact_separate_fresh_types_and_no_old_entrypoint_admission(self):
        state=fixture();self.assertIs(type(state.public_book),l.EarlyPaydateBook)
        self.assertEqual(state.public_book.phases,())
        self.assertIsNone(state.public_book.early_credit)
        l.validate_early_paydate_public(state.public_book,state.scale,0)
        for validator in (l.validate_paydate_public,l.validate_funded_public):
            with self.assertRaises((TypeError,ValueError)):validator(state.public_book,state.scale,0)
        base,terms=legacy()
        for old in (state,l.enable_paydate_public(base,terms)):
            with self.assertRaises(ValueError):l.enable_early_paydate_public(old,terms)
        self.assertEqual(l.PAYDATE_PHASES,('opening','principal','early_income','funded_payroll',
                                          'household_income','income_close','trading_close'))

    def test_strict_golden_refusal_new_actual_novation_and_original_bases(self):
        old=fixture(early=False);before=repr(old)
        strict=attempt(old);self.assertFalse(strict.ok);self.assertEqual(strict.status,'funding_failure')
        self.assertIs(strict.state,old);self.assertEqual(repr(old),before)
        state=fixture();before=repr(state);out=attempt(state)
        self.assertTrue(out.ok,out.reason);self.assertEqual(repr(state),before)
        book=out.state.public_book;plan=book.early_credit.plan
        self.assertEqual(tuple(p.name for p in book.phases),l.EARLY_PAYDATE_PHASES)
        self.assertEqual(book.observations[8].basis,1)
        self.assertEqual(book.observations[8].settled,F(1,100))
        self.assertEqual(book.observations[6].basis,state.reserves('B'))
        self.assertEqual(plan.refinanced[1],1)
        self.assertEqual(plan.advances[1],F(9999,10**6))
        retire=[n for n in out.state.last.trace if n.kind=='cb_principal_retired' and n.claim_id=='OLD:B']
        self.assertEqual(len(retire),1);self.assertEqual(retire[0].amount,1)
        early=book.phases[2].snapshot
        self.assertEqual(early.cb_faces[1],F(1009999,10**6))
        self.assertEqual(early.reserves[1],F(1,100))
        self.assertEqual(early.wallets,book.phases[1].snapshot.wallets)
        self.assertEqual(early.tga,book.phases[1].snapshot.tga)
        self.assertTrue(all(z.maturity==2 and z.start==1 for z in out.state.cb_loans))
        validate(out.state)
        phase=book.phases[0]
        old_phase=l.PaydatePhase(phase.name,phase.payment_end,phase.trace_end,phase.snapshot)
        with self.assertRaises(TypeError):replace(book,phases=(old_phase,)+book.phases[1:])
        with self.assertRaises(TypeError):replace(old.public_book,phases=(phase,))
        with self.assertRaises(ValueError):l.PaydatePhase('early_credit',0,1,phase.snapshot)
        for factory in (l.enable_early_paydate_public,l.enable_paydate_public):
            with self.assertRaises(ValueError):factory(out.state,state.public_book.terms)

    def test_partial_refinance_cash_retirement_and_original_interest(self):
        state=fixture(reserve=F(3,5))
        out=attempt(state,controls(state,limit=F(1,2)))
        self.assertTrue(out.ok,out.reason)
        plan=out.state.public_book.early_credit.plan
        self.assertEqual(plan.refinanced[1],F(1,2));self.assertEqual(plan.cash_repayments[1],F(1,2))
        self.assertEqual(plan.advances[1],0)
        self.assertEqual(out.state.public_book.observations[8].settled,F(1,100))
        self.assertEqual(sum(p.amount for p in out.state.last.payments
            if p.kind=='cb_cash_repayment' and p.claim_id=='OLD:B'),F(1,2))
        validate(out.state)

    def test_missing_terms_zero_opening_debt_needed_credit_is_unsupported(self):
        state=fixture(old=0,rate=None,reserve=F(1,1000))
        out=attempt(state,controls(state,iorb_rate_pct=-800))
        self.assertFalse(out.ok);self.assertEqual(out.status,'unsupported_public_income');self.assertIs(out.state,state)

    def test_shared_gross_limit_and_collateral_refusal_are_atomic(self):
        for state,limit in ((fixture(),1),(fixture(reserve=0),F(1,2))):
            before=repr(state);out=attempt(state,controls(state,limit=limit))
            self.assertFalse(out.ok);self.assertEqual(out.status,'funding_failure')
            self.assertIs(out.state,state);self.assertEqual(repr(state),before)

    def test_zero_and_negative_fixed_coupon_do_not_charge_new_face(self):
        for rate in (0,-4):
            state=fixture(rate=rate);out=attempt(state)
            self.assertTrue(out.ok,out.reason)
            self.assertEqual(out.state.public_book.early_credit.plan.advances,(0,0))
            self.assertEqual(out.state.public_book.observations[8].settled,F(rate,400))
            validate(out.state)

    def test_next_date_original_interest_uses_actual_new_opening_face(self):
        state=fixture();out=attempt(state);self.assertTrue(out.ok,out.reason)
        state=out.state;face=state.cb_debt('B')
        out=attempt(state,controls(state,limit=100))
        self.assertTrue(out.ok,out.reason)
        self.assertEqual(out.state.public_book.observations[8].basis,face)
        self.assertEqual(sum(n.amount for n in out.state.last.trace
            if n.kind=='cb_principal_retired' and n.claim_id=='CB1:B'),face)
        validate(out.state)

    def test_tampered_credit_plan_pledges_receipts_and_phase_order_reject(self):
        out=attempt(fixture());self.assertTrue(out.ok,out.reason);state=out.state
        book=state.public_book;w=book.early_credit
        variants=(replace(book,early_credit=replace(w,plan=replace(w.plan,advances=(0,0)))),
            replace(book,early_credit=replace(w,replacement_loans=())),
            replace(book,phases=(book.phases[0],book.phases[2],book.phases[1])+book.phases[3:]))
        for changed in variants:
            with self.assertRaises((TypeError,ValueError)):validate(state,book=changed)
        for kind in ('cb_draw','cb_loan_coupon'):
            payments=tuple(p for p in state.last.payments if p.kind!=kind)
            with self.assertRaises(ValueError):validate(state,payments=payments)
        trace=tuple(replace(n,amount=n.amount+1) if n.kind=='facility_applied' else n for n in state.last.trace)
        with self.assertRaises(ValueError):validate(state,trace=trace)
        # Metadata must reject before callbacks/equality, not adopt a supplied schema.
        calls=[]
        class Schema(dict):
            def values(self):calls.append('schema');return super().values()
        object.__setattr__(w.plan,'__dataclass_fields__',Schema(type(w.plan).__dataclass_fields__))
        with self.assertRaises((TypeError,ValueError)):validate(state)
        self.assertEqual(calls,[])

    def test_later_private_funding_shares_not_replenishes_gross_limit(self):
        for limit,paid in ((2,False),(4,True)):
            state=fixture()
            finance=controls(state,limit=limit,new_loans=(l.LoanOffer('B',2,0,2,borrower='R'),))
            out=attempt(state,finance)
            self.assertEqual(out.ok,paid,out.reason)
            if paid:
                validate(out.state)
                gross=sum(n.amount for n in out.state.last.trace
                          if n.kind=='facility_applied' and n.actor=='B')
                self.assertGreater(gross,out.state.public_book.early_credit.plan.gross_used[1])
                self.assertLessEqual(gross,limit)
                book=out.state.public_book
                self.assertTrue(book.later_credit)
                witness=book.later_credit[0]
                variants=(replace(book,later_credit=()),replace(book,later_credit=(
                    replace(witness,gross_before=0),)+book.later_credit[1:]),
                    replace(book,later_credit=(replace(witness,new_loan=replace(witness.new_loan,
                        collateral=())),)+book.later_credit[1:]))
                for changed in variants:
                    with self.assertRaises((TypeError,ValueError)):validate(out.state,book=changed)
                trace=tuple(replace(n,details=tuple((k,v+1 if k=='capacity' else v)
                    for k,v in n.details)) if n.kind=='facility_applied' else n
                    for n in out.state.last.trace)
                with self.assertRaises(ValueError):validate(out.state,trace=trace)
            else:
                self.assertEqual(out.status,'funding_failure');self.assertIs(out.state,state)

    def test_actual_collateral_and_positive_equity_not_projected_income(self):
        from scripts.research.funded_production.tests.test_public_paydate_journal import pools
        for cash in (0,1):
            state=fixture(old=0,faces=pools({5:20},{5:18},{}),firms=(17,cash),households=(3,0))
            loans=tuple(replace(z,allowance=F(35,4)) for z in state.loans)
            state=replace(state,loans=loans)
            old=l.CBLoan('OLD:B','B',1,0,1,l._pledges(state,'B',1))
            state=replace(state,cb_loans=(old,),public_book=replace(state.public_book,
                capital_other=state.public_book.capital_other+1))
            self.assertEqual(l.HAIRCUT_VALUE*(state.securities('B')+l._private_collateral(state,'B')),1)
            self.assertEqual(state.bank_equity('B')>0,not bool(cash))
            before=repr(state);out=attempt(state)
            self.assertFalse(out.ok);self.assertEqual(out.status,'funding_failure')
            self.assertIs(out.state,state);self.assertEqual(repr(state),before)

    def test_partial_treasury_roll_keeps_original_cb_iorb_bases(self):
        from scripts.research.funded_production.tests.test_public_paydate_journal import pools
        state=fixture(faces=pools({5:20},{5:18},{0:1}))
        command=l.FundedPublicInstructions(treasury_rolls=(0,0,F(1,2)),treasury_issue_authorization=F(1,2))
        out=attempt(state,controls(state,public_instructions=command,iorb_rate_pct=4))
        self.assertTrue(out.ok,out.reason);validate(out.state)
        book=out.state.public_book
        self.assertEqual(book.phases[1].snapshot.reserves[1],F(500001,10**6))
        self.assertEqual(book.observations[6].basis,F(1,10**6))
        self.assertEqual(book.observations[8].basis,1)
        self.assertEqual(book.early_credit.plan.advances[1],0)

    def test_unpaired_extra_facility_or_retirement_metadata_is_not_actual_credit(self):
        # Pure validator-unit fixture, NOT an executed/saved quarter: reproduce
        # an exact early-event recipe and append an unpaired later metadata note.
        state=fixture();book=state.public_book
        observations=l.public_income.quote(book.terms,
            treasuries=(book.treasuries,*book.private_treasuries),mortgages=book.mortgages,
            reserves=tuple(state.reserves(b) for b in l.BANKS),
            cb_faces=tuple(state.cb_debt(b) for b in l.BANKS),rrp_faces=(0,0),scale=state.scale)
        plan=l.early_liquidity.plan(scale=state.scale,
            reserves=tuple(state.reserves(b) for b in l.BANKS),old_faces=(0,1),
            equities=tuple(state.bank_equity(b) for b in l.BANKS),
            capacities=tuple(l.HAIRCUT_VALUE*(state.securities(b)+l._private_collateral(state,b))
                             for b in l.BANKS),facility_limits=(100,3),cb_rates_pct=(0,4),
            tga=book.tga,observations=observations)
        replacements=tuple(l.CBLoan('CB1:'+bank,bank,face,1,2,l._pledges(state,bank,face))
                           for bank,face in zip(l.BANKS,plan.replacement_faces) if face)
        witness=l.EarlyCreditWitness(plan,state.cb_loans,state.loans,replacements)
        trace=[];position=0
        for event in l._early_credit_events(witness,1,tuple(state.securities(b) for b in l.BANKS)):
            if type(event) is l.Trace:trace.append(event)
            else:
                trace.extend((l.Trace(event.kind,event.payer,event.payee,event.amount,event.claim_id),
                    l.Trace('paydate_payment',event.payer,event.payee,event.amount,event.claim_id,
                            (('payment_kind',event.kind),('position',position)))))
                position+=1
        trace.append(l.Trace('boundary','journal','early_credit',0))
        snapshot=l.PaydateSnapshot(reserves=plan.credit_reserves,
            wallets=tuple(state.deposit(a) for a in l.ACTORS),cb_faces=plan.replacement_faces,
            treasuries=(book.treasuries,*book.private_treasuries),terms=book.terms,
            mortgages=book.mortgages,rrp_faces=(0,0),currency=book.currency,
            capital_other=book.capital_other,tga=book.tga,deferred=0,
            previous_income=(20,F(63,20)),previous_dividends=(None,None))
        opening=l.FundingOpening(quarter=1,scale=state.scale,terms=book.terms,
            treasuries=snapshot.treasuries,cb_faces=(0,1))
        phases=tuple(l.EarlyPhase(name,0,len(trace) if name=='early_credit' else 1,snapshot)
                     for name in ('opening','principal','early_credit'))
        asserted=replace(book,income_paid_through=1,observations=observations,opening=opening,
                         early_credit=witness,phases=phases,closing_cb_loans=replacements)
        l._validate_early_gross_usage(asserted,tuple(trace))
        extra=(l.Trace('facility_applied','B','CB',1,'CB1:B',
                       (('offered',F(3)),('gross_applied',plan.gross_used[1]+1),('capacity',F(100)))),
               l.Trace('cb_principal_retired','B','CB',1,'OLD:B',
                       (('net_cash_repaid',F(1)),('refinanced',F(0)))))
        for note in extra:
            with self.assertRaises(ValueError):l._validate_early_gross_usage(asserted,tuple(trace)+(note,))

    def test_pure_closing_identity_must_retain_witnessed_origin(self):
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('Pure only')) as raw:
            with patch.object(l,'_Transaction',side_effect=AssertionError('Pure only')) as tx:
                state,book,payments,trace=synthetic_identity_book()
                l.validate_early_paydate_public(book,state.scale,1,payments,trace)
                forged=replace(book,closing_cb_loans=tuple(replace(z,id='RENAMED-CLOSING')
                                                           for z in book.closing_cb_loans))
                with self.assertRaises(ValueError):
                    l.validate_early_paydate_public(forged,state.scale,1,payments,trace)
                self.assertEqual((raw.call_count,tx.call_count),(0,0))

    def test_pure_later_repayment_identity_must_retain_witnessed_origin(self):
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('Pure only')) as raw:
            with patch.object(l,'_Transaction',side_effect=AssertionError('Pure only')) as tx:
                state,book,payments,trace=synthetic_identity_book(reserve=F(3,5))
                amount=F(1,1000);closing=book.phases[-1].snapshot
                snapshot=replace(closing,reserves=(closing.reserves[0],closing.reserves[1]-amount),
                                 cb_faces=(closing.cb_faces[0],closing.cb_faces[1]-amount))
                old=book.closing_cb_loans[0]
                assets=l._EarlyAssets(book.closing_private_loans,
                    tuple(sum(row,F(0)) for row in snapshot.treasuries[1:]))
                new=replace(old,face=old.face-amount,collateral=l._pledges(assets,'B',old.face-amount))
                for claim in (old.id,'NOT-A-REAL-CB-CLAIM'):
                    p=l.Payment('B','CB',amount,'cb_collateral_prepayment',claim)
                    additions=(l.Trace(p.kind,p.payer,p.payee,p.amount,p.claim_id),
                        l.Trace('paydate_payment',p.payer,p.payee,p.amount,p.claim_id,
                            (('payment_kind',p.kind),('position',len(payments)))),
                        l.Trace('cb_early_principal_retired','B','CB',amount,claim,(('remaining',new.face),)))
                    notes=trace[:-1]+additions+(replace(trace[-1],details=(('payment_end',len(payments)+1),)),)
                    end=replace(book.phases[-1],payment_end=len(payments)+1,
                                trace_end=len(notes),snapshot=snapshot)
                    changed=replace(book,phases=book.phases[:-1]+(end,),closing_cb_loans=(new,))
                    if claim==old.id:
                        l.validate_early_paydate_public(changed,state.scale,1,payments+(p,),notes)
                    else:
                        with self.assertRaises(ValueError):
                            l.validate_early_paydate_public(changed,state.scale,1,payments+(p,),notes)
                self.assertEqual((raw.call_count,tx.call_count),(0,0))

    def test_pure_replacement_identity_cannot_reuse_any_original_id(self):
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('Pure only')) as raw:
            with patch.object(l,'_Transaction',side_effect=AssertionError('Pure only')) as tx:
                state,book,payments,trace=synthetic_identity_book(old_id='CB1:B')
                with self.assertRaises(ValueError):
                    l.validate_early_paydate_public(book,state.scale,1,payments,trace)
                state,book,payments,trace=synthetic_identity_book(old_id='CB1:B',replacement_id='CB1:B:new')
                l.validate_early_paydate_public(book,state.scale,1,payments,trace)
                self.assertEqual(book.early_credit.old_loans[0].id,'CB1:B')
                self.assertEqual(book.closing_cb_loans[0].id,'CB1:B:new')
                self.assertEqual((raw.call_count,tx.call_count),(0,0))

    def test_actual_collision_allocates_fresh_id_and_preserves_original_history(self):
        state=fixture(old_id='CB1:B');before=repr(state)
        out=attempt(state);self.assertTrue(out.ok,out.reason);validate(out.state)
        book=out.state.public_book
        self.assertEqual(book.early_credit.old_loans[0].id,'CB1:B')
        self.assertEqual(book.early_credit.replacement_loans[0].id,'CB1:B:new')
        self.assertEqual(book.closing_cb_loans[0].id,'CB1:B:new')
        self.assertEqual(repr(state),before)
        retirement=tuple(n for n in out.state.last.trace if n.kind=='cb_principal_retired')
        self.assertEqual(tuple(n.claim_id for n in retirement),('CB1:B',))
        current=tuple(n.claim_id for n in out.state.last.trace if n.kind=='facility_applied')
        self.assertTrue(current);self.assertTrue(all(n=='CB1:B:new' for n in current))

    def test_actual_fully_cash_repaid_old_id_remains_reserved_for_later_draw(self):
        from scripts.research.funded_production.tests.test_public_paydate_journal import pools
        state=fixture(old_id='CB1:B',reserve=F(11,10),firms=(17,F(101,5)),households=(3,0),
                      masses=pools({}, {}, {5:8}))
        self.assertLess(state.bank_equity('B'),0)
        finance=controls(state,limit=100,new_loans=(l.LoanOffer('B',3,0,2,borrower='R'),))
        out=attempt(state,finance);self.assertTrue(out.ok,out.reason);validate(out.state)
        book=out.state.public_book
        self.assertEqual(book.early_credit.plan.cash_repayments[1],1)
        self.assertEqual(book.early_credit.plan.refinanced[1],0)
        self.assertEqual(book.early_credit.replacement_loans,())
        self.assertTrue(book.later_credit)
        self.assertIsNone(book.later_credit[0].old_loan)
        self.assertEqual(book.later_credit[0].new_loan.id,'CB1:B:new')
        self.assertEqual(book.closing_cb_loans[0].id,'CB1:B:new')
        self.assertEqual(sum(p.amount for p in out.state.last.payments
            if p.kind=='cb_cash_repayment' and p.claim_id=='CB1:B'),1)

    def test_pure_id_allocator_reserves_all_original_ids_and_suffixes(self):
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('Pure only')) as raw:
            with patch.object(l,'_Transaction',side_effect=AssertionError('Pure only')) as tx:
                state=fixture()
                original=(replace(state.cb_loans[0],bank='A',id='CB1:B',collateral=l._pledges(state,'A',1)),
                          replace(state.cb_loans[0],id='CB1:B:new'))
                before=repr(original)
                self.assertEqual(l._early_cb_id(1,'B',original),'CB1:B:new:new')
                self.assertEqual(l._early_cb_id(1,'A',original),'CB1:A')
                self.assertEqual(l._early_cb_id(1,'B',()),'CB1:B')
                self.assertEqual(repr(original),before)
                self.assertEqual((raw.call_count,tx.call_count),(0,0))

    def test_actual_collateral_repayment_is_bound_to_fresh_current_cohort(self):
        from scripts.research.funded_production.tests.test_public_paydate_journal import rebound_receipts
        state=fixture(old=15,old_id='CB1:B',reserve=20,firms=(17,11))
        state=replace(state,loans=tuple(replace(z,maturity=1) for z in state.loans))
        out=attempt(state,controls(state,limit=20));self.assertTrue(out.ok,out.reason);validate(out.state)
        claims=tuple((i,p) for i,p in enumerate(out.state.last.payments)
                     if p.kind=='cb_collateral_prepayment')
        self.assertTrue(claims)
        self.assertTrue(all(p.claim_id=='CB1:B:new' for _,p in claims))
        self.assertTrue(all(z.id=='CB1:B:new' for z in out.state.cb_loans))
        index,original=claims[0]
        forged=replace(original,claim_id='NOT-A-REAL-CB-CLAIM')
        payments,trace=rebound_receipts(out.state.last.payments,out.state.last.trace,{index:forged})
        trace=tuple(replace(n,claim_id=forged.claim_id) if n.kind=='cb_early_principal_retired'
                    and n.claim_id==original.claim_id else n for n in trace)
        with self.assertRaises(ValueError):validate(out.state,payments=payments,trace=trace)

    def test_prior_actual_witness_rejected_before_current_rate_or_transaction(self):
        out=attempt(fixture());self.assertTrue(out.ok,out.reason)
        state=out.state
        report=replace(state.last,trace=state.last.trace[1:])
        object.__setattr__(state,'last',report)
        before=repr(state)
        with patch.object(l,'_Transaction',side_effect=AssertionError('Prior witness must reject first')) as tx:
            with self.assertRaises(ValueError):attempt(state,controls(state,iorb_rate_pct=-4))
            self.assertEqual(tx.call_count,0)
        self.assertEqual(repr(state),before)


if __name__=='__main__':unittest.main()
