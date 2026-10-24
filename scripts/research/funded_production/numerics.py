"""Exact flow rounding and finite numeric boundaries for offline qualification."""
from fractions import Fraction
import math
ZERO=Fraction(0)

def amount(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, Fraction)):
        raise TypeError('An amount must be a real finite number, not a Boolean.')
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError('An amount must be finite.')
        value = Fraction(str(value))
    value = Fraction(value)
    if value < 0:
        raise ValueError('An amount cannot be negative.')
    return value


def _signed(value):
    """Use the bank's finite numeric boundary while permitting signed coupons."""
    if isinstance(value, bool) or not isinstance(value, (int, float, Fraction)):
        raise TypeError('A finite numeric amount is required, not Boolean or text.')
    return -amount(-value) if value < 0 else amount(value)


def _quantum(value):
    value = amount(value)
    if value.numerator != 1 or not 100 <= value.denominator <= 1000000000:
        raise ValueError('Quantum must be 1/n for an integer n in [100, 1000000000].')
    return value


def _floor(value, quantum):
    return (value // quantum) * quantum


def ration(capacity, *orders, quantum=Fraction(1, 1000000)):
    """Largest-remainder allocation of funded, floored physical order units.

    Equal exact remainders keep original-order priority; allocations cannot
    exceed either each funded order or the floored aggregate capacity.
    """
    quantum = _quantum(quantum)
    capacity_units = amount(capacity) // quantum
    units = tuple(amount(order) // quantum for order in orders)
    total = sum(units)
    target = min(capacity_units, total)
    if not total:
        return tuple(ZERO for _ in units)
    shares = [divmod(target * order, total) for order in units]
    allocated = [whole for whole, _ in shares]
    priority = sorted(range(len(units)), key=lambda i: -shares[i][1])
    for i in priority[:target - sum(allocated)]:
        allocated[i] += 1
    return tuple(n * quantum for n in allocated)


def coupon(face, rate_pct, scale, quantum=Fraction(1, 1000000)):
    """Return (contractual, settled) signed cashflows without changing debt.

    The caller must book and report the actual settled amount; their difference
    is numerical rounding, not a change in contractual rate or principal.
    """
    quantum = _quantum(quantum)
    face, rate_pct, scale = amount(face), _signed(rate_pct), amount(scale)
    if not scale:
        raise ValueError('The nominal price/wage unit must be positive.')
    contractual = face * rate_pct / 400
    magnitude = _floor(abs(contractual), scale * quantum)
    return contractual, -magnitude if contractual < 0 else magnitude
