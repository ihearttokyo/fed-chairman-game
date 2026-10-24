"""Fresh hand cases: initial SIXTEEN raw calls, separate EIGHT-call repair wave.

Paid witnesses are reused for adversarial checks, never converted old books.
This is not the aging/fixed-one experiment or recovery/native qualification.
"""
from contextlib import contextmanager
from dataclasses import fields, replace
from fractions import Fraction as F
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts.research.funded_production import ledger as l, macro as m, paydate_households
from scripts.research.funded_production.tests.test_public_paydate_journal import legacy, fiscal, pools


COUNTS = dict(attempts=0, paid=0, refused=0, raw_exceptions=0,
              transactions=0, macro_close_calls=0, macro_closes=0, macro_exceptions=0)

FIX_COUNTS = dict(COUNTS)


def fixture(*, old=1, old_id='CB1:B', reserve=F(1, 10**6), rate=4,
            cb_rate=4, convention='household', nonperforming=False, **changes):
    values = dict(reserves=(5, reserve), households=(3, 2),
                  mortgage_rates=(0, rate), cb_rates=(0, cb_rate))
    values.update(changes)
    state, terms = legacy(**values)
    if nonperforming:
        state = replace(state, loans=tuple(replace(loan, performing=False) for loan in state.loans))
    if old:
        claim = l.CBLoan(old_id, 'B', F(old), 0, 1, l._pledges(state, 'B', F(old)))
        state = replace(state, cb_loans=(claim,), public_book=replace(state.public_book,
            capital_other=state.public_book.capital_other+old))
    if convention == 'early': return l.enable_early_paydate_public(state, terms)
    if convention != 'household': raise ValueError('Unknown test convention')
    return l.enable_household_liquidity_public(state, terms)


def controls(state, *, limit=100, **changes):
    values = dict(iorb_rate_pct=0, household_mode='cash_stock_close_v1',
                  facility_limits=(100, limit), public_instructions=fiscal(state), security_bids=(0, 0))
    values.update(changes)
    return l.PublicIncomeControls(**values)


@contextmanager
def counted_actual(*, fix=False):
    raw = l.advance_given_orders; transaction = l._Transaction; close = m._close_paid
    counts = FIX_COUNTS if fix else COUNTS
    cap = 8 if fix else 16
    def increment(key):
        path = os.environ.get('FED569_FIX_BUDGET_FILE' if fix else 'FED569_BUDGET_FILE')
        total = json.loads(Path(path).read_text()) if path and Path(path).exists() else dict(counts)
        if key == 'attempts' and total[key] >= cap:
            raise AssertionError('Bounded actual attempts exhausted; preserve evidence.')
        total[key] += 1; counts[key] += 1
        if path: Path(path).write_text(json.dumps(total))
    def called(*args, **kwargs):
        increment('attempts')
        try: result = raw(*args, **kwargs)
        except Exception:
            increment('raw_exceptions'); raise
        increment('paid' if result.ok else 'refused')
        return result
    def constructed(*args, **kwargs):
        increment('transactions')
        return transaction(*args, **kwargs)
    def closed(*args, **kwargs):
        increment('macro_close_calls')
        try: result = close(*args, **kwargs)
        except Exception:
            increment('macro_exceptions'); raise
        if result.ok: increment('macro_closes')
        return result
    with patch.object(l, 'advance_given_orders', side_effect=called), \
         patch.object(l, '_Transaction', side_effect=constructed), \
         patch.object(m, '_close_paid', side_effect=closed):
        yield


def attempt(state, finance=None, orders=None):
    with counted_actual():
        return l.advance_given_orders(state,
            orders or replace(l.depth_orders(), market_clearing=True, investment_units=0),
            finance or controls(state))


def validate(state, **changes):
    values = dict(book=state.public_book, scale=state.scale, quarter=state.quarter,
                  payments=state.last.payments, trace=state.last.trace)
    values.update(changes)
    return l.validate_household_liquidity_public(**values)


