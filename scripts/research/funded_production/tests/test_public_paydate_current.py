"""Bounded actual current-date bridge, not a future career/recovery test."""
from dataclasses import FrozenInstanceError, fields, replace
from fractions import Fraction as F
import unittest
from unittest.mock import patch

from scripts.research.funded_production import public_paydate as q
from scripts.research.funded_production import public_forecast as p, coupled as c
from scripts.research.funded_production import checkpoint as k, macro as m, ledger as l
from scripts.research.funded_production import public_scenarios as scenarios
from scripts.research.funded_production import paydate_households as household
from scripts.research.funded_production.tests.test_public_funding import fixture, pools, with_rrp


POLICY = m.Policy(3.5, 3.5)
COUNTS = dict(attempts=0, paid=0, refused=0, raw_exceptions=0, macro_closes=0)


def opening(scale=1, cash_poor=False, **rates):
    a = m.initial(scale=scale, growth=0)
    a = replace(a, macro=replace(a.macro, price_history=(100.,) * 5,
        annualized_quarterly_inflation_pct=0, four_quarter_inflation_pct=0,
        expected_short_inflation_pct=0, expected_long_inflation_pct=0))
    sector = a.sector
    if cash_poor:
        b = sector.banks[1]
        sector = replace(sector, banks=(sector.banks[0],
            replace(b, deposits=(sum(b.deposits, F(0)), F(0)))))
    rates.setdefault('cb_rates_pct', (0, 0))
    return replace(a, sector=l.enable_paydate_public(sector,
        l.public_income_terms(sector, **rates)))


def step(a, *, iorb=0, limits=None, **changes):
    book = a.sector.public_book
    rolls = tuple(row[0] for row in (book.treasuries, *book.private_treasuries))
    values = dict(treasury_rolls=rolls, treasury_issue_authorization=sum(rolls))
    values.update(changes)
    return p.PublicStep(iorb, l.FundedPublicInstructions(**values),
        (100 * a.sector.scale,) * 2 if limits is None else limits)


def fixture_opening(**values):
    sector = fixture(**values)
    # Construct the fresh test fixture directly; no production migration route.
    old = sector.public_book
    book = l.PaydatePublicBook(**{f.name: getattr(old, f.name)
                                 for f in fields(l.FundedPublicBook)})
    return replace(opening(), sector=replace(sector, public_book=book))


