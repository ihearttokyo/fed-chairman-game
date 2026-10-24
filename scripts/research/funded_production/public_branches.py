"""Finite canonical public forecasts; quotations, never career adoption.

The existing public bridge executes every simulated quarter. Only scalar cash,
production and candidate-debt receipts survive a path; no future state/replay is
exported. Explicit common discount factors are opportunity assumptions, not a
forecast policy curve or an empirically calibrated welfare measure.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from fractions import Fraction as F
import hashlib

from . import macro as m, ledger as l, public_forecast as p
from . import public_funding as funding, checkpoint


def _fraction(value, *, signed=False):
    if type(value) is not F:
        raise TypeError('Quotation amounts require exact Fraction scalars.')
    funding._number(value, signed=signed)


def _integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise TypeError('Quotation counts/dates require plain nonnegative integers.')


def _text(value):
    if type(value) is not str:
        raise TypeError('Quotation labels require plain strings.')


def _cell(sign, fulfilled):
    if type(sign) is not int or sign not in (-1, 1) or type(fulfilled) is not bool:
        raise TypeError('Require exact signal/promise labels.')


def _observation(value):
    if value is None:
        return
    if type(value) is not tuple:
        raise TypeError('Observations require immutable scalar tuples.')
    # Module1 owns the definition of this coarse release. Validate immutable
    # scalar leaves before hashing, rather than invoking arbitrary callbacks.
    def visit(x):
        if type(x) is tuple:
            for child in x:
                visit(child)
        elif type(x) is F:
            _fraction(x, signed=True)
        elif type(x) is str or type(x) is bool or type(x) is int or type(x) is type(None):
            pass
        elif type(x) is float:
            funding._number(x, signed=True)
        elif any(x is cls for cls in
                (str, bool, int, float, F, tuple, type(None), *checkpoint._TAGS, p.PublicStep)):
            # Canonical signatures can carry fixed known type tags; no caller
            # class or callback is admitted as an observation token.
            pass
        else:
            raise TypeError('Observations contain a noncanonical scalar.')
    visit(value)


@dataclass(frozen=True)
class Row:
    """Actual nominal F cash; GDP is quarterly real output, jobs paid workers."""
    date: int
    quarter: int
    receipts: F
    payroll: F
    construction_invoice: F
    operating_cash: F
    discount_factor: F
    pv: F
    gdp: F
    jobs: F
    requested_units: F
    paid_units: F
    project_origin_face: F
    project_retired_principal: F
    project_outstanding_face: F

    def __post_init__(self):
        _integer(self.date); _integer(self.quarter, 1)
        if self.date > 18:
            raise ValueError('A canonical quotation has exactly nineteen dates.')
        for name in ('receipts', 'payroll', 'construction_invoice', 'gdp', 'jobs',
                     'requested_units', 'paid_units', 'project_origin_face',
                     'project_retired_principal', 'project_outstanding_face'):
            _fraction(getattr(self, name))
        for name in ('operating_cash', 'pv'):
            _fraction(getattr(self, name), signed=True)
        _fraction(self.discount_factor)
        if (not self.discount_factor
                or self.operating_cash != self.receipts - self.payroll - self.construction_invoice
                or self.pv != self.operating_cash * self.discount_factor):
            raise ValueError('Inconsistent operating cash/PV receipt.')


@dataclass(frozen=True)
class Path:
    demand_sign: int
    fulfilled: bool
    weight: F
    action: str
    status: str
    reason: str
    rows: tuple[Row, ...]
    prefix_pv: F
    total_pv: F | None
    incremental_pv: F | None
    observation: tuple | None
    requested_units: F
    paid_units: F
    paid_quarter: int | None
    canceled_reason: str
    project_ids: tuple[str, ...]
    project_origin_face: F
    project_retired_principal: F
    project_outstanding_face: F
    executor_calls: int
    paid_closes: int
    refused_closes: int
    prefix_failures: int
    unknown_coverage: int

    def __post_init__(self):
        _cell(self.demand_sign, self.fulfilled)
        for name in ('action', 'status', 'reason', 'canceled_reason'):
            _text(getattr(self, name))
        if self.action not in ('NOW', 'WAIT', 'NEVER') or self.status not in ('completed', 'failed', 'unknown'):
            raise ValueError('Unknown branch action/status.')
        for name in ('weight', 'requested_units', 'paid_units', 'project_origin_face',
                     'project_retired_principal', 'project_outstanding_face'):
            _fraction(getattr(self, name))
        _fraction(self.prefix_pv, signed=True)
        for name in ('total_pv', 'incremental_pv'):
            if getattr(self, name) is not None:
                _fraction(getattr(self, name), signed=True)
        if self.status != 'completed' and (self.total_pv is not None or self.incremental_pv is not None):
            raise ValueError('An incomplete prefix is not a total/incremental value.')
        if type(self.rows) is not tuple or any(type(x) is not Row for x in self.rows) or len(self.rows) > 19:
            raise TypeError('Require at most nineteen exact immutable cash rows.')
        _observation(self.observation)
        if self.paid_quarter is not None:
            _integer(self.paid_quarter, 1)
        checkpoint._ids(self.project_ids)
        for name in ('executor_calls', 'paid_closes', 'refused_closes', 'prefix_failures', 'unknown_coverage'):
            _integer(getattr(self, name))
        if self.executor_calls != self.paid_closes + self.refused_closes or self.paid_closes != len(self.rows):
            raise ValueError('Forecast attempt/close/receipt counts do not reconcile.')
        if self.project_origin_face != self.project_retired_principal + self.project_outstanding_face:
            raise ValueError('Candidate principal does not reconcile.')


@dataclass(frozen=True)
class Decision:
    observation: tuple | None
    cells: tuple[tuple[int, bool], ...]
    weight: F
    admissible: bool
    conditional_delta: F | None
    action: str

    def __post_init__(self):
        _observation(self.observation)
        if type(self.cells) is not tuple:
            raise TypeError('Require immutable group membership.')
        for cell in self.cells:
            if type(cell) is not tuple or len(cell) != 2:
                raise TypeError('Require exact cell pairs.')
            _cell(*cell)
        _fraction(self.weight)
        if type(self.admissible) is not bool:
            raise TypeError('Group admission requires a Boolean.')
        if self.conditional_delta is not None:
            _fraction(self.conditional_delta, signed=True)
        _text(self.action)
        if self.action not in ('WAIT', 'NEVER'):
            raise ValueError('A WAIT observation chooses only WAIT or NEVER.')


@dataclass(frozen=True)
class Quotation:
    status: str
    action: str | None
    expected_now: F | None
    wait_value: F | None
    now_admissible: bool
    exercise_choices: tuple[Decision, ...]
    paths: tuple[Path, ...]
    units: F
    forward_gross: tuple[F, ...]
    tolerance: F
    opening_digest: str
    executor_calls: int
    paid_closes: int
    refused_closes: int
    prefix_failures: int
    unknown_coverage: int

    def __post_init__(self):
        _text(self.status)
        if self.status not in ('completed', 'baseline_incomplete', 'admission_incomplete'):
            raise ValueError('Unknown quotation status.')
        if self.action is not None:
            _text(self.action)
            if self.action not in ('NOW', 'WAIT', 'NEVER'):
                raise ValueError('Unknown quotation action.')
        for name in ('expected_now', 'wait_value'):
            if getattr(self, name) is not None:
                _fraction(getattr(self, name), signed=True)
        if type(self.now_admissible) is not bool:
            raise TypeError('NOW admission requires a Boolean.')
        for name, cls in (('exercise_choices', Decision), ('paths', Path)):
            values = getattr(self, name)
            if type(values) is not tuple or any(type(x) is not cls for x in values):
                raise TypeError('Require exact immutable quotation records.')
        _fraction(self.units); _fraction(self.tolerance)
        _discount_factors(self.forward_gross)
        for value in self.forward_gross:
            _fraction(value)
        checkpoint._hash_text(self.opening_digest)
        for name in ('executor_calls', 'paid_closes', 'refused_closes', 'prefix_failures', 'unknown_coverage'):
            _integer(getattr(self, name))
        if len(self.paths) != 12 or self.executor_calls > 228 or self.row_count > 228:
            raise ValueError('Canonical table exceeds its fixed finite dimensions.')

    @property
    def row_count(self) -> int:
        return sum(len(path.rows) for path in self.paths)


def _discount_factors(forward_gross):
    factors = funding._vector(forward_gross, 18, 'Common forward gross factors')
    if any(value <= 0 for value in factors):
        raise ValueError('Every common forward gross factor must be positive.')
    result = [F(1)]
    for value in factors:
        result.append(result[-1] / value)
    return tuple(result)


def _cash_row(date, report, scale, price_factor, requested, paid,
              origin, retired, outstanding, *, discount=F(1)):
    # The actual whole invoice is already funded, regardless of its financing.
    # No loan proceeds, private debt service, dividends or depreciation enter.
    receipts = report.services * scale * price_factor
    invoice = report.investment * scale * price_factor
    cash = receipts - report.payroll_focal - invoice
    return Row(date, report.quarter, receipts, report.payroll_focal, invoice,
               cash, discount, cash * discount, report.real_output,
               report.paid_residual_workers + report.paid_focal_workers,
               requested, paid, origin, retired, outstanding)


def _digest(opening):
    return hashlib.sha256(repr(p._canonical_value(opening)).encode()).hexdigest()


def _run_path(opening, cell, action, units, discounts, weight, scenarios):
    state = opening
    build = {'NOW': 0, 'WAIT': 1, 'NEVER': None}[action] if units else None
    rows = []
    status = 'completed'; reason = ''; canceled = ''; observation = None
    calls = closes = refusals = prefixes = unknown = 0
    paid_units = F(0); paid_quarter = None
    origin = retired = outstanding = F(0)
    ids = (); terms = {}
    for date, descriptor in enumerate(cell.dates):
        try:
            current = scenarios.resolve_date(state, descriptor)
            if action == 'WAIT' and date == 1:
                observation = scenarios.wait_observation(state, current)
                _observation(observation)
            requested = units if date == build else F(0)
            prepared = p.prepare(state, current.policy, current.step,
                                 current.news, project_units=requested)
            finance = p.controls(prepared)
        except scenarios.MissingCoverage as error:
            status = 'unknown'; reason = str(error); unknown += 1
            break
        except p.FundingFailure as error:
            status = 'failed'; reason = 'funding_failure: ' + str(error); prefixes += 1
            break
        # One p.execute attempt means one raw ledger attempt, not necessarily a
        # successful macro close. Unexpected errors deliberately propagate.
        calls += 1
        outcome = p.execute(prepared, finance)
        if not outcome.ok:
            refusals += 1
            if outcome.envelope is not state:
                raise AssertionError('Refused forecast changed its predecessor.')
            status = 'unknown' if outcome.status == 'unsupported_public_income' else 'failed'
            if status == 'unknown':
                unknown += 1
            reason = outcome.status + ': ' + outcome.reason
            break
        closes += 1
        next_state = outcome.envelope
        report = next_state.sector.last
        # Only NEW actual protected project claims belong to this candidate;
        # opening debt and operating offers are never relabeled as investment.
        old_ids = {loan.id for loan in state.sector.loans}
        new = tuple(loan for loan in next_state.sector.loans
                    if type(loan) is l.ProjectLoan and loan.id not in old_ids)
        if new and date != build:
            raise AssertionError('A future project order/claim was invented.')
        new_face = sum((loan.face for loan in new), F(0))
        for loan in new:
            if loan.id in terms:
                raise AssertionError('Candidate project claim identity was reused.')
            terms[loan.id] = (loan.lender, loan.borrower, loan.start, loan.maturity, loan.rate_pct)
        ids += tuple(loan.id for loan in new)
        origin += new_face
        paid_principal = F(0)
        for receipt in report.payments:
            if receipt.claim_id in terms and receipt.kind == 'private_principal':
                if (receipt.payer, receipt.payee) != ('F', 'Bank' + terms[receipt.claim_id][0]):
                    raise AssertionError('Candidate principal receipt has the wrong owner.')
                paid_principal += receipt.amount
        retired += paid_principal
        remaining = tuple(loan for loan in next_state.sector.loans if loan.id in terms)
        for loan in remaining:
            if type(loan) is not l.ProjectLoan or terms[loan.id] != (
                    loan.lender, loan.borrower, loan.start, loan.maturity, loan.rate_pct):
                raise AssertionError('Protected candidate project debt was refinanced.')
        outstanding = sum((loan.face for loan in remaining), F(0))
        if origin != retired + outstanding:
            raise AssertionError('Actual candidate principal receipts do not reconcile.')
        actual_units = report.investment / prepared.orders.capital_resource_cost
        rows.append(_cash_row(date, report, state.sector.scale, prepared.orders.price_factor,
                              requested, actual_units, new_face, paid_principal, outstanding,
                              discount=discounts[date]))
        state = next_state
        if actual_units:
            if date != build:
                raise AssertionError('Forecast invested outside its single legal construction date.')
            paid_units += actual_units
            paid_quarter = report.quarter
        if requested and actual_units != requested:
            canceled = next((dict(item.details)['reason'] for item in report.trace
                             if item.kind == 'project_cancelled'), 'tranche_not_fully_paid')
            # A staged optional draw can fail for undeclared CB terms without
            # refusing the otherwise fundable quarter. It is missing coverage,
            # not a proven economic rejection of the candidate investment.
            status = 'unknown' if canceled == 'unsupported_public_income' else 'failed'
            unknown += int(status == 'unknown')
            reason = 'project_cancelled: ' + canceled
            break
    if status == 'completed' and outstanding:
        raise AssertionError('Candidate project principal survived its entire quoted life.')
    prefix = sum((row.pv for row in rows), F(0))
    return Path(cell.demand_sign, cell.fulfilled, weight, action, status, reason,
                tuple(rows), prefix, prefix if status == 'completed' else None, None,
                observation, units if build is not None else F(0), paid_units,
                paid_quarter, canceled, ids, origin, retired, outstanding,
                calls, closes, refusals, prefixes, unknown)


def _incrementals(paths):
    baselines = {(path.demand_sign, path.fulfilled): path for path in paths if path.action == 'NEVER'}
    result = []
    for path in paths:
        baseline = baselines[(path.demand_sign, path.fulfilled)]
        delta = (path.total_pv - baseline.total_pv
                 if path.status == baseline.status == 'completed' else None)
        result.append(replace(path, incremental_pv=delta))
    return tuple(result)


def _select(paths, tolerance):
    active = tuple(path for path in paths if path.weight > 0)
    baselines = tuple(path for path in active if path.action == 'NEVER')
    now = tuple(path for path in active if path.action == 'NOW')
    baseline_complete = all(path.status == 'completed' for path in baselines)
    now_admissible = baseline_complete and all(path.status == 'completed' for path in now)
    expected_now = (sum((path.weight * path.incremental_pv for path in now), F(0))
                    if now_admissible else None)
    incomplete = ('baseline_incomplete' if any(path.status == 'failed' for path in baselines) else
                  'admission_incomplete' if any(path.status == 'unknown' for path in active) else None)
    groups = {}
    for path in active:
        if path.action == 'WAIT':
            groups.setdefault(path.observation, []).append(path)
    choices = []; wait_value = F(0)
    for observation, group in groups.items():
        weight = sum((path.weight for path in group), F(0))
        admitted = not incomplete and all(path.status == 'completed' and path.incremental_pv is not None
                                           for path in group)
        weighted = sum((path.weight * path.incremental_pv for path in group), F(0)) if admitted else None
        conditional = weighted / weight if admitted else None
        exercise = admitted and conditional > tolerance
        if exercise:
            wait_value += weighted
        choices.append(Decision(observation, tuple((path.demand_sign, path.fulfilled) for path in group),
                                weight, bool(admitted), conditional, 'WAIT' if exercise else 'NEVER'))
    if incomplete:
        return incomplete, None, expected_now, None, now_admissible, tuple(choices)
    # An ineligible option cannot veto NOW merely by falling within its
    # near-tie margin. Keep the preference for waiting when WAIT is eligible.
    if (now_admissible and expected_now > tolerance
            and (wait_value <= tolerance or expected_now > wait_value + tolerance)):
        action = 'NOW'
    elif wait_value > tolerance:
        action = 'WAIT'
    else:
        action = 'NEVER'
    return 'completed', action, expected_now, wait_value, now_admissible, tuple(choices)


def evaluate(opening, cells, *, units, forward_gross, tolerance=1e-6) -> Quotation:
    """Quote one NOW0/WAIT1/NEVER tranche, four cells and nineteen dates.

    At most 228 actual simulated executor attempts, without prefix caching.
    Missing/failed positive-weight baselines stay visible; missing positive-
    weight admission coverage never becomes an investment recommendation.
    """
    from . import public_scenarios as scenarios

    checkpoint._check_sources()
    if type(opening) is not m.Envelope:
        raise TypeError('Require the exact canonical reference Envelope.')
    p._canonical_value(opening)  # Strict nested scalars BEFORE equality/fields.
    if type(opening.sector.public_book) is not l.FundedPublicBook:
        raise TypeError('Require the exact funded public book.')
    checkpoint._paid_economy(opening)
    l.validate_funded_public(opening.sector.public_book, opening.sector.scale,
                            opening.sector.quarter,
                            None if opening.sector.last is None else opening.sector.last.payments)
    # Recheck coherent current clocks, macro bounds and ledger balance sheets.
    replace(opening.macro); replace(opening.sector)
    before = _digest(opening)
    checked = scenarios.validated_cells(cells)
    units = funding._number(units)
    if units % l.QUANTUM:
        raise ValueError('Project units require the fixed physical grid.')
    tolerance = funding._number(tolerance)
    forwards = funding._vector(forward_gross, 18, 'Common forward gross factors')
    discounts = _discount_factors(forwards)
    current_signature = None
    # Resolve every known current disclosure BEFORE any action gets a paid call.
    # Equivalent rules are allowed; hidden differences in today's news are not.
    for cell in checked:
        try:
            current = scenarios.resolve_date(opening, cell.dates[0])
        except scenarios.MissingCoverage:
            pass
        else:
            signature = p._canonical_value((current.policy, current.news, current.step))
            if current_signature is not None and signature != current_signature:
                raise ValueError('Current date-zero information differs between scenario cells.')
            current_signature = signature
        structural_u = opening.macro.structural_unemployment_pct
        for descriptor in cell.dates:
            if descriptor is not None:
                # Scale is constant along every envelope. A malformed future
                # facility limit must not spend a valid partial forecast first.
                for limit in descriptor.facility_limits:
                    l._money(limit, opening.sector.scale)
        for descriptor in cell.dates:
            if descriptor is None:
                break  # The cumulative path beyond a missing date is unknown.
            structural_u += descriptor.news.structural_unemployment_change_pct
            if not 0 < structural_u < 100:
                raise ValueError('Invalid structural unemployment forecast path.')
    credibility = m.rational(opening.macro.credibility)
    paths = []
    try:
        for cell in sorted(checked, key=lambda cell: (cell.demand_sign, cell.fulfilled)):
            weight = (credibility if cell.fulfilled else 1 - credibility) / 2
            for action in ('NEVER', 'NOW', 'WAIT'):
                paths.append(_run_path(opening, cell, action, units, discounts, weight, scenarios))
        paths = _incrementals(tuple(paths))
        status, action, expected, wait, admissible, choices = _select(paths, tolerance)
        counts = tuple(sum(getattr(path, name) for path in paths) for name in
                       ('executor_calls', 'paid_closes', 'refused_closes', 'prefix_failures', 'unknown_coverage'))
        return Quotation(status, action, expected, wait, admissible, choices, paths,
                         units, forwards, tolerance, before, *counts)
    finally:
        if _digest(opening) != before:
            raise ValueError('Forecast mutated its actual opening root.')
        checkpoint._check_sources()
