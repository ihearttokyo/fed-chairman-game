"""Bounded paid-journal hand cases; no native, recovery or forecast qualification."""
from collections import Counter
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import ledger as l
from scripts.research.funded_production import public_funding as f
from scripts.research.funded_production import public_income as income

Q = F(1, 10**6)


def pools(cb=None, a=None, b=None):
    return tuple(tuple(F((row or {}).get(i, 0)) for i in range(120))
                 for row in (cb, a, b))


def fixture(*, faces=None, masses=None, reserves=(5, 5), deposits=(3, 3),
            mortgages=(1, 1), tga=20, cb_rates=(None, None),
            rrp_rates=(None, None), mortgage_rates=(0, 0), iorb=0, scale=1):
    """Matched, explicit legal stocks, not a checkpoint or migrated career."""
    a = l.initial_core(scale=scale)
    faces = faces or pools({1: 10}, {1: 18}, {1: 10})
    banks = tuple(replace(bank, reserves=F(reserve), securities=sum(row),
                          deposits=(bank.deposits[0], F(deposit)))
                  for bank, reserve, deposit, row in zip(
                      a.banks, reserves, deposits, faces[1:]))
    book = replace(a.public_book, treasuries=faces[0], private_treasuries=faces[1:],
                   mortgages=tuple(map(F, mortgages)), mbs=sum(mortgages), tga=F(tga),
                   capital_other=sum(faces[0]) + sum(mortgages) - sum(reserves)
                   - sum(a.public_book.currency) - tga)
    a = replace(a, banks=banks, public_book=book,
                public_securities=sum(faces[0]) + sum(mortgages),
                gov_debt_face=sum(map(sum, faces)))
    terms = income.PublicIncomeTerms(masses or pools(), tuple(map(F, mortgage_rates)),
                                    F(iorb), cb_rates, rrp_rates)
    return l.enable_funded_public(a, terms)


def fiscal(a, *, rolls=None, subscriptions=(0, 0), masses=(None, None),
           repayments=(0, 0), maturity=120, authorization=None):
    book = a.public_book
    if rolls is None:
        rolls = tuple(row[0] for row in (book.treasuries, *book.private_treasuries))
    if authorization is None:
        authorization = sum(rolls) + sum(subscriptions)
    return l.FundedPublicInstructions(treasury_rolls=rolls,
        treasury_subscriptions=subscriptions, subscription_coupon_mass=masses,
        treasury_issue_authorization=authorization, mortgage_repayments=repayments,
        replacement_maturity=maturity)


def journal(a, instructions=None, controls=None):
    tx = l._Transaction(a, controls or l.Controls(), a.quarter + 1)
    tx.settle_funded_public(instructions or fiscal(a))
    return tx, tx.finish()


def receipts(payments):
    return Counter((p.payer, p.payee, p.amount, p.kind, p.claim_id) for p in payments)


def with_rrp(a):
    left, collateral = F(1), []
    for index, face in enumerate(a.public_book.treasuries[1:], 1):
        take = min(left, face)
        if take:
            collateral.append((index, take)); left -= take
        if not left:
            break
    assert not left
    return replace(a, banks=(replace(a.banks[0], reserves=a.reserves('A') - 1), a.banks[1]),
                   public_book=replace(a.public_book, rrp_claims=(l.RRPClaim('A', 1, 0, 1, tuple(collateral)),)))