def synthetic_household_book(*, preadvance=F(0), fake_private=False, future_private=False, pending_private=False, pending_face=2, early_delivery=False, **fixture_changes):
    """Pure asserted validator stream, never an actual quarter or approval."""
    s=fixture(**fixture_changes);b=s.public_book
    original=l.PaydateSnapshot(reserves=tuple(s.reserves(x) for x in l.BANKS),
        wallets=tuple(s.deposit(x) for x in l.ACTORS),cb_faces=tuple(s.cb_debt(x) for x in l.BANKS),
        treasuries=(b.treasuries,*b.private_treasuries),terms=b.terms,mortgages=b.mortgages,
        rrp_faces=(F(0),F(0)),currency=b.currency,capital_other=b.capital_other,tga=b.tga,deferred=F(0),
        previous_income=(F(20),F(63,20)),previous_dividends=(None,None))
    opening=l.FundingOpening(quarter=1,scale=s.scale,terms=original.terms,treasuries=original.treasuries,
        mortgages=original.mortgages,reserves=original.reserves,household_deposits=original.wallets[2:],
        cb_faces=original.cb_faces,rrp_faces=original.rrp_faces,tga=original.tga,deferred=original.deferred)
    batch=l.FundingBatch();projection=l.public_funding.project_batch(opening,batch)
    principal=replace(original,reserves=projection.reserves,wallets=(*original.wallets[:2],*projection.household_deposits),
        treasuries=projection.treasuries,terms=projection.terms,mortgages=projection.mortgages,tga=projection.tga)
    lines=l.public_income.quote(opening.terms,treasuries=opening.treasuries,mortgages=opening.mortgages,
        reserves=opening.reserves,cb_faces=opening.cb_faces,rrp_faces=opening.rrp_faces,scale=s.scale)
    assets,eq,cap=l._early_conditions(principal,s.loans)
    plan=l.early_liquidity.plan(scale=s.scale,reserves=principal.reserves,old_faces=principal.cb_faces,
        equities=eq,capacities=cap,facility_limits=(F(100),F(100)),cb_rates_pct=principal.terms.cb_rates_pct,tga=principal.tga,observations=lines)
    active=tuple(l.CBLoan(l._early_cb_id(1,bank,s.cb_loans),bank,face,1,2,l._pledges(assets,bank,face))
                 for bank,face in zip(l.BANKS,plan.replacement_faces) if face)
    early=l.EarlyCreditWitness(plan,s.cb_loans,s.loans,active)
    payments=[];trace=[];phases=[];later=[]
    def pay(p):
        position=len(payments);payments.append(p)
        trace.extend((l.Trace(p.kind,p.payer,p.payee,p.amount,p.claim_id),
            l.Trace('paydate_payment',p.payer,p.payee,p.amount,p.claim_id,(('payment_kind',p.kind),('position',position)))))
    def phase(name,snapshot):
        trace.append(l.Trace('paydate_phase','journal',name,F(0),details=(('payment_end',len(payments)),)))
        phases.append(l.HouseholdLiquidityPhase(name,len(payments),len(trace),snapshot))
    phase('opening',original)
    for p in projection.payments:pay(l.Payment(*p))
    phase('principal',principal)
    for event in l._early_credit_events(early,1,assets.securities_faces):
        if type(event) is l.Payment:pay(event)
        else:trace.append(event)
    current=replace(principal,reserves=plan.credit_reserves,cb_faces=plan.replacement_faces)
    phase('early_credit',current)
    nonhh=l._paydate_ordered_lines(lines)
    for receipt in l._paydate_coupon_receipts(nonhh):pay(l.Payment(*receipt))
    current=l._paydate_income_snapshot(current,nonhh);phase('early_income',current)
    def draw(bank,amount,private,transit=(F(0),F(0))):
        nonlocal current,active
        if not amount:return
        index=l.BANKS.index(bank);view,eq,cap=l._early_conditions(current,private)
        old=next((loan for loan in active if loan.bank==bank),None)
        new=l.CBLoan(l._early_cb_id(1,bank,s.cb_loans),bank,current.cb_faces[index]+amount,1,2,l._pledges(view,bank,current.cb_faces[index]+amount))
        used=sum((n.amount for n in trace if n.kind=='facility_applied' and n.actor==bank),F(0))
        witness=l.LaterCreditWitness(bank,len(payments),len(trace),current,private,transit,old,F(100),used,amount,new)
        receipt=l.Payment('CB',bank,amount,'cb_draw',new.id);pay(receipt)
        trace.append(l.Trace('facility_applied',bank,'CB',amount,new.id,(('offered',F(100)),('gross_applied',used+amount),('capacity',cap[index]))))
        for pledge in new.collateral:
            trace.append(l.Trace('collateral_pledged',bank,'CB',pledge.face,pledge.claim_id,(('kind_of_asset',pledge.kind),)))
        later.append(witness);current,_=l._paydate_private_snapshot(current,receipt,(),0,s.scale)
        active=tuple(z for z in active if z.bank!=bank)+(new,)
    delivered=s.loans
    pending=l.Loan('PENDING','B',pending_face,0,3,0,0,borrower='R') if pending_private else None
    if pending is not None:
        trace.append(l.Trace('household_private_pending','B','R',pending.face,pending.id,
            (('old_id',None),('claim_type','loan'),('rate_pct',pending.rate_pct),
             ('maturity',pending.maturity),('start',pending.start),('last_coupon_paid',pending.last_coupon_paid),
             ('allowance',pending.allowance),('performing',pending.performing))))
        trace.append(l.Trace('loan_deposit_created','B','R',pending.face,pending.id))
        delivered=(*delivered,pending)
    claimed=delivered
    if fake_private:
        claimed=(*claimed,l.Loan('UNRECORDED-PHANTOM','B',F(20),F(0),2,0,0,borrower='F'))
    future = l.ProjectLoan('FUTURE', 'B', 50, 0, 2, 0, 0, borrower='F') if future_private else None
    if future is not None: claimed = (*claimed, future)
    if pending is not None and early_delivery:
        trace.append(l.Trace('reserve_settlement','B','A',pending.face,pending.id,(('purpose','loan_origination'),)))
        trace.append(l.Trace('loan_deposit_delivered','B','R',pending.face,pending.id))
    draw('B',preadvance,claimed,(F(0),pending.face) if pending is not None and not early_delivery else (F(0),F(0)))
    if pending is not None:
        if not early_delivery:
            trace.append(l.Trace('reserve_settlement','B','A',pending.face,pending.id,(('purpose','loan_origination'),)))
            trace.append(l.Trace('loan_deposit_delivered','B','R',pending.face,pending.id))
        receipt=l.Payment('BankB','R',pending.face,'loan_origination',pending.id);pay(receipt)
        trace.append(l.Trace('matching_loan_created','B','R',pending.face,pending.id,
            (('maturity',pending.maturity),('start',pending.start),('rate_pct',pending.rate_pct))))
        trace.append(l._household_private_origin(pending))
        current,_=l._paydate_private_snapshot(current,receipt,(),0,s.scale)
    phase('funded_payroll',current)
    _,eq,cap=l._early_conditions(current,delivered)
    gross=tuple(sum((n.amount for n in trace if n.kind=='facility_applied' and n.actor==bank),F(0)) for bank in l.BANKS)
    hhplan=l.early_liquidity.household_plan(scale=s.scale,reserves=current.reserves,household_deposits=current.wallets[2:],
        cb_faces=current.cb_faces,equities=eq,capacities=cap,facility_limits=plan.facility_limits,gross_used=gross,
        cb_rates_pct=current.terms.cb_rates_pct,observations=lines)
    household=l.HouseholdLiquidityWitness(hhplan,delivered)
    for bank,amount in zip(l.BANKS,hhplan.advances):draw(bank,amount,delivered)
    phase('household_credit',current)
    hh=l._paydate_ordered_lines(lines,household_phase=True)
    for receipt in l._paydate_coupon_receipts(hh):pay(l.Payment(*receipt))
    current=l._paydate_income_snapshot(current,hh);phase('household_income',current)
    deferred,remit=l.public_income.earnings_close(opening.deferred,l.public_income.cb_profit(lines))
    if remit:pay(l.Payment('CB','Treasury',remit,'cb_remittance'))
    current=replace(current,tga=current.tga+remit,deferred=deferred);phase('income_close',current)
    orders=replace(l.depth_orders(),market_clearing=True,residual_workers=0,focal_workers=0,investment_units=0,
        residual_consumption=0,service_a=0,service_b=0,available_workers=0,cash_floor_r=0,cash_floor_f=0)
    direct=('price_factor','real_wage','residual_workers','focal_workers','investment_units','residual_consumption','service_a','service_b','available_workers','residual_productivity','service_productivity','capital_productivity','capital_resource_cost','cash_floor_r','cash_floor_f','market_clearing','max_clearing_rounds','demand_multiplier')
    details=[(name,getattr(orders,name)) for name in direct]
    for owner,prefs in (('a',orders.preferences_a),('b',orders.preferences_b)):
        details.extend(('preference_'+owner+'_'+name,getattr(prefs,name)) for name in ('residual','services','cash'))
    details.extend((('expected_a_nominal',None),('expected_b_nominal',None),('initial_dividend_a_real',orders.initial_dividends_real[0]),('initial_dividend_b_real',orders.initial_dividends_real[1])))
    trace.append(l.Trace('production_orders','production','goods',F(0),details=tuple(details)))
    incomes=tuple(-z.settled for z in lines[3:5])
    for i,owner in enumerate(('HA','HB')):
        cash=principal.wallets[i+2];prior=original.previous_income[i];forecast=orders.initial_dividends_real[i]*s.scale
        expected=forecast+incomes[i];ratio=(F(3,20),F(1,21))[i]
        budget=paydate_households.cash_stock_budget(opening_cash=cash,paid_wages=0,settled_income=incomes[i],previous_income=prior,forecast_income=expected,cash_ratio=ratio)
        trace.append(l.Trace('household_budget',owner,'goods',budget.wallet,details=(('mode','cash_stock_close_v1'),
            ('opening_cash',cash),('paid_wages',F(0)),('settled_income',incomes[i]),('income_previous',prior),
            ('income_forecast',expected),('forecast',forecast),('forecast_source','initial_reference'),
            ('cash_ratio',ratio),('adjustment',F(1,4)),('desired',budget.desired),('funded',budget.funded))))
    closing = delivered
    if future is not None:
        # Creation really occurs only here, AFTER household settlement.
        trace.append(l.Trace('household_private_pending', future.lender, future.borrower,
            future.face, future.id, (('old_id', None), ('claim_type', 'project'),
            ('rate_pct', future.rate_pct), ('maturity', future.maturity), ('start', future.start),
            ('last_coupon_paid', future.last_coupon_paid), ('allowance', future.allowance),
            ('performing', future.performing))))
        trace.extend((l.Trace('loan_deposit_created','B','F',future.face,future.id),
                      l.Trace('loan_deposit_delivered','B','F',future.face,future.id)))
        receipt=l.Payment('BankB','F',future.face,'loan_origination',future.id);pay(receipt)
        trace.append(l.Trace('matching_loan_created','B','F',future.face,future.id,
            (('maturity',future.maturity),('start',future.start),('rate_pct',future.rate_pct))))
        trace.append(l._household_private_origin(future))
        current,_=l._paydate_private_snapshot(current,receipt,(),0,s.scale)
        closing=(*delivered, future)
    phase('trading_close',current)
    book=replace(b,treasuries=current.treasuries[0],private_treasuries=current.treasuries[1:],terms=current.terms,tga=current.tga,
        deferred_asset=current.deferred,income_paid_through=1,opening_deferred_asset=opening.deferred,observations=lines,
        opening=opening,funding=batch,phases=tuple(phases),early_credit=early,paid_wages=(F(0),F(0)),household_income=incomes,
        closing_cb_loans=active,closing_private_loans=closing,later_credit=tuple(later),household_credit=household)
    return s,book,tuple(payments),tuple(trace)


