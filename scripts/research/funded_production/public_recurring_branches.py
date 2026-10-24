"""Marginal quotations conditional on an AUTHORED fixed construction schedule.

This is a counterfactual, not an optimal/endogenous investment controller or a
recovery forecast. Each date uses the existing paydate bridge and ONE actual
journal. Joint construction is never split into fictional physical ownership
or candidate-only debt. Later background claims can remain right-censored.
No future envelope, command or adopted checkpoint survives in these receipts.
"""
from __future__ import annotations

from dataclasses import dataclass, fields, replace
from fractions import Fraction as F

from . import public_branches as core, public_funding as funding


BACKGROUND_POLICY = 'authored_fixed_schedule_counterfactual'
_ROLES = ('decision_date_joint', 'background')
_COUNTS = ('executor_calls', 'paid_closes', 'refused_closes', 'prefix_failures', 'unknown_coverage')


def _shape(value, cls):
    """Class-owned fields, never an instance-authored schema or callback."""
    if type(value) is not cls:
        raise TypeError('Require the exact recurring quotation record.')
    attributes = object.__getattribute__(value, '__dict__')
    if (type(attributes) is not dict or any(type(key) is not str for key in attributes)
            or set(attributes) != {field.name for field in fields(cls)}):
        raise ValueError('Recurring records require only their class-defined fields.')


def _records(values, cls):
    if type(values) is not tuple:
        raise TypeError('Require exact immutable recurring receipt tuples.')
    for value in values:
        _shape(value, cls)
        replace(value)  # Revalidate ONLY after the fixed schema/type admission.


def _physical(value):
    value = funding._number(value)
    if value % core.l.QUANTUM:
        raise ValueError('Construction requests require the fixed physical grid.')
    return value


@dataclass(frozen=True)
class ProjectClaim:
    """One ACTUAL new claim, not a proportional candidate-financing estimate."""
    id: str
    role: str
    construction_date: int
    lender: str
    borrower: str
    start: int
    maturity: int
    rate_pct: F
    origin_face: F
    retired_principal: F
    outstanding_face: F

    def __post_init__(self):
        _shape(self, ProjectClaim)
        for name in ('id', 'role', 'lender', 'borrower'):
            core._text(getattr(self, name))
        if (not self.id or self.role not in _ROLES
                or self.lender not in core.l.BANKS or self.borrower != 'F'):
            raise ValueError('Require an identified actual F project claim and cohort.')
        for name in ('construction_date', 'start', 'maturity'):
            core._integer(getattr(self, name))
        if self.construction_date > 18 or not 2 <= self.maturity - self.start <= 17:
            raise ValueError('Invalid dated protected project claim.')
        core._fraction(self.rate_pct, signed=True)
        for name in ('origin_face', 'retired_principal', 'outstanding_face'):
            core._fraction(getattr(self, name))
        if not self.origin_face or self.origin_face != self.retired_principal + self.outstanding_face:
            raise ValueError('Actual project principal does not reconcile.')


@dataclass(frozen=True)
class Row:
    """WHOLE-F unlevered cash and total joint physical delivery, not a split."""
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
    background_requested_units: F
    candidate_requested_units: F
    requested_units: F
    paid_units: F
    shortfall_units: F
    canceled_reason: str
    decision_date_origin_face: F = F(0)
    decision_date_retired_principal: F = F(0)
    decision_date_outstanding_face: F = F(0)
    background_origin_face: F = F(0)
    background_retired_principal: F = F(0)
    background_outstanding_face: F = F(0)

    def __post_init__(self):
        _shape(self, Row)
        core._integer(self.date); core._integer(self.quarter, 1)
        if self.date > 18:
            raise ValueError('A recurring quotation has nineteen dates.')
        for name in ('receipts', 'payroll', 'construction_invoice', 'discount_factor',
                     'gdp', 'jobs', 'background_requested_units', 'candidate_requested_units',
                     'requested_units', 'paid_units', 'shortfall_units',
                     'decision_date_origin_face', 'decision_date_retired_principal',
                     'decision_date_outstanding_face', 'background_origin_face',
                     'background_retired_principal', 'background_outstanding_face'):
            core._fraction(getattr(self, name))
        core._fraction(self.operating_cash, signed=True); core._fraction(self.pv, signed=True)
        core._text(self.canceled_reason)
        for value in (self.background_requested_units, self.candidate_requested_units,
                      self.requested_units, self.paid_units, self.shortfall_units):
            _physical(value)
        if (not self.discount_factor or self.operating_cash != self.receipts - self.payroll - self.construction_invoice
                or self.pv != self.operating_cash * self.discount_factor):
            raise ValueError('Inconsistent whole-invoice operating cash or PV.')
        if (self.requested_units != self.background_requested_units + self.candidate_requested_units
                or self.paid_units > self.requested_units
                or self.shortfall_units != self.requested_units - self.paid_units
                or bool(self.shortfall_units) != bool(self.canceled_reason)):
            raise ValueError('Inconsistent total joint construction delivery receipt.')

    @property
    def candidate_fully_delivered(self):
        return bool(self.candidate_requested_units and self.paid_units == self.requested_units)


