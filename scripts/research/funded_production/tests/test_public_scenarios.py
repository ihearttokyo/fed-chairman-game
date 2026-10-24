"""Pure authored-scenario fixtures, not paid closures or career forecasts."""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_scenarios as s
from scripts.research.funded_production import episodes as e, macro as m, ledger as l
from scripts.research.funded_production import public_forecast as p
from scripts.research.funded_production import public_funding as funding
from scripts.research.funded_production.tests.test_public_funding import fixture, pools


POLICY = m.Policy(3.5, 3.5)


def opening(**kwargs):
    """Construct legal q0 stocks only; never execute a journal."""
    return replace(m.initial(growth=0), sector=fixture(**kwargs))


def date(**kwargs):
    options = dict(policy=POLICY, news=m.News(), iorb_rate_pct=F(0),
                   facility_limits=(F(100), F(100)))
    options.update(kwargs)
    return s.FullRollDate(**options)


def cells(descriptor=None):
    dates = (date() if descriptor is None else descriptor,) * 19
    return tuple(s.ScenarioCell(sign, fulfilled, dates)
                 for sign in (-1, 1) for fulfilled in (False, True))


def tampered(record, **kwargs):
    """Fresh exact class, with constructor-bypassing adversarial old leaves."""
    clone = object.__new__(type(record))
    for field in fields(record):
        object.__setattr__(clone, field.name, kwargs.get(field.name, getattr(record, field.name)))
    return clone


class CallbackInt(int):
    @property
    def numerator(self):
        return self

    def __bool__(self):
        raise AssertionError('Untrusted truthiness ran.')

    def __eq__(self, other):
        raise AssertionError('Untrusted equality ran.')

    def __float__(self):
        raise AssertionError('Untrusted conversion ran.')

    __hash__ = int.__hash__


class CallbackStr(str):
    def __eq__(self, other):
        raise AssertionError('Untrusted rule equality ran.')

    __hash__ = str.__hash__


class CallbackFloat(float):
    def __eq__(self, other):
        raise AssertionError('Untrusted float equality ran.')

    def __float__(self):
        raise AssertionError('Untrusted float conversion ran.')