class HouseholdDrawHistoryPureTests(unittest.TestCase):
    """Complete synthetic streams: consistency only, ZERO actual execution."""
    def setUp(self):
        self.raw = patch.object(l, 'advance_given_orders', side_effect=AssertionError('No replay')).start()
        self.tx = patch.object(l, '_Transaction', side_effect=AssertionError('No Transaction')).start()
        self.close = patch.object(m, '_close_paid', side_effect=AssertionError('No macro')).start()
        self.addCleanup(patch.stopall)

    def tearDown(self):
        self.assertEqual((self.raw.call_count, self.tx.call_count, self.close.call_count), (0, 0, 0))

    def check(self, stream):
        state, book, payments, trace = stream
        l.validate_household_liquidity_public(book, state.scale, 1, payments, trace)

    def test_legitimate_created_but_undelivered_claim_is_asset_and_transit_liability(self):
        stream=synthetic_household_book(preadvance=2,pending_private=True)
        self.check(stream)
        state,book,payments,trace=stream; w=book.later_credit[0]
        self.assertEqual(w.private_loans[-1].id,'PENDING')
        self.assertEqual(w.transit_deposits,(0,2))
        created=next(i for i,n in enumerate(trace) if n.kind=='loan_deposit_created')
        delivered=next(i for i,n in enumerate(trace) if n.kind=='loan_deposit_delivered')
        self.assertLess(created,w.trace_start); self.assertLess(w.trace_start,delivered)
        for transit in ((0,0),(0,1),(1,2)):
            changed=replace(w,transit_deposits=transit)
            with self.assertRaisesRegex(ValueError,'chronological'):
                self.check((state,replace(book,later_credit=(changed,*book.later_credit[1:])),payments,trace))

    def test_real_pending_asset_cannot_erase_its_lender_transit_liability(self):
        state,book,payments,trace=synthetic_household_book(old=0,reserve=0,rate=0,
            firms=(17,30),preadvance=20,pending_private=True,pending_face=20)
        w=book.later_credit[0]
        self.assertEqual(l._early_conditions(w.snapshot,w.private_loans)[1][1],8)
        self.assertEqual(w.transit_deposits,(0,20))
        # Exact pending history is not approval: net equity remains -12.
        with self.assertRaisesRegex(ValueError,'equity'):
            self.check((state,book,payments,trace))
        erased=replace(w,transit_deposits=(0,0))
        with self.assertRaisesRegex(ValueError,'chronological'):
            self.check((state,replace(book,later_credit=(erased,*book.later_credit[1:])),payments,trace))

    def test_nested_loan_metadata_and_boolean_field_aliases_reject_without_callbacks(self):
        state,book,payments,trace=synthetic_household_book(preadvance=2,pending_private=True)
        self.check((state,book,payments,trace)); w=book.later_credit[0]
        for field,value in (('performing',1),('start',False),('rate_pct',True),('__dataclass_fields__',{})):
            loan=replace(w.private_loans[-1]);object.__setattr__(loan,field,value)
            changed=replace(w,private_loans=(*w.private_loans[:-1],loan))
            with self.assertRaises((TypeError,ValueError)):
                self.check((state,replace(book,later_credit=(changed,*book.later_credit[1:])),payments,trace))
        loan=replace(book.household_credit.private_loans[-1]);object.__setattr__(loan,'performing',1)
        altered=replace(book,household_credit=replace(book.household_credit,
            private_loans=(*book.household_credit.private_loans[:-1],loan)))
        with self.assertRaises((TypeError,ValueError)):self.check((state,altered,payments,trace))

    def test_future_origination_is_legal_only_after_its_actual_creation(self):
        self.check(synthetic_household_book(future_private=True))

    def test_pending_markers_missing_reordered_or_boolean_fields_reject(self):
        state,book,payments,trace=synthetic_household_book(preadvance=2,pending_private=True)
        self.check((state,book,payments,trace))
        index=next(i for i,n in enumerate(trace) if n.kind=='household_private_pending')
        marker=trace[index]; values=dict(marker.details)
        for key,value in (('start',False),('rate_pct',False),('performing',1),('old_id',False)):
            data={**values,key:value}
            note=replace(marker,details=tuple(data.items()))
            with self.assertRaises((TypeError,ValueError)):
                self.check((state,book,payments,(*trace[:index],note,*trace[index+1:])))
        for changes in (
            {index:replace(marker,kind='unrecorded_pending')},
            {index:trace[index+1],index+1:marker},
            {index:replace(marker,details=marker.details[::-1])}):
            altered=tuple(changes.get(i,n) for i,n in enumerate(trace))
            with self.assertRaises((TypeError,ValueError)): self.check((state,book,payments,altered))

    def test_delivery_cannot_erase_transit_before_its_actual_cash_receipt(self):
        stream=synthetic_household_book(preadvance=2,pending_private=True,early_delivery=True)
        w=stream[1].later_credit[0]
        self.assertEqual(w.transit_deposits,(0,0))
        trace=stream[3]
        delivery=next(i for i,n in enumerate(trace) if n.kind=='loan_deposit_delivered')
        self.assertLess(delivery,w.trace_start)
        # Receipt remains after this draw, so the claimed zero transit must not
        # expose a claim without either its liability or delivered wallet.
        with self.assertRaises((TypeError,ValueError)):self.check(stream)

    def test_no_new_credit_does_not_require_positive_equity(self):
        stream = synthetic_household_book(old=0, reserve=0, rate=0, firms=(17,30))
        self.assertEqual(stream[0].bank_equity('B'), -12)
        self.assertEqual(stream[1].later_credit, ())
        self.check(stream)

    def test_unrecorded_twenty_cannot_flip_negative_equity_for_pre_payroll_draw(self):
        stream = synthetic_household_book(old=0, reserve=0, firms=(17,30),
                                         preadvance=F(1,100), fake_private=True)
        w = stream[1].later_credit[0]
        self.assertEqual(stream[0].bank_equity('B'), -12)
        self.assertEqual(l._early_conditions(w.snapshot, w.private_loans)[1][1], 8)
        with self.assertRaises((TypeError, ValueError)): self.check(stream)

    def test_existing_rate_four_cannot_become_five_only_in_draw_inventory(self):
        state, book, payments, trace = synthetic_household_book(preadvance=F(1,200))
        self.check((state, book, payments, trace))
        w = book.later_credit[0]; loan = w.private_loans[0]
        self.assertEqual((loan.id, loan.rate_pct), ('L0', 4))
        changed = replace(w, private_loans=(replace(loan, rate_pct=5), *w.private_loans[1:]))
        with self.assertRaises((TypeError, ValueError)):
            self.check((state, replace(book, later_credit=(changed,*book.later_credit[1:])), payments, trace))

    def test_future_fifty_project_after_household_cannot_back_earlier_twenty_draw(self):
        stream = synthetic_household_book(preadvance=20, future_private=True)
        state, book, payments, trace = stream
        w = book.later_credit[0]
        self.assertEqual(l._early_conditions(w.snapshot, state.loans)[2][1], 16)
        self.assertGreater(w.new_loan.face, 16)
        self.assertEqual(w.private_loans[-1].face, 50)
        creation = next(i for i,n in enumerate(trace) if n.kind=='loan_deposit_created')
        self.assertGreater(creation, book.phases[6].trace_end)
        with self.assertRaises((TypeError, ValueError)): self.check(stream)


