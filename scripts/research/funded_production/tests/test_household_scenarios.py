"""Closed household programs and primitive WAIT information; pure guards."""
from contextlib import contextmanager
from dataclasses import FrozenInstanceError, replace
from fractions import Fraction as F
import importlib
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts.research.funded_production import ledger as l, macro as m, checkpoint as k
from scripts.research.funded_production import public_market as market, public_scenarios as old
from scripts.research.funded_production import public_household_paydate as current


COUNTS = dict(attempts=0, paid=0, refused=0, raw_exceptions=0, transactions=0,
              macro_calls=0, macro_closes=0, macro_exceptions=0)
PAID_STATES = []  # Test-only reuse; never part of a quotation.


def modules():
    return importlib.import_module('scripts.research.funded_production.public_household_branches')


def opening(*, debt=False, convention='household', **rates):
    a = m.initial(growth=0)
    a = replace(a, macro=replace(a.macro, price_history=(100.,)*5,
        annualized_quarterly_inflation_pct=0, four_quarter_inflation_pct=0,
        expected_short_inflation_pct=0, expected_long_inflation_pct=0))
    sector = a.sector
    if debt:
        bank = replace(sector.banks[1], deposits=(F(0), sum(sector.banks[1].deposits, F(0))))
        sector = replace(sector, banks=(sector.banks[0], bank))
    rates.setdefault('cb_rates_pct', (0, 0))
    terms = l.public_income_terms(sector, **rates)
    if convention == 'household': sector = l.enable_household_liquidity_public(sector, terms)
    elif convention == 'paydate': sector = l.enable_paydate_public(sector, terms)
    elif convention == 'funded': sector = l.enable_funded_public(sector, terms)
    elif convention == 'early': sector = l.enable_early_paydate_public(sector, terms)
    else: raise ValueError('Unknown test convention')
    return replace(a, sector=sector)


def date(**changes):
    values = dict(policy=m.Policy(3.5,3.5), news=m.News(), iorb_rate_pct=F(0),
        facility_limits=(F(100),F(100)), full_roll=True, new_issue_authorization=F(0),
        subscription_limits=(F(0),F(0)), subscription_rates_pct=(F(0),F(0)),
        replacement_maturity=F(118,5), allocation_priority=('A','B'))
    values.update(changes)
    return market.MarketFundingDate(**values)


def cells(*, missing=None, descriptor=None):
    q = modules(); descriptor = date() if descriptor is None else descriptor
    dates = tuple(None if h == missing else descriptor for h in range(19))
    return tuple(q.ScenarioCell(sign, fulfilled, dates) for sign in (-1,1) for fulfilled in (False,True))


@contextmanager
def counted():
    """Wrap real boundaries, never substitute financial execution; <=50 calls."""
    raw, tx, close = l.advance_given_orders, l._Transaction, m._close_paid
    def inc(name):
        path = os.environ.get('FED571_BUDGET_FILE')
        total = json.loads(Path(path).read_text()) if path and Path(path).exists() else dict(COUNTS)
        if name == 'attempts' and total[name] >= 50:
            raise AssertionError('Initial FIFTY forecast raw calls exhausted; preserve effects.')
        COUNTS[name] += 1; total[name] += 1
        if path: Path(path).write_text(json.dumps(total))
    def called(*args, **kwargs):
        inc('attempts')
        try: result = raw(*args, **kwargs)
        except Exception:
            inc('raw_exceptions'); raise
        inc('paid' if result.ok else 'refused')
        return result
    def constructed(*args, **kwargs):
        inc('transactions'); return tx(*args, **kwargs)
    def closed(*args, **kwargs):
        inc('macro_calls')
        try: result = close(*args, **kwargs)
        except Exception:
            inc('macro_exceptions'); raise
        if result.ok:
            inc('macro_closes'); PAID_STATES.append(result.envelope)
        return result
    with patch.object(l,'advance_given_orders',side_effect=called), \
         patch.object(l,'_Transaction',side_effect=constructed), \
         patch.object(m,'_close_paid',side_effect=closed):
        yield


