"""Reference codec integration; not native-save migration or model qualification."""
from dataclasses import replace
from fractions import Fraction as F
from pathlib import Path
import hashlib,unittest
from unittest.mock import patch
from scripts.research.funded_production import checkpoint as k,macro as m,ledger as l
from scripts.research.funded_production import early_liquidity as e


def fresh():
    a=m.initial(growth=0)
    return replace(a,sector=l.enable_early_paydate_public(a.sector,
        l.public_income_terms(a.sector,cb_rates_pct=(0,0))))


class EarlyCheckpointPureTests(unittest.TestCase):
    def test_new_records_have_closed_logical_tags_and_source_identity(self):
        for cls in (l.EarlyPhase,l.EarlyCreditWitness,l.LaterCreditWitness,l.EarlyPaydateBook,e.EarlyPlan):
            self.assertIn(cls,k._TAGS)
        self.assertEqual(k._SOURCES['early_liquidity'],
            hashlib.sha256(Path(e.__file__).read_bytes()).hexdigest())

    def test_fresh_exact_book_round_trip_zero_quarters(self):
        root=fresh();state=k.CandidateState(root)
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw:
            text=k.encode_checkpoint(state)
            decoded=k.decode_checkpoint(text)
            self.assertEqual(decoded,state)
            self.assertIs(type(decoded.economy.sector.public_book),l.EarlyPaydateBook)
            self.assertEqual(raw.call_count,0)

    def test_old_current_and_forecast_routes_refuse_new_convention(self):
        from scripts.research.funded_production import public_paydate as old,public_forecast as p
        root=fresh();book=root.sector.public_book
        rolls=tuple(row[0] for row in (book.treasuries,*book.private_treasuries))
        step=p.PublicStep(0,l.FundedPublicInstructions(treasury_rolls=rolls,
            treasury_issue_authorization=sum(rolls)),(100,100))
        with patch.object(l,'advance_given_orders',side_effect=AssertionError('No quarter')) as raw:
            with self.assertRaises((TypeError,NotImplementedError,ValueError)):
                old.prepare(root,m.Policy(3.5,3.5),step)
            self.assertEqual(raw.call_count,0)

    def test_fresh_mutated_numeric_components_refused_before_encoding(self):
        for component in ('bank','macro'):
            root=fresh()
            if component=='bank':
                object.__setattr__(root.sector.banks[0],'reserves',True)
            else:
                object.__setattr__(root.macro,'growth_pct',True)
            with self.assertRaises((TypeError,ValueError)):
                k.encode_checkpoint(k.CandidateState(root))

    def test_fresh_new_book_cannot_invent_paid_history(self):
        root=fresh()
        object.__setattr__(root.sector.public_book,'paid_wages',(F(1),F(0)))
        with self.assertRaises((TypeError,ValueError)):
            k.encode_checkpoint(k.CandidateState(root))

    def test_new_source_failure_precedes_codec(self):
        root=fresh()
        with patch.object(k,'_check_sources',side_effect=ValueError('source drift')):
            with self.assertRaisesRegex(ValueError,'source drift'):
                k.encode_checkpoint(k.CandidateState(root))


class EarlyCheckpointActualTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        a=fresh();policy=m.Policy(3.5,3.5)
        source=m._quote_source(a,policy,m.News())
        # _quote_source has placeholder orders; bind the same quoted nominal
        # price used by the macro close, never waive invoice reconciliation.
        orders=replace(source.orders,market_clearing=True,
                       price_factor=m.rational(source.price_index/100))
        source=replace(source,orders=orders)
        book=a.sector.public_book
        rolls=tuple(row[0] for row in (book.treasuries,*book.private_treasuries))
        finance=l.PublicIncomeControls(iorb_rate_pct=0,
            public_instructions=l.FundedPublicInstructions(treasury_rolls=rolls,
                treasury_issue_authorization=sum(rolls)),facility_limits=(100,100),
            household_mode='cash_stock_close_v1')
        raw=l.advance_given_orders(a.sector,orders,finance)
        if not raw.ok:raise AssertionError('Retain one-attempt codec fixture failure: '+raw.status+': '+raw.reason)
        if raw.state.last.real_output<=0:raise AssertionError('Codec fixture has no positive paid GDP.')
        out=m._close_paid(source,raw.state,closing_households=True)
        if not out.ok:raise AssertionError('Codec fixture macro close failed: '+out.reason)
        cls.root=a;cls.state=k.CandidateState(out.envelope)

    def test_paid_witness_round_trip_and_preserved_original(self):
        self.assertEqual(k.decode_checkpoint(k.encode_checkpoint(self.state)),self.state)
        self.assertEqual(self.root.macro.quarter,0)
        self.assertIs(type(self.state.economy.sector.public_book),l.EarlyPaydateBook)

    def test_paid_early_metadata_rejected_when_tampered(self):
        a=self.state.economy;book=a.sector.public_book
        self.assertIsNotNone(book.early_credit)
        original=book.early_credit.plan
        bad=replace(original,gross_used=(original.gross_used[0]+F(1),original.gross_used[1]))
        with self.assertRaises((TypeError,ValueError)):
            altered=replace(book,early_credit=replace(book.early_credit,plan=bad))
            forged=replace(a,sector=replace(a.sector,public_book=altered))
            k.encode_checkpoint(k.CandidateState(forged))


if __name__=='__main__':unittest.main()