class HouseholdJournalPureTests(unittest.TestCase):
    def test_new_exact_nine_phase_fresh_only_schema_old_routes_refuse(self):
        with patch.object(l, '_Transaction', side_effect=AssertionError('No transaction')) as tx, \
             patch.object(l, 'advance_given_orders', side_effect=AssertionError('No quarter')) as raw:
            state = fixture()
            self.assertIs(type(state.public_book), l.HouseholdLiquidityBook)
            self.assertEqual(l.HOUSEHOLD_LIQUIDITY_PHASES, ('opening', 'principal', 'early_credit',
                'early_income', 'funded_payroll', 'household_credit', 'household_income',
                'income_close', 'trading_close'))
            self.assertIsNone(state.public_book.household_credit)
            l.validate_household_liquidity_public(state.public_book, state.scale, 0)
            for old in (l.validate_funded_public, l.validate_paydate_public, l.validate_early_paydate_public):
                with self.assertRaises((TypeError, ValueError)): old(state.public_book, state.scale, 0)
            for state in (state, fixture(convention='early')):
                with self.assertRaises(ValueError): l.enable_household_liquidity_public(state, state.public_book.terms)
            self.assertEqual((tx.call_count, raw.call_count), (0, 0))


class HouseholdJournalActualTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = fixture(); cls.before = repr(cls.root)
        result = attempt(cls.root)
        if not result.ok: raise AssertionError('Retain first actual fixture failure, not retry: '+result.status+': '+result.reason)
        cls.paid = result.state

    def test_paired_old_household_reserve_refusal_new_draw_pays_with_original_bases(self):
        old = fixture(convention='early'); before = repr(old)
        refused = attempt(old)
        self.assertFalse(refused.ok); self.assertEqual(refused.status, 'funding_failure')
        self.assertIs(refused.state, old); self.assertEqual(repr(old), before)
        state = self.paid; book = state.public_book; w = book.household_credit
        self.assertEqual(tuple(p.name for p in book.phases), l.HOUSEHOLD_LIQUIDITY_PHASES)
        self.assertEqual(w.plan.advances, (0, F(1, 100)))
        self.assertEqual(book.phases[5].snapshot.wallets, book.phases[4].snapshot.wallets)
        self.assertEqual(book.observations[8].basis, 1)
        self.assertEqual(book.observations[6].basis, self.root.reserves('B'))
        self.assertEqual(book.closing_cb_loans[0].id, 'CB1:B:new')
        retired = [n for n in state.last.trace if n.kind == 'cb_principal_retired' and n.claim_id == 'CB1:B']
        self.assertEqual(len(retired), 1)
        self.assertEqual(repr(self.root), self.before)
        validate(state)

    def test_wallet_failure_cannot_be_cured_by_bank_facility(self):
        state = fixture(old=0, rate=4000, households=(3, 0))
        out = attempt(state)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'funding_failure')
        self.assertIs(out.state, state)

    def test_missing_needed_contract_is_unsupported_and_explicit_zero_pays(self):
        state = fixture(old=0, cb_rate=None)
        out = attempt(state)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'unsupported_public_income')
        self.assertIs(out.state, state)
        out = attempt(fixture(old=0, cb_rate=0))
        self.assertTrue(out.ok, out.reason); validate(out.state)
        self.assertEqual(out.state.public_book.observations[8].basis, 0)
        self.assertGreater(out.state.public_book.household_credit.plan.advances[1], 0)

    def test_signed_negative_coupon_needs_no_cb_contract_or_cash_gift(self):
        state = fixture(old=0, rate=-4, cb_rate=None)
        out = attempt(state); self.assertTrue(out.ok, out.reason)
        w = out.state.public_book.household_credit
        self.assertEqual(w.plan.advances, (0, 0))
        self.assertEqual(out.state.public_book.household_income[1], F(1, 100))
        self.assertEqual(out.state.public_book.phases[6].snapshot.wallets[3],
                         out.state.public_book.phases[5].snapshot.wallets[3]+F(1, 100))
        validate(out.state)

    def test_actual_private_origination_and_all_gross_usage_bind_before_household_credit(self):
        offer = l.LoanOffer('B', 2, 0, 2, borrower='R')
        for limit, paid in ((F(301, 100), False), (4, True)):
            state = fixture()
            out = attempt(state, controls(state, limit=limit, new_loans=(offer,)))
            self.assertEqual(out.ok, paid, out.reason)
            if not paid:
                self.assertEqual(out.status, 'funding_failure'); self.assertIs(out.state, state)
                continue
            book = out.state.public_book; w = book.household_credit
            self.assertGreater(w.plan.gross_used[1], book.early_credit.plan.gross_used[1])
            self.assertEqual(w.plan.gross_after[1], w.plan.gross_used[1]+w.plan.advances[1])
            self.assertEqual(len(w.private_loans), len(state.loans)+1)
            self.assertTrue(any(n.kind == 'household_private_origin' for n in out.state.last.trace))
            validate(out.state)
            self.cross_paid = out.state
            # Change a collateral claim consistently in BOTH current witness
            # and CB-draw metadata: preceding actual origination still binds it.
            original = w.private_loans[-1]
            fake = replace(original, rate_pct=original.rate_pct+1)
            loans = (*w.private_loans[:-1], fake)
            altered = replace(book, household_credit=replace(w, private_loans=loans),
                later_credit=tuple(replace(z, private_loans=loans) if z.payment_position >= book.phases[4].payment_end else z
                                   for z in book.later_credit))
            with self.assertRaises((TypeError, ValueError)): validate(out.state, book=altered)

    def test_current_equity_and_current_eligible_collateral_still_refuse(self):
        state = fixture(old=0, firms=(17, 30))
        out = attempt(state)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'funding_failure')
        state = fixture(old=0, faces=pools({5:20}, {5:18}), nonperforming=True)
        out = attempt(state)
        self.assertFalse(out.ok); self.assertEqual(out.status, 'funding_failure')

    def test_next_interest_uses_actual_new_opening_and_no_second_old_retirement(self):
        state = self.paid
        out = attempt(state); self.assertTrue(out.ok, out.reason)
        self.assertEqual(out.state.public_book.observations[8].basis, state.cb_debt('B'))
        self.assertEqual(sum(n.amount for n in out.state.last.trace if n.kind == 'cb_principal_retired'),
                         sum(z.face for z in state.cb_loans))
        validate(out.state)

    def test_paid_metadata_positions_pledges_and_claims_reject_without_execution(self):
        state = self.paid; book = state.public_book; w = book.household_credit
        with patch.object(l, 'advance_given_orders', side_effect=AssertionError('No replay')) as raw, \
             patch.object(l, '_Transaction', side_effect=AssertionError('No replay')) as tx:
            for changed in (replace(book, household_credit=None), replace(book, phases=book.phases[:5]+book.phases[6:]),
                replace(book, household_credit=replace(w, plan=replace(w.plan, gross_after=(0, 0)))),
                replace(book, household_credit=replace(w, private_loans=())),
                replace(book, closing_cb_loans=tuple(replace(z, id='forged') for z in book.closing_cb_loans))):
                with self.assertRaises((TypeError, ValueError)): validate(state, book=changed)
            for stream in ('payments', 'trace'):
                with self.assertRaises((TypeError, ValueError)): validate(state, **{stream:getattr(state.last, stream)[::-1]})
            phase = replace(book.phases[5]); object.__setattr__(phase, 'payment_end', True)
            with self.assertRaises((TypeError, ValueError)): validate(state, book=replace(book, phases=(*book.phases[:5], phase, *book.phases[6:])))
            plan = replace(w.plan); object.__setattr__(plan, '__dataclass_fields__', {})
            with self.assertRaises((TypeError, ValueError)): validate(state, book=replace(book, household_credit=replace(w, plan=plan)))
            self.assertEqual((raw.call_count, tx.call_count), (0, 0))