class HouseholdDataPureTests(unittest.TestCase):
    """Independent data/reducer checks can run before source registration."""
    def test_closed_data_shapes_and_primitive_tokens_have_no_callbacks(self):
        q=modules();calls=[]
        class Alias(int):
            def __int__(self):calls.append('int');return 1
            def __eq__(self,other):calls.append('eq');return True
        for value in (Alias(1),lambda:1,m.Policy(3.5,3.5),l.Loan):
            with self.assertRaises((TypeError,ValueError)):q._tokens(value)
        self.assertEqual(calls,[])
        self.assertNotEqual(q._tokens(True),q._tokens(1))
        self.assertNotEqual(q._tokens(1.),q._tokens(F(1)))
        descriptor=date();object.__setattr__(descriptor,'new_issue_authorization',True)
        with self.assertRaises((TypeError,ValueError)):q.ScenarioCell(-1,False,(descriptor,)*19)
        self.assertIsNot(q.ScenarioCell,old.ScenarioCell)
        from scripts.research.funded_production import paydate_scenarios
        self.assertIsNot(q.ScenarioCell,paydate_scenarios.ScenarioCell)

    def test_float_zero_tokens_are_numeric_but_nonzero_precision_and_types_are_exact(self):
        q=modules()
        self.assertEqual(q._tokens(+0.0),q._tokens(-0.0))
        self.assertEqual(q._tokens(+0.0),('float',(+0.0).hex()))
        tiny=float.fromhex('0x0.0000000000001p-1022')
        for value in (tiny,-tiny,.1,-.1,1.,float.fromhex('0x1.0000000000001p+0')):
            with self.subTest(value=value):
                self.assertEqual(q._tokens(value),('float',value.hex()))
                self.assertNotEqual(q._tokens(value),q._tokens(0.0))
        self.assertNotEqual(q._tokens(1.),q._tokens(float.fromhex('0x1.0000000000001p+0')))
        self.assertEqual(len({q._tokens(x) for x in (False,0,0.,F(0))}),4)
        for value in (float('inf'),float('-inf'),float('nan')):
            with self.assertRaises((TypeError,ValueError)):q._tokens(value)

    def test_missing_date_is_data_not_fabricated_zero_program(self):
        q=modules();cell=q.ScenarioCell(-1,False,(None,)*19)
        self.assertEqual(cell.dates,(None,)*19)
        self.assertIs(q.ProgramDate,market.MarketFundingDate)
        with self.assertRaises((TypeError,ValueError)):q.ScenarioCell(-1,False,(date(),)*18)
        with self.assertRaises((TypeError,ValueError)):k._pack(cell)


