"""Pure bounded primary-funding hand cases; no executor or simulated quarter."""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import hashlib
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_market as market
from scripts.research.funded_production import public_scenarios as s
from scripts.research.funded_production import public_forecast as p
from scripts.research.funded_production import public_funding as funding
from scripts.research.funded_production import public_income as income
from scripts.research.funded_production import episodes as e, macro as m, ledger as l
from scripts.research.funded_production.tests.test_public_funding import fixture, pools, with_rrp
from scripts.research.funded_production.tests.test_public_scenarios import (
    tampered, CallbackInt, CallbackFloat, CallbackStr)

Q = F(1, 10**6)
POLICY = m.Policy(3.5, 3.5)


def opening(**kwargs):
    return replace(m.initial(growth=0), sector=fixture(**kwargs))


def date(**kwargs):
    values = dict(policy=POLICY, news=m.News(), iorb_rate_pct=0,
        facility_limits=(100, 100), full_roll=True, new_issue_authorization=10,
        subscription_limits=(5, 5), subscription_rates_pct=(4, -4),
        replacement_maturity=F(118, 5), allocation_priority=('A', 'B'))
    values.update(kwargs)
    return market.MarketFundingDate(**values)


def snapshot(a, rate=0):
    sector = a.sector; book = sector.public_book
    return funding.FundingOpening(quarter=sector.quarter + 1, scale=sector.scale,
        terms=replace(book.terms, iorb_rate_pct=rate),
        treasuries=(book.treasuries, *book.private_treasuries), mortgages=book.mortgages,
        reserves=tuple(bank.reserves for bank in sector.banks),
        household_deposits=tuple(sector.deposit(owner) for owner in ('HA', 'HB')),
        cb_faces=tuple(sector.cb_debt(bank) for bank in l.BANKS),
        rrp_faces=tuple(sector.rrp_face(bank) for bank in l.BANKS),
        tga=book.tga, deferred=book.deferred_asset)


def batch(command):
    return funding.FundingBatch(rolls=command.treasury_rolls,
        subscriptions=command.treasury_subscriptions,
        subscription_coupon_mass=command.subscription_coupon_mass,
        authorization=command.treasury_issue_authorization,
        maturity=command.replacement_maturity)


def coupons(a, rate=0):
    z = snapshot(a, rate)
    return income.quote(z.terms, treasuries=z.treasuries, mortgages=z.mortgages,
        reserves=z.reserves, cb_faces=z.cb_faces, rrp_faces=z.rrp_faces, scale=z.scale)


def digest(value):
    return hashlib.sha256(repr(value).encode()).hexdigest()