class HouseholdZeroCreditParityTests(unittest.TestCase):
    def test_zero_household_credit_preserves_old_actual_economic_golden(self):
        old = fixture(old=0, reserve=5, rate=0, cb_rate=0, convention='early')
        new = fixture(old=0, reserve=5, rate=0, cb_rate=0)
        left = attempt(old); right = attempt(new)
        self.assertTrue(left.ok, left.reason); self.assertTrue(right.ok, right.reason)
        self.assertEqual(right.state.public_book.household_credit.plan.advances, (0, 0))
        for name in ('banks', 'loans', 'cb_loans', 'vintages', 'wip_units', 'wip_basis',
                     'public_securities', 'gov_debt_face', 'next_private_id'):
            self.assertEqual(getattr(left.state, name), getattr(right.state, name))
        for field in fields(l.Report):
            if field.name != 'trace':
                self.assertEqual(getattr(left.state.last, field.name), getattr(right.state.last, field.name))


class HouseholdDrawHistoryActualTests(unittest.TestCase):
    """Separate repair wave (at most EIGHT raw calls), no macro execution."""
    @staticmethod
    def run_fix(state, finance, orders=None):
        with counted_actual(fix=True):
            result=l.advance_given_orders(state, orders or replace(l.depth_orders(),
                market_clearing=True, investment_units=0), finance)
        if not result.ok: raise AssertionError('Retain bounded actual failure: '+result.status+': '+result.reason)
        return result.state

    @classmethod
    def setUpClass(cls):
        cls.origins=[]
        for convention in ('early','household'):
            root=fixture(old=0,rate=0,cb_rate=0,convention=convention)
            finance=controls(root,new_loans=(l.OperatingLoanOffer('B',2,0,2,borrower='R'),))
            cls.origins.append(cls.run_fix(root,finance))

    def assert_golden(self,left,right):
        for name in ('banks','loans','cb_loans','vintages','wip_units','wip_basis',
                     'public_securities','gov_debt_face','next_private_id'):
            self.assertEqual(getattr(left,name),getattr(right,name))
        for field in fields(l.Report):
            if field.name!='trace': self.assertEqual(getattr(left.last,field.name),getattr(right.last,field.name))
        stripped=tuple(n for n in right.last.trace if n.kind not in ('household_private_pending','household_private_origin')
                       and not (n.kind=='paydate_phase' and n.counterparty=='household_credit'))
        self.assertEqual(left.last.trace,stripped)

    def test_actual_pending_operating_origination_preserves_old_numeric_and_trace_golden(self):
        left,right=self.origins; self.assert_golden(left,right); validate(right)
        witnesses=[w for w in right.public_book.later_credit if any(w.transit_deposits)]
        self.assertTrue(witnesses)
        w=witnesses[0]; self.assertEqual(w.transit_deposits,(0,2))
        self.assertIs(type(w.private_loans[-1]),l.OperatingLoan)
        self.assertLess(w.payment_position,right.public_book.phases[4].payment_end)
        self.assertEqual(right.public_book.household_credit.plan.advances,(0,0))

    def test_actual_renewal_replacement_and_pending_delta_bind_before_draw(self):
        pair=[]
        for convention in ('early','household'):
            root=fixture(old=0,rate=0,cb_rate=0,convention=convention)
            root=replace(root,loans=(replace(root.loans[0],borrower='R',rate_pct=0,maturity=1,allowance=2),))
            pair.append(self.run_fix(root,controls(root,renewals=(l.Renewal('L0',30,-4,3),))))
        left,right=pair; self.assert_golden(left,right); validate(right)
        w=next(w for w in right.public_book.later_credit if any(w.transit_deposits))
        self.assertEqual(w.transit_deposits,(0,20))
        self.assertEqual([(z.id,z.face,z.allowance) for z in w.private_loans],[('L1',30,2)])
        self.assertGreater(w.payment_position,right.public_book.phases[7].payment_end)
        self.assertNotIn('L0',[z.id for z in w.private_loans])
        self.check_reused_paid_adversaries(right,w)

    def check_reused_paid_adversaries(self,state,w):
        book=state.public_book
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No replay')) as raw, \
             patch.object(l,'_Transaction',side_effect=AssertionError('No Transaction')) as tx:
            for changed in (replace(w,transit_deposits=(0,0)),
                replace(w,private_loans=tuple(replace(z,rate_pct=z.rate_pct+1) for z in w.private_loans)),
                replace(w,private_loans=book.early_credit.private_loans)):
                altered=replace(book,later_credit=tuple(changed if z is w else z for z in book.later_credit))
                with self.assertRaises((TypeError,ValueError)): validate(state,book=altered)
            for kind in ('household_private_pending','loan_deposit_created','loan_deposit_delivered',
                         'coupon_paid','renewal_old_retired','renewal_new_created'):
                index=next(i for i,n in enumerate(state.last.trace) if n.kind==kind)
                changed=replace(state.last.trace[index],kind='omitted_'+kind)
                trace=(*state.last.trace[:index],changed,*state.last.trace[index+1:])
                with self.assertRaises((TypeError,ValueError)): validate(state,trace=trace)
            self.assertEqual((raw.call_count,tx.call_count),(0,0))

    def test_actual_after_household_project_creation_and_coupon_history(self):
        root=fixture(old=0,rate=0,cb_rate=0)
        state=self.run_fix(root,controls(root,project_commitment=l.ProjectCommitment('B',3,4)),
            replace(l.depth_orders(),market_clearing=True,investment_units=2))
        validate(state)
        projects=[z for z in state.loans if type(z) is l.ProjectLoan]
        self.assertTrue(projects,'Useful actual case must create project claims, not unused reservation.')
        self.assertTrue(all(z.last_coupon_paid==1 for z in projects))
        marker=next(i for i,n in enumerate(state.last.trace) if n.kind=='household_private_pending')
        self.assertGreater(marker,state.public_book.phases[7].trace_end)

    def test_reused_paid_origin_witness_cannot_erase_pending_liability_or_terms(self):
        state=self.origins[1]
        w=next(w for w in state.public_book.later_credit if any(w.transit_deposits))
        book=state.public_book
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No replay')) as raw, \
             patch.object(l,'_Transaction',side_effect=AssertionError('No Transaction')) as tx:
            for changed in (replace(w,transit_deposits=(0,0)),replace(w,transit_deposits=(1,2)),
                replace(w,private_loans=w.private_loans[:-1]),
                replace(w,private_loans=tuple(replace(z,rate_pct=5) for z in w.private_loans))):
                altered=replace(book,later_credit=tuple(changed if z is w else z for z in book.later_credit))
                with self.assertRaises((TypeError,ValueError)): validate(state,book=altered)
            for key,value in (('start',False),('performing',1)):
                index=next(i for i,n in enumerate(state.last.trace) if n.kind=='household_private_origin')
                note=state.last.trace[index]; data={**dict(note.details),key:value}
                trace=(*state.last.trace[:index],replace(note,details=tuple(data.items())),*state.last.trace[index+1:])
                with self.assertRaises((TypeError,ValueError)): validate(state,trace=trace)
            self.assertEqual((raw.call_count,tx.call_count),(0,0))


