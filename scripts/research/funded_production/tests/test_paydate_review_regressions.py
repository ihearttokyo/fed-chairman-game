"""Reproductions of independent review findings, not extra career diagnostics."""
from dataclasses import replace
import unittest

from scripts.research.funded_production import ledger as l, macro as m, checkpoint as k
from scripts.research.funded_production.tests.test_public_paydate_journal import fixture, run
from scripts.research.funded_production.tests.test_public_paydate_integration import source, controls


class PaydateReviewRegressionTests(unittest.TestCase):
    def test_snapshot_metadata_cannot_run_callback_or_mutate_original(self):
        out=run(fixture());self.assertTrue(out.ok,out.reason)
        book=out.state.public_book;calls=[]
        class Schema(dict):
            def values(self):
                calls.append('metadata')
                object.__setattr__(out.state.banks[0],'reserves',0)
                return super().values()
        snapshot=replace(book.phases[0].snapshot)
        object.__setattr__(snapshot,'__dataclass_fields__',Schema(type(snapshot).__dataclass_fields__))
        bad=replace(book,phases=(replace(book.phases[0],snapshot=snapshot),)+book.phases[1:])
        before=repr(out.state)
        with self.assertRaises((TypeError,ValueError)):
            l.validate_paydate_public(bad,out.state.scale,out.state.quarter,
                                      out.state.last.payments,out.state.last.trace)
        self.assertEqual(calls,[])
        self.assertEqual(repr(out.state),before)

    def test_trace_boundary_alias_cannot_spoof_a_real_payment_position(self):
        out=run(fixture());self.assertTrue(out.ok,out.reason);calls=[]
        class Alias(int):
            def __eq__(self,other):calls.append('equality');return True
            __hash__=int.__hash__
        trace=list(out.state.last.trace)
        trace[0]=replace(trace[0],details=(('payment_end',Alias(999)),))
        with self.assertRaises((TypeError,ValueError)):
            l.validate_paydate_public(out.state.public_book,out.state.scale,out.state.quarter,
                                      out.state.last.payments,tuple(trace))
        self.assertEqual(calls,[])

    def test_checkpoint_rejects_instance_metadata_before_packing(self):
        base=source(); terms=l.public_income_terms(base,cb_rates_pct=(0,0))
        economy=replace(m.initial(growth=0),sector=l.enable_paydate_public(base,terms))
        candidate=k.CandidateState(economy);book=economy.sector.public_book;calls=[]
        class Schema(dict):
            def values(self):calls.append('packing callback');return super().values()
        object.__setattr__(book,'__dataclass_fields__',Schema(type(book).__dataclass_fields__))
        with self.assertRaises((TypeError,ValueError)):
            k.encode_checkpoint(candidate)
        self.assertEqual(calls,[])

    def test_budget_cannot_report_zero_funding_after_positive_actual_purchases(self):
        base=source();terms=l.public_income_terms(base,mortgage_rates_pct=(0,4),cb_rates_pct=(0,0))
        economy=replace(m.initial(growth=0),sector=l.enable_paydate_public(base,terms))
        prepared=m._quote_source(economy,m.Policy(3.5,3.5))
        orders=replace(l.depth_orders(),market_clearing=True,residual_workers=0,focal_workers=1,
            investment_units=0,price_factor=m.rational(prepared.price_index/100),
            real_wage=m.rational(prepared.trend),available_workers=m.rational(economy.macro.workforce))
        out=l.advance_given_orders(economy.sector,orders,controls(economy.sector))
        self.assertTrue(out.ok,out.reason)
        self.assertGreater(sum(p.amount for p in out.state.last.payments
                               if p.payer=='HB' and p.kind=='services'),0)
        trace=[]
        for note in out.state.last.trace:
            if note.kind=='household_budget' and note.actor=='HB':
                data=dict(note.details);data.update(demand_multiplier=0,desired=0,funded=0)
                note=replace(note,details=tuple(data.items()))
            trace.append(note)
        with self.assertRaises((TypeError,ValueError)):
            bad=replace(out.state,last=replace(out.state.last,trace=tuple(trace)))
            k.CandidateState(m._close_paid(replace(prepared,orders=orders),bad,
                                          closing_households=True).envelope)


if __name__=='__main__':unittest.main()