def _totals(claims, role):
    return tuple(sum((getattr(claim, name) for claim in claims if claim.role == role), F(0))
                 for name in ('origin_face', 'retired_principal', 'outstanding_face'))


@dataclass(frozen=True)
class Path:
    """Scalar prefix; paid_closes are MACRO closes, not every raw-paid result."""
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
    units: F
    background_units: F
    claims: tuple[ProjectClaim, ...]
    executor_calls: int
    paid_closes: int
    refused_closes: int
    prefix_failures: int
    unknown_coverage: int
    background_policy: str = BACKGROUND_POLICY

    def __post_init__(self):
        _shape(self, Path)
        core._cell(self.demand_sign, self.fulfilled)
        for name in ('action', 'status', 'reason', 'background_policy'):
            core._text(getattr(self, name))
        if (self.action not in ('NOW', 'WAIT', 'NEVER')
                or self.status not in ('completed', 'failed', 'unknown')
                or self.background_policy != BACKGROUND_POLICY):
            raise ValueError('Unknown recurring action/status/background convention.')
        for name in ('weight', 'units', 'background_units'):
            core._fraction(getattr(self, name))
        _physical(self.units); _physical(self.background_units)
        if self.weight > 1:
            raise ValueError('A cell weight cannot exceed one.')
        core._fraction(self.prefix_pv, signed=True)
        for name in ('total_pv', 'incremental_pv'):
            if getattr(self, name) is not None:
                core._fraction(getattr(self, name), signed=True)
        if self.status != 'completed' and (self.total_pv is not None or self.incremental_pv is not None):
            raise ValueError('An incomplete prefix is not a total or incremental value.')
        _records(self.rows, Row); _records(self.claims, ProjectClaim)
        core._observation(self.observation)
        core.checkpoint._ids(tuple(claim.id for claim in self.claims))
        for name in _COUNTS:
            core._integer(getattr(self, name))
        if (self.executor_calls > 19 or self.executor_calls != self.paid_closes + self.refused_closes
                or self.paid_closes != len(self.rows) or len(self.rows) > 19):
            raise ValueError('Raw-attempt/macro-close/row counts do not reconcile.')
        if self.prefix_pv != sum((row.pv for row in self.rows), F(0)):
            raise ValueError('Prefix PV differs from its actual cash rows.')
        if self.status == 'completed' and (len(self.rows) != 19 or self.total_pv != self.prefix_pv):
            raise ValueError('A completed recurring path requires nineteen cash rows.')
        for date, row in enumerate(self.rows):
            if (row.date != date or row.quarter != self.rows[0].quarter + date
                    or row.background_requested_units != self.background_units
                    or row.candidate_requested_units != (self.units if date == self.decision_date else 0)):
                raise ValueError('Rows differ from the one declared common construction schedule.')
        for claim in self.claims:
            role = 'decision_date_joint' if claim.construction_date == self.decision_date else 'background'
            if claim.construction_date >= len(self.rows) or claim.role != role:
                raise ValueError('Actual joint/background claim was relabeled or undated.')
            if claim.start != self.rows[claim.construction_date].quarter - 1:
                raise ValueError('Actual project claim differs from its construction clock.')
        for role, prefix in (('decision_date_joint', 'decision_date'), ('background', 'background')):
            origin = retired = F(0)
            for row in self.rows:
                dated = sum((c.origin_face for c in self.claims
                    if c.role == role and c.construction_date == row.date), F(0))
                if dated != getattr(row, prefix + '_origin_face'):
                    raise ValueError('Actual claim origin differs from its dated row.')
                origin += getattr(row, prefix + '_origin_face')
                retired += getattr(row, prefix + '_retired_principal')
                if origin != retired + getattr(row, prefix + '_outstanding_face'):
                    raise ValueError('Dated cohort principal counters do not reconcile.')
            final = F(0) if not self.rows else getattr(self.rows[-1], prefix + '_outstanding_face')
            if (origin, retired, final) != _totals(self.claims, role):
                raise ValueError('Cohort rows differ from actual identified project claims.')
        if self.status == 'completed' and self.decision_date is not None:
            if not self.candidate_fully_delivered or self.decision_date_outstanding_face:
                raise ValueError('Completed admission requires joint delivery and decision-cohort retirement.')

    @property
    def decision_date(self):
        return {'NOW': 0, 'WAIT': 1, 'NEVER': None}[self.action] if self.units else None

    @property
    def candidate_fully_delivered(self):
        return any(row.date == self.decision_date and row.candidate_fully_delivered for row in self.rows)

    @property
    def decision_date_cohort(self):
        return tuple(claim for claim in self.claims if claim.role == 'decision_date_joint')

    @property
    def background_claims(self):
        return tuple(claim for claim in self.claims if claim.role == 'background')

    @property
    def decision_date_origin_face(self): return _totals(self.claims, 'decision_date_joint')[0]

    @property
    def decision_date_retired_principal(self): return _totals(self.claims, 'decision_date_joint')[1]

    @property
    def decision_date_outstanding_face(self): return _totals(self.claims, 'decision_date_joint')[2]

    @property
    def background_origin_face(self): return _totals(self.claims, 'background')[0]

    @property
    def background_retired_principal(self): return _totals(self.claims, 'background')[1]

    @property
    def background_outstanding_face(self): return _totals(self.claims, 'background')[2]

    @property
    def background_right_censored(self):
        return bool(self.status == 'completed' and self.background_outstanding_face)

    @property
    def requested_units(self): return sum((row.requested_units for row in self.rows), F(0))

    @property
    def paid_units(self): return sum((row.paid_units for row in self.rows), F(0))


