"""Pure funding hand cases, not ledger, custody or native qualification."""
from dataclasses import FrozenInstanceError, replace
from fractions import Fraction as F
import unittest

from scripts.research.funded_production import public_funding as funding
from scripts.research.funded_production import public_income as income


ZERO = F(0)
Q = F(1, 10**6)


def pools(cb=None, a=None, b=None):
    return tuple(tuple(F((row or {}).get(i, 0)) for i in range(120))
                 for row in (cb, a, b))


def opening(**changes):
    values = dict(quarter=1, scale=F(1), terms=income.PublicIncomeTerms(pools()),
                  treasuries=pools(), mortgages=(F(1), F(1)),
                  reserves=(F(5), F(5)), household_deposits=(F(3), F(3)),
                  cb_faces=(ZERO, ZERO), rrp_faces=(ZERO, ZERO),
                  tga=F(1), deferred=ZERO)
    values.update(changes)
    return funding.FundingOpening(**values)


def observations(state):
    return income.quote(state.terms, treasuries=state.treasuries,
                        mortgages=state.mortgages, reserves=state.reserves,
                        cb_faces=state.cb_faces, rrp_faces=state.rrp_faces,
                        scale=state.scale)


def income_case():
    faces = pools({1: 1}, {1: 1})
    terms = income.PublicIncomeTerms(
        pools({1: F(3, 10)}, {1: F(2, 5)}),
        mortgage_rates_pct=(F(4), F(4)), iorb_rate_pct=F(10))
    return opening(treasuries=faces, terms=terms, reserves=(F(1), F(1)),
                   household_deposits=(F(1), F(1)), tga=F(1, 20))