class HouseholdDrawHistorySettlementActualTests(unittest.TestCase):
    def test_signed_coupon_negative_zero_renewal_and_actual_principal_history(self):
        for face in (6,10,None):
            with self.subTest(replacement_face=face):
                root=fixture(old=0,rate=0,cb_rate=0)
                root=replace(root,loans=(replace(root.loans[0],borrower='R',rate_pct=-4,maturity=1,allowance=2),))
                finance=controls(root,renewals=() if face is None else (l.Renewal('L0',face,-5,3),))
                state=HouseholdDrawHistoryActualTests.run_fix(root,finance);validate(state)
                coupon=next(n for n in state.last.trace if n.kind=='coupon_paid')
                self.assertEqual(coupon.amount,-F(1,10))
                if face is None:
                    self.assertEqual(state.loans,())
                    self.assertTrue(any(n.kind=='matching_principal_retired' for n in state.last.trace))
                else:
                    self.assertEqual([(z.id,z.face,z.allowance) for z in state.loans],[('L1',face,2)])
                    net=next(n for n in state.last.trace if n.kind=='renewal_net_cash')
                    self.assertEqual(net.amount,10-face)
                    with patch.object(l,'advance_given_orders',side_effect=AssertionError('No replay')) as raw, \
                         patch.object(l,'_Transaction',side_effect=AssertionError('No Transaction')) as tx:
                        for kind in ('coupon_paid','renewal_old_retired','renewal_new_created'):
                            index=next(i for i,n in enumerate(state.last.trace) if n.kind==kind)
                            note=state.last.trace[index];data=dict(note.details)
                            key='paid_quarter' if kind=='coupon_paid' else 'allowance_released' if kind=='renewal_old_retired' else 'maturity'
                            data[key]=True
                            trace=(*state.last.trace[:index],replace(note,details=tuple(data.items())),*state.last.trace[index+1:])
                            with self.assertRaises((TypeError,ValueError)):validate(state,trace=trace)
                        self.assertEqual((raw.call_count,tx.call_count),(0,0))


if __name__ == '__main__': unittest.main()