class PublicMarketTests(unittest.TestCase):
    def setUp(self):
        self.guards = []
        for target, name in ((p, 'prepare'), (p, 'controls'), (p, 'execute'),
                             (m, 'prepare'), (m, 'execute'),
                             (l, 'advance_given_orders'),
                             (l, '_Transaction')):
            guard = patch.object(target, name,
                side_effect=AssertionError('No forecast, executor or transaction is permitted.'))
            self.guards.append(guard.start())
            self.addCleanup(guard.stop)

    def tearDown(self):
        for guard in self.guards:
            self.assertEqual(guard.call_count, 0, 'Zero-executor proof failed.')

    def resolve(self, a, descriptor=None):
        # No candidate-wide income preflight: mortgage affordability remains a
        # separate calendar constraint, not a Treasury coupon-funding diagnosis.
        with patch.object(funding, 'project_income',
                          side_effect=AssertionError('No whole-income preflight.')) as whole:
            result = market.resolve_date(a, date() if descriptor is None else descriptor)
            self.assertEqual(whole.call_count, 0)
            return result

    def test_descriptor_all_inputs_required_independently_frozen(self):
        names = ['policy', 'news', 'iorb_rate_pct', 'facility_limits', 'full_roll',
                 'new_issue_authorization', 'subscription_limits',
                 'subscription_rates_pct', 'replacement_maturity', 'allocation_priority']
        self.assertEqual([field.name for field in fields(market.MarketFundingDate)], names)
        authored = date()
        values = {name: getattr(authored, name) for name in names}
        for name in names:
            with self.subTest(missing=name), self.assertRaises(TypeError):
                market.MarketFundingDate(**{key: value for key, value in values.items() if key != name})
        self.assertFalse(issubclass(market.MarketFundingDate, s.FullRollDate))
        with self.assertRaises(FrozenInstanceError):
            authored.full_roll = False
        result = self.resolve(opening())
        self.assertIs(type(result), s.ResolvedDate)
        self.assertIs(type(result.step), p.PublicStep)
        self.assertIs(type(result.step.fiscal), l.FundedPublicInstructions)

    def test_one_quantum_short_roll_only_fails_explicit_new_subscription_cures(self):
        a = opening(faces=pools({0: 2}, {0: 3}, {0: 4}),
            masses=pools({0: F(2, 5)}, {0: F(4, 5)}, {0: F(6, 5)}), tga=F(3, 5) - Q)
        old = s.resolve_date(a, s.FullRollDate(POLICY, m.News(), 0, (100, 100)))
        with self.assertRaises(p.FundingFailure):
            p.quote_prefix(a, old.step)
        with self.assertRaises(p.FundingFailure):
            self.resolve(a, date(new_issue_authorization=0))
        before = digest(a)
        result = self.resolve(a)
        command = result.step.fiscal
        self.assertEqual(command.treasury_subscriptions, (Q, 0))
        self.assertEqual(command.treasury_rolls, (2, 3, 4))
        self.assertEqual(command.treasury_issue_authorization, 19)
        self.assertEqual(command.subscription_coupon_mass, (Q / 25, 0))
        self.assertEqual(p.quote_prefix(a, result.step).principal_prefix.tga, F(3, 5))
        self.assertEqual(digest(a), before)

    def test_scaled_ceil_grid_never_rounds_away_an_inherited_shortfall(self):
        for scale in (1, 2, 7, F(3, 2)):
            q = scale * Q
            # Settled coupon is 3q. Inherited TGA may have off-grid dust.
            a = opening(scale=scale, masses=pools({1: 12 * q}), tga=3 * q - q / 3)
            result = self.resolve(a, date(new_issue_authorization=5 * q,
                subscription_limits=(5 * q, 5 * q), facility_limits=(0, 0)))
            self.assertEqual(result.step.fiscal.treasury_subscriptions, (q, 0))
            self.assertEqual(result.step.fiscal.treasury_subscriptions[0] % q, 0)
            principal = funding.project_batch(snapshot(a), batch(result.step.fiscal))
            self.assertEqual(principal.tga, 3 * q + 2 * q / 3)

    def test_signed_mixed_treasury_prefix_not_terminal_netting(self):
        for cash, expected in (((1, -2, 3), 2), ((2, -3, 0), 2),
                               ((-1, 2, -1), 1), ((-2, 1, 0), 0),
                               ((0, 0, 0), 0), ((-1, -1, -1), 0)):
            a = opening(masses=pools({1: 4 * cash[0]}, {1: 4 * cash[1]},
                                    {1: 4 * cash[2]}), tga=0, reserves=(5, 5))
            result = self.resolve(a, date(new_issue_authorization=10))
            self.assertEqual(sum(result.step.fiscal.treasury_subscriptions), expected)

    def test_priority_is_deterministic_and_limits_are_caps_not_orders(self):
        a = opening(masses=pools({1: 12}), tga=0)
        left = self.resolve(a, date(subscription_limits=(1, 4), allocation_priority=('A', 'B')))
        right = self.resolve(a, date(subscription_limits=(1, 4), allocation_priority=('B', 'A')))
        self.assertEqual(left.step.fiscal.treasury_subscriptions, (1, 2))
        self.assertEqual(right.step.fiscal.treasury_subscriptions, (0, 3))
        self.assertEqual(self.resolve(opening()).step.fiscal.treasury_subscriptions, (0, 0))

    def test_authorization_bids_and_reserves_shortfalls_are_known_failures(self):
        a = opening(masses=pools({1: 12}), tga=0, reserves=(1, 1))
        cases = (date(new_issue_authorization=2), date(subscription_limits=(1, 1)), date())
        for descriptor in cases:
            before = digest(a)
            with self.subTest(descriptor=descriptor), self.assertRaises(p.FundingFailure) as error:
                self.resolve(a, descriptor)
            self.assertEqual(error.exception.status, 'funding_failure')
            self.assertEqual(digest(a), before)

    def test_boundaries_exact_funding_and_one_quantum_short_each_limit(self):
        a = opening(masses=pools({1: 4}), tga=0, reserves=(1, 0))
        good = date(new_issue_authorization=1, subscription_limits=(1, 0))
        self.assertEqual(self.resolve(a, good).step.fiscal.treasury_subscriptions, (1, 0))
        for descriptor in (replace(good, new_issue_authorization=1 - Q),
                           replace(good, subscription_limits=(1 - Q, 0))):
            with self.assertRaises(p.FundingFailure):
                self.resolve(a, descriptor)
        poor = opening(masses=pools({1: 4}), tga=0, reserves=(1 - Q, 0))
        with self.assertRaises(p.FundingFailure):
            self.resolve(poor, good)

    def test_false_roll_consent_redeems_principal_and_funds_coupon_separately(self):
        a = opening(faces=pools({0: 2}, {0: 3}, {0: 4}),
            masses=pools({0: 4}), tga=5, reserves=(1, 1))
        result = self.resolve(a, date(full_roll=False, new_issue_authorization=5,
            subscription_limits=(4, 5)))
        command = result.step.fiscal
        self.assertEqual(command.treasury_rolls, (0, 0, 0))
        self.assertEqual(command.treasury_subscriptions, (4, 1))
        self.assertEqual(command.treasury_issue_authorization, 5)
        principal = funding.project_batch(snapshot(a), batch(command))
        self.assertEqual(principal.tga, 1)
        self.assertEqual(principal.reserves, (0, 4))
        with self.assertRaises(p.FundingFailure):
            self.resolve(a, date(full_roll=False, new_issue_authorization=4))

    def test_cb_due_reduces_tga_but_never_supplies_private_subscription_reserves(self):
        a = opening(faces=pools({0: 3}, {1: 1}, {1: 1}), tga=0, reserves=(0, 0))
        with self.assertRaises(p.FundingFailure):
            self.resolve(a, date(full_roll=False))
        funded = opening(faces=pools({0: 3}, {1: 1}, {1: 1}), tga=0, reserves=(3, 0))
        result = self.resolve(funded, date(full_roll=False))
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (3, 0))
        principal = funding.project_batch(snapshot(funded), batch(result.step.fiscal))
        self.assertEqual((principal.tga, principal.reserves), (0, (0, 0)))

    def test_private_due_can_fund_same_date_subscription_not_a_roll(self):
        a = opening(faces=pools({1: 1}, {0: 3}, {1: 1}),
                    tga=0, reserves=(0, 0))
        result = self.resolve(a, date(full_roll=False, subscription_limits=(3, 0)))
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (3, 0))
        self.assertEqual(funding.project_batch(snapshot(a), batch(result.step.fiscal)).reserves, (0, 0))
        self.assertEqual(self.resolve(a).step.fiscal.treasury_subscriptions, (0, 0))

    def test_rrp_return_is_available_but_original_iorb_and_rrp_bases_do_not_change(self):
        old = with_rrp(l.initial_core())
        old = replace(old, banks=(replace(old.banks[0], reserves=0), replace(old.banks[1], reserves=0)),
            public_book=replace(old.public_book, capital_other=old.public_book.capital_other
                + sum(bank.reserves for bank in old.banks)))
        sector = l.enable_funded_public(old, l.public_income_terms(old,
            treasury_rates_pct=(0, 0, 0), rrp_rates_pct=(0, None)))
        # Synthetic q0 book with a 1-unit CB coupon and no TGA.
        book = sector.public_book
        masses = pools({1: 4})
        sector = replace(sector, public_book=replace(book, tga=0,
            capital_other=book.capital_other + book.tga,
            terms=replace(book.terms, annual_treasury=masses)))
        a = replace(m.initial(growth=0), sector=sector)
        result = self.resolve(a, date(iorb_rate_pct=100, subscription_limits=(1, 0)))
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (1, 0))
        principal = funding.project_batch(snapshot(a, 100), batch(result.step.fiscal))
        self.assertEqual(principal.reserves, (0, 0))
        self.assertEqual(tuple(z.basis for z in coupons(a, 100)[5:7]), (0, 0))
        self.assertEqual(coupons(a, 100)[9].basis, 1)

    def test_later_coupons_iorb_remittance_and_facilities_cannot_fund_subscriptions(self):
        a = opening(masses=pools({1: 4}), tga=0, reserves=(0, 0),
                    mortgage_rates=(400, 400), deposits=(3, 3))
        # A later positive remittance exists; it still cannot precede the coupon.
        self.assertGreater(income.earnings_close(0, income.cb_profit(coupons(a)))[1], 0)
        for descriptor in (date(), date(iorb_rate_pct=10**6, facility_limits=(10**6, 10**6)),
                           date(subscription_rates_pct=(-10**6, -10**6))):
            with self.assertRaises(p.FundingFailure):
                self.resolve(a, descriptor)
        # A's future positive Treasury coupon does not augment its bid reserves.
        b = opening(masses=pools({1: 4}, {1: 4}), tga=0, reserves=(0, 2))
        with self.assertRaises(p.FundingFailure):
            self.resolve(b, date(subscription_limits=(2, 0)))

    def test_signed_new_coupon_rates_use_actual_face_not_bids_or_authorization(self):
        a = opening(masses=pools({1: 12}), tga=0)
        for rates in ((-7, 0), (0, 0), (4, -5), (F(1, 7), F(-1, 3))):
            result = self.resolve(a, date(subscription_limits=(1, 5),
                                         subscription_rates_pct=rates))
            command = result.step.fiscal
            self.assertEqual(command.treasury_subscriptions, (1, 2))
            self.assertEqual(command.subscription_coupon_mass,
                             (F(rates[0]) / 100, 2 * F(rates[1]) / 100))
        command = self.resolve(opening(), date(subscription_rates_pct=(-7, 5))).step.fiscal
        self.assertEqual(command.subscription_coupon_mass, (0, 0))

    def test_new_subscriptions_excluded_from_original_coupon_bases(self):
        a = opening(masses=pools({1: 4}), tga=0)
        before = digest(a)
        result = self.resolve(a, date(subscription_rates_pct=(4000000, -4000000)))
        source = snapshot(a)
        observed = coupons(a)
        principal = funding.project_batch(source, batch(result.step.fiscal))
        self.assertEqual(tuple(z.basis for z in observed[:3]), (10, 18, 10))
        self.assertEqual(tuple(z.settled for z in observed[:3]), (1, 0, 0))
        self.assertEqual(sum(principal.terms.annual_treasury[1]), 40000)
        self.assertEqual(a.sector.public_book.terms.annual_treasury, source.terms.annual_treasury)
        self.assertEqual(digest(a), before)

    def test_fractional_maturity_uses_existing_batch_allocation(self):
        a = opening(masses=pools({1: 12 * Q}), tga=0)
        result = self.resolve(a, date(replacement_maturity=F(3, 2),
            subscription_rates_pct=(-7, 0), subscription_limits=(3 * Q, 0)))
        principal = funding.project_batch(snapshot(a), batch(result.step.fiscal))
        self.assertEqual(principal.treasuries[1][:2], (18 + 2 * Q, Q))
        self.assertEqual(principal.terms.annual_treasury[1][:2], (-14 * Q / 100, -7 * Q / 100))

    def test_reserve_dust_is_floored_while_required_new_cash_is_ceiled(self):
        a = opening(masses=pools({1: 8 * Q}), tga=0, reserves=(F(3, 2) * Q, F(3, 2) * Q))
        command = self.resolve(a).step.fiscal
        self.assertEqual(command.treasury_subscriptions, (Q, Q))
        principal = funding.project_batch(snapshot(a), batch(command))
        self.assertEqual(principal.reserves, (Q / 2, Q / 2))

    def test_treasury_negative_coupon_still_requires_own_holder_reserves(self):
        a = opening(masses=pools(a={1: -4}), tga=0, reserves=(0, 5))
        with self.assertRaises(p.FundingFailure):
            self.resolve(a)
        b = opening(masses=pools(a={1: -4}), tga=0, reserves=(1, 0))
        self.assertEqual(self.resolve(b).step.fiscal.treasury_subscriptions, (0, 0))

    def test_mortgage_pre_wage_failure_is_not_misreported_as_treasury_funding(self):
        a = opening(masses=pools({1: 4}), tga=0, deposits=(0, 0), mortgage_rates=(400, 400))
        result = self.resolve(a)
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (1, 0))
        with self.assertRaisesRegex(p.FundingFailure, 'Mortgage coupon'):
            p.quote_prefix(a, result.step)

    def test_actual_own_branch_dues_rights_tga_and_reserves_are_used(self):
        a = opening(faces=pools({0: 2}, {0: 3}, {0: 4}),
            masses=pools({0: 4}, {0: -8}, {0: 12}), tga=0)
        book = a.sector.public_book
        _, faces, terms = funding.make_transfer((book.treasuries, *book.private_treasuries),
                                                book.terms, 'A', 'B', 1)
        b = opening(faces=faces, masses=terms.annual_treasury, tga=F(1, 2), reserves=(2, 5))
        authored = date(allocation_priority=('B', 'A'))
        left = self.resolve(a, authored).step.fiscal
        right = self.resolve(b, authored).step.fiscal
        self.assertEqual(left.treasury_rolls, (2, 3, 4))
        self.assertEqual(right.treasury_rolls, (2, 2, 5))
        self.assertEqual(left.treasury_subscriptions, (0, 2))
        self.assertEqual(right.treasury_subscriptions, (0, F(3, 2)))

    def test_policy_news_iorb_and_facilities_are_explicit_and_own_branch_resolved(self):
        a = opening()
        b = replace(a, macro=replace(a.macro, output_gap_pct=-10))
        authored = date(policy=e.PolicyRule('staff'), news=m.News(demand_shock_pct=-2),
            iorb_rate_pct=s.PolicyIORB(), facility_limits=(0, 7))
        left, right = self.resolve(a, authored), self.resolve(b, authored)
        self.assertNotEqual(left.policy, right.policy)
        for result in (left, right):
            self.assertEqual(result.step.iorb_rate_pct, m.rational(result.policy.rate_pct))
            self.assertEqual(result.news, m.News(demand_shock_pct=-2))
            self.assertEqual(result.step.facility_limits, (0, 7))
        self.assertEqual(self.resolve(a, date(policy=m.Policy(-3, -3), iorb_rate_pct=-7))
                         .step.iorb_rate_pct, -7)
        with self.assertRaises(s.MissingCoverage):
            self.resolve(a, date(policy=e.PolicyRule('promise')))
        active = replace(b, macro=replace(b.macro, guidance_active=True))
        self.assertEqual(self.resolve(active, date(policy=e.PolicyRule('promise'))).policy,
                         e.PolicyRule('promise').resolve(active))

    def test_missing_date_is_unknown_not_implicit_zero_or_funding_failure(self):
        with self.assertRaises(s.MissingCoverage) as error:
            market.resolve_date(opening(), None)
        self.assertEqual(error.exception.status, 'unknown')
        result = self.resolve(opening(), date(full_roll=False, new_issue_authorization=0,
            subscription_limits=(0, 0), subscription_rates_pct=(0, 0), facility_limits=(0, 0)))
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (0, 0))

    def test_numeric_fields_refuse_hostile_nonfinite_and_nested_fraction_components(self):
        bads = (True, CallbackInt(1), CallbackFloat(1), F(CallbackInt(1)),
                object(), lambda: 1, float('nan'), float('inf'), None, '1')
        for bad in bads:
            for name, value in (('iorb_rate_pct', bad), ('facility_limits', (bad, 0)),
                ('new_issue_authorization', bad), ('subscription_limits', (0, bad)),
                ('subscription_rates_pct', (bad, 0)), ('replacement_maturity', bad)):
                with self.subTest(field=name, bad=type(bad)), self.assertRaises((TypeError, ValueError)):
                    date(**{name: value})
        for name in ('new_issue_authorization', 'subscription_limits', 'facility_limits'):
            with self.assertRaises(ValueError):
                date(**{name: -1 if name == 'new_issue_authorization' else (0, -1)})

    def test_boolean_consent_priority_tuple_shapes_and_maturity_are_strict(self):
        for consent in (None, 0, 1, F(1), CallbackInt(1), 'true'):
            with self.assertRaises((TypeError, ValueError)):
                date(full_roll=consent)
        for priority in (None, ['A', 'B'], ('A',), ('A', 'A'), ('CB', 'A'),
                         ('B', 'CB'), (CallbackStr('A'), 'B'), ('B', 'A', 'CB')):
            with self.assertRaises((TypeError, ValueError)):
                date(allocation_priority=priority)
        for field in ('facility_limits', 'subscription_limits', 'subscription_rates_pct'):
            for values in ([0, 0], (0,), (0, 0, 0), (None, 0)):
                with self.assertRaises((TypeError, ValueError)):
                    date(**{field: values})
        for maturity in (0, F(1, 2), 121):
            with self.assertRaises(ValueError):
                date(replacement_maturity=maturity)
        self.assertEqual(date(replacement_maturity=1).replacement_maturity, 1)
        self.assertEqual(date(replacement_maturity=120).replacement_maturity, 120)

    def test_money_fields_checked_on_current_scale_even_if_unused(self):
        a = opening(scale=2)
        for authored in (date(new_issue_authorization=Q), date(subscription_limits=(Q, 0)),
                         date(facility_limits=(Q, 0))):
            self.resolve(opening(), authored)
            with self.assertRaises(ValueError) as error:
                self.resolve(a, authored)
            self.assertNotIsInstance(error.exception, p.FundingFailure)
        a = opening(scale=2, faces=pools({0: Q}, {1: 1}, {1: 1}))
        with self.assertRaises(ValueError) as error:
            self.resolve(a)
        self.assertNotIsInstance(error.exception, p.FundingFailure)
        # False consent does not smuggle an off-grid roll instruction.
        self.assertEqual(self.resolve(a, date(full_roll=False)).step.fiscal.treasury_rolls, (0, 0, 0))

    def test_exact_descriptor_policy_news_and_nested_reconstruction_guards(self):
        class DateSubclass(market.MarketFundingDate):
            pass
        values = {field.name: getattr(date(), field.name) for field in fields(market.MarketFundingDate)}
        for authored in (DateSubclass(**values), object(), lambda: date(),
            s.FullRollDate(POLICY, m.News(), 0, (0, 0)),
            tampered(date(), full_roll=1),
            tampered(date(), allocation_priority=(CallbackStr('A'), 'B')),
            tampered(date(), subscription_rates_pct=(F(CallbackInt(1)), 0)),
            tampered(date(), policy=tampered(e.PolicyRule('staff'), kind=CallbackStr('staff')))):
            with self.assertRaises((TypeError, ValueError)):
                self.resolve(opening(), authored)
        for changes in (dict(policy=None), dict(news=None), dict(iorb_rate_pct='policy'),
            dict(policy=tampered(POLICY, rate_pct=CallbackFloat(3.5))),
            dict(news=tampered(m.News(), demand_shock_pct=True)),
            dict(policy=tampered(POLICY, rate_pct=3.501))):
            with self.assertRaises((TypeError, ValueError)):
                date(**changes)

    def test_canonical_root_guard_precedes_rule_or_funding_calculations(self):
        a = opening()
        bank = tampered(a.sector.banks[0], deposits=(F(CallbackInt(1)), F(3)))
        macro = tampered(a.macro, prior_policy=tampered(POLICY, rate_pct=CallbackFloat(3.5)))
        for root in (object(), tampered(a, macro=macro),
            tampered(a, sector=tampered(a.sector, banks=(bank, a.sector.banks[1]))),
            tampered(a, sector=tampered(a.sector, loans=list(a.sector.loans)))):
            with patch.object(e.PolicyRule, 'resolve', side_effect=AssertionError('Rule ran too soon.')) as rule:
                with patch.object(funding, 'project_batch', side_effect=AssertionError('Arithmetic ran too soon.')) as project:
                    with self.assertRaises((TypeError, ValueError)):
                        market.resolve_date(root, date(policy=e.PolicyRule('staff')))
                    self.assertEqual((rule.call_count, project.call_count), (0, 0))

    def test_root_semantics_versions_invalid_leaves_rechecked_without_mutation(self):
        a = opening()
        roots = (tampered(a, version=True), tampered(a, version=2),
            tampered(a, macro=tampered(a.macro, guidance_active=1)),
            tampered(a, macro=tampered(a.macro, workforce=-1)),
            tampered(a, macro=tampered(a.macro, quarter=1)),
            tampered(a, sector=tampered(a.sector, scale=True)),
            tampered(a, sector=tampered(a.sector, gov_debt_face=a.sector.gov_debt_face + 1)),
            tampered(a, sector=tampered(a.sector, banks=(
                tampered(a.sector.banks[0], reserves=-1), a.sector.banks[1]))))
        for root in roots:
            before = digest(root)
            with self.assertRaises((TypeError, ValueError)):
                market.resolve_date(root, date())
            self.assertEqual(digest(root), before)

    def test_wrong_exact_root_components_are_input_errors_not_attribute_errors(self):
        a = opening()
        for root in (tampered(a, macro=None), tampered(a, sector=None),
                     tampered(a, sector=1), tampered(a, sector=POLICY),
                     tampered(a, macro=a.sector)):
            with self.subTest(root=root), self.assertRaises((TypeError, ValueError)):
                market.resolve_date(root, date())

    def test_paid_history_and_funded_book_validation_precede_new_calculations(self):
        a = opening()
        forged = tampered(a, macro=replace(a.macro, quarter=1),
                          sector=tampered(a.sector, quarter=1))
        forged_book = tampered(a.sector.public_book, income_paid_through=1)
        for root in (forged, tampered(a, sector=tampered(a.sector, public_book=forged_book))):
            with patch.object(funding, 'project_batch', side_effect=AssertionError('New batch ran too soon.')) as project:
                with patch.object(e.PolicyRule, 'resolve', side_effect=AssertionError('Rule ran too soon.')) as rule:
                    with self.assertRaises((TypeError, ValueError)):
                        market.resolve_date(root, date(policy=e.PolicyRule('staff')))
                    self.assertEqual((project.call_count, rule.call_count), (0, 0))
        with patch.object(p, '_paid_economy', wraps=p._paid_economy) as paid:
            with patch.object(l, 'validate_funded_public', wraps=l.validate_funded_public) as validate:
                result = self.resolve(a)
                self.assertIs(type(result), s.ResolvedDate)
                self.assertGreaterEqual(paid.call_count, 1)
                self.assertGreaterEqual(validate.call_count, 1)

    def test_project_batch_proves_principal_and_no_other_cash_routes_are_authored(self):
        a = opening(masses=pools({1: 4}), tga=0)
        with patch.object(funding, 'project_batch', wraps=funding.project_batch) as project:
            result = self.resolve(a)
            self.assertGreaterEqual(project.call_count, 1)
            source, proposed = project.call_args.args
            self.assertIs(type(source), funding.FundingOpening)
            self.assertIs(type(proposed), funding.FundingBatch)
        command = result.step.fiscal
        self.assertEqual((command.currency_to_deposits, command.mortgage_repayments,
                          command.rrp_offers), ((0, 0),) * 3)
        self.assertEqual((command.treasury_redemption, command.rrp_request), (0, 0))
        principal = funding.project_batch(snapshot(a), batch(command))
        self.assertEqual(principal.household_deposits, (3, 3))
        self.assertEqual(tuple(map(sum, principal.treasuries)), (10, 19, 10))
        self.assertEqual(principal.reserves, (4, 5))

    def test_old_full_roll_and_scenario_cells_remain_roll_only_and_unextended(self):
        self.assertEqual([field.name for field in fields(s.FullRollDate)],
            ['policy', 'news', 'iorb_rate_pct', 'facility_limits', 'replacement_maturity'])
        self.assertEqual([field.name for field in fields(s.ScenarioCell)],
                         ['demand_sign', 'fulfilled', 'dates'])
        a = opening(masses=pools({1: 4}), tga=0)
        old = s.FullRollDate(POLICY, m.News(), 0, (0, 0))
        result = s.resolve_date(a, old)
        self.assertEqual(result.step.fiscal.treasury_subscriptions, (0, 0))
        self.assertEqual(result.step.fiscal.subscription_coupon_mass, (None, None))
        with self.assertRaises(p.FundingFailure):
            p.quote_prefix(a, result.step)
        with self.assertRaises(TypeError):
            s.ScenarioCell(1, False, (date(),) * 19)
        with self.assertRaises(TypeError):
            s.resolve_date(a, date())

    def test_root_and_descriptor_digests_remain_unchanged_across_success_and_failure(self):
        a = opening(masses=pools({1: 4}), tga=0)
        good, bad = date(), date(new_issue_authorization=0)
        before = tuple(map(digest, (a, good, bad)))
        canonical_before = p._canonical_value(a)
        self.resolve(a, good)
        with self.assertRaises(p.FundingFailure):
            self.resolve(a, bad)
        self.assertEqual(tuple(map(digest, (a, good, bad))), before)
        self.assertEqual(p._canonical_value(a), canonical_before)


if __name__ == '__main__':
    unittest.main()