class FundingBoundaryTests(unittest.TestCase):
    def test_defaults_keep_missing_subscription_terms_distinct_from_zero(self):
        batch = funding.FundingBatch()
        self.assertEqual(batch.subscription_coupon_mass, (None, None))
        self.assertEqual(funding.FundingBatch(
            subscription_coupon_mass=(0, None)).subscription_coupon_mass,
            (ZERO, None))
        self.assertEqual(funding.project_batch(opening(), batch).payments, ())

    def test_all_result_and_instruction_records_are_frozen(self):
        state = opening()
        batch = funding.FundingBatch()
        projected = funding.project_batch(state, batch)
        prefix = funding.project_income(state, projected, observations(state))
        event = funding.TreasuryTransfer('A', 'B', 1, 0)
        for record, field in ((state, 'quarter'), (batch, 'maturity'),
                              (projected, 'tga'), (prefix, 'tga'),
                              (event, 'face')):
            with self.subTest(record=type(record).__name__):
                with self.assertRaises(FrozenInstanceError):
                    setattr(record, field, 2)

    def test_opening_integer_clock_and_positive_scale(self):
        for value in (True, F(1), 1.0, '1', lambda: 1):
            with self.subTest(value=value), self.assertRaises(TypeError):
                opening(quarter=value)
        for value in (0, -1):
            with self.assertRaises(ValueError):
                opening(quarter=value)
            with self.assertRaises(ValueError):
                opening(scale=value)

    def test_numeric_boundaries_refuse_bool_nonfinite_text_and_callbacks(self):
        for value in (True, float('inf'), float('-inf'), float('nan'),
                      '1', None, lambda: 1):
            for field in ('scale', 'tga', 'deferred'):
                with self.subTest(field=field, value=value):
                    with self.assertRaises((TypeError, ValueError)):
                        opening(**{field: value})
            with self.subTest(value=value), self.assertRaises((TypeError, ValueError)):
                funding.FundingBatch(authorization=value)
            with self.subTest(value=value), self.assertRaises((TypeError, ValueError)):
                funding.TreasuryTransfer('A', 'B', 1, value)

    def test_fraction_with_callback_backed_integer_is_not_a_plain_scalar(self):
        calls = []

        class Proxy(int):
            @property
            def numerator(self):
                return self

            def __mul__(self, other):
                calls.append('multiply')
                return int(self) * other

        wrapped = F(Proxy(1))
        self.assertIs(type(wrapped.numerator), Proxy)
        unsafe_terms = income.PublicIncomeTerms(pools(), iorb_rate_pct=wrapped)
        unsafe_line = replace(observations(opening())[0], contractual=wrapped)
        state = opening()
        projection = funding.project_batch(state, funding.FundingBatch())
        unsafe_observations = (unsafe_line, *observations(state)[1:])
        for operation in (
            lambda: opening(tga=wrapped),
            lambda: funding.FundingBatch(authorization=wrapped),
            lambda: funding.TreasuryTransfer('A', 'B', 1, wrapped),
            lambda: opening(terms=unsafe_terms),
            lambda: funding.project_income(state, projection, unsafe_observations),
        ):
            calls.clear()
            with self.subTest(operation=operation):
                with self.assertRaises(TypeError):
                    operation()
                self.assertEqual(calls, [])

    def test_positions_require_exact_immutable_shapes_and_nonnegative_faces(self):
        for field, values in (
            ('reserves', [1, 1]), ('reserves', (1,)),
            ('household_deposits', (1, -1)), ('mortgages', (True, 0)),
            ('cb_faces', (lambda: 1, 0)), ('rrp_faces', (0, float('nan'))),
            ('treasuries', list(pools())), ('treasuries', ((0,) * 119,) * 3),
            ('treasuries', ((0,) * 120,) * 2),
        ):
            with self.subTest(field=field, values=values):
                with self.assertRaises((TypeError, ValueError)):
                    opening(**{field: values})
        with self.assertRaises(TypeError):
            opening(terms=lambda: None)

    def test_orphan_annual_coupon_mass_is_refused(self):
        for mass in (F(1), F(-1)):
            with self.subTest(mass=mass), self.assertRaises(ValueError):
                opening(terms=income.PublicIncomeTerms(pools({1: mass})))

    def test_batch_shapes_nonnegative_fields_and_maturity_bounds(self):
        for changes in (
            {'rolls': [0, 0, 0]}, {'rolls': (0, 0)},
            {'subscriptions': (0, -1)}, {'mortgage_repayments': (True, 0)},
            {'subscription_coupon_mass': [None, None]},
            {'subscription_coupon_mass': (lambda: 1, None)},
            {'authorization': -1}, {'maturity': True}, {'maturity': 0},
            {'maturity': F(120001, 1000)}, {'maturity': float('inf')},
        ):
            with self.subTest(changes=changes), self.assertRaises((TypeError, ValueError)):
                funding.FundingBatch(**changes)

    def test_subscription_requires_explicit_terms_and_zero_face_has_no_mass(self):
        with self.assertRaises(ValueError):
            funding.FundingBatch(subscriptions=(1, 0), authorization=1)
        for mass in (F(1), F(-1)):
            with self.subTest(mass=mass), self.assertRaises(ValueError):
                funding.FundingBatch(subscription_coupon_mass=(mass, None))
        batch = funding.FundingBatch(subscriptions=(1, 0), authorization=1,
                                     subscription_coupon_mass=(0, None))
        self.assertEqual(batch.subscription_coupon_mass, (ZERO, None))

    def test_money_grid_uses_opening_scale_not_fixed_unit(self):
        state = opening(scale=2)
        for changes in (
            {'authorization': Q}, {'rolls': (Q, 0, 0), 'authorization': 2 * Q},
            {'subscriptions': (Q, 0), 'subscription_coupon_mass': (0, None),
             'authorization': 2 * Q}, {'mortgage_repayments': (Q, 0)},
        ):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                funding.project_batch(state, funding.FundingBatch(**changes))
        result = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(2 * Q, 0), subscription_coupon_mass=(F(-1, 7), None),
            authorization=2 * Q))
        self.assertEqual(sum(result.terms.annual_treasury[1]), F(-1, 7))

    def test_projection_and_prefix_validate_receipt_scalars_and_balances(self):
        projected = funding.project_batch(opening(), funding.FundingBatch())
        prefix = funding.project_income(opening(), projected, observations(opening()))
        for record, field, value in (
            (projected, 'reserves', [-1, 0]), (projected, 'tga', -1),
            (prefix, 'earnings', (float('nan'), 0)),
            (prefix, 'deferred', -1), (prefix, 'household_deposits', (0, -1)),
        ):
            with self.subTest(field=field), self.assertRaises((TypeError, ValueError)):
                replace(record, **{field: value})
        for receipts in ([], (('A', 'B', 1, 'kind'),),
                         (('A', 'B', True, 'kind', None),),
                         (('A', 'B', -1, 'kind', None),),
                         (('A', 'B', 1, lambda: 1, None),),
                         (('A', 'B', 1, 'kind', lambda: 1),)):
            with self.subTest(receipts=receipts), self.assertRaises((TypeError, ValueError)):
                replace(projected, payments=receipts)