class HouseholdScenarioTests(unittest.TestCase):
    def setUp(self):
        self.q = modules(); self.guards = []
        for obj,name in ((l,'advance_given_orders'),(l,'_Transaction'),(m,'_close_paid'),
                         (current,'prepare'),(current,'controls'),(current,'execute')):
            guard = patch.object(obj,name,side_effect=AssertionError('Pure scenario'))
            self.guards.append(guard.start()); self.addCleanup(guard.stop)
    def tearDown(self): self.assertTrue(all(g.call_count == 0 for g in self.guards))

    def test_exact_alias_and_four_cells_do_not_widen_old_schemas(self):
        q = self.q; table = cells()
        self.assertIs(q.ProgramDate,market.MarketFundingDate)
        self.assertEqual(q.validated_cells(table),table)
        with self.assertRaises(FrozenInstanceError): table[0].fulfilled=True
        for wrong in (list(table),table[:3],table[:3]+table[:1]):
            with self.assertRaises((TypeError,ValueError)): q.validated_cells(wrong)
        from scripts.research.funded_production import paydate_scenarios as strict
        for fn in (old.validated_cells,strict.validated_cells):
            with self.assertRaises(TypeError):fn(table)
        for sign,fulfilled in ((True,False),(-1,1)):
            with self.assertRaises((TypeError,ValueError)):q.ScenarioCell(sign,fulfilled,(date(),)*19)
        with self.assertRaises((TypeError,ValueError)):k._pack(table[0])

    def test_explicit_current_resolver_missing_and_exact_old_route_rejections(self):
        q=self.q;root=opening();descriptor=date()
        self.assertEqual(q.resolve_date(root,descriptor),market.resolve_household_paydate_date(root,descriptor))
        with self.assertRaises(q.MissingCoverage):q.resolve_date(root,None)
        for convention in ('funded','paydate','early'):
            with self.assertRaises((TypeError,ValueError)):q.resolve_date(opening(convention=convention),descriptor)
        for fn in (market.resolve_date,market.resolve_paydate_date,market.resolve_early_paydate_date):
            with self.assertRaises(TypeError):fn(root,descriptor)

    def test_observation_is_primitive_typed_and_only_own_public_facts(self):
        q=self.q;root=opening();resolved=q.resolve_date(root,date())
        key=q.wait_observation(root,resolved)
        def primitive(value):
            if type(value) is tuple:
                for child in value:primitive(child)
            else:self.assertIn(type(value),(str,int,bool,float,type(None)))
        primitive(key);hash(key)
        changed=replace(root,macro=replace(root.macro,credibility=.5,r_star_pct=-2,
            expected_short_inflation_pct=-1,expected_long_inflation_pct=3))
        self.assertEqual(key,q.wait_observation(changed,resolved))
        loan=replace(root.sector.loans[0],id='HIDDEN-ID')
        changed=replace(root,sector=replace(root.sector,loans=(loan,)))
        self.assertEqual(key,q.wait_observation(changed,resolved))
        self.assertNotEqual(key,q.wait_observation(root,replace(resolved,news=m.News(demand_shock_pct=1))))
        self.assertNotEqual(key,q.wait_observation(root,replace(resolved,policy=m.Policy(4,4))))

    def test_bank_other_wallets_and_allowances_excluded_but_own_legal_terms_visible(self):
        q=self.q;root=opening();resolved=q.resolve_date(root,date());key=q.wait_observation(root,resolved)
        bank=root.sector.banks[0]
        changed_bank=replace(bank,deposits=(bank.deposits[0]+1,bank.deposits[1]-1))
        changed=replace(root,sector=replace(root.sector,banks=(changed_bank,root.sector.banks[1])))
        self.assertEqual(key,q.wait_observation(changed,resolved))
        loan=root.sector.loans[0]
        changed=replace(root,sector=replace(root.sector,loans=(replace(loan,allowance=1,performing=False),)))
        self.assertEqual(key,q.wait_observation(changed,resolved))
        changed=replace(root,sector=replace(root.sector,loans=(replace(loan,rate_pct=-4),)))
        self.assertNotEqual(key,q.wait_observation(changed,resolved))
        other=root.sector.banks[1]
        changed_bank=replace(other,deposits=(other.deposits[0]-1,other.deposits[1]+1))
        changed=replace(root,sector=replace(root.sector,banks=(bank,changed_bank)))
        self.assertNotEqual(key,q.wait_observation(changed,resolved))

    def test_all_published_news_and_policy_float_zeros_are_equivalent_information(self):
        q=self.q;root=opening();before=repr(root)
        news_names=('demand_shock_pct','supply_innovation_pct','r_star_change_pct',
                    'r_star_reference_change_pct','structural_unemployment_change_pct')
        for name in news_names:
            with self.subTest(news=name):
                left=q.resolve_date(root,date(news=m.News(**{name:+0.0})))
                right=q.resolve_date(root,date(news=m.News(**{name:-0.0})))
                self.assertEqual(left,right)
                self.assertEqual(q.wait_observation(root,left),q.wait_observation(root,right))
                changed=q.resolve_date(root,date(news=m.News(**{name:1e-12})))
                self.assertNotEqual(q.wait_observation(root,left),q.wait_observation(root,changed))
        for name in ('rate_pct','guidance_pct','inflation_sensitivity','gap_sensitivity'):
            with self.subTest(policy=name):
                values=dict(rate_pct=3.5,guidance_pct=3.5,inflation_sensitivity=1.5,gap_sensitivity=.5)
                left=q.resolve_date(root,date(policy=m.Policy(**{**values,name:+0.0})))
                right=q.resolve_date(root,date(policy=m.Policy(**{**values,name:-0.0})))
                self.assertEqual(left,right)
                self.assertEqual(q.wait_observation(root,left),q.wait_observation(root,right))
                changed=q.resolve_date(root,date(policy=m.Policy(**{**values,name:.25})))
                self.assertNotEqual(q.wait_observation(root,left),q.wait_observation(root,changed))
        left=q.resolve_date(root,date(iorb_rate_pct=+0.0))
        right=q.resolve_date(root,date(iorb_rate_pct=-0.0))
        self.assertEqual(left,right)
        self.assertIs(type(left.step.iorb_rate_pct),F)
        self.assertEqual(q.wait_observation(root,left),q.wait_observation(root,right))
        self.assertEqual(repr(root),before)

    def test_all_valid_published_macro_float_zeros_are_equivalent_information(self):
        q=self.q;root=opening();resolved=q.resolve_date(root,date())
        names=('annualized_quarterly_inflation_pct','four_quarter_inflation_pct',
               'public_support','unemployment_rate_pct','output_gap_pct','annualized_actual_growth_pct')
        for name in names:
            with self.subTest(macro=name):
                left=replace(root,macro=replace(root.macro,**{name:+0.0}))
                right=replace(root,macro=replace(root.macro,**{name:-0.0}))
                self.assertEqual(left,right)
                self.assertEqual(q.wait_observation(left,resolved),q.wait_observation(right,resolved))
                changed=replace(root,macro=replace(root.macro,**{name:1e-12}))
                self.assertNotEqual(q.wait_observation(left,resolved),q.wait_observation(changed,resolved))
        # Remaining public fields cannot represent an admitted floating zero:
        # quarter is a plain integer, while price/GDP are strictly positive.
        for name in ('quarter','price_index','actual_output_index'):
            for value in (+0.0,-0.0):
                with self.subTest(invalid_zero=name,value=value),self.assertRaises((TypeError,ValueError)):
                    replace(root.macro,**{name:value})

    def test_future_descriptor_and_promise_labels_cannot_leak_to_WAIT(self):
        q=self.q;root=opening();table=cells();changed=list(table[0].dates)
        changed[18]=date(policy=m.Policy(-3,-3),news=m.News(demand_shock_pct=-20))
        altered=(replace(table[0],dates=tuple(changed)),*table[1:])
        self.assertNotEqual(table,altered)
        current_date=q.resolve_date(root,table[0].dates[1])
        self.assertEqual(q.wait_observation(root,current_date),
                         q.wait_observation(root,q.resolve_date(root,altered[0].dates[1])))
        with self.assertRaises(q.MissingCoverage):q.resolve_date(root,date(policy=old.e.PolicyRule('promise')))

    def test_malicious_nested_metadata_rejects_before_callbacks_or_sorting(self):
        q=self.q;calls=[]
        class Trap(dict):
            def values(self):calls.append('schema');raise AssertionError('callback')
        descriptor=date();object.__setattr__(descriptor,'__dataclass_fields__',Trap())
        with self.assertRaises((TypeError,ValueError)):q.ScenarioCell(-1,False,(descriptor,)*19)
        class Alias(float):
            def __float__(self):calls.append('numeric');return 1.
            def __eq__(self,other):calls.append('equality');return True
        root=opening();object.__setattr__(root.macro,'public_support',Alias(70))
        with self.assertRaises((TypeError,ValueError)):q.wait_observation(root,q.resolve_date(opening(),date()))
        self.assertEqual(calls,[])

    def test_source_binding_and_unknown_vs_explicit_zero_are_not_adoption(self):
        q=self.q
        self.assertIn('public_household_branches',k._SOURCES)
        with patch.object(k,'_check_sources',side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError,'source drift'):q.resolve_date(opening(),date())
        with self.assertRaises((TypeError,ValueError)):q.ScenarioCell(-1,False,(None,)*18)
        self.assertIs(q.MissingCoverage,old.MissingCoverage)
        self.assertIs(type(q.resolve_date(opening(),date()).step.iorb_rate_pct),F)


if __name__=='__main__':unittest.main()