@dataclass(frozen=True)
class Decision:
    observation: tuple | None
    cells: tuple[tuple[int, bool], ...]
    weight: F
    admissible: bool
    conditional_delta: F | None
    action: str

    def __post_init__(self):
        _shape(self, Decision)
        # Reuse only the old scalar admission contract, not its output identity.
        core.Decision(self.observation, self.cells, self.weight, self.admissible,
                      self.conditional_delta, self.action)


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
    background_units: F
    forward_gross: tuple[F, ...]
    tolerance: F
    opening_digest: str
    executor_calls: int
    paid_closes: int
    refused_closes: int
    prefix_failures: int
    unknown_coverage: int
    background_policy: str = BACKGROUND_POLICY

    def __post_init__(self):
        _shape(self, Quotation)
        core._text(self.status); core._text(self.background_policy)
        if (self.status not in ('completed', 'baseline_incomplete', 'admission_incomplete')
                or self.background_policy != BACKGROUND_POLICY):
            raise ValueError('Unknown recurring quotation/background convention.')
        if self.action is not None:
            core._text(self.action)
            if self.action not in ('NOW', 'WAIT', 'NEVER'):
                raise ValueError('Unknown recurring quotation action.')
        if type(self.now_admissible) is not bool:
            raise TypeError('Admission requires an exact Boolean.')
        for name in ('expected_now', 'wait_value'):
            if getattr(self, name) is not None:
                core._fraction(getattr(self, name), signed=True)
        for name in ('units', 'background_units', 'tolerance'):
            core._fraction(getattr(self, name))
        _physical(self.units); _physical(self.background_units)
        core._discount_factors(self.forward_gross)
        for value in self.forward_gross: core._fraction(value)
        core.checkpoint._hash_text(self.opening_digest)
        _records(self.exercise_choices, Decision); _records(self.paths, Path)
        if (len(self.paths) != 12 or {(p.demand_sign, p.fulfilled, p.action) for p in self.paths}
                != {(s, f, a) for s in (-1, 1) for f in (False, True) for a in ('NEVER', 'NOW', 'WAIT')}):
            raise ValueError('Require the exact finite four-cell/three-action table.')
        if any(p.units != self.units or p.background_units != self.background_units for p in self.paths):
            raise ValueError('Every path requires the SAME declared construction schedule.')
        for name in _COUNTS:
            core._integer(getattr(self, name))
            if getattr(self, name) != sum(getattr(p, name) for p in self.paths):
                raise ValueError('Quotation counters differ from their actual path counters.')
        if self.executor_calls > 228 or self.row_count > 228:
            raise ValueError('Recurring quotation exceeds its fixed finite bound.')

    @property
    def row_count(self): return sum(len(path.rows) for path in self.paths)