class FundingBatchTests(unittest.TestCase):
    def test_full_roll_preserves_mass_and_shifts_all_future_cohorts(self):
        faces = pools({0: 10, 2: 2}, {0: 6}, {119: 3})
        masses = pools({0: F(2, 5), 2: F(-1, 10)}, {0: F(3, 5)}, {119: 1})
        state = opening(treasuries=faces, terms=income.PublicIncomeTerms(masses))
        result = funding.project_batch(state, funding.FundingBatch(
            rolls=(10, 6, 0), authorization=16, maturity=120))
        self.assertEqual(result.treasuries, pools({1: 2, 119: 10}, {119: 6}, {118: 3}))
        self.assertEqual(result.terms.annual_treasury,
                         pools({1: F(-1, 10), 119: F(2, 5)},
                               {119: F(3, 5)}, {118: 1}))
        self.assertEqual(result.tga, state.tga)
        self.assertEqual(result.payments, ())

    def test_partial_roll_and_signed_subscription_use_only_real_net_cash(self):
        state = opening(treasuries=pools({0: 10}, {0: 6}, {0: 2}), tga=20,
                        terms=income.PublicIncomeTerms(
                            pools({0: F(2, 5)}, {0: F(3, 5)}, {0: F(-1, 5)})))
        result = funding.project_batch(state, funding.FundingBatch(
            rolls=(4, 3, 0), subscriptions=(1, 4), authorization=12,
            subscription_coupon_mass=(F(-1, 5), F(2, 5)), maturity=2))
        self.assertEqual(result.treasuries, pools({1: 4}, {1: 4}, {1: 4}))
        self.assertEqual(result.terms.annual_treasury,
                         pools({1: F(4, 25)}, {1: F(1, 10)}, {1: F(2, 5)}))
        self.assertEqual(result.tga, 14)
        self.assertEqual(result.reserves, (F(7), F(3)))
        self.assertEqual(result.payments, (
            ('Treasury', 'CB', F(6), 'tga_funded_treasury_redemption', None),
            ('Treasury', 'A', F(2), 'treasury_net_cash', None),
            ('B', 'Treasury', F(2), 'treasury_net_cash', None)))

    def test_fractional_maturity_mass_follows_quantized_principal(self):
        state = opening(treasuries=pools({0: 4 * Q}),
                        terms=income.PublicIncomeTerms(pools({0: F(2, 5)})))
        result = funding.project_batch(state, funding.FundingBatch(
            rolls=(3 * Q, 0, 0), subscriptions=(3 * Q, 0), authorization=6 * Q,
            subscription_coupon_mass=(F(-3, 5), None), maturity=F(3, 2)))
        self.assertEqual(result.treasuries, pools({0: 2 * Q, 1: Q}, {0: 2 * Q, 1: Q}))
        self.assertEqual(result.terms.annual_treasury,
                         pools({0: F(1, 5), 1: F(1, 10)},
                               {0: F(-2, 5), 1: F(-1, 5)}))

    def test_roll_and_subscription_allocate_separately_like_actual_source(self):
        state = opening(treasuries=pools(a={0: Q}),
                        terms=income.PublicIncomeTerms(pools(a={0: F(1, 10)})))
        result = funding.project_batch(state, funding.FundingBatch(
            rolls=(0, Q, 0), subscriptions=(Q, 0), authorization=2 * Q,
            subscription_coupon_mass=(F(1, 5), None), maturity=F(3, 2)))
        self.assertEqual(result.treasuries[1][:2], (2 * Q, ZERO))
        self.assertEqual(result.terms.annual_treasury[1][:2], (F(3, 10), ZERO))

    def test_fractional_last_maturity_and_inherited_off_grid_stocks(self):
        dust = F(7, 10**7)
        state = opening(treasuries=pools({0: dust, 119: dust}))
        result = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(3 * Q, 0), authorization=3 * Q,
            subscription_coupon_mass=(F(3, 10), None), maturity=F(239, 2)))
        self.assertEqual(result.treasuries[0][118], dust)
        self.assertEqual(result.treasuries[1][118:], (2 * Q, Q))
        self.assertEqual(result.terms.annual_treasury[1][118:], (F(1, 5), F(1, 10)))
        self.assertEqual(result.tga, state.tga + 3 * Q - dust)

    def test_rrp_principal_then_mortgage_principal_precedes_treasury(self):
        state = opening(reserves=(ZERO, ZERO), household_deposits=(F(1), F(1)),
                        rrp_faces=(F(1), F(2)))
        result = funding.project_batch(state, funding.FundingBatch(
            mortgage_repayments=(1, 1), subscriptions=(0, 1), authorization=1,
            subscription_coupon_mass=(None, 0)))
        self.assertEqual(result.reserves, (ZERO, ZERO))
        self.assertEqual(result.household_deposits, (ZERO, ZERO))
        self.assertEqual(result.mortgages, (ZERO, ZERO))
        self.assertEqual(result.payments, (
            ('CB', 'A', F(1), 'rrp_principal_repaid', None),
            ('CB', 'B', F(2), 'rrp_principal_repaid', None),
            ('HA', 'MortgagePool', F(1), 'household_mortgage_principal', None),
            ('MortgagePool', 'CB', F(1), 'pass_through_mbs_principal', None),
            ('HB', 'MortgagePool', F(1), 'household_mortgage_principal', None),
            ('MortgagePool', 'CB', F(1), 'pass_through_mbs_principal', None),
            ('B', 'Treasury', F(1), 'treasury_net_cash', None)))

    def test_mortgage_cannot_use_later_treasury_redemption(self):
        state = opening(treasuries=pools(a={0: 1}), reserves=(ZERO, ZERO))
        with self.assertRaisesRegex(ValueError, '[Mm]ortgage'):
            funding.project_batch(state, funding.FundingBatch(mortgage_repayments=(1, 0)))

    def test_mortgage_requires_each_owned_cash_reserve_and_legal_face(self):
        for changes in ({'mortgages': (ZERO, F(1))},
                        {'household_deposits': (ZERO, F(1))},
                        {'reserves': (ZERO, F(1))}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                funding.project_batch(opening(**changes),
                                      funding.FundingBatch(mortgage_repayments=(1, 0)))

    def test_rolls_and_total_issuance_require_holder_and_issuer_consent(self):
        state = opening(treasuries=pools({0: 1}, {0: 1}))
        for batch in (funding.FundingBatch(rolls=(2, 0, 0), authorization=2),
                      funding.FundingBatch(rolls=(1, 1, 0), authorization=1),
                      funding.FundingBatch(rolls=(1, 0, 0), subscriptions=(1, 0),
                                           subscription_coupon_mass=(0, None),
                                           authorization=1)):
            with self.subTest(batch=batch), self.assertRaises(ValueError):
                funding.project_batch(state, batch)

    def test_batch_refuses_negative_tga_or_bank_reserve_prefix(self):
        for state, batch in (
            (opening(treasuries=pools({0: 2}), tga=1), funding.FundingBatch()),
            (opening(reserves=(ZERO, ZERO)), funding.FundingBatch(
                subscriptions=(1, 0), authorization=1, subscription_coupon_mass=(0, None))),
        ):
            before = repr(state)
            with self.assertRaises(ValueError):
                funding.project_batch(state, batch)
            self.assertEqual(repr(state), before)

    def test_non_treasury_rates_and_missing_zero_contracts_are_unchanged(self):
        state = opening(terms=income.PublicIncomeTerms(pools(), (F(-4), F(3)),
                        F(-2), (None, F(0)), (F(0), None)))
        result = funding.project_batch(state, funding.FundingBatch())
        self.assertEqual(result.terms, state.terms)


class FundingIncomeTests(unittest.TestCase):
    def test_subscription_funds_actual_income_then_remit_last_closes_point_12(self):
        state = income_case()
        projected = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(F(1, 5), 0), authorization=F(1, 5),
            subscription_coupon_mass=(0, None)))
        prefix = funding.project_income(state, projected, observations(state))
        self.assertEqual(projected.tga, F(1, 4))
        self.assertEqual(prefix.tga, F(3, 25))
        self.assertEqual(prefix.reserves, (F(183, 200), F(203, 200)))
        self.assertEqual(prefix.household_deposits, (F(99, 100), F(99, 100)))
        self.assertEqual(prefix.earnings, (F(1, 8), F(1, 40)))
        self.assertEqual(prefix.deferred, ZERO)
        self.assertEqual(prefix.payments, income.expected_payments(observations(state), ZERO))
        self.assertFalse(any(p[3] == 'treasury_net_cash' for p in prefix.payments))
        self.assertEqual(prefix.payments[-1],
                         ('CB', 'Treasury', F(9, 200), 'cb_remittance', None))

    def test_insufficient_subscription_cannot_use_hypothetical_future_remit(self):
        state = income_case()
        projected = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(F(1, 10), 0), authorization=F(1, 10),
            subscription_coupon_mass=(0, None)))
        self.assertGreater(income.cb_profit(observations(state)), 0)
        with self.assertRaisesRegex(ValueError, 'TGA'):
            funding.project_income(state, projected, observations(state))

    def test_all_eleven_observations_must_match_original_bases_and_order(self):
        state = income_case()
        projected = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(F(1, 5), 0), authorization=F(1, 5),
            subscription_coupon_mass=(4, None), mortgage_repayments=(F(1, 10), 0)))
        lines = observations(state)
        wrong_basis = (replace(lines[0], basis=lines[0].basis + 1),) + lines[1:]
        wrong_cash = (replace(lines[0], settled=0),) + lines[1:]
        wrong_contract = (replace(lines[0], contractual=0),) + lines[1:]
        changed = income.quote(projected.terms, treasuries=projected.treasuries,
            mortgages=projected.mortgages, reserves=projected.reserves,
            cb_faces=state.cb_faces, rrp_faces=state.rrp_faces, scale=state.scale)
        for supplied in (list(lines), lines[:-1], lines + lines[:1],
                         lines[:1] * 11, tuple(reversed(lines)), wrong_basis,
                         wrong_cash, wrong_contract, changed):
            with self.subTest(supplied=supplied), self.assertRaises((TypeError, ValueError)):
                funding.project_income(state, projected, supplied)
        funding.project_income(state, projected, lines)

    def test_original_iorb_basis_survives_returned_rrp_and_new_subscription(self):
        state = opening(reserves=(F(1), ZERO), rrp_faces=(F(2), ZERO),
            terms=income.PublicIncomeTerms(pools(), iorb_rate_pct=4,
                                           rrp_rates_pct=(0, None)))
        projected = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(1, 0), authorization=1, subscription_coupon_mass=(0, None)))
        prefix = funding.project_income(state, projected, observations(state))
        self.assertEqual(prefix.earnings, (F(1, 100), ZERO))
        self.assertEqual(prefix.reserves, (F(201, 100), ZERO))

    def test_missing_cb_and_rrp_contracts_refuse_but_explicit_zero_covers(self):
        for field, ratefield in (('cb_faces', 'cb_rates_pct'), ('rrp_faces', 'rrp_rates_pct')):
            state = opening(**{field: (F(1), ZERO)})
            projected = funding.project_batch(state, funding.FundingBatch())
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'Missing contractual'):
                funding.project_income(state, projected, ())
            state = replace(state, terms=replace(state.terms, **{ratefield: (0, None)}))
            prefix = funding.project_income(state, projected, observations(state))
            self.assertEqual(prefix.earnings, (ZERO, ZERO))

    def test_cb_origin_outflows_precede_private_mortgage_debits(self):
        state = opening(reserves=(ZERO, F(1)), cb_faces=(F(1), ZERO),
            terms=income.PublicIncomeTerms(pools(), mortgage_rates_pct=(4, 0),
                                           cb_rates_pct=(-4, None)))
        prefix = funding.project_income(state, funding.project_batch(
            state, funding.FundingBatch()), observations(state))
        self.assertEqual(prefix.reserves, (ZERO, F(1)))
        self.assertEqual(prefix.household_deposits, (F(299, 100), F(3)))
        self.assertEqual(prefix.earnings, (F(1, 100), ZERO))

    def test_positive_iorb_funds_mortgage_but_does_not_create_household_cash(self):
        state = opening(reserves=(F(1), ZERO),
            terms=income.PublicIncomeTerms(pools(), mortgage_rates_pct=(400, 0),
                                           iorb_rate_pct=400))
        batch = funding.FundingBatch(subscriptions=(1, 0), authorization=1,
                                     subscription_coupon_mass=(0, None))
        projection = funding.project_batch(state, batch)
        self.assertEqual(projection.reserves, (ZERO, ZERO))
        prefix = funding.project_income(state, projection, observations(state))
        self.assertEqual(prefix.reserves, (ZERO, ZERO))
        self.assertEqual(prefix.household_deposits, (F(2), F(3)))
        state = replace(state, household_deposits=(ZERO, F(3)))
        with self.assertRaisesRegex(ValueError, '[Mm]ortgage'):
            funding.project_income(state, funding.project_batch(
                state, batch), observations(state))

    def test_positive_rrp_coupon_precedes_positive_cb_loan_debit(self):
        state = opening(reserves=(ZERO, ZERO), cb_faces=(F(1), ZERO),
            rrp_faces=(F(1), ZERO), terms=income.PublicIncomeTerms(
                pools(), cb_rates_pct=(400, None), rrp_rates_pct=(400, None)))
        projection = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(1, 0), authorization=1, subscription_coupon_mass=(0, None)))
        self.assertEqual(projection.reserves, (ZERO, ZERO))
        prefix = funding.project_income(state, projection, observations(state))
        self.assertEqual(prefix.reserves, (ZERO, ZERO))
        self.assertEqual(prefix.earnings, (ZERO, ZERO))

    def test_private_coupon_debits_cannot_automatically_borrow(self):
        for rates, positions in (
            ({'iorb_rate_pct': -800}, {}),
            ({'cb_rates_pct': (800, None)}, {'cb_faces': (F(1), ZERO)}),
            ({'rrp_rates_pct': (-1600, None)}, {'rrp_faces': (F(1), ZERO)}),
        ):
            state = opening(reserves=(F(1), ZERO),
                terms=income.PublicIncomeTerms(pools(), **rates), **positions)
            with self.subTest(rates=rates), self.assertRaisesRegex(ValueError, '[Rr]eserves'):
                funding.project_income(state, funding.project_batch(
                    state, funding.FundingBatch()), observations(state))

    def test_treasury_first_rejects_future_cb_receipt_as_current_cash(self):
        state = opening(reserves=(F(1), ZERO), treasuries=pools(a={1: 1}),
            terms=income.PublicIncomeTerms(pools(a={1: -8}), iorb_rate_pct=800))
        with self.assertRaisesRegex(ValueError, '[Rr]eserves'):
            funding.project_income(state, funding.project_batch(
                state, funding.FundingBatch()), observations(state))

    def test_signed_coupons_reverse_routes_and_preserve_earnings_arithmetic(self):
        state = opening(treasuries=pools({1: 1}, {1: 1}),
            cb_faces=(F(1), ZERO), rrp_faces=(ZERO, F(1)),
            terms=income.PublicIncomeTerms(pools({1: F(-2, 5)}, {1: F(-4, 5)}),
                (-4, -8), -4, (-12, None), (None, -16)))
        prefix = funding.project_income(state, funding.project_batch(
            state, funding.FundingBatch()), observations(state))
        self.assertEqual(prefix.earnings, (F(-11, 50), F(-9, 100)))
        self.assertEqual(prefix.household_deposits, (F(301, 100), F(151, 50)))
        # CB profit = -.10 - .03 - .03 + .10 + .04 = -.02.
        self.assertEqual(prefix.deferred, F(1, 50))
        self.assertIn(('CB', 'MortgagePool', F(1, 100), 'mbs_coupon', 'mortgage:HA'),
                      prefix.payments)
        self.assertIn(('BankA', 'Treasury', F(1, 5), 'treasury_coupon', 'Treasury:A'),
                      prefix.payments)

    def test_deferred_loss_is_not_cash_and_profit_covers_it_before_remittance(self):
        state = income_case()
        projected = funding.project_batch(state, funding.FundingBatch(
            subscriptions=(F(1, 5), 0), authorization=F(1, 5),
            subscription_coupon_mass=(0, None)))
        for deferred, closing, remit in ((F(1, 20), F(1, 200), ZERO),
                                         (F(1, 50), ZERO, F(1, 40))):
            current = replace(state, deferred=deferred)
            prefix = funding.project_income(current, projected, observations(current))
            self.assertEqual(prefix.deferred, closing)
            self.assertEqual(prefix.tga, F(3, 40) + remit)
        loss = replace(state, terms=replace(state.terms, iorb_rate_pct=40))
        prefix = funding.project_income(loss, projected, observations(loss))
        self.assertEqual(prefix.deferred, F(21, 200))
        self.assertEqual(prefix.tga, F(3, 40))

    def test_principal_repayment_does_not_erase_opening_mortgage_coupon(self):
        state = opening(terms=income.PublicIncomeTerms(pools(), (4, 0)))
        projected = funding.project_batch(state, funding.FundingBatch(mortgage_repayments=(1, 0)))
        prefix = funding.project_income(state, projected, observations(state))
        self.assertEqual(projected.mortgages[0], 0)
        self.assertEqual(prefix.household_deposits[0], F(199, 100))
        self.assertEqual(prefix.reserves[0], F(399, 100))
        self.assertEqual(len(prefix.payments), 3)
        self.assertTrue(all(p[3] in income.PAYMENT_KINDS for p in prefix.payments))

    def test_full_retirement_preserves_all_signed_opening_obligations(self):
        state = opening(treasuries=pools({0: 2}, {0: 3}, {0: 4}),
            terms=income.PublicIncomeTerms(
                pools({0: F(2, 5)}, {0: F(-4, 5)}, {0: F(6, 5)}), (4, -4)),
            tga=20)
        projection = funding.project_batch(state, funding.FundingBatch(
            mortgage_repayments=(1, 1)))
        prefix = funding.project_income(state, projection, observations(state))
        self.assertFalse(any(sum(row) for row in projection.treasuries))
        self.assertEqual(projection.terms.annual_treasury, pools())
        self.assertEqual(projection.mortgages, (ZERO, ZERO))
        self.assertEqual(prefix.earnings, (F(-1, 5), F(3, 10)))
        self.assertEqual(prefix.household_deposits, (F(199, 100), F(201, 100)))
        self.assertEqual(prefix.tga, F(109, 10))


