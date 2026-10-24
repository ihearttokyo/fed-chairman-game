"""Bounded actual one-journal hand cases, not native or macro qualification."""
from dataclasses import fields, replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import ledger as l
from scripts.research.funded_production import public_income as income
from scripts.research.funded_production import public_funding as funding
from scripts.research.funded_production import paydate_households


Q = F(1, 10**6)


def pools(cb=None, a=None, b=None):
    return tuple(tuple(F((row or {}).get(i, 0)) for i in range(120))
                 for row in (cb, a, b))


def legacy(*, faces=None, masses=None, reserves=(5, 5), households=(3, F(3, 20)),
           firms=(17, 3), mortgage_rates=(0, 120), cb_rates=(None, None),
           rrp_rates=(None, None), tga=20, cb_a=0, rrp_a=0):
    """Explicit matched legal hand stocks; no consumption/GDP calibration."""
    state = l.initial_core()
    faces = faces or pools({5: 20}, {5: 18}, {5: 10})
    banks = tuple(replace(bank, reserves=F(reserve), securities=sum(row),
                          deposits=(F(firm), F(cash)))
                  for bank, reserve, firm, cash, row in zip(
                      state.banks, reserves, firms, households, faces[1:]))
    claims = (l.RRPClaim('A', F(rrp_a), 0, 1, ((5, F(rrp_a)),)),) if rrp_a else ()
    book = replace(state.public_book, treasuries=faces[0], private_treasuries=faces[1:],
                   mortgages=(F(1), F(1)), mbs=F(2), tga=F(tga), rrp_claims=claims,
                   capital_other=sum(faces[0]) + 2 - sum(reserves)
                       - sum(state.public_book.currency) - tga - F(rrp_a))
    state = replace(state, banks=banks, public_book=book,
                    public_securities=sum(faces[0]) + 2,
                    gov_debt_face=sum(map(sum, faces)))
    if cb_a:
        state = replace(state, cb_loans=(l.CBLoan('CB0:A', 'A', F(cb_a), 0, 1,
                                                l._pledges(state, 'A', F(cb_a))),),
                        public_book=replace(state.public_book,
                            capital_other=state.public_book.capital_other + F(cb_a)))
    terms = income.PublicIncomeTerms(masses or pools(), tuple(map(F, mortgage_rates)),
                                    F(0), cb_rates, rrp_rates)
    return state, terms


def fixture(**kwargs):
    state, terms = legacy(**kwargs)
    return l.enable_paydate_public(state, terms)


def fiscal(state, *, subscriptions=(0, 0), masses=(None, None)):
    rolls = tuple(row[0] for row in (state.public_book.treasuries,
                                   *state.public_book.private_treasuries))
    return l.FundedPublicInstructions(treasury_rolls=rolls,
        treasury_issue_authorization=sum(rolls) + sum(subscriptions),
        treasury_subscriptions=subscriptions, subscription_coupon_mass=masses)


def run(state, *, instructions=None, controls=None, orders=None):
    controls = controls or l.Controls(household_mode='cash_stock_close_v1',
                                      public_instructions=instructions or fiscal(state))
    orders = orders or replace(l.depth_orders(), market_clearing=True)
    return l.advance_given_orders(state, orders, controls)


def validate(state, *, book=None, payments=None, trace=None):
    l.validate_paydate_public(book or state.public_book, state.scale, state.quarter,
                              state.last.payments if payments is None else payments,
                              state.last.trace if trace is None else trace)


def rebound_receipts(payments, trace, replacements):
    """Change receipt AND matching trace notes: tests semantics, not just tags."""
    new_payments, new_trace = list(payments), list(trace)
    for index, note in enumerate(trace):
        if note.kind != 'paydate_payment':
            continue
        position = dict(note.details)['position']
        if position not in replacements:
            continue
        payment = replacements[position]
        new_payments[position] = payment
        new_trace[index - 1] = l.Trace(payment.kind, payment.payer, payment.payee,
                                      payment.amount, payment.claim_id)
        new_trace[index] = l.Trace('paydate_payment', payment.payer, payment.payee,
            payment.amount, payment.claim_id,
            (('payment_kind', payment.kind), ('position', position)))
    return tuple(new_payments), tuple(new_trace)