def _loan_terms(loan):
    return loan.lender, loan.borrower, loan.start, loan.maturity, loan.rate_pct


def _claim_terms(claim):
    return claim.lender, claim.borrower, claim.start, claim.maturity, claim.rate_pct


def _track_claims(claims, before, after, payments, *, construction_date, quarter,
                  decision_date, root_ids=()):
    """Pure binding of actual identities/receipts for ALL new project cohorts."""
    _records(claims, ProjectClaim)
    core.checkpoint._ids(tuple(claim.id for claim in claims))
    core.checkpoint._ids(root_ids)
    funding.validate_records((before, after, payments),
        (core.l.Loan, core.l.OperatingLoan, core.l.ProjectLoan, core.l.Payment))
    if any(type(values) is not tuple for values in (before, after, payments)):
        raise TypeError('Require exact immutable actual loan/payment collections.')
    for loans in (before, after):
        if any(type(loan) not in (core.l.Loan, core.l.OperatingLoan, core.l.ProjectLoan) for loan in loans):
            raise TypeError('Require known exact actual private claim types.')
        for loan in loans: replace(loan)
        core.checkpoint._ids(tuple(loan.id for loan in loans))
    if any(type(payment) is not core.l.Payment for payment in payments):
        raise TypeError('Require exact actual payment receipts.')
    for payment in payments: replace(payment)
    core._integer(construction_date); core._integer(quarter, 1)
    if construction_date > 18:
        raise ValueError('Construction cohort exceeds the nineteen-date horizon.')
    if decision_date is not None:
        core._integer(decision_date)
        if decision_date not in (0, 1): raise ValueError('Unknown decision construction date.')
    old = {loan.id: loan for loan in before}; closing = {loan.id: loan for loan in after}
    tracked = {claim.id: claim for claim in claims}
    core.checkpoint._ids(tuple(tracked))
    for claim in claims:
        loan = old.get(claim.id)
        if claim.outstanding_face:
            if (type(loan) is not core.l.ProjectLoan or _loan_terms(loan) != _claim_terms(claim)
                    or loan.face != claim.outstanding_face):
                raise AssertionError('Protected actual project predecessor terms/face changed.')
        elif loan is not None:
            raise AssertionError('Retired actual project identity was reused.')
    for loan in after:
        if type(loan) is core.l.ProjectLoan and loan.id not in old:
            if loan.id in tracked or loan.id in root_ids:
                raise AssertionError('Actual project identity was reused.')
            if loan.start != quarter - 1:
                raise AssertionError('New actual project claim has the wrong construction clock.')
            tracked[loan.id] = ProjectClaim(loan.id,
                'decision_date_joint' if construction_date == decision_date else 'background',
                construction_date, *_loan_terms(loan), loan.face, F(0), loan.face)
    retired = dict.fromkeys(tracked, F(0))
    for payment in payments:
        if payment.claim_id in tracked and payment.kind == 'private_principal':
            claim = tracked[payment.claim_id]
            if (payment.payer, payment.payee) != ('F', 'Bank' + claim.lender):
                raise AssertionError('Actual project principal receipt has the wrong owner.')
            retired[payment.claim_id] += payment.amount
    result = []
    for claim in tracked.values():
        loan = closing.get(claim.id)
        if loan is not None and (type(loan) is not core.l.ProjectLoan
                                 or _loan_terms(loan) != _claim_terms(claim)):
            raise AssertionError('Protected actual joint/background debt was refinanced.')
        outstanding = F(0) if loan is None else loan.face
        paid = claim.retired_principal + retired[claim.id]
        if claim.origin_face != paid + outstanding:
            raise AssertionError('Actual project principal receipts do not reconcile.')
        result.append(replace(claim, retired_principal=paid, outstanding_face=outstanding))
    return tuple(result)