class PublicPaydateCurrentTests(unittest.TestCase):
    def setUp(self):
        actual = l.advance_given_orders
        close = m._close_paid
        def counted(*args, **kwargs):
            COUNTS['attempts'] += 1
            try:
                out = actual(*args, **kwargs)
            except Exception:
                COUNTS['raw_exceptions'] += 1
                raise
            COUNTS['paid' if out.ok else 'refused'] += 1
            return out
        def closed(*args, **kwargs):
            COUNTS['macro_closes'] += 1
            return close(*args, **kwargs)
        self.advance = patch.object(l, 'advance_given_orders', side_effect=counted).start()
        self.close = patch.object(m, '_close_paid', side_effect=closed).start()
        self.addCleanup(patch.stopall)

    def pure(self):
        self.assertEqual(self.advance.call_count, 0)
        self.assertEqual(self.close.call_count, 0)

    def test_exact_api_frozen_preparation_zero_transaction_or_executor(self):
        a = opening(); before = repr(a)
        self.assertIs(q.PublicStep,p.PublicStep)
        self.assertIs(q.FundingFailure,p.FundingFailure)
        with patch.object(l, '_Transaction', side_effect=AssertionError('Not a quote')):
            prefix = q.quote_prefix(a, step(a))
            prepared = q.prepare(a, POLICY, step(a))
            finance = q.controls(prepared)
        self.assertIs(type(prefix), q.PublicPrefix)
        self.assertIs(type(prepared), q.Prepared)
        for name in ('opening', 'policy', 'step', 'news', 'source', 'orders'):
            self.assertTrue(hasattr(prepared, name))
        self.assertIs(prepared.opening, a)
        self.assertIs(prepared.source.opening, a)
        self.assertIs(type(finance), l.PublicIncomeControls)
        with self.assertRaises(FrozenInstanceError): prepared.orders = l.depth_orders()
        self.assertEqual(repr(a), before)
        self.pure()

    def test_old_prewage_prefix_fails_but_current_wage_case_pays(self):
        a = opening(cash_poor=True, mortgage_rates_pct=(0, 4))
        old = a.sector.public_book
        legacy = replace(a, sector=replace(a.sector, public_book=l.FundedPublicBook(
            **{f.name: getattr(old, f.name) for f in fields(l.FundedPublicBook)})))
        with self.assertRaises(p.FundingFailure): p.prepare(legacy, POLICY, step(legacy))
        prepared = q.prepare(a, POLICY, step(a))
        self.pure()
        out = q.execute(prepared, q.controls(prepared))
        self.assertTrue(out.ok, out.reason)
        self.assertEqual(self.advance.call_count, 1)
        report = out.envelope.sector.last
        wage = next(i for i, z in enumerate(report.payments) if z.kind == 'focal_payroll')
        coupon = next(i for i, z in enumerate(report.payments)
                      if z.kind == 'mortgage_coupon' and z.claim_id == 'mortgage:HB')
        self.assertLess(wage, coupon)
        self.assertGreater(report.payroll_focal, 0)

    def test_conditional_negative_wallet_is_not_owned_cash_or_actual_refusal(self):
        a = opening(cash_poor=True, mortgage_rates_pct=(0, 4000))
        prepared = q.prepare(a, POLICY, step(a))
        budget = prepared.household_budgets[1]
        self.assertIs(type(budget), q.ConditionalBudget)
        self.assertLess(budget.conditional_wallet, 0)
        self.assertEqual(budget.predicted_shortfall, -budget.conditional_wallet)
        self.assertEqual(budget.spending_intention, 0)
        self.assertEqual(prepared.income_prefix.wallets[3], 0)
        self.pure()  # A negative prediction did not refuse or attempt the date.
        out = q.execute(prepared, q.controls(prepared))
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'funding_failure')
        self.assertIs(out.envelope, a)
        self.assertEqual((self.advance.call_count, self.close.call_count), (1, 0))

    def test_conditional_formula_parity_and_signed_income_once(self):
        a = opening(mortgage_rates_pct=(4, -4))
        prepared = q.prepare(a, POLICY, step(a), m.News(demand_shock_pct=-5))
        for i in range(2):
            cash = prepared.principal_prefix.household_deposits[i]
            signed = -prepared.observations[3+i].settled
            self.assertEqual(prepared.income_prefix.wallets[2+i], cash)
            self.assertEqual(prepared.forecast_income[i], prepared.forecast_payroll[i]
                             + prepared.orders.expected_dividends_nominal[i] + signed)
            actual_formula = household.cash_stock_budget(opening_cash=cash,
                paid_wages=prepared.forecast_payroll[i], settled_income=signed,
                previous_income=prepared.previous_income[i],
                forecast_income=prepared.forecast_income[i], cash_ratio=(F(3,20),F(1,21))[i],
                demand_multiplier=prepared.orders.demand_multiplier)
            conditional = prepared.household_budgets[i]
            self.assertEqual((conditional.desired, conditional.conditional_wallet,
                              conditional.spending_intention),
                             (actual_formula.desired, actual_formula.wallet, actual_formula.funded))
        self.pure()

    def test_adaptive_hiring_matches_original_quoter_when_wallets_cover_coupons(self):
        a = opening(mortgage_rates_pct=(4, -4))
        prepared = q.prepare(a, POLICY, step(a), project_units=1)
        signed = tuple(-z.settled for z in prepared.observations[3:5])
        comparison = c._quote_orders(a, prepared.source, F(1),
            household_cash=tuple(d+i for d, i in zip(
                prepared.principal_prefix.household_deposits, signed)),
            current_public=signed, net_income=True)
        self.assertEqual(prepared.orders, comparison.orders)
        self.assertEqual(prepared.forecast_payroll, (17, 3))
        self.assertEqual(prepared.previous_income, (20, F(63,20)))
        self.assertEqual(prepared.orders.expected_dividends_nominal, (3, F(3,20)))
        self.pure()

    def test_source_actual_gdp_price_orders_and_checkpoint(self):
        a = opening(mortgage_rates_pct=(4, -4)); before = repr(a)
        prepared = q.prepare(a, POLICY, step(a, iorb=2), project_units=1)
        out = q.execute(prepared, q.controls(prepared))
        self.assertTrue(out.ok, out.reason)
        self.assertEqual((self.advance.call_count, self.close.call_count), (1, 1))
        self.assertEqual(out.envelope.macro.actual_output_index,
                         4*float(out.envelope.sector.last.real_output))
        self.assertEqual(out.envelope.macro.price_index, prepared.source.price_index)
        self.assertEqual(self.advance.call_args.args[1], prepared.source.orders)
        candidate = k.CandidateState(out.envelope)
        self.assertEqual(k.decode_checkpoint(k.encode_checkpoint(candidate)), candidate)
        self.assertEqual(self.advance.call_count, 1)
        self.assertEqual(repr(a), before)
        with self.assertRaises((TypeError, ValueError)): k._pack(prepared)

    def test_custom_actual_underwriting_refusal_is_atomic_once(self):
        a = opening(); before = repr(a)
        prepared = q.prepare(a, POLICY, step(a))
        finance = replace(q.controls(prepared), new_loans=(
            l.OperatingLoanOffer('A', 10**6, 4, 2, borrower='R'),))
        out = q.execute(prepared, finance)
        self.assertFalse(out.ok)
        self.assertEqual(out.status, 'credit_constraint')
        self.assertIs(out.envelope, a)
        self.assertEqual((self.advance.call_count, self.close.call_count), (1, 0))
        self.assertEqual(repr(a), before)

    def test_signed_zero_iorb_and_original_coupon_bases_after_principal(self):
        a = opening(treasury_rates_pct=(2,-1,0), mortgage_rates_pct=(4,-4), iorb_rate_pct=1)
        for rate in (-4, 0, 4):
            prepared = q.prepare(a, m.Policy(-3,-3), step(a, iorb=rate,
                mortgage_repayments=(F(1,10),0)))
            original = a.sector.public_book
            self.assertEqual(prepared.projected_opening.terms.iorb_rate_pct, rate)
            self.assertEqual(original.terms.iorb_rate_pct, 1)
            self.assertEqual(prepared.projected_opening.terms.annual_treasury,
                             original.terms.annual_treasury)
            self.assertEqual(prepared.projected_opening.terms.mortgage_rates_pct, (4,-4))
            self.assertEqual(prepared.observations[3].basis, original.mortgages[0])
            self.assertEqual(prepared.observations[5].basis, a.sector.reserves('A'))
            self.assertEqual(prepared.income_prefix.wallets[2], a.sector.deposit('HA')-F(1,10))
        self.pure()

    def test_early_bank_earnings_only_quote_conditional_credit_not_cash(self):
        a = opening(); low = q.prepare(a, POLICY, step(a), project_units=1)
        high = q.prepare(a, POLICY, step(a, iorb=40), project_units=1)
        self.assertGreater(high.early_bank_earnings[1], low.early_bank_earnings[1])
        self.assertEqual(high.income_prefix.wallets, low.income_prefix.wallets)
        self.assertEqual(high.orders, low.orders)
        self.assertGreater(q.controls(high).project_commitment.face_ceiling,
                           q.controls(low).project_commitment.face_ceiling)
        self.pure()

    def test_missing_applicable_cb_rrp_terms_unknown_explicit_zero_valid(self):
        a = opening()
        self.assertEqual(q.prepare(a, POLICY, step(a)).projected_opening.terms.cb_rates_pct,(0,0))
        # Valid fresh RRP/CB roots first; then an adversarial absent-term leaf.
        base = m.initial(growth=0); sector = with_rrp(base.sector)
        sector = l.enable_paydate_public(sector,
            l.public_income_terms(sector, cb_rates_pct=(0,0), rrp_rates_pct=(0,None)))
        rrp = replace(base, sector=sector)
        q.quote_prefix(rrp, step(rrp))
        object.__setattr__(rrp.sector.public_book.terms,'rrp_rates_pct',(None,None))
        with self.assertRaises(scenarios.MissingCoverage): q.quote_prefix(rrp, step(rrp))
        from scripts.research.funded_production.tests.test_public_paydate_journal import fixture as paid_fixture
        cb_sector = paid_fixture(cb_a=1, cb_rates=(0,0))
        cb = replace(base, sector=cb_sector)
        q.quote_prefix(cb, step(cb))
        object.__setattr__(cb.sector.public_book.terms,'cb_rates_pct',(None,None))
        with self.assertRaises(scenarios.MissingCoverage): q.quote_prefix(cb, step(cb))
        self.pure()

    def test_returned_rrp_principal_and_early_quote_match_actual_boundary(self):
        base = m.initial(growth=0); sector = with_rrp(base.sector)
        sector = l.enable_paydate_public(sector,l.public_income_terms(sector,
            cb_rates_pct=(0,0),rrp_rates_pct=(4,None),mortgage_rates_pct=(4,-4)))
        a = replace(base,sector=sector)
        prepared = q.prepare(a,POLICY,step(a,iorb=4,mortgage_repayments=(F(1,10),0)))
        self.assertEqual(prepared.projected_opening.rrp_faces,(1,0))
        self.assertEqual(prepared.income_prefix.rrp_faces,(0,0))
        self.assertEqual(prepared.observations[5].basis,a.sector.reserves('A'))
        self.assertEqual(prepared.observations[9].settled,F(1,100))
        self.pure()
        out = q.execute(prepared,q.controls(prepared)); self.assertTrue(out.ok,out.reason)
        self.assertEqual(out.envelope.sector.public_book.phases[2].snapshot,
                         prepared.income_prefix)
        self.assertEqual((self.advance.call_count,self.close.call_count),(1,1))

    def test_conditional_nominal_scaling_preserves_orders_and_income_history(self):
        quotes = []
        for scale in (1,7):
            a = opening(scale=scale,mortgage_rates_pct=(4,-4))
            quotes.append(q.prepare(a,POLICY,step(a,iorb=-2),project_units=1))
        low,high = quotes
        self.assertEqual(replace(low.orders,expected_dividends_nominal=tuple(
            7*x for x in low.orders.expected_dividends_nominal)),high.orders)
        self.assertEqual(high.previous_income,tuple(7*x for x in low.previous_income))
        self.assertEqual(high.income_prefix.previous_income,high.previous_income)
        self.assertEqual(high.income_prefix.previous_dividends,(None,None))
        for lo,hi in zip(low.household_budgets,high.household_budgets):
            self.assertEqual(hi,q.ConditionalBudget(*(7*getattr(lo,f.name)
                                                    for f in fields(q.ConditionalBudget))))
        self.pure()

    def test_tga_short_early_prefix_cannot_use_future_wages_or_remittance(self):
        a = fixture_opening(faces=pools({1:1},{1:1}),
            masses=pools({1:F(3,10)},{1:F(2,5)}), reserves=(1,1),
            deposits=(1,1), tga=F(1,20), mortgage_rates=(400,400), iorb=0)
        with self.assertRaises(p.FundingFailure): q.prepare(a, POLICY, step(a))
        prepared = q.prepare(a, POLICY, step(a, treasury_subscriptions=(F(1,5),0),
            subscription_coupon_mass=(0,None), treasury_issue_authorization=F(1,5)))
        self.assertEqual(prepared.income_prefix.tga, F(3,40))
        self.assertEqual(prepared.income_prefix.deferred, a.sector.public_book.deferred_asset)
        self.assertFalse(any(z[3] == 'cb_remittance' for z in prepared.principal_prefix.payments))
        self.pure()

    def test_prior_paid_history_both_streams_and_iorb_not_rewritten(self):
        a = opening(mortgage_rates_pct=(4,-4))
        first = q.prepare(a, POLICY, step(a, iorb=2))
        paid = q.execute(first, q.controls(first)); self.assertTrue(paid.ok, paid.reason)
        a = paid.envelope; before = repr(a)
        prepared = q.prepare(a, POLICY, step(a, iorb=-4))
        last = a.sector.last
        self.assertEqual(prepared.previous_income, tuple(last.disposable_income(h) for h in ('HA','HB')))
        self.assertEqual(prepared.income_prefix.previous_income, prepared.previous_income)
        divs = (last.dividend_residual+last.bank_dividend_to('HA'),
                last.dividend_focal+last.bank_dividend_to('HB'))
        self.assertEqual(prepared.income_prefix.previous_dividends, divs)
        self.assertEqual(prepared.orders.expected_dividends_nominal, divs)
        self.assertEqual(prepared.forecast_payroll,
            tuple(j*prepared.orders.price_factor*prepared.orders.real_wage*a.sector.scale
                  for j in (last.paid_residual_workers,last.paid_focal_workers)))
        self.assertEqual(a.sector.public_book.terms.iorb_rate_pct, 2)
        self.assertEqual(repr(a), before)
        for field in ('payments','trace'):
            forged = replace(a)
            sector = replace(a.sector)
            report = replace(last)
            object.__setattr__(report,field,getattr(report,field)[1:])
            object.__setattr__(sector,'last',report); object.__setattr__(forged,'sector',sector)
            with patch.object(m,'_quote_source',side_effect=AssertionError('Reject before quote')):
                with self.assertRaises((ValueError,TypeError)): q.prepare(forged,POLICY,step(forged))
        self.assertEqual(self.advance.call_count,1)

    def test_prepared_and_finance_command_binding_zero_calls(self):
        a = opening(); prepared = q.prepare(a,POLICY,step(a)); finance = q.controls(prepared)
        variants = (replace(prepared,step=replace(prepared.step,iorb_rate_pct=1)),
            replace(prepared,step=replace(prepared.step,facility_limits=(0,0))),
            replace(prepared,step=replace(prepared.step,fiscal=replace(prepared.step.fiscal,
                treasury_issue_authorization=prepared.step.fiscal.treasury_issue_authorization+1))),
            replace(prepared,opening=replace(a,macro=replace(a.macro,public_support=69))),
            replace(prepared,orders=replace(prepared.orders,residual_workers=0)),
            replace(prepared,household_budgets=(replace(prepared.household_budgets[0],
                desired=prepared.household_budgets[0].desired+1),prepared.household_budgets[1])))
        for changed in variants:
            with self.assertRaises(ValueError): q.execute(changed,finance)
            with self.assertRaises(ValueError): q.controls(changed)
        for changed in (replace(finance,iorb_rate_pct=1),replace(finance,facility_limits=(0,0)),
            replace(finance,public_instructions=replace(finance.public_instructions,
                treasury_issue_authorization=finance.public_instructions.treasury_issue_authorization+1))):
            with self.assertRaises(ValueError): q.execute(prepared,changed)
        object.__setattr__(prepared.step,'facility_limits',(F(0),F(0)))
        with self.assertRaises(ValueError): q.execute(prepared,finance)
        self.pure()

    def test_nested_metadata_aliases_stale_quote_reject_before_callbacks(self):
        calls = []
        class Alias(float):
            def __eq__(self, other): calls.append('equal'); return True
            def __float__(self): calls.append('float'); return 1.
        class Meta(dict):
            def values(self): calls.append('schema'); return super().values()
        a = opening(); prepared = q.prepare(a,POLICY,step(a)); finance = q.controls(prepared)
        for field,value in (('source',replace(prepared.source,price_index=Alias(123))),
                            ('household_budgets',(replace(prepared.household_budgets[0],
                                conditional_wallet=Alias(100)),prepared.household_budgets[1]))):
            with self.assertRaises((TypeError,ValueError)): q.execute(replace(prepared,**{field:value}),finance)
        for record in (prepared.source,prepared.income_prefix,prepared.household_budgets[0]):
            object.__setattr__(record,'__dataclass_fields__',Meta(type(record).__dataclass_fields__))
            with self.assertRaises((TypeError,ValueError)): q.execute(prepared,finance)
            record.__dict__.pop('__dataclass_fields__')
        object.__setattr__(a,'version',2)
        with patch.object(m,'_quote_source',side_effect=AssertionError('Reject before quote')):
            with self.assertRaises(ValueError): q.quote_prefix(a,step(a))
        self.assertEqual(calls,[])
        self.pure()

    def test_invalid_actual_root_wallet_rejects_before_principal_projection(self):
        a = opening()
        bank = a.sector.banks[0]
        # Same sum, but one illegal owned wallet: aggregate identities alone
        # cannot validate the four actual actor balances.
        object.__setattr__(bank,'deposits',(F(-1),sum(bank.deposits)+1))
        with patch.object(q.funding,'project_batch',side_effect=AssertionError('Invalid root')):
            with self.assertRaises(ValueError): q.quote_prefix(a,step(a))
        self.pure()

    def test_source_check_before_quotation_and_execute(self):
        a = opening(); prepared = q.prepare(a,POLICY,step(a)); finance = q.controls(prepared)
        with patch.object(k,'_check_sources',side_effect=ValueError('Source changed')):
            with patch.object(m,'_quote_source',side_effect=AssertionError('No stale quotes')):
                with self.assertRaises(ValueError): q.prepare(a,POLICY,step(a))
                with self.assertRaises(ValueError): q.execute(prepared,finance)
        self.pure()

    def test_supported_project_tranche_and_one_protected_retirement_prefix(self):
        a = opening(); prepared = q.prepare(a,POLICY,step(a),project_units=2)
        paid = q.execute(prepared,q.controls(prepared)); self.assertTrue(paid.ok,paid.reason)
        a = paid.envelope
        projects = tuple(z for z in a.sector.loans if type(z) is l.ProjectLoan)
        self.assertTrue(projects)
        self.assertEqual(a.sector.wip_units,2)
        due = tuple(z for z in projects if z.maturity == a.sector.quarter+1)
        self.assertTrue(due)
        prepared = q.prepare(a,POLICY,step(a))
        finance = q.controls(prepared)
        self.assertFalse(any(z.loan_id in {x.id for x in projects} for z in finance.renewals))
        paid = q.execute(prepared,finance); self.assertTrue(paid.ok,paid.reason)
        ids = {z.id for z in due}
        self.assertFalse(ids & {z.id for z in paid.envelope.sector.loans})
        retired = sum((z.amount for z in paid.envelope.sector.last.payments
                       if z.kind == 'private_principal' and z.claim_id in ids),F(0))
        self.assertEqual(retired,sum(z.face for z in due))
        self.assertEqual((self.advance.call_count,self.close.call_count),(2,2))

    def test_zero_actual_gdp_has_one_raw_paid_result_but_no_macro_close(self):
        a = opening()
        prepared = q.prepare(a,POLICY,step(a),m.News(demand_shock_pct=-100000))
        out = q.execute(prepared,q.controls(prepared))
        self.assertFalse(out.ok)
        self.assertEqual(out.status,'terminal_crisis')
        self.assertIs(out.envelope,a)
        self.assertEqual((self.advance.call_count,self.close.call_count),(1,0))

    def test_new_cb_credit_absent_contract_retains_raw_unsupported_status(self):
        from scripts.research.funded_production.tests.test_public_paydate_journal import fixture as paid_fixture
        a = replace(opening(),sector=paid_fixture(reserves=(0,0),mortgage_rates=(0,0)))
        prepared = q.prepare(a,POLICY,step(a))
        self.assertEqual(prepared.projected_opening.terms.cb_rates_pct,(None,None))
        out = q.execute(prepared,q.controls(prepared))
        self.assertFalse(out.ok)
        self.assertEqual(out.status,'unsupported_public_income')
        self.assertIs(out.envelope,a)
        self.assertEqual((self.advance.call_count,self.close.call_count),(1,0))

    def test_unsupported_routes_old_adapters_and_old_sources_unchanged(self):
        a = opening(); command = step(a)
        for change in (dict(currency_to_deposits=(1,0)),dict(rrp_request=1),
                       dict(rrp_offers=(1,0)),dict(treasury_redemption=1)):
            with self.assertRaises(NotImplementedError):
                q.prepare(a,POLICY,replace(command,fiscal=replace(command.fiscal,**change)))
        prepared = q.prepare(a,POLICY,command); finance = q.controls(prepared)
        for changed in (replace(finance,asset_purchase_request=1),replace(finance,asset_offers=(1,0)),
                        replace(finance,security_bids=(0,0))):
            with self.assertRaises(NotImplementedError): q.execute(prepared,changed)
        for old in (lambda:m.prepare(a,POLICY),lambda:c.prepare(a,POLICY),
                    lambda:p.prepare(a,POLICY,command)):
            with self.assertRaises((TypeError,NotImplementedError)): old()
        for field in ('consumption_state_pct','deferred_consumption_units'):
            changed = replace(a,macro=replace(a.macro,**{field:1}))
            with self.assertRaises(ValueError): q.prepare(changed,POLICY,step(changed))
        self.pure()


if __name__ == '__main__': unittest.main()