class PublicScenarioTests(unittest.TestCase):
    def test_explicit_policy_iorb_uses_nominal_quote_not_effective_rate(self):
        a = opening()
        descriptor = date(policy=m.Policy(-3, -3), iorb_rate_pct=s.PolicyIORB())
        resolved = s.resolve_date(a, descriptor)
        self.assertEqual(resolved.step.iorb_rate_pct, -3)
        self.assertNotEqual(resolved.step.iorb_rate_pct, m.rational(m.effective(-3)))
        self.assertEqual(s.resolve_date(a, date(policy=m.Policy(-3, -3),
                                               iorb_rate_pct=0)).step.iorb_rate_pct, 0)

    def test_policy_iorb_follows_own_branch_staff_and_refuses_implicit_modes(self):
        a = opening()
        b = replace(a, macro=replace(a.macro, output_gap_pct=-10))
        descriptor = date(policy=e.PolicyRule('staff'), iorb_rate_pct=s.PolicyIORB())
        resolved = tuple(s.resolve_date(state, descriptor) for state in (a, b))
        self.assertNotEqual(resolved[0].policy, resolved[1].policy)
        for item in resolved:
            self.assertEqual(item.step.iorb_rate_pct, m.rational(item.policy.rate_pct))

        class Subclass(s.PolicyIORB):
            pass

        for value in (None, 'policy', Subclass()):
            with self.subTest(value=type(value).__name__), self.assertRaises((TypeError, ValueError)):
                date(iorb_rate_pct=value)

    def setUp(self):
        # Every test is pure. Even a mistaken attempt must fail before a call
        # can become an actual simulation/paid journal.
        self.forbidden = []
        for target, name in ((p, 'prepare'), (p, 'controls'), (p, 'execute'),
                             (m, 'execute'), (l, 'advance_given_orders')):
            guard = patch.object(target, name, side_effect=AssertionError('No executor/forecast here.'))
            self.forbidden.append(guard.start())
            self.addCleanup(guard.stop)

    def tearDown(self):
        for guard in self.forbidden:
            self.assertEqual(guard.call_count, 0)

    def test_frozen_api_required_inputs_and_defaults(self):
        self.assertEqual([f.name for f in fields(s.FullRollDate)],
            ['policy', 'news', 'iorb_rate_pct', 'facility_limits', 'replacement_maturity'])
        self.assertEqual([f.name for f in fields(s.ScenarioCell)],
            ['demand_sign', 'fulfilled', 'dates'])
        self.assertEqual([f.name for f in fields(s.ResolvedDate)], ['policy', 'news', 'step'])
        for args in ((), (POLICY,), (POLICY, m.News()), (POLICY, m.News(), 0)):
            with self.assertRaises(TypeError):
                s.FullRollDate(*args)
        descriptor = date()
        self.assertEqual(descriptor.replacement_maturity, F(118, 5))
        self.assertIs(type(descriptor.iorb_rate_pct), F)
        self.assertTrue(all(type(x) is F for x in descriptor.facility_limits))
        for record, name in ((descriptor, 'policy'), (cells()[0], 'fulfilled'),
                             (s.resolve_date(opening(), descriptor), 'policy')):
            with self.assertRaises(FrozenInstanceError):
                setattr(record, name, None)

    def test_date_strict_numbers_and_nested_fraction_components(self):
        bad_fraction = F(CallbackInt(1))
        self.assertIs(type(bad_fraction.numerator), CallbackInt)
        for bad in (True, CallbackInt(1), CallbackFloat(1), bad_fraction,
                    object(), lambda: 1, float('nan'), float('inf')):
            for field, value in (('iorb_rate_pct', bad), ('facility_limits', (bad, 1)),
                                 ('replacement_maturity', bad)):
                with self.subTest(field=field, bad=type(bad)), self.assertRaises((TypeError, ValueError)):
                    date(**{field: value})
        for limits in ([1, 1], (1,), (1, -1), (1, 1, 1)):
            with self.assertRaises((TypeError, ValueError)):
                date(facility_limits=limits)
        for maturity in (0, F(1, 2), F(120000001, 1000000)):
            with self.assertRaises(ValueError):
                date(replacement_maturity=maturity)
        self.assertEqual(date(replacement_maturity=1).replacement_maturity, 1)
        self.assertEqual(date(replacement_maturity=120).replacement_maturity, 120)

    def test_policy_and_news_exact_old_leaf_guards_before_constructors(self):
        class PolicySubclass(m.Policy):
            pass
        for policy in (PolicySubclass(3.5, 3.5), object(), lambda: POLICY,
                       tampered(POLICY, rate_pct=CallbackFloat(3.5)),
                       tampered(POLICY, gap_sensitivity=F(CallbackInt(1))),
                       tampered(POLICY, rate_pct=True),
                       tampered(POLICY, rate_pct=3.501),
                       tampered(POLICY, inflation_sensitivity=-1)):
            with self.assertRaises((TypeError, ValueError)):
                date(policy=policy)
        for news in (object(), None, tampered(m.News(), demand_shock_pct=CallbackFloat(0)),
                     tampered(m.News(), demand_shock_pct=True),
                     tampered(m.News(), demand_shock_pct=float('nan'))):
            with self.assertRaises((TypeError, ValueError)):
                date(news=news)

    def test_policy_rules_explicit_kind_and_fixed_policy_validation(self):
        for rule in (e.PolicyRule('fixed', POLICY), e.PolicyRule('staff'), e.PolicyRule('promise')):
            checked = date(policy=rule).policy
            self.assertIs(type(checked), e.PolicyRule)
            self.assertIsNot(checked, rule)
        for rule in (tampered(e.PolicyRule('staff'), kind=CallbackStr('staff')),
                     tampered(e.PolicyRule('staff'), kind='other'),
                     tampered(e.PolicyRule('staff'), fixed=POLICY),
                     tampered(e.PolicyRule('fixed', POLICY), fixed=None),
                     tampered(e.PolicyRule('fixed', POLICY),
                              fixed=tampered(POLICY, rate_pct=CallbackFloat(3.5)))):
            with self.assertRaises((TypeError, ValueError)):
                date(policy=rule)

    def test_cells_require_exact_cartesian_labels_and_nineteen_dates(self):
        good = cells()
        self.assertEqual(len(s.validated_cells(good)), 4)
        for sign in (True, -2, 0, 2, CallbackInt(1), F(1)):
            with self.assertRaises((TypeError, ValueError)):
                s.ScenarioCell(sign, False, (date(),) * 19)
        for fulfilled in (0, 1, CallbackInt(1), None):
            with self.assertRaises((TypeError, ValueError)):
                s.ScenarioCell(1, fulfilled, (date(),) * 19)
        for dates in ([date()] * 19, (date(),) * 18, (date(),) * 20, (object(),) * 19):
            with self.assertRaises((TypeError, ValueError)):
                s.ScenarioCell(1, True, dates)
        for batch in (list(good), good[:3], good + good[:1], (good[0],) * 4,
                      (object(), *good[1:])):
            with self.assertRaises((TypeError, ValueError)):
                s.validated_cells(batch)

    def test_validated_cells_reconstruct_nested_records_and_preserve_missing_dates(self):
        supplied = tuple(replace(cell, dates=cell.dates[:5] + (None,) + cell.dates[6:])
                         for cell in reversed(cells()))
        checked = s.validated_cells(supplied)
        self.assertIs(type(checked), tuple)
        self.assertEqual(checked, supplied)
        for old, new in zip(supplied, checked):
            self.assertIsNot(old, new)
            self.assertIsNot(old.dates[0], new.dates[0])
            self.assertIsNone(new.dates[5])

    def test_constructor_bypass_in_cells_and_dates_is_revalidated(self):
        original = cells()
        bad_dates = (tampered(date(), iorb_rate_pct=F(CallbackInt(1))),) + original[0].dates[1:]
        for changed in (tampered(original[0], demand_sign=CallbackInt(-1)),
                        tampered(original[0], fulfilled=CallbackInt(0)),
                        tampered(original[0], dates=bad_dates)):
            with self.assertRaises((TypeError, ValueError)):
                s.validated_cells((changed, *original[1:]))

    def test_missing_is_unknown_but_explicit_future_zero_is_covered(self):
        a = opening()
        with self.assertRaises(s.MissingCoverage) as error:
            s.resolve_date(a, None)
        self.assertIsInstance(error.exception, ValueError)
        self.assertEqual(error.exception.status, 'unknown')
        zero = date(iorb_rate_pct=0, facility_limits=(0, 0), news=m.News())
        resolved = s.resolve_date(a, zero)
        self.assertIs(type(resolved), s.ResolvedDate)
        self.assertEqual(resolved.news, m.News())
        self.assertEqual(resolved.step.facility_limits, (0, 0))

    def test_actual_branch_holder_dues_not_other_branch_or_snapshot(self):
        a = opening(faces=pools({0: 2}, {0: 3}, {0: 4}),
                    masses=pools({0: F(2, 5)}, {0: F(-4, 5)}, {0: F(6, 5)}))
        book = a.sector.public_book
        # A pure synthetic branch with current rights after an A->B par trade;
        # this is NOT a claimed paid transfer or a real career transition.
        _, faces, terms = funding.make_transfer(
            (book.treasuries, *book.private_treasuries), book.terms, 'A', 'B', F(1))
        b = opening(faces=faces, masses=terms.annual_treasury)
        before = (repr(a), repr(b))
        left, right = (s.resolve_date(branch, date()) for branch in (a, b))
        self.assertEqual(left.step.fiscal.treasury_rolls, (2, 3, 4))
        self.assertEqual(right.step.fiscal.treasury_rolls, (2, 2, 5))
        for resolved in (left, right):
            fiscal = resolved.step.fiscal
            self.assertIs(type(fiscal), l.FundedPublicInstructions)
            self.assertEqual(fiscal.treasury_issue_authorization, 9)
            self.assertEqual((fiscal.treasury_subscriptions, fiscal.currency_to_deposits,
                              fiscal.mortgage_repayments, fiscal.rrp_offers), ((0, 0),) * 4)
            self.assertEqual((fiscal.treasury_redemption, fiscal.rrp_request), (0, 0))
            self.assertEqual(fiscal.subscription_coupon_mass, (None, None))
        self.assertEqual((repr(a), repr(b)), before)

    def test_replacement_preserves_declared_pooled_coupon_mass_without_pricing(self):
        a = opening(faces=pools({0: 2}, {0: 3}, {0: 4}),
                    masses=pools({0: F(2, 5)}, {0: F(-4, 5)}, {0: F(6, 5)}))
        resolved = s.resolve_date(a, date())
        b = a.sector.public_book
        source = funding.FundingOpening(quarter=1, scale=a.sector.scale,
            terms=b.terms, treasuries=(b.treasuries, *b.private_treasuries))
        fiscal = resolved.step.fiscal
        projected = funding.project_batch(source, funding.FundingBatch(
            rolls=fiscal.treasury_rolls, authorization=fiscal.treasury_issue_authorization,
            maturity=fiscal.replacement_maturity))
        self.assertEqual(tuple(map(sum, projected.treasuries)), (2, 3, 4))
        self.assertEqual(tuple(map(sum, projected.terms.annual_treasury)),
                         (F(2, 5), F(-4, 5), F(6, 5)))
        self.assertEqual(projected.payments, ())

    def test_negative_iorb_explicit_independent_of_policy_and_existing_contracts(self):
        a = opening(iorb=2, cb_rates=(None, None))
        descriptor = date(policy=m.Policy(-3, -2), iorb_rate_pct=-7)
        resolved = s.resolve_date(a, descriptor)
        self.assertEqual(resolved.policy, m.Policy(-3, -2))
        self.assertEqual(resolved.step.iorb_rate_pct, -7)
        self.assertNotEqual(resolved.step.iorb_rate_pct, m.effective(-3))
        self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 2)
        self.assertEqual(a.sector.public_book.terms.cb_rates_pct, (None, None))

    def test_staff_and_promise_resolve_own_current_macro_and_fixed_is_honored(self):
        a = opening()
        b = replace(a, macro=replace(a.macro, output_gap_pct=2,
                                     four_quarter_inflation_pct=4))
        rule = e.PolicyRule('staff')
        self.assertEqual(s.resolve_date(a, date(policy=rule)).policy, rule.resolve(a))
        self.assertEqual(s.resolve_date(b, date(policy=rule)).policy, rule.resolve(b))
        self.assertNotEqual(rule.resolve(a), rule.resolve(b))
        self.assertEqual(s.resolve_date(b, date()).policy, POLICY)
        promise = e.PolicyRule('promise')
        with self.assertRaises(s.MissingCoverage):
            s.resolve_date(a, date(policy=promise))
        active = replace(b, macro=replace(b.macro, guidance_active=True,
            prior_policy=m.Policy(3.5, 4, 1.5, .5)))
        self.assertEqual(s.resolve_date(active, date(policy=promise)).policy,
                         promise.resolve(active))

    def test_facility_limits_checked_against_current_branch_money_grid(self):
        a = opening(scale=2)
        descriptor = date(facility_limits=(F(1, 10**6), 0))
        # A descriptor is independent of scale; resolution is not.
        s.resolve_date(opening(), descriptor)
        with self.assertRaises(ValueError):
            s.resolve_date(a, descriptor)
        resolved = s.resolve_date(a, date(facility_limits=(F(2, 10**6), 0)))
        self.assertEqual(resolved.step.facility_limits, (F(2, 10**6), 0))

    def test_resolution_rechecks_tampered_descriptor_and_root_before_field_use(self):
        a = opening()
        for descriptor in (object(), lambda: date(),
                           tampered(date(), policy=tampered(e.PolicyRule('staff'), kind=CallbackStr('staff'))),
                           tampered(date(), facility_limits=(F(CallbackInt(1)), 1))):
            with self.assertRaises((TypeError, ValueError)):
                s.resolve_date(a, descriptor)
        bad_macro = tampered(a.macro, output_gap_pct=CallbackFloat(0))
        bad_bank = tampered(a.sector.banks[0], reserves=F(CallbackInt(1)))
        for root in (object(), tampered(a, macro=bad_macro),
                     tampered(a, sector=tampered(a.sector, banks=(bad_bank, a.sector.banks[1]))),
                     m.initial()):
            with self.assertRaises((TypeError, ValueError, NotImplementedError)):
                s.resolve_date(root, date())

    def test_wait_key_immutable_hashable_and_future_cell_invariant(self):
        a = opening()
        original = cells()
        changed = tuple(replace(cell, dates=(cell.dates[0], cell.dates[1]) +
            (date(news=m.News(demand_shock_pct=cell.demand_sign * 10),
                  policy=e.PolicyRule('promise') if cell.fulfilled else POLICY),) * 17)
            for cell in original)
        keys = []
        for batch in (original, changed):
            for cell in s.validated_cells(batch):
                key = s.wait_observation(a, s.resolve_date(a, cell.dates[1]))
                self.assertIs(type(key), tuple)
                hash(key)
                keys.append(key)
        self.assertTrue(all(key == keys[0] for key in keys))
        self.assertEqual(s.wait_observation(a, s.resolve_date(a, date())), keys[0])

    def test_wait_key_changes_with_current_published_policy_news_and_iorb(self):
        a = opening()
        baseline = s.wait_observation(a, s.resolve_date(a, date()))
        for descriptor in (date(policy=m.Policy(3.75, 3.5)),
                           date(news=m.News(demand_shock_pct=1)), date(iorb_rate_pct=-1)):
            self.assertNotEqual(baseline, s.wait_observation(a, s.resolve_date(a, descriptor)))

    def test_wait_key_changes_with_each_declared_public_macro_field(self):
        a = opening(); resolved = s.resolve_date(a, date())
        baseline = s.wait_observation(a, resolved)
        # These observed indicators, not the full latent Macro record, are the
        # deliberately conservative v1 information set.
        for name in ('price_index', 'annualized_quarterly_inflation_pct',
                     'four_quarter_inflation_pct', 'public_support',
                     'unemployment_rate_pct', 'actual_output_index',
                     'output_gap_pct', 'annualized_actual_growth_pct'):
            kwargs = {name: getattr(a.macro, name) + .1}
            if name == 'price_index':
                kwargs['price_history'] = (*a.macro.price_history[:-1], kwargs[name])
            b = replace(a, macro=replace(a.macro, **kwargs))
            self.assertNotEqual(baseline, s.wait_observation(b, resolved), name)

    def test_wait_key_changes_with_own_cash_capital_wip_and_loan_terms(self):
        a = opening(); resolved = s.resolve_date(a, date())
        baseline = s.wait_observation(a, resolved)
        bank = a.sector.banks[1]
        variants = [replace(a.sector, banks=(a.sector.banks[0],
            replace(bank, deposits=(bank.deposits[0] + 1, bank.deposits[1])))),
            replace(a.sector, vintages=(replace(a.sector.vintages[0], units=2),
                                       *a.sector.vintages[1:])),
            replace(a.sector, wip_units=a.sector.wip_units + 1),
            replace(a.sector, wip_basis=a.sector.wip_basis + 1)]
        own = next(loan for loan in a.sector.loans if loan.borrower == 'F')
        for field, value in (('face', own.face + 1), ('rate_pct', own.rate_pct + 1),
                             ('maturity', own.maturity + 1)):
            variants.append(replace(a.sector, loans=tuple(
                replace(loan, **{field: value}) if loan.id == own.id else loan
                for loan in a.sector.loans)))
        for sector in variants:
            self.assertNotEqual(baseline, s.wait_observation(replace(a, sector=sector), resolved))

    def test_wait_key_ignores_claim_ids_order_and_private_allowances(self):
        a = opening(); resolved = s.resolve_date(a, date())
        baseline = s.wait_observation(a, resolved)
        loans = tuple(replace(loan, id='opaque-alternative-' + str(i),
                              allowance=loan.face / 2)
                      for i, loan in enumerate(reversed(a.sector.loans)))
        changed = replace(a, sector=replace(a.sector, loans=loans,
            vintages=tuple(reversed(a.sector.vintages)), next_private_id=800))
        self.assertEqual(baseline, s.wait_observation(changed, resolved))

    def test_wait_key_ignores_other_cash_private_bank_books_and_latent_macro(self):
        a = opening(); resolved = s.resolve_date(a, date())
        baseline = s.wait_observation(a, resolved)
        banks = tuple(replace(bank, deposits=(bank.deposits[0] + (bank.name == 'A'),
                                              bank.deposits[1] + 3)) for bank in a.sector.banks)
        changed = replace(a, sector=replace(a.sector, banks=banks),
            macro=replace(a.macro, expected_short_inflation_pct=5,
                          r_star_pct=7, credibility=.2, financial_restraint_pct=9,
                          public_hardship_memory=4, productivity_trend=2))
        self.assertEqual(baseline, s.wait_observation(changed, resolved))
        # Published facility capacity and replacement calendars are not in the
        # declared coarse v1 signal (nor is their branch-specific due vector).
        alternative = s.resolve_date(a, date(facility_limits=(1, 2), replacement_maturity=120))
        self.assertEqual(baseline, s.wait_observation(a, alternative))

    def test_wait_key_loan_legal_type_and_dates_are_not_opaque_ids(self):
        a = opening()
        own = l.Loan('own', 'B', 1, -2, 2, 0, 0)
        states = [replace(a, sector=replace(a.sector, loans=(own,))),
                  replace(a, sector=replace(a.sector, loans=(l.OperatingLoan('own', 'B', 1, -2, 2, 0, 0),))),
                  replace(a, sector=replace(a.sector, loans=(l.ProjectLoan('own', 'B', 1, -2, 2, 0, 0),)))]
        keys = tuple(s.wait_observation(root, s.resolve_date(root, date())) for root in states)
        self.assertEqual(len(set(keys)), 3)

    def test_resolved_date_and_observation_revalidate_exact_old_leaves(self):
        a = opening(); resolved = s.resolve_date(a, date())
        for args in ((e.PolicyRule('staff'), m.News(), resolved.step),
                     (tampered(POLICY, rate_pct=CallbackFloat(3.5)), m.News(), resolved.step),
                     (POLICY, object(), resolved.step), (POLICY, m.News(), object())):
            with self.assertRaises((TypeError, ValueError)):
                s.ResolvedDate(*args)
        for bad in (object(), tampered(resolved, news=tampered(m.News(), demand_shock_pct=CallbackFloat(0))),
                    tampered(resolved, step=tampered(resolved.step, iorb_rate_pct=F(CallbackInt(1))))):
            with self.assertRaises((TypeError, ValueError)):
                s.wait_observation(a, bad)
        # Even an omitted field cannot carry a callback into key construction.
        bad_macro = tampered(a.macro, r_star_pct=CallbackFloat(1.5))
        with self.assertRaises((TypeError, ValueError)):
            s.wait_observation(tampered(a, macro=bad_macro), resolved)


if __name__ == '__main__':
    unittest.main()
