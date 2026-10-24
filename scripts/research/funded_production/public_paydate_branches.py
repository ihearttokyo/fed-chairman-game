"""Explicit paid-payroll public-calendar quotations, never career adoption.

The finite dimensions, cashflow accounting, candidate-principal protection and
conservative conditional reducer are shared with the original funded route.
Only the code-owned new adapter/scenario pair and exact PaydatePublicBook are
admitted; no legacy migration, implicit funding or native qualification follows.
"""
from __future__ import annotations

from . import public_branches
from .public_branches import Quotation


def evaluate(opening, cells, *, units, forward_gross, tolerance=1e-6) -> Quotation:
    """Quote one NOW0/WAIT1/NEVER tranche through explicit bounded programs.

    Four cells x three actions x nineteen dates: at most 228 actual raw journal
    attempts. Missing or failed positive-weight baselines cannot recommend an
    investment. Preparations and quotations are not saved commands or adoptions.
    """
    return public_branches._evaluate(opening, cells, units=units,
        forward_gross=forward_gross, tolerance=tolerance, paydate=True)