class TreasuryTransferTests(unittest.TestCase):
    def test_sequential_cross_maturity_transfers_conserve_each_buckets_rights(self):
        for n in range(1, 81):
            faces = pools(a={0: n+2, 37: n+5}, b={0: n+3, 37: n+7})
            terms = income.PublicIncomeTerms(pools(
                a={0: F((-1)**n, n+1), 37: F(2, n+3)},
                b={0: F(3, n+4), 37: F(-5, n+6)}))
            original = faces, terms
            total_face = tuple(map(sum, zip(*faces)))
            total_mass = tuple(map(sum, zip(*terms.annual_treasury)))
            for seller, buyer, face in (('A', 'B', F(n+3)),
                                        ('B', 'CB', F(n+2)),
                                        ('CB', 'A', F(n+1)),
                                        ('B', 'A', F(1, 3))):
                with self.subTest(n=n, seller=seller, buyer=buyer):
                    event, changed, changed_terms = funding.make_transfer(
                        faces, terms, seller, buyer, face)
                    self.assertEqual(funding.apply_transfer(faces, terms, event),
                                     (changed, changed_terms))
                    self.assertEqual(tuple(map(sum, zip(*changed))), total_face)
                    self.assertEqual(tuple(map(sum, zip(*changed_terms.annual_treasury))),
                                     total_mass)
                    faces, terms = changed, changed_terms
            self.assertEqual(original[0],
                             pools(a={0: n+2, 37: n+5}, b={0: n+3, 37: n+7}))

    def test_partial_transfer_preserves_buyer_existing_coupon_mass(self):
        faces = pools(a={3: 10}, b={3: 6})
        terms = income.PublicIncomeTerms(pools(a={3: F(2, 5)}, b={3: F(3, 5)}))
        event, moved, new_terms = funding.make_transfer(faces, terms, 'A', 'B', 4)
        self.assertEqual(event, funding.TreasuryTransfer('A', 'B', F(4), F(4, 25)))
        self.assertEqual((moved[1][3], new_terms.annual_treasury[1][3]), (F(6), F(6, 25)))
        self.assertEqual((moved[2][3], new_terms.annual_treasury[2][3]), (F(10), F(19, 25)))
        self.assertEqual(funding.apply_transfer(faces, terms, event), (moved, new_terms))

    def test_signed_masses_full_and_partial_keep_exact_rights(self):
        for seller_mass, buyer_mass in ((F(-2, 5), F(3, 5)),
                                         (F(2, 5), F(-3, 5))):
            faces = pools(a={0: 10}, b={0: 6})
            terms = income.PublicIncomeTerms(pools(a={0: seller_mass}, b={0: buyer_mass}))
            for face in (F(4), F(10)):
                event, moved, new_terms = funding.make_transfer(faces, terms, 'A', 'B', face)
                self.assertEqual(event.annual_cash, seller_mass * face / 10)
                self.assertEqual(new_terms.annual_treasury[2][0], buyer_mass + event.annual_cash)
                self.assertEqual(sum(row[0] for row in new_terms.annual_treasury),
                                 seller_mass + buyer_mass)
                self.assertTrue(moved[1][0] or not new_terms.annual_treasury[1][0])

    def test_earliest_bucket_order_and_sequence_validate_current_rights(self):
        faces = pools(a={0: 4, 2: 6})
        terms = income.PublicIncomeTerms(pools(a={0: F(2, 5), 2: F(6, 5)}))
        event, moved, new_terms = funding.make_transfer(faces, terms, 'A', 'B', 5)
        self.assertEqual(event.annual_cash, F(3, 5))
        self.assertEqual(moved[1][:3], (ZERO, ZERO, F(5)))
        self.assertEqual(new_terms.annual_treasury[1][2], F(1))
        with self.assertRaisesRegex(ValueError, '[Cc]oupon|annual|rights'):
            funding.apply_transfer(moved, new_terms, event)
        next_event, final, final_terms = funding.make_transfer(moved, new_terms, 'A', 'CB', 5)
        self.assertEqual(next_event.annual_cash, F(1))
        self.assertEqual(funding.apply_transfer(moved, new_terms, next_event), (final, final_terms))

    def test_forged_annual_cash_is_refused_even_with_same_face(self):
        faces = pools(a={1: 10})
        terms = income.PublicIncomeTerms(pools(a={1: F(2, 5)}))
        event, _, _ = funding.make_transfer(faces, terms, 'A', 'B', 4)
        for mass in (ZERO, F(-4, 25), F(4, 25) + F(1, 10**12)):
            with self.subTest(mass=mass), self.assertRaises(ValueError):
                funding.apply_transfer(faces, terms, replace(event, annual_cash=mass))

    def test_unknown_self_zero_negative_and_overdraw_refuse_without_mutation(self):
        faces = pools(a={1: 10})
        terms = income.PublicIncomeTerms(pools(a={1: F(2, 5)}))
        before = repr((faces, terms))
        for seller, buyer, face in (('BankA', 'B', 1), ('A', 'C', 1),
                                   ('A', 'A', 1), ('A', 'B', 0),
                                   ('A', 'B', -1), ('A', 'B', 11),
                                   (lambda: 'A', 'B', 1), ('A', 'B', True)):
            with self.subTest(seller=seller, buyer=buyer, face=face):
                with self.assertRaises((ValueError, TypeError)):
                    funding.make_transfer(faces, terms, seller, buyer, face)
            self.assertEqual(repr((faces, terms)), before)

    def test_transfer_receipt_routes_claims_and_no_price_inference(self):
        for seller, buyer, kind in (('A', 'CB', 'public_par_purchase'),
                                    ('A', 'B', 'private_public_par_trade'),
                                    ('CB', 'B', 'public_par_sale')):
            event = funding.TreasuryTransfer(seller, buyer, F(7, 10), F(-9, 13))
            self.assertEqual(funding.transfer_payment(event),
                (buyer, seller, F(7, 10), kind, 'Treasury:' + seller))


if __name__ == '__main__':
    unittest.main()
