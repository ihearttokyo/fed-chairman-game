"""Conditional dated quotes and exact cashflow PV, not market calibration."""
from fractions import Fraction
from .numerics import amount, _signed, coupon

def price_cashflows(cashflows, forward_gross):
    """Exact present value; each quarter's positive gross forward factor matters.

    Gross factors below one support negative yields. This prices fixed,
    nonnegative promised cashflows, not swaps, credit defaults or policy curves.
    """
    if not isinstance(cashflows, (list, tuple)) or not isinstance(forward_gross, (list, tuple)):
        raise TypeError('Cashflows and forward factors require ordered list/tuple vectors.')
    flows, curve = tuple(map(amount, cashflows)), tuple(map(amount, forward_gross))
    if not flows or len(flows) != len(curve) or any(x == 0 for x in curve):
        raise ValueError('Require a positive gross forward factor for every cashflow period.')
    discount_denominator, value = Fraction(1), Fraction(0)
    for cash, gross in zip(flows, curve):
        discount_denominator *= gross
        value += cash / discount_denominator
    return value


def _positive_curve(values):
    if not isinstance(values, (list, tuple)):
        raise TypeError('Forward factors require an ordered list/tuple.')
    curve = tuple(map(amount, values))
    if not curve or any(x == 0 for x in curve):
        raise ValueError('Every gross discount factor must be positive.')
    return curve


def _schedule(principal, forward_gross, coupon_at_issue):
    if type(coupon_at_issue) is not bool:
        raise TypeError('Coupon-at-issue must be an explicit Boolean.')
    if not isinstance(principal, (list, tuple)):
        raise TypeError('Principal dates require an ordered list/tuple.')
    principal = tuple(map(amount, principal))
    curve = _positive_curve(forward_gross)
    face = sum(principal, Fraction(0))
    if not face or len(principal) != len(curve):
        raise ValueError('Require positive total principal and one factor per future date.')
    return principal, curve, face


def par_coupon(principal, forward_gross, *, coupon_at_issue=False):
    """Annual signed par coupon for a declared, unrounded promised schedule.

    Principal is paid on FUTURE dates. Each date's coupon uses face BEFORE its
    principal payment. An optional issue-date coupon has discount factor one.
    Prepayment options and quantized actual settlements are not priced here.
    """
    principal, curve, face = _schedule(principal, forward_gross, coupon_at_issue)
    discount, outstanding = Fraction(1), face
    pv_principal = Fraction(0)
    pv_bases = face if coupon_at_issue else Fraction(0)
    for payment, gross in zip(principal, curve):
        discount /= gross
        pv_principal += payment * discount
        pv_bases += outstanding * discount
        outstanding -= payment
    return 400 * (face - pv_principal) / pv_bases


def loan_present_value(principal, rate_pct, forward_gross, *, coupon_at_issue=False):
    """Exact PV of unrounded signed coupons plus their dated principal."""
    principal, curve, face = _schedule(principal, forward_gross, coupon_at_issue)
    rate = _signed(rate_pct) / 400
    value = face * rate if coupon_at_issue else Fraction(0)
    discount, outstanding = Fraction(1), face
    for payment, gross in zip(principal, curve):
        discount /= gross
        value += (payment + outstanding * rate) * discount
        outstanding -= payment
    return value


def settled_loan_present_value(principal, rate_pct, forward_gross, *,
                               coupon_at_issue=False, scale=1):
    """PV with the ledger's per-claim coupon truncation, never a book adjustment.

    Each positive principal slot is one claim. A zero slot creates no coupon.
    Compare this with unrounded PV/face to report schedule and rounding errors;
    do not manufacture income or cash to restore mathematical par.
    """
    principal, curve, _ = _schedule(principal, forward_gross, coupon_at_issue)
    scale, rate = amount(scale), _signed(rate_pct)
    if not scale:
        raise ValueError('Settlement scale must be positive.')
    per_claim = tuple(coupon(face, rate, scale)[1] for face in principal)
    remaining = sum(per_claim, Fraction(0))
    value = remaining if coupon_at_issue else Fraction(0)
    discount = Fraction(1)
    for payment, gross, retired_coupon in zip(principal, curve, per_claim):
        discount /= gross
        value += (payment + remaining) * discount
        remaining -= retired_coupon
    return value