def _delivery_failure(candidate, requested, paid, canceled):
    for value in (candidate, requested, paid): core._fraction(value)
    core._text(canceled)
    if candidate > requested or paid > requested:
        raise AssertionError('Actual investment exceeds its sole declared joint order.')
    if paid == requested:
        return None, ''
    if canceled == 'unsupported_public_income':
        return 'unknown', 'project_cancelled: ' + canceled
    if candidate:
        return 'failed', 'project_cancelled: ' + canceled
    # A known unfilled BACKGROUND intention is observed, not a forced payment
    # or an invented macro refusal. Its shortfall remains on the actual row.
    return None, ''


def _cash_row(date, report, scale, price_factor, *, background, candidate, paid,
              canceled, previous_claims, claims, discount):
    receipts = report.services * scale * price_factor
    invoice = report.investment * scale * price_factor
    cash = receipts - report.payroll_focal - invoice
    debt = []
    for role in _ROLES:
        before = _totals(previous_claims, role); after = _totals(claims, role)
        debt.extend((after[0] - before[0], after[1] - before[1], after[2]))
    requested = background + candidate
    return Row(date, report.quarter, receipts, report.payroll_focal, invoice, cash,
        discount, cash * discount, report.real_output,
        report.paid_residual_workers + report.paid_focal_workers,
        background, candidate, requested, paid, requested - paid, canceled, *debt)


def _select(paths, tolerance):
    result = core._select(paths, tolerance)
    choices = tuple(Decision(x.observation, x.cells, x.weight, x.admissible,
                             x.conditional_delta, x.action) for x in result[5])
    return (*result[:5], choices)


def _unchanged(opening, digest, label):
    if core._digest(opening) != digest:
        raise ValueError('Recurring forecast mutated its ' + label + '.')


def _run_path(opening, cell, action, units, background_units, discounts, weight, *, household=False):
    """Private exact paydate runner; caller admits the full table before use."""
    adapter, scenarios, book_type = core._pair(True, household=household)

    core.checkpoint._check_sources()
    if household:
        scenarios._admit((opening, cell))
    before = core._digest(opening)
    core._text(action)
    if action not in ('NEVER', 'NOW', 'WAIT'): raise ValueError('Unknown recurring action.')
    for value in (units, background_units, weight): core._fraction(value)
    _physical(units); _physical(background_units)
    if weight > 1: raise ValueError('A cell weight cannot exceed one.')
    if (type(discounts) is not tuple or len(discounts) != 19
            or type(cell) is not scenarios.ScenarioCell):
        raise TypeError('Require exact prevalidated recurring dates and discounts.')
    for value in discounts:
        core._fraction(value)
        if not value: raise ValueError('Discount factors must be positive.')
    if discounts[0] != 1: raise ValueError('Date zero must be undiscounted.')
    if type(opening.sector.public_book) is not book_type:
        raise TypeError('Require the exact paydate public convention.')
    # The full public admission already checked scale grids and current common
    # disclosures. Still reject a forged private cell schema before iteration.
    _shape(cell, scenarios.ScenarioCell)
    scenarios.ScenarioCell(cell.demand_sign, cell.fulfilled, cell.dates)
    state = opening; rows = []; claims = ()
    root_ids = tuple(loan.id for loan in opening.sector.loans)
    build = {'NOW': 0, 'WAIT': 1, 'NEVER': None}[action] if units else None
    status = 'completed'; reason = ''; observation = None
    calls = closes = refusals = prefixes = unknown = 0
    try:
        for date, descriptor in enumerate(cell.dates):
            predecessor = state; predecessor_digest = core._digest(predecessor)
            try:
                candidate = units if date == build else F(0)
                requested = background_units + candidate
                try:
                    current = scenarios.resolve_date(state, descriptor)
                    if action == 'WAIT' and date == 1:
                        observation = scenarios.wait_observation(state, current)
                        core._observation(observation)
                    prepared = adapter.prepare(state, current.policy, current.step,
                                               current.news, project_units=requested)
                    finance = adapter.controls(prepared)
                except scenarios.MissingCoverage as error:
                    status = 'unknown'; reason = str(error); unknown += 1
                    break
                except core.p.FundingFailure as error:
                    status = 'failed'; reason = 'funding_failure: ' + str(error); prefixes += 1
                    break
                calls += 1
                outcome = adapter.execute(prepared, finance)
                if not outcome.ok:
                    refusals += 1
                    if outcome.envelope is not state:
                        raise AssertionError('Refused macro close changed its predecessor.')
                    status = 'unknown' if outcome.status == 'unsupported_public_income' else 'failed'
                    unknown += int(status == 'unknown')
                    reason = outcome.status + ': ' + outcome.reason
                    break
                closes += 1
                successor = outcome.envelope
                core.p._canonical_value(successor)  # BEFORE inspecting trace/payment fields.
                report = successor.sector.last
                prior_claims = claims
                claims = _track_claims(claims, state.sector.loans, successor.sector.loans,
                    report.payments, construction_date=date, quarter=report.quarter,
                    decision_date=build, root_ids=root_ids)
                paid = report.investment / prepared.orders.capital_resource_cost
                canceled = ''
                if paid != requested:
                    canceled = next((dict(note.details)['reason'] for note in report.trace
                        if note.kind == 'project_cancelled'), 'tranche_not_fully_paid')
                rows.append(_cash_row(date, report, state.sector.scale, prepared.orders.price_factor,
                    background=background_units, candidate=candidate, paid=paid, canceled=canceled,
                    previous_claims=prior_claims, claims=claims, discount=discounts[date]))
                state = successor
                failure, detail = _delivery_failure(candidate, requested, paid, canceled)
                if failure is not None:
                    status = failure; reason = detail; unknown += int(status == 'unknown')
                    break
            finally:
                try:
                    _unchanged(predecessor, predecessor_digest, 'actual predecessor')
                finally:
                    core.checkpoint._check_sources()
        if status == 'completed' and _totals(claims, 'decision_date_joint')[2]:
            raise AssertionError('Decision-date joint principal survived its full quoted life.')
        prefix = sum((row.pv for row in rows), F(0))
        return Path(cell.demand_sign, cell.fulfilled, weight, action, status, reason,
            tuple(rows), prefix, prefix if status == 'completed' else None, None,
            observation, units, background_units, claims, calls, closes, refusals, prefixes, unknown)
    finally:
        try:
            _unchanged(opening, before, 'actual opening root')
        finally:
            core.checkpoint._check_sources()