class PaydateJournalTests(unittest.TestCase):
    def test_api_is_new_exact_type_and_activation_is_fresh_legacy_only(self):
        original, terms = legacy()
        state = l.enable_paydate_public(original, terms)
        self.assertIs(type(state.public_book), l.PaydatePublicBook)
        self.assertTrue(issubclass(l.PaydatePublicBook, l.FundedPublicBook))
        self.assertEqual(state.public_book.phases, ())
        self.assertEqual(state.public_book.paid_wages, (0, 0))
        self.assertEqual(state.public_book.household_income, (0, 0))
        l.validate_paydate_public(state.public_book, state.scale, 0)
        for source in (state, l.enable_funded_public(original, terms),
                       l.enable_public_income(original, terms), run(state).state):
            with self.subTest(source=type(source.public_book).__name__), self.assertRaises(ValueError):
                l.enable_paydate_public(source, terms)
        self.assertIs(type(original.public_book), l.PublicBook)
        with self.assertRaises(TypeError):
            l.validate_funded_public(state.public_book, state.scale, 0)
        self.assertEqual([x.name for x in fields(l.FundedPublicBook)
                          if x.name not in l.PublicIncomeBook.__dataclass_fields__],
                         ['opening', 'funding', 'transfers'])

    def test_paid_wages_cure_opening_coupon_shortage_before_any_purchase(self):
        state = fixture()
        before = repr(state)
        out = run(state)
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(repr(state), before)
        report, book = out.state.last, out.state.public_book
        self.assertGreater(book.paid_wages[1], 0)
        self.assertLess(state.deposit('HB'), -book.household_income[1])
        self.assertEqual(book.household_income, (0, -F(3, 10)))
        kinds = [p.kind for p in report.payments]
        self.assertLess(kinds.index('focal_payroll'), kinds.index('mortgage_coupon'))
        self.assertLess(kinds.index('mortgage_coupon'), kinds.index('services'))
        self.assertEqual(tuple(p.name for p in book.phases), l.PAYDATE_PHASES)
        validate(out.state)
        with patch.object(l, 'advance_given_orders', side_effect=AssertionError('validator replayed a quarter')):
            validate(out.state)

    def test_intended_but_unpaid_wages_cannot_fund_coupon_atomic(self):
        state = fixture(firms=(17, 0))
        before = repr(state)
        out = run(state)
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'funding_failure')
        self.assertIn('deposits', out.reason)
        self.assertIs(out.state, state)
        self.assertEqual(repr(state), before)

    def test_owned_household_cash_does_not_cure_actual_reserve_shortage(self):
        state = fixture(reserves=(5, F(1, 10)), households=(3, 3), cb_rates=(0, 0))
        before = repr(state)
        out = run(state, controls=l.Controls(household_mode='cash_stock_close_v1',
            public_instructions=fiscal(state), facility_limits=(100, 100)))
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'funding_failure')
        self.assertIn('reserves', out.reason)
        self.assertIs(out.state, state)
        self.assertEqual(repr(state), before)

    def test_signed_and_zero_household_coupons_are_matched_exactly_once(self):
        for rate, signed in ((-120, F(3, 10)), (0, F(0)), (120, -F(3, 10))):
            with self.subTest(rate=rate):
                out = run(fixture(mortgage_rates=(0, rate)))
                self.assertTrue(out.ok, out.reason)
                state, report = out.state, out.state.last
                self.assertEqual(state.public_book.household_income[1], signed)
                receipts = [p for p in report.payments if p.kind in ('mortgage_coupon', 'mbs_coupon')]
                self.assertEqual(len(receipts), 2 if rate else 0)
                self.assertTrue(all(p.amount == abs(signed) for p in receipts))
                budget = next(n for n in report.trace if n.kind == 'household_budget' and n.actor == 'HB')
                data = dict(budget.details)
                self.assertEqual(data['settled_income'], signed)
                self.assertEqual(budget.amount, F(3, 20) + report.payroll_focal + signed)
                self.assertEqual(data['income_forecast'], report.payroll_focal + F(3, 20) + signed)
                validate(state)

    def test_negative_adjustment_base_is_not_negative_owned_cash(self):
        out = run(fixture())
        self.assertTrue(out.ok, out.reason)
        note = next(n for n in out.state.last.trace if n.kind == 'household_budget' and n.actor == 'HB')
        data = dict(note.details)
        self.assertEqual(data['opening_cash'], F(3, 20))
        self.assertLess(data['opening_cash'] + data['settled_income'], 0)
        self.assertGreaterEqual(note.amount, 0)
        self.assertLessEqual(data['funded'], note.amount)

    def test_missing_contracts_unknown_but_explicit_zero_is_covered(self):
        for kwargs in ({'cb_a': 1}, {'rrp_a': 1}):
            state, terms = legacy(**kwargs)
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                l.enable_paydate_public(state, terms)
        for kwargs in ({'cb_a': 1, 'cb_rates': (0, None)},
                       {'rrp_a': 1, 'rrp_rates': (0, None)}):
            out = run(fixture(**kwargs))
            self.assertTrue(out.ok, out.reason)
            validate(out.state)
        for rates, status in (((None, None), 'unsupported_public_income'), ((0, 0), 'ok')):
            state = fixture(reserves=(0, 5), firms=(1, 3), households=(1, F(3, 20)),
                            cb_rates=rates)
            controls = l.Controls(household_mode='cash_stock_close_v1',
                public_instructions=fiscal(state), new_loans=(l.LoanOffer('A', 1, 0, 2),),
                facility_limits=(5, 0), security_bids=(0, 0))
            out = run(state, controls=controls)
            self.assertEqual(out.status, status, out.reason)
            if out.ok:
                validate(out.state)
            else:
                self.assertIs(out.state, state)

    def test_new_issuance_never_enters_original_opening_coupon_basis(self):
        state = fixture(masses=pools(a={5: F(2, 5)}))
        out = run(state, instructions=fiscal(state, subscriptions=(1, 0), masses=(F(4, 5), None)))
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(out.state.public_book.observations[1].settled, F(1, 10))
        self.assertEqual(sum(out.state.public_book.terms.annual_treasury[1]), F(6, 5))
        validate(out.state)
        following = run(out.state)
        self.assertTrue(following.ok, following.reason)
        self.assertEqual(following.state.public_book.observations[1].settled, F(3, 10))
        self.assertEqual(following.state.public_book.opening.quarter, 2)
        validate(following.state)

    def test_retired_mortgage_keeps_original_coupon_and_current_pre_wage_cash(self):
        state = fixture(households=(3, 3))
        instructions = replace(fiscal(state), mortgage_repayments=(0, 1))
        out = run(state, instructions=instructions)
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(out.state.public_book.mortgages, (1, 0))
        line = next(z for z in out.state.public_book.observations if (z.kind, z.owner) == ('mortgage', 'HB'))
        self.assertEqual((line.basis, line.settled), (1, F(3, 10)))
        note = next(n for n in out.state.last.trace if n.kind == 'household_budget' and n.actor == 'HB')
        self.assertEqual(dict(note.details)['opening_cash'], 2)
        validate(out.state)

    def test_interposed_maturity_trade_keeps_current_coupon_rights(self):
        state = fixture(reserves=(0, 5), firms=(1, 3), households=(1, F(3, 20)),
                        cb_a=1, cb_rates=(0, None), masses=pools(a={5: F(9, 5)}))
        clocks = []
        original_transfer = l._Transaction.transfer_treasuries
        def observe_transfer(tx, *args):
            clocks.append((tx.paydate_stage, tx.public_book.income_paid_through))
            return original_transfer(tx, *args)
        with patch.object(l._Transaction, 'transfer_treasuries', observe_transfer):
            out = run(state, controls=l.Controls(household_mode='cash_stock_close_v1',
                public_instructions=fiscal(state), security_bids=(0, 2)))
        self.assertTrue(out.ok, out.reason)
        book = out.state.public_book
        self.assertTrue(book.transfers)
        self.assertEqual(book.transfers[0].seller, 'A')
        self.assertEqual(book.transfers[0].buyer, 'B')
        self.assertEqual(book.income_paid_through, 1)
        self.assertEqual(clocks[0], ('funded_payroll', 0))
        projection = funding.project_batch(book.opening, book.funding)
        faces, terms = projection.treasuries, projection.terms
        for event in book.transfers:
            faces, terms = funding.apply_transfer(faces, terms, event)
        self.assertEqual((book.treasuries, *book.private_treasuries), faces)
        self.assertEqual(book.terms, terms)
        validate(out.state)

    def test_actual_cb_credit_and_transfers_bind_tampering_not_just_coupons(self):
        state = fixture(reserves=(0, 5), firms=(1, 3), households=(1, F(3, 20)),
                        cb_rates=(0, 0))
        credit = run(state, controls=l.Controls(household_mode='cash_stock_close_v1',
            public_instructions=fiscal(state), new_loans=(l.LoanOffer('A', 1, 0, 2),),
            facility_limits=(5, 0), security_bids=(0, 0)))
        transfer_state = fixture(reserves=(0, 5), firms=(1, 3), households=(1, F(3, 20)),
                                 cb_a=1, cb_rates=(0, None), masses=pools(a={5: F(9, 5)}))
        trade = run(transfer_state, controls=l.Controls(household_mode='cash_stock_close_v1',
            public_instructions=fiscal(transfer_state), security_bids=(0, 2)))
        for out, kinds in ((credit, ('cb_draw', 'loan_origination')),
                           (trade, ('private_public_par_trade', 'cb_cash_repayment'))):
            self.assertTrue(out.ok, out.reason)
            state = out.state
            validate(state)
            for kind in kinds:
                payments = state.last.payments
                index = next(i for i, p in enumerate(payments) if p.kind == kind)
                for forged in (payments[:index] + payments[index + 1:],
                               payments[:index] + (payments[index],) + payments[index:],
                               payments[:index] + (replace(payments[index], amount=payments[index].amount + Q),)
                                   + payments[index + 1:],
                               payments[:index] + (payments[index + 1], payments[index]) + payments[index + 2:]):
                    with self.subTest(kind=kind), self.assertRaises(ValueError):
                        validate(state, payments=forged)

    def test_semantic_reconciliation_rejects_rebound_cash_and_credit_prefix(self):
        state = run(fixture()).state
        for kind in ('focal_payroll', 'mortgage_coupon', 'mbs_coupon'):
            payments, trace = state.last.payments, state.last.trace
            index = next(i for i, p in enumerate(payments) if p.kind == kind)
            replacements = {index: replace(payments[index], amount=payments[index].amount + Q)}
            forged_payments, forged_trace = rebound_receipts(payments, trace, replacements)
            book = state.public_book
            if kind == 'focal_payroll':
                book = replace(book, paid_wages=(book.paid_wages[0], book.paid_wages[1] + Q))
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                validate(state, book=book, payments=forged_payments, trace=forged_trace)
        opening = fixture(reserves=(0, 5), firms=(1, 3), households=(1, F(3, 20)), cb_rates=(0, 0))
        out = run(opening, controls=l.Controls(household_mode='cash_stock_close_v1',
            public_instructions=fiscal(opening), new_loans=(l.LoanOffer('A', 1, 0, 2),),
            facility_limits=(5, 0), security_bids=(0, 0)))
        self.assertTrue(out.ok, out.reason)
        state = out.state
        payments, trace = state.last.payments, state.last.trace
        credit = next(i for i, p in enumerate(payments) if p.kind == 'cb_draw')
        delivered = next(i for i, p in enumerate(payments) if p.kind == 'loan_origination')
        self.assertLess(credit, delivered)
        forged_payments, forged_trace = rebound_receipts(payments, trace,
            {credit: payments[delivered], delivered: payments[credit]})
        # Same ending movements and updated identity tags, but the cross-bank
        # deposit delivery would spend reserves before the actual CB draw.
        with self.assertRaisesRegex(ValueError, 'prefix'):
            validate(state, payments=forged_payments, trace=forged_trace)

    def test_new_calendar_never_calls_old_all_income_projection(self):
        with patch.object(funding, 'project_income', side_effect=AssertionError('legacy projection used')):
            out = run(fixture())
            self.assertTrue(out.ok, out.reason)
            validate(out.state)

    def test_legacy_shortage_and_zero_program_monetary_results_stay_unchanged(self):
        original, terms = legacy()
        old = l.enable_funded_public(original, terms)
        out = run(old)
        self.assertFalse(out.ok)
        self.assertIs(out.state, old)
        self.assertEqual(out.status, 'funding_failure')
        zero, terms = legacy(mortgage_rates=(0, 0))
        old, new = l.enable_funded_public(zero, terms), l.enable_paydate_public(zero, terms)
        old_out, new_out = run(old), run(new)
        self.assertTrue(old_out.ok, old_out.reason)
        self.assertTrue(new_out.ok, new_out.reason)
        self.assertEqual(old_out.state.banks, new_out.state.banks)
        self.assertEqual(old_out.state.loans, new_out.state.loans)
        self.assertEqual(old_out.state.cb_loans, new_out.state.cb_loans)
        self.assertEqual(old_out.state.last.payments, new_out.state.last.payments)
        for name in l.Report.__dataclass_fields__:
            if name != 'trace':
                self.assertEqual(getattr(old_out.state.last, name), getattr(new_out.state.last, name))
        for mode in ('fixed', 'wallet', 'liquidity'):
            old_out = run(old, controls=l.Controls(household_mode=mode, public_instructions=fiscal(old)))
            self.assertTrue(old_out.ok, old_out.reason)

    def test_future_remittance_or_wages_cannot_bridge_early_tga_failure(self):
        state = fixture(tga=F(1, 10) - Q, masses=pools(cb={5: F(2, 5)}))
        out = run(state)
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'funding_failure')
        self.assertIn('TGA', out.reason)
        self.assertIs(out.state, state)
        funded = run(state, instructions=fiscal(state, subscriptions=(Q, 0), masses=(0, None)))
        self.assertTrue(funded.ok, funded.reason)
        validate(funded.state)

    def test_nonclosing_modes_and_quarterless_mutations_refuse_new_route(self):
        state = fixture()
        for mode in ('fixed', 'wallet', 'liquidity'):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                run(state, controls=l.Controls(household_mode=mode, public_instructions=fiscal(state)))
        with self.assertRaises(ValueError):
            run(state, orders=l.depth_orders())
        for helper in (lambda: l.settle_public(state, fiscal(state)),
                       lambda: l.originate(state, l.LoanOffer('B', 1, 0, 2)),
                       lambda: l.repay(state, 'L0', 1)):
            with self.assertRaises(ValueError):
                helper()

    def test_phase_and_receipt_tampering_drop_duplicate_reorder_rejected(self):
        state = run(fixture()).state
        validate(state)
        book, payments, trace = state.public_book, state.last.payments, state.last.trace
        for phases in (book.phases[1:], book.phases + (book.phases[-1],),
                       (book.phases[1], book.phases[0], *book.phases[2:])):
            with self.subTest(phases='shape'), self.assertRaises(ValueError):
                validate(state, book=replace(book, phases=phases))
        phase = book.phases[3]
        forged = replace(phase, snapshot=replace(phase.snapshot,
            wallets=(*phase.snapshot.wallets[:3], phase.snapshot.wallets[3] + Q)))
        with self.assertRaises(ValueError):
            validate(state, book=replace(book, phases=(*book.phases[:3], forged, *book.phases[4:])))
        with self.assertRaises(ValueError):
            validate(state, book=replace(book, paid_wages=(0, 0)))
        with self.assertRaises(ValueError):
            validate(state, book=replace(book, household_income=(0, 0)))
        for kind in ('focal_payroll', 'mortgage_coupon', 'mbs_coupon'):
            index = next(i for i, p in enumerate(payments) if p.kind == kind)
            dropped = payments[:index] + payments[index + 1:]
            duplicate = payments[:index] + (payments[index],) + payments[index:]
            tampered = payments[:index] + (replace(payments[index], amount=payments[index].amount + Q),) + payments[index + 1:]
            reordered = payments[:index] + (payments[index + 1], payments[index]) + payments[index + 2:]
            for forged_payments in (dropped, duplicate, tampered, reordered):
                with self.subTest(kind=kind), self.assertRaises(ValueError):
                    validate(state, payments=forged_payments)
        markers = tuple(n for n in trace if n.kind != 'paydate_phase')
        with self.assertRaises(ValueError):
            validate(state, trace=markers)
        removed = tuple(n for n in trace if n.kind != 'focal_payroll')
        with self.assertRaises(ValueError):
            validate(state, trace=removed)
        index = next(i for i, n in enumerate(trace) if n.kind == 'household_budget' and n.actor == 'HB')
        note = trace[index]
        data = dict(note.details)
        data['settled_income'] = 0
        forged = trace[:index] + (replace(note, details=tuple(data.items())),) + trace[index + 1:]
        with self.assertRaises(ValueError):
            validate(state, trace=forged)

    def test_report_and_closing_state_bind_the_actual_witness(self):
        state = run(fixture()).state
        book = state.public_book
        with self.assertRaises(ValueError):
            l.validate_paydate_public(book, state.scale, state.quarter)
        with self.assertRaises(ValueError):
            replace(state, banks=(state.banks[0], replace(state.banks[1],
                deposits=(state.deposit('F'), state.deposit('HB') + Q))))
        index = next(i for i, p in enumerate(state.last.payments) if p.kind == 'focal_payroll')
        forged = replace(state.last, payments=state.last.payments[:index] + state.last.payments[index + 1:])
        with self.assertRaises(ValueError):
            replace(state, last=forged)

    def test_joint_zero_order_and_budget_cannot_hide_actual_household_spending(self):
        state = run(fixture()).state
        self.assertGreater(sum(p.amount for p in state.last.payments
                               if p.payer == 'HB' and p.kind == 'services'), 0)
        trace = []
        for note in state.last.trace:
            data = dict(note.details)
            if note.kind == 'production_orders':
                data['demand_multiplier'] = 0
                note = replace(note, details=tuple(data.items()))
            elif note.kind == 'household_budget':
                data.update(demand_multiplier=0, desired=0, funded=0)
                note = replace(note, details=tuple(data.items()))
            trace.append(note)
        with self.assertRaises(ValueError):
            validate(state, trace=tuple(trace))

    def test_budget_inputs_bind_to_recorded_orders_and_original_income_history(self):
        state = run(fixture()).state
        index = next(i for i, n in enumerate(state.last.trace)
                     if n.kind == 'household_budget' and n.actor == 'HB')
        original = state.last.trace[index]
        for changed in ('forecast', 'income_previous', 'forecast_source'):
            data = dict(original.details)
            if changed == 'forecast':
                data['forecast'] += 10
                data['income_forecast'] += 10
            elif changed == 'income_previous':
                data['income_previous'] += 10
            else:
                data['forecast_source'] = 'explicit_forecast'
            quote = paydate_households.cash_stock_budget(
                opening_cash=data['opening_cash'], paid_wages=data['paid_wages'],
                settled_income=data['settled_income'], previous_income=data['income_previous'],
                forecast_income=data['income_forecast'], cash_ratio=data['cash_ratio'],
                adjustment=data['adjustment'], demand_multiplier=data.get('demand_multiplier', 1))
            data.update(desired=quote.desired, funded=quote.funded)
            trace = state.last.trace[:index] + (replace(original, details=tuple(data.items())),) + state.last.trace[index + 1:]
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                validate(state, trace=trace)
        orders_index = next(i for i, n in enumerate(state.last.trace) if n.kind == 'production_orders')
        note = state.last.trace[orders_index]
        for changes in ({'demand_multiplier': 0},
                        {'preference_b_services': 0},
                        {'expected_a_nominal': 0, 'expected_b_nominal': 10}):
            data = dict(note.details)
            data.update(changes)
            trace = state.last.trace[:orders_index] + (replace(note, details=tuple(data.items())),) + state.last.trace[orders_index + 1:]
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(state, trace=trace)

    def test_exactly_one_production_marker_precedes_both_frozen_budgets(self):
        state = run(fixture()).state
        trace = state.last.trace
        index = next(i for i, n in enumerate(trace) if n.kind == 'production_orders')
        missing = trace[:index] + (replace(trace[index], kind='not_production_orders'),) + trace[index + 1:]
        with self.assertRaises(ValueError):
            validate(state, trace=missing)
        duplicate_index = next(i for i, n in enumerate(trace) if n.kind == 'public_coupon_observed')
        duplicate = trace[:duplicate_index] + (trace[index],) + trace[duplicate_index + 1:]
        with self.assertRaises(ValueError):
            validate(state, trace=duplicate)
        later_index = next(i for i, n in enumerate(trace) if n.kind == 'market_clearing')
        reordered = list(trace)
        reordered[index], reordered[later_index] = reordered[later_index], reordered[index]
        with self.assertRaises(ValueError):
            validate(state, trace=tuple(reordered))

    def test_per_good_limits_reject_changed_preference_split_even_if_total_funded(self):
        state = run(fixture()).state
        trace = state.last.trace
        index = next(i for i, n in enumerate(trace) if n.kind == 'production_orders')
        data = dict(trace[index].details)
        # The same funded total now permits HA only services, but its actual
        # journal contains residual-good purchases from R. Total cash alone
        # would not establish consistency with this frozen basket.
        data['preference_a_residual'] = 0
        changed = trace[:index] + (replace(trace[index], details=tuple(data.items())),) + trace[index + 1:]
        with self.assertRaises(ValueError):
            validate(state, trace=changed)

    def test_goods_none_and_unfilled_goods_keep_funded_ceilings_not_forced_spending(self):
        for prefs_a, prefs_b in (
                (l.household.Preferences(0, 0, 1), l.household.Preferences(0, 0, 1)),
                (l.household.Preferences(0, 20, 1), l.depth_orders().preferences_b)):
            with self.subTest(prefs_a=prefs_a, prefs_b=prefs_b):
                state = fixture(firms=(17, 4))  # Matched fixture cash funds existing private dues.
                out = run(state, orders=replace(l.depth_orders(), market_clearing=True,
                                               preferences_a=prefs_a, preferences_b=prefs_b))
                self.assertTrue(out.ok, out.reason)
                validate(out.state)
                for owner in ('HA', 'HB'):
                    budget = next(n for n in out.state.last.trace
                                  if n.kind == 'household_budget' and n.actor == owner)
                    spent = sum(p.amount for p in out.state.last.payments
                                if p.payer == owner and p.kind in ('services', 'residual_consumption'))
                    self.assertLess(spent, dict(budget.details)['funded'])

    def test_explicit_forecast_and_previous_paid_history_remain_valid(self):
        opening = fixture()
        orders = replace(l.depth_orders(), market_clearing=True,
                         expected_dividends_nominal=(F(1, 7), F(2, 7)))
        first = run(opening, orders=orders)
        self.assertTrue(first.ok, first.reason)
        validate(first.state)
        snapshot = first.state.public_book.phases[0].snapshot
        self.assertEqual(snapshot.previous_income, (20, F(63, 20)))
        self.assertEqual(snapshot.previous_dividends, (None, None))
        second = run(first.state)
        self.assertTrue(second.ok, second.reason)
        previous = first.state.last
        snapshot = second.state.public_book.phases[0].snapshot
        self.assertEqual(snapshot.previous_income, tuple(previous.disposable_income(h) for h in ('HA', 'HB')))
        self.assertEqual(snapshot.previous_dividends,
                         (previous.dividend_residual + previous.bank_dividend_to('HA'),
                          previous.dividend_focal + previous.bank_dividend_to('HB')))
        self.assertTrue(all(p.snapshot.previous_income == snapshot.previous_income
                            and p.snapshot.previous_dividends == snapshot.previous_dividends
                            for p in second.state.public_book.phases))
        validate(second.state)

    def test_zero_demand_with_zero_actual_goods_spending_remains_valid(self):
        opening = fixture(firms=(17, 4))
        out = run(opening, orders=replace(l.depth_orders(), market_clearing=True,
                                         demand_multiplier=0))
        self.assertTrue(out.ok, out.reason)
        self.assertFalse(any(p.kind in ('services', 'residual_consumption') for p in out.state.last.payments))
        for note in out.state.last.trace:
            if note.kind == 'household_budget':
                self.assertEqual((dict(note.details)['desired'], dict(note.details)['funded']), (0, 0))
        validate(out.state)


if __name__ == '__main__':
    unittest.main()