class FundedJournalTests(unittest.TestCase):
    def test_exact_exported_types_and_fields_without_inherited_schema_change(self):
        self.assertTrue(issubclass(l.FundedPublicBook, l.PublicIncomeBook))
        self.assertTrue(issubclass(l.FundedPublicInstructions, l.PublicInstructions))
        self.assertEqual([x.name for x in fields(l.FundedPublicBook)
                          if x.name not in l.PublicIncomeBook.__dataclass_fields__],
                         ['opening', 'funding', 'transfers'])
        self.assertEqual([x.name for x in fields(l.FundedPublicInstructions)
                          if x.name not in l.PublicInstructions.__dataclass_fields__],
                         ['subscription_coupon_mass'])
        a = fixture()
        self.assertEqual((a.public_book.opening, a.public_book.funding,
                          a.public_book.transfers), (None, None, ()))
        self.assertEqual(l.FundedPublicInstructions().subscription_coupon_mass, (None, None))
        l.validate_funded_public(a.public_book, a.scale, 0)
        with self.assertRaises(FrozenInstanceError):
            a.public_book.opening = None

    def test_activation_is_exact_legacy_q0_and_never_migration(self):
        old = l.initial_core()
        terms = l.public_income_terms(old)
        a = l.enable_funded_public(old, terms)
        for source in (a, l.enable_public_income(old, terms),
                       l.advance_given_orders(old, l.ProductionOrders()).state):
            with self.subTest(source=type(source.public_book).__name__), self.assertRaises(ValueError):
                l.enable_funded_public(source, terms)
        with self.assertRaises(ValueError):
            l.enable_funded_public(l.initial(), terms)
        self.assertIs(type(old.public_book), l.PublicBook)
        self.assertEqual(old.quarter, 0)

    def test_original_tga_shortfall_is_funded_before_opening_coupons(self):
        a = fixture(faces=pools({1: 1}, {1: 1}),
                    masses=pools({1: F(3, 10)}, {1: F(2, 5)}),
                    reserves=(1, 1), deposits=(1, 1), tga=F(1, 20),
                    mortgage_rates=(4, 4), iorb=10)
        before = repr(a)
        tx, b = journal(a, fiscal(a, subscriptions=(F(1, 5), 0), masses=(0, None)))
        self.assertEqual(repr(a), before)
        self.assertEqual(b.public_book.tga, F(3, 25))
        self.assertEqual(tuple(tx.r.values()), (F(183, 200), F(203, 200)))
        self.assertEqual((tx.d['HA'], tx.d['HB']), (F(99, 100),) * 2)
        self.assertEqual(tuple(tx.earnings.values()), (F(1, 8), F(1, 40)))
        self.assertEqual(b.public_book.deferred_asset, 0)
        kinds = [p.kind for p in tx.payments]
        self.assertLess(kinds.index('treasury_net_cash'), kinds.index('treasury_coupon'))
        self.assertEqual(kinds[-1], 'cb_remittance')
        l.validate_funded_public(b.public_book, b.scale, b.quarter, tx.payments)

    def test_insufficient_current_subscription_cannot_spend_future_remittance(self):
        a = fixture(faces=pools({1: 1}, {1: 1}),
                    masses=pools({1: F(3, 10)}, {1: F(2, 5)}),
                    reserves=(1, 1), deposits=(1, 1), tga=F(1, 20),
                    mortgage_rates=(4, 4), iorb=10)
        before = repr(a)
        controls = l.Controls(public_instructions=fiscal(
            a, subscriptions=(F(1, 10), 0), masses=(0, None)), facility_limits=(100, 100))
        out = l.advance_given_orders(a, l.ProductionOrders(), controls)
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'funding_failure')
        self.assertIs(out.state, a)
        self.assertEqual(repr(a), before)

    def test_full_partial_and_zero_rolls_keep_original_income_rights(self):
        for rolls in ((2, 3, 4), (1, 1, 0), (0, 0, 0)):
            a = fixture(faces=pools({0: 2}, {0: 3}, {0: 4}),
                        masses=pools({0: F(2, 5)}, {0: F(-4, 5)}, {0: F(6, 5)}))
            with self.subTest(rolls=rolls):
                tx, b = journal(a, fiscal(a, rolls=rolls))
                self.assertEqual(tuple(sum(row) for row in
                    (b.public_book.treasuries, *b.public_book.private_treasuries)), rolls)
                self.assertEqual(tuple(sum(row) for row in b.public_book.terms.annual_treasury),
                    tuple(mass * roll / due for mass, roll, due in
                          zip((F(2, 5), F(-4, 5), F(6, 5)), rolls, (2, 3, 4))))
                self.assertEqual(tuple(z.settled for z in b.public_book.observations[:3]),
                                 (F(1, 10), F(-1, 5), F(3, 10)))
                l.validate_funded_public(b.public_book, b.scale, 1, tx.payments)

    def test_new_subscription_does_not_earn_current_quarter_coupon(self):
        a = fixture(masses=pools(a={1: F(2, 5)}))
        _, b = journal(a, fiscal(a, subscriptions=(1, 0), masses=(F(4, 5), None)))
        self.assertEqual(b.public_book.observations[1].settled, F(1, 10))
        _, c = journal(b)
        self.assertEqual(c.public_book.observations[1].settled, F(3, 10))
        self.assertEqual(c.public_book.opening.quarter, 2)
        self.assertEqual(c.public_book.transfers, ())

    def test_fractional_maturity_rights_follow_actual_grid_allocation(self):
        a = fixture(faces=pools({0: 4 * Q}, {0: Q}),
                    masses=pools({0: F(2, 5)}, {0: F(1, 7)}))
        tx, b = journal(a, fiscal(a, rolls=(3 * Q, Q, 0),
            subscriptions=(3 * Q, 0), masses=(F(-3, 5), None), maturity=F(3, 2)))
        self.assertEqual(b.public_book.treasuries[:2], (2 * Q, Q))
        self.assertEqual(b.public_book.terms.annual_treasury[0][:2], (F(1, 5), F(1, 10)))
        # Roll and new issue allocate separately, not their aggregate face.
        self.assertEqual(b.public_book.private_treasuries[0][:2], (3 * Q, Q))
        self.assertEqual(b.public_book.terms.annual_treasury[1][:2],
                         (F(1, 7) - F(2, 5), F(-1, 5)))
        l.validate_funded_public(b.public_book, b.scale, 1, tx.payments)

    def test_mortgage_retirement_still_pays_original_coupon_and_exact_pass_through(self):
        a = fixture(mortgage_rates=(4, -4))
        tx, b = journal(a, fiscal(a, repayments=(1, 1)))
        self.assertEqual(b.public_book.mortgages, (0, 0))
        self.assertEqual(b.public_book.mbs, 0)
        self.assertEqual((b.deposit('HA'), b.deposit('HB')), (F(199, 100), F(201, 100)))
        self.assertEqual(tuple(z.basis for z in b.public_book.observations[3:5]), (1, 1))
        l.validate_funded_public(b.public_book, b.scale, 1, tx.payments)

    def test_missing_terms_authorization_and_principal_funds_refuse_atomically(self):
        a = fixture(tga=0)
        bad = [l.PublicInstructions(treasury_subscriptions=(1, 0), treasury_issue_authorization=1),
               fiscal(a, subscriptions=(1, 0), masses=(0, None), authorization=0),
               fiscal(a, subscriptions=(6, 0), masses=(0, None)),
               fiscal(a, repayments=(4, 0)), fiscal(a, rolls=(1, 0, 0))]
        for instructions in bad:
            before = repr(a)
            with self.subTest(instructions=instructions):
                out = l.advance_given_orders(a, l.ProductionOrders(), l.Controls(public_instructions=instructions))
                self.assertFalse(out.ok)
                self.assertIs(out.state, a)
                self.assertEqual(repr(a), before)
        with self.assertRaises(ValueError):
            l.FundedPublicInstructions(treasury_subscriptions=(1, 0), treasury_issue_authorization=1)

    def test_currency_new_rrp_and_quarterless_settlement_remain_unsupported(self):
        a = fixture()
        for values in ({'currency_to_deposits': (1, 0)}, {'rrp_request': 1},
                       {'rrp_offers': (1, 0)}, {'treasury_redemption': 1}):
            with self.subTest(values=values):
                out = l.advance_given_orders(a, l.ProductionOrders(),
                    l.Controls(public_instructions=l.FundedPublicInstructions(**values)))
                self.assertFalse(out.ok)
                self.assertIs(out.state, a)
        with self.assertRaises(ValueError):
            l.settle_public(a, l.FundedPublicInstructions())
        tx = l._Transaction(a, l.Controls(), 1)
        with self.assertRaises(l._Failure):
            tx.new_rrp(l.FundedPublicInstructions(rrp_request=1, rrp_offers=(1, 0)))

    def test_snapshot_and_administered_rate_are_current_but_coupon_bases_are_opening(self):
        a = fixture(iorb=1)
        tx, b = journal(a, fiscal(a, subscriptions=(1, 0), masses=(0, None)),
                        l.PublicIncomeControls(iorb_rate_pct=-4))
        self.assertEqual(b.public_book.opening.reserves, (5, 5))
        self.assertEqual(b.public_book.opening.terms.iorb_rate_pct, -4)
        self.assertEqual(tuple(z.settled for z in b.public_book.observations[5:7]), (-F(1, 20),) * 2)
        self.assertEqual(tuple(tx.r.values()), (F(79, 20), F(99, 20)))
        self.assertEqual(a.public_book.terms.iorb_rate_pct, 1)

    def test_returned_rrp_principal_never_enlarges_iorb_basis(self):
        old = with_rrp(l.initial_core())
        a = l.enable_funded_public(old, l.public_income_terms(old, iorb_rate_pct=4, rrp_rates_pct=(4, None)))
        tx, b = journal(a)
        self.assertEqual(b.public_book.opening.rrp_faces, (1, 0))
        self.assertEqual(b.public_book.observations[5].basis, a.reserves('A'))
        self.assertEqual(b.public_book.observations[9].settled, F(1, 100))
        self.assertEqual(b.public_book.rrp_claims, ())
        l.validate_funded_public(b.public_book, b.scale, 1, tx.payments)

    def test_signed_and_zero_coupons_loss_then_remittance_waterfall(self):
        a = fixture(masses=pools({1: F(2, 5)}, {1: F(-2, 5)}),
                    mortgage_rates=(-4, 4), iorb=10)
        tx, b = journal(a)
        self.assertEqual(b.public_book.deferred_asset, F(3, 20))
        self.assertFalse(any(p.kind == 'cb_remittance' for p in tx.payments))
        self.assertIn(('BankA', 'Treasury', F(1, 10), 'treasury_coupon', 'Treasury:A'), receipts(tx.payments))
        tx, c = journal(b, controls=l.PublicIncomeControls(iorb_rate_pct=0))
        self.assertEqual(c.public_book.deferred_asset, F(1, 20))
        self.assertFalse(any(p.kind == 'cb_remittance' for p in tx.payments))
        tx, d = journal(c)
        self.assertEqual(d.public_book.deferred_asset, 0)
        self.assertEqual(sum(p.amount for p in tx.payments if p.kind == 'cb_remittance'), F(1, 20))

    def test_public_coupons_never_draw_cb_credit_to_pay(self):
        for rates in ({'iorb': -1000}, {'mortgage_rates': (10000, 0)},
                      {'masses': pools(a={1: -100})}):
            a = fixture(**rates)
            out = l.advance_given_orders(a, l.ProductionOrders(), l.Controls(
                facility_limits=(100, 100), public_instructions=fiscal(a)))
            with self.subTest(rates=rates):
                self.assertFalse(out.ok)
                self.assertEqual(out.status, 'funding_failure')
                self.assertIs(out.state, a)

    def test_new_cb_draw_missing_terms_refuses_but_explicit_zero_allows(self):
        a = fixture()
        tx = l._Transaction(a, l.Controls(facility_limits=(2, 0)), 1)
        with self.assertRaises(l._Failure):
            tx._draw('A', 1)
        self.assertEqual(tx.cb, {})
        covered = replace(a, public_book=replace(a.public_book,
            terms=replace(a.public_book.terms, cb_rates_pct=(0, None))))
        tx = l._Transaction(covered, l.Controls(facility_limits=(2, 0)), 0)
        tx._draw('A', 1)
        state = tx.finish()
        tx, b = journal(state, controls=l.Controls(facility_limits=(1, 0)))
        tx.cb_maturities()
        b = tx.finish()
        self.assertEqual(b.cb_debt('A'), 1)
        self.assertFalse(any(p.kind == 'cb_loan_coupon' for p in tx.payments))

    def test_refinance_entrypoint_checks_missing_cb_terms_before_mutation(self):
        a = fixture(cb_rates=(0, None))
        tx = l._Transaction(a, l.Controls(facility_limits=(1, 0)), 0)
        tx._draw('A', 1)
        a = tx.finish()
        tx = l._Transaction(a, l.Controls(facility_limits=(1, 0)), 1)
        tx.public_book = replace(tx.public_book, terms=replace(tx.public_book.terms, cb_rates_pct=(None, None)))
        before = repr((tx.cb, tx.r, tx.used, tx.payments))
        with self.assertRaises(l._Failure):
            tx.cb_maturities()
        self.assertEqual(repr((tx.cb, tx.r, tx.used, tx.payments)), before)

    def test_missing_existing_cb_and_rrp_terms_refuse_activation(self):
        a = l.initial_core()
        tx = l._Transaction(a, l.Controls(facility_limits=(1, 0)), 0)
        tx._draw('A', 1)
        a = tx.finish()
        with self.assertRaisesRegex(ValueError, 'Missing contractual'):
            l.enable_funded_public(a, l.public_income_terms(a))
        old = with_rrp(l.initial_core())
        with self.assertRaisesRegex(ValueError, 'Missing contractual'):
            l.enable_funded_public(old, l.public_income_terms(old))
        covered = l.enable_funded_public(old, l.public_income_terms(old, rrp_rates_pct=(0, None)))
        tx, b = journal(covered)
        self.assertFalse(any(p.kind == 'rrp_coupon' for p in tx.payments))
        self.assertEqual(b.public_book.rrp_claims, ())

    def test_sequential_private_and_cb_cash_trades_move_exact_rights_once(self):
        a = fixture(faces=pools({1: 10}, {1: 4, 3: 14}, {1: 10}),
                    masses=pools(a={1: F(2, 5), 3: F(14, 5)}))
        tx, _ = journal(a, controls=l.Controls(security_bids=(0, 5)))
        tx.sell_for_funding('A', 5)
        tx.qe(3, (0, 3))
        b = tx.finish()
        events = b.public_book.transfers
        self.assertEqual(events, (f.TreasuryTransfer('A', 'B', 5, F(3, 5)),
                                  f.TreasuryTransfer('B', 'CB', 3, F(3, 35))))
        self.assertEqual(len(events), 2)  # First trade spans two buckets, one event.
        self.assertEqual(sum(p.kind == 'private_public_par_trade' for p in tx.payments), 1)
        self.assertEqual(sum(p.kind == 'public_par_purchase' for p in tx.payments), 1)
        self.assertEqual(b.public_book.observations[2].settled, 0)
        l.validate_funded_public(b.public_book, b.scale, 1, tx.payments)
        _, c = journal(b)
        # B's original ten zero-coupon face shares its earliest bucket with
        # A's four transferred face: CB receives 3/14 of that bucket's .4 mass.
        self.assertEqual(c.public_book.observations[0].contractual, F(3, 140))
        self.assertEqual(c.public_book.observations[2].contractual, F(9, 70))
        self.assertEqual(c.public_book.transfers, ())

    def test_qe_uses_only_actual_offered_and_unencumbered_face(self):
        a = fixture(cb_rates=(0, None))
        tx = l._Transaction(a, l.Controls(facility_limits=(8, 0)), 0)
        tx._draw('A', 8)
        a = tx.finish()
        tx, _ = journal(a)
        tx.qe(100, (100, 0))
        self.assertEqual(tx.qe_applied, 8)  # 10 face still pledged at 80%.
        self.assertEqual(tx.s['A'], 10)
        b = tx.finish()
        self.assertEqual(b.cb_debt('A'), 8)
        l.validate_funded_public(b.public_book, b.scale, 1, tx.payments)

    def test_cb_secondary_sales_are_explicitly_refused(self):
        a = fixture()
        tx, _ = journal(a)
        before = repr((tx.treasuries, tx.payments, tx.public_book))
        with self.assertRaises(l._Failure):
            tx.transfer_treasuries('CB', 'A', 1)
        self.assertEqual(repr((tx.treasuries, tx.payments, tx.public_book)), before)

    def test_validator_binds_final_rights_batch_terms_mortgages_and_opening_clock(self):
        a = fixture(masses=pools(a={1: F(2, 5)}), mortgage_rates=(4, 0))
        tx, b = journal(a, fiscal(a, repayments=(F(1, 10), 0)))
        book = b.public_book
        wrong_mass = tuple(tuple(x + (Q if i == 0 else 0) for i, x in enumerate(row))
                           if n == 1 else row for n, row in enumerate(book.terms.annual_treasury))
        variants = [replace(book, terms=replace(book.terms, annual_treasury=wrong_mass)),
                    replace(book, terms=replace(book.terms, iorb_rate_pct=1)),
                    replace(book, tga=book.tga + Q),
                    replace(book, mortgages=(1, 1), mbs=2),
                    replace(book, funding=replace(book.funding, mortgage_repayments=(0, 0))),
                    replace(book, opening=replace(book.opening, quarter=2)),
                    replace(book, opening=replace(book.opening, scale=2)),
                    replace(book, opening_deferred_asset=1),
                    replace(book, observations=tuple(reversed(book.observations)))]
        for changed in variants:
            with self.subTest(changed=changed), self.assertRaises((ValueError, TypeError)):
                l.validate_funded_public(changed, b.scale, b.quarter, tx.payments)
        for scale, quarter in ((2, 1), (1, 2), (True, 1), (1, True)):
            with self.subTest(scale=scale, quarter=quarter), self.assertRaises((ValueError, TypeError)):
                l.validate_funded_public(book, scale, quarter)

    def test_exact_principal_receipt_counter_catches_missing_invented_and_misattributed_pairs(self):
        a = fixture(faces=pools({0: 2}, {0: 3, 1: 1}, {0: 4}))
        tx, b = journal(a, fiscal(a, rolls=(0, 0, 0), repayments=(1, 1)))
        tx.qe(1, (1, 0)); b = tx.finish()
        paid = tuple(tx.payments)
        changes = [paid + (l.Payment('CB', 'A', 0, 'public_par_purchase', 'Treasury:A'),)]
        for kind in ('tga_funded_treasury_redemption', 'treasury_net_cash',
                     'household_mortgage_principal', 'pass_through_mbs_principal', 'public_par_purchase'):
            p = next(p for p in paid if p.kind == kind)
            changes.extend((tuple(x for x in paid if x is not p), paid + (p,),
                            tuple(replace(x, claim_id='invented') if x is p else x for x in paid),
                            tuple(replace(x, amount=x.amount + Q) if x is p else x for x in paid)))
        for changed in changes:
            with self.subTest(count=len(changed)), self.assertRaisesRegex(ValueError, '[Pp]ublic.*receipt|principal'):
                l.validate_funded_public(b.public_book, b.scale, 1, changed)
        l.validate_funded_public(b.public_book, b.scale, 1, tuple(reversed(paid)))

    def test_transfer_rights_and_order_forgery_refuse(self):
        a = fixture(masses=pools(a={1: F(2, 5)}))
        tx, _ = journal(a, controls=l.Controls(security_bids=(0, 2)))
        tx.sell_for_funding('A', 2); tx.qe(1, (0, 1)); b = tx.finish()
        events = b.public_book.transfers
        for changed in ((replace(events[0], annual_cash=0), events[1]),
                        tuple(reversed(events)), events[:1],
                        events + (f.TreasuryTransfer('CB', 'A', 1, 0),)):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                l.validate_funded_public(replace(b.public_book, transfers=changed), 1, 1, tx.payments)

    def test_full_quarter_private_cash_changes_do_not_break_early_prefix_validation(self):
        old = l.initial_core()
        a = l.enable_funded_public(old, l.public_income_terms(old, treasury_rates_pct=(1, 1, 0),
                                                            mortgage_rates_pct=(1, 1), iorb_rate_pct=1))
        before = repr(a)
        out = l.advance_given_orders(a, l.ProductionOrders(), l.Controls(public_instructions=fiscal(a)))
        self.assertTrue(out.ok, out.reason)
        b = out.state
        l.validate_funded_public(b.public_book, b.scale, b.quarter, b.last.payments)
        self.assertNotEqual(tuple(bank.reserves for bank in b.banks),
            f.project_income(b.public_book.opening, f.project_batch(b.public_book.opening,
                b.public_book.funding), b.public_book.observations).reserves)
        self.assertEqual(repr(a), before)

    def test_forged_receipts_refuse_before_current_report_consumption(self):
        a = fixture()
        out = l.advance_given_orders(a, l.ProductionOrders(), l.Controls(public_instructions=fiscal(a,
            subscriptions=(1, 0), masses=(0, None), repayments=(1, 0))))
        self.assertTrue(out.ok, out.reason)
        b = out.state
        for kinds in ({'treasury_net_cash'}, {'household_mortgage_principal', 'pass_through_mbs_principal'}):
            forged = replace(b, last=replace(b.last, payments=tuple(p for p in b.last.payments if p.kind not in kinds)))
            with self.subTest(kinds=kinds), self.assertRaises(ValueError):
                l.advance_given_orders(forged, l.ProductionOrders(), l.Controls(public_instructions=fiscal(b)))

    def test_duplicate_or_unprepared_funded_phase_refuses(self):
        a = fixture(); tx, _ = journal(a)
        with self.assertRaises(l._Failure):
            tx.settle_funded_public(fiscal(a))
        with self.assertRaises(l._Failure):
            tx.settle_public_income()
        fresh = l._Transaction(a, l.Controls(), 1)
        with self.assertRaises(l._Failure):
            fresh.settle_public_income()

    def test_fresh_and_paid_snapshot_shapes_are_strict(self):
        a = fixture()
        for changes in ({'transfers': []}, {'funding': f.FundingBatch()},
                        {'opening': object()}, {'transfers': (object(),)}):
            with self.subTest(changes=changes), self.assertRaises((TypeError, ValueError)):
                book = replace(a.public_book, **changes)
                l.validate_funded_public(book, a.scale, 0)
        tx, b = journal(a)
        for changes in ({'opening': None}, {'funding': None}):
            with self.subTest(changes=changes), self.assertRaises((TypeError, ValueError)):
                l.validate_funded_public(replace(b.public_book, **changes), 1, 1)

    def test_zero_funded_and_v1_program_preserve_legacy_report_and_stocks(self):
        old = l.initial_core()
        a = l.enable_funded_public(old, l.public_income_terms(old))
        v1 = l.enable_public_income(old, l.public_income_terms(old))
        # Exact original instructions accepted for a zero-subscription program.
        controls = l.Controls(public_instructions=l.PublicInstructions(
            treasury_rolls=fiscal(a).treasury_rolls,
            treasury_issue_authorization=fiscal(a).treasury_issue_authorization,
            replacement_maturity=fiscal(a).replacement_maturity))
        results = [l.advance_given_orders(x, l.ProductionOrders(), controls) for x in (old, a, v1)]
        self.assertTrue(all(o.ok for o in results), [o.reason for o in results])
        for out in results[1:]:
            self.assertEqual(out.state.banks, results[0].state.banks)
            self.assertEqual(out.state.last, results[0].state.last)
            self.assertEqual(out.state.loans, results[0].state.loans)
            self.assertEqual(out.state.gov_debt_face, results[0].state.gov_debt_face)
        self.assertIs(type(results[2].state.public_book), l.PublicIncomeBook)

    def test_q0_changed_actual_claims_cannot_drop_missing_contracts(self):
        a = fixture(cb_rates=(0, None))
        tx = l._Transaction(a, l.Controls(facility_limits=(1, 0)), 0)
        tx._draw('A', 1); a = tx.finish()
        with self.assertRaisesRegex(ValueError, 'Missing contractual'):
            replace(a, public_book=replace(a.public_book,
                terms=replace(a.public_book.terms, cb_rates_pct=(None, None))))
        old = with_rrp(l.initial_core())
        a = l.enable_funded_public(old, l.public_income_terms(old, rrp_rates_pct=(0, None)))
        with self.assertRaisesRegex(ValueError, 'Missing contractual'):
            replace(a, public_book=replace(a.public_book,
                terms=replace(a.public_book.terms, rrp_rates_pct=(None, None))))

    def test_receipt_iterators_preserve_both_exact_principal_and_income_checks(self):
        a = fixture(mortgage_rates=(4, 4), iorb=4)
        tx, b = journal(a, fiscal(a, subscriptions=(1, 0), masses=(0, None)))
        l.validate_funded_public(b.public_book, 1, 1, iter(tx.payments))

    def test_signed_cb_and_rrp_contracts_reverse_only_their_actual_cash_routes(self):
        a = fixture(cb_rates=(-4, 8), rrp_rates=(-4, 4),
                    mortgage_rates=(4, -4), iorb=-4)
        tx = l._Transaction(a, l.Controls(facility_limits=(1, 1)), 0)
        tx._draw('A', 1); tx._draw('B', 1); a = tx.finish()
        a = replace(a, banks=tuple(replace(bank, reserves=bank.reserves - 1) for bank in a.banks),
                    public_book=replace(a.public_book, rrp_claims=(
                        l.RRPClaim('A', 1, 0, 1, ((1, F(1)),)),
                        l.RRPClaim('B', 1, 0, 1, ((1, F(1)),)))))
        tx, b = journal(a)
        self.assertEqual(tuple(tx.earnings.values()), (F(-1, 20), F(-3, 50)))
        self.assertEqual(tuple(tx.r.values()), (F(297, 50), F(119, 20)))
        self.assertEqual(b.public_book.tga, F(2011, 100))
        cash = receipts(tx.payments)
        self.assertIn(('CB', 'BankA', F(1, 100), 'cb_loan_coupon', 'cb_loan:A'), cash)
        self.assertIn(('BankB', 'CB', F(1, 50), 'cb_loan_coupon', 'cb_loan:B'), cash)
        self.assertIn(('BankA', 'CB', F(1, 100), 'rrp_coupon', 'rrp:A'), cash)
        self.assertIn(('CB', 'BankB', F(1, 100), 'rrp_coupon', 'rrp:B'), cash)
        l.validate_funded_public(b.public_book, 1, 1, tx.payments)

    def test_live_principal_and_postincome_prefix_checks_detect_actual_cash_drift(self):
        a = fixture(iorb=-4)
        record = l._Transaction.record
        for kind, message in (('treasury_net_cash', 'principal prefix'),
                              ('cb_remittance', 'postincome prefix')):
            def altered(tx, payer, payee, value, purpose, claim_id=None):
                record(tx, payer, payee, value, purpose, claim_id)
                if purpose == kind:
                    tx.r['A'] += Q
            before = repr(a)
            with self.subTest(kind=kind), patch.object(l._Transaction, 'record', altered):
                with self.assertRaisesRegex(ValueError, message):
                    journal(a, fiscal(a, subscriptions=(1, 0), masses=(0, None)))
            self.assertEqual(repr(a), before)

    def test_income_receipt_and_original_basis_forgery_refuse(self):
        a = fixture(mortgage_rates=(4, 4), iorb=4)
        tx, b = journal(a, fiscal(a, subscriptions=(1, 0), masses=(1, None), repayments=(1, 0)))
        book = b.public_book
        closing_quote = income.quote(book.terms,
            treasuries=(book.treasuries, *book.private_treasuries), mortgages=book.mortgages,
            reserves=tuple(bank.reserves for bank in b.banks), cb_faces=(0, 0),
            rrp_faces=(0, 0), scale=1)
        with self.assertRaisesRegex(ValueError, 'original opening'):
            l.validate_funded_public(replace(book, observations=closing_quote), 1, 1)
        for changed in (tuple(p for p in tx.payments if p.kind not in ('mortgage_coupon', 'mbs_coupon')),
                        tuple(replace(p, claim_id='mortgage:HB') if p.kind == 'mbs_coupon'
                              and p.claim_id == 'mortgage:HA' else p for p in tx.payments)):
            with self.assertRaisesRegex(ValueError, '[Pp]ublic.*receipt|obligation'):
                l.validate_funded_public(book, 1, 1, changed)

    def test_scaled_money_grid_and_signed_newmass_survive_a_paid_transition(self):
        a = fixture(scale=2)
        with self.assertRaises(l._Failure):
            journal(a, fiscal(a, subscriptions=(Q, 0), masses=(0, None)))
        tx, b = journal(a, fiscal(a, subscriptions=(2 * Q, 0), masses=(F(-1, 7), None)))
        self.assertEqual(sum(b.public_book.terms.annual_treasury[1]), F(-1, 7))
        self.assertEqual(b.public_book.observations[1].contractual, 0)
        l.validate_funded_public(b.public_book, 2, 1, tx.payments)

    def test_unfilled_qe_offer_has_no_invented_trade_event_or_cash(self):
        a = fixture()
        tx, _ = journal(a)
        tx.qe(100, (2, 0)); b = tx.finish()
        self.assertEqual(tx.qe_applied, 2)
        self.assertEqual(len(b.public_book.transfers), 1)
        self.assertEqual(b.public_book.transfers[0].face, 2)
        l.validate_funded_public(b.public_book, 1, 1, tx.payments)


if __name__ == '__main__':
    unittest.main()