def _floor_root(value, degree):
    if value < 2:
        return value
    low, high = 0, 1 << ((value.bit_length() + degree - 1) // degree)
    while low + 1 < high:
        middle = (low + high) // 2
        if middle ** degree <= value:
            low = middle
        else:
            high = middle
    return low


def _binary_power(exponent):
    return Fraction(1 << exponent) if exponent >= 0 else Fraction(1, 1 << -exponent)


def policy_curve(short_rate_pct, long_anchor_pct):
    """Authored 16-interval completion, not an observed Treasury term structure.

    First interval uses the supplied short opportunity quote (already including
    any effective-rate adjustment/spread). Fifteen equal tail factors match the
    long anchor up to a nearest binary root grid with 60 fractional bits in its
    own magnitude bin. Ties round upward. Relative root error is at most2^-61;
    curve_anchor_residual reports the compound discrepancy. The adaptive grid
    does not turn tiny positive roots into zero or amplify a half-tick into a
    wildly different anchor. This is quote arithmetic, not a policy-rate cap.
    """
    short, anchor = 1 + _signed(short_rate_pct) / 400, 1 + _signed(long_anchor_pct) / 400
    if short <= 0 or anchor <= 0:
        raise ValueError('Opportunity quotes must define positive gross discount factors.')
    if short == anchor:
        return (short,) * 16
    target = anchor ** 16 / short
    exponent = (target.numerator.bit_length() - target.denominator.bit_length()) // 15
    while _binary_power(15 * exponent) > target:
        exponent -= 1
    while _binary_power(15 * (exponent + 1)) <= target:
        exponent += 1
    quantum = _binary_power(exponent - 60)
    scaled = target / quantum**15
    ticks = _floor_root(scaled.numerator // scaled.denominator, 15)
    if ((2*ticks + 1) * quantum / 2)**15 <= target:
        ticks += 1
    return (short,) + (ticks * quantum,) * 15


def curve_anchor_residual(forward_gross, long_anchor_pct):
    curve = _positive_curve(forward_gross)
    anchor = 1 + _signed(long_anchor_pct) / 400
    if len(curve) != 16 or anchor <= 0:
        raise ValueError('Anchor comparison requires 16 intervals and a positive anchor.')
    product = Fraction(1)
    for gross in curve:
        product *= gross
    return product - anchor ** 16


def _window(curve, start, count):
    curve = _positive_curve(curve)
    return tuple(curve[i] if i < len(curve) else curve[-1]
                 for i in range(start, start + count))


def project_forward_gross(curve):
    """Sixteen intervals AFTER the current closing draw; extend the last quote."""
    return _window(curve, 1, 16)


def operating_offer(lender, face, quarter, borrower, curve):
    """Opening credit: coupons at current and next CLOSING, both future dates.

    Returns a conditional command, not an underwriting approval. Execution
    types are imported only here; pure valuation never calls the executor.
    """
    from . import ledger
    ledger._integer(quarter, 'Opening quarter', 1)
    face = amount(face)
    rate = par_coupon((Fraction(0), face), _window(curve, 0, 2))
    return ledger.OperatingLoanOffer(lender, face, rate, quarter + 1, borrower=borrower)


def project_commitment(lender, ceiling, curve):
    """Closing draw: same-date coupon, then 16 future principal/coupon dates.

    Quote normalized equal principal before the actual draw is chosen. Uneven
    final quanta and per-claim settlement can change realized PV; use the actual
    schedule and settled PV helper to disclose that residual. No credit granted.
    """
    from . import ledger
    rate = par_coupon((Fraction(1, 16),) * 16, project_forward_gross(curve), coupon_at_issue=True)
    return ledger.ProjectCommitment(lender, ceiling, rate)