def evaluate(opening, cells, *, units, background_units, forward_gross, tolerance=1e-6) -> Quotation:
    """Quote marginal NOW0/WAIT1/NEVER against the SAME fixed background.

    At most228 actual raw attempts, not zero-executor quotes. Known background
    delivery shortfalls remain observed intentions; unknown terms stop coverage.
    A joint decision-date shortfall cannot be split into candidate delivery.
    """
    return _evaluate(opening, cells, units=units, background_units=background_units,
                     forward_gross=forward_gross, tolerance=tolerance, household=False)


def _evaluate(opening, cells, *, units, background_units, forward_gross, tolerance=1e-6, household=False) -> Quotation:
    _, scenarios, _ = core._pair(True, household=household)  # Exact selection before traversal.
    core.checkpoint._check_sources()
    if household:
        scenarios._admit((opening, cells))
    before = core._digest(opening)
    try:
        checked, units, tolerance, forwards, discounts, admitted = core._validated_inputs(
            opening, cells, units=units, forward_gross=forward_gross,
            tolerance=tolerance, paydate=True, household=household)
        if admitted != before: raise ValueError('Admission changed the actual opening root.')
        background = _physical(background_units)
        credibility = core.m.rational(opening.macro.credibility)
        paths = []
        for cell in sorted(checked, key=lambda cell: (cell.demand_sign, cell.fulfilled)):
            weight = (credibility if cell.fulfilled else 1 - credibility) / 2
            for action in ('NEVER', 'NOW', 'WAIT'):
                paths.append(_run_path(opening, cell, action, units, background, discounts, weight, household=household))
        paths = core._incrementals(tuple(paths))
        status, action, expected, wait, admissible, choices = _select(paths, tolerance)
        counts = tuple(sum(getattr(path, name) for path in paths) for name in _COUNTS)
        return Quotation(status, action, expected, wait, admissible, choices, paths,
                         units, background, forwards, tolerance, before, *counts)
    finally:
        try:
            _unchanged(opening, before, 'actual opening root')
        finally:
            core.checkpoint._check_sources()
