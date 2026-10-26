#!/usr/bin/env python3
"""Offline structural/provenance guards, not an independent economic parity oracle."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
EXPORTER = ROOT / "game/tests/export_walkthrough.gd"
COMMIT = "a91d7dfc8ee2ac04e408285b20203a047711ebd2"
MODEL_FILES = ["economy.gd", "parameters.json", "scenarios.json",
               "exogenous_shocks.json", "portfolio_reference.json"]
METRICS = {"quarter", "inflation", "unemployment", "output_gap", "uncovered_funding",
           "credibility", "support", "assets", "loans"}
BEFORE = {"inflation", "unemployment", "output_gap", "credibility", "support"}
REQUIRED_POLICY = {"policy_rate_request_pct", "guidance_rate_pct",
                   "guidance_inflation_sensitivity", "guidance_output_gap_sensitivity",
                   "asset_flow_request_pct_initial_gdp", "liquidity_request_pct_initial_gdp"}
SWITCHES = {"reinvest_principal", "maintain_ample_reserves", "sterilize_purchases"}
STARTS = {
    "committee": ("stagflation_bank_run", 417, 0),
    "rates": ("lower_bound_slump", 113, 0),
    "guidance": ("unanchored_inflation", 217, 0),
    "portfolio": ("base", 315, 0),
    "liquidity": ("funding_stress", 419, 4),
    "credibility": ("unanchored_inflation", 521, 0),
    "recovery": ("lower_bound_slump", 613, 4),
    "workout": ("stagflation_bank_run", 417, 0),
}
LEDGER = {"bank_states", "credit_states", "credit_results", "bank_results", "credit_contexts"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def finite_tree(value, context="$"):
    if value is None or type(value) in (str, bool):
        return
    if type(value) in (int, float):
        require(number(value), f"{context}: nonfinite number ({value!r})")
    elif type(value) is list:
        for index, child in enumerate(value):
            finite_tree(child, f"{context}[{index}]")
    elif type(value) is dict:
        for key, child in value.items():
            require(type(key) is str, f"{context}: non-string JSON key ({key!r})")
            finite_tree(child, f"{context}.{key}")
    else:
        raise ValueError(f"{context}: not pure JSON ({type(value).__name__})")


def exact_json(expected, actual, context="$"):
    """Exact JSON values, permitting only equal int/float representations."""
    expected_number = type(expected) in (int, float)
    actual_number = type(actual) in (int, float)

    def different(reason):
        raise ValueError(f"{context}: {reason}; expected({type(expected).__name__})={expected!r}; "
                         f"actual({type(actual).__name__})={actual!r}")

    if expected_number or actual_number:
        if not expected_number or not actual_number:
            different("numeric/non-numeric type mismatch")
        if not number(expected) or not number(actual):
            different("nonfinite roundtrip number")
        if type(expected) is not type(actual):
            integer = expected if type(expected) is int else actual
            floating = actual if type(actual) is float else expected
            if (not -(2**63) <= floating < 2**63 or not floating.is_integer()
                    or int(floating) != integer):
                different("numeric value drift")
        elif expected != actual:
            different("numeric value drift")
        return
    if type(expected) is not type(actual):
        different("JSON type mismatch")
    if type(expected) is list:
        if len(expected) != len(actual):
            different("array length differs")
        for index, (left, right) in enumerate(zip(expected, actual)):
            exact_json(left, right, f"{context}[{index}]")
    elif type(expected) is dict:
        if expected.keys() != actual.keys():
            different("dictionary keys differ")
        for key in expected:
            exact_json(expected[key], actual[key], f"{context}.{key}")
    elif expected is None or type(expected) in (str, bool):
        if expected != actual:
            different("JSON scalar differs")
    else:
        different("unsupported JSON comparison type")


def roundtrip_source_guards():
    text = EXPORTER.read_text()
    require('_same_json(document, parsed' not in text,
            "Godot own-parser exact gate is nonqualifying and removed")
    require('JSON.parse_string(encoded)' in text and 'if not _valid_document(parsed):' in text,
            "Godot syntax/schema checks retained, not exact numeric oracle")
    require('JSON.stringify(parsed, "", true, true) != encoded' not in text,
            "roundtrip must not compare int/float spelling")
    require('var_to_bytes(document) != untouched or var_to_bytes(raw) != raw_untouched' in text,
            "raw and normalized document byte-purity retained")
    start = text.index("func _same_json(")
    end = text.index("func _check_roundtrip_comparator(", start)
    comparator = text[start:end]
    for guard in ("int(floating) != integer", "floating != floor(floating)",
                  "numeric value drift", "missing dictionary key", "unexpected dictionary key",
                  "array length differs", "JSON scalar differs", "is_finite"):
        require(guard in comparator, "exact recursive comparator guard: " + guard)
    require("func _check_roundtrip_comparator(" in text and "if not _check_roundtrip_comparator():" in text,
            "native comparator synthetic cases run on parent export")
    require("is_equal_approx" not in comparator and "epsilon" not in comparator,
            "no approximate numeric comparison")
    require(text.index('_collect_native_float64(document, "", floats)') <
            text.index('JSON.stringify(document, "", true, true)'), "native bits before serialization")
    require('bytes.encode_double(0, value)' in text and 'WALKTHROUGH_NATIVE_FLOAT64 ' in text,
            "native little-endian binary64 console proof")
    require('"json_sha256": (encoded + "\\n").sha256_text()' in text,
            "proof binds exact artifact bytes")


def strict_pairs(pairs):
    value = {}
    for key, child in pairs:
        require(key not in value, "duplicate JSON key: " + key)
        value[key] = child
    return value


def load(path):
    require(path.stat().st_size <= 4_000_000, "export exceeds bounded 4 MB budget")
    return json.loads(path.read_text(), object_pairs_hook=strict_pairs,
                      parse_constant=lambda token: (_ for _ in ()).throw(ValueError(token)))


PROOF_MARKER = "WALKTHROUGH_NATIVE_FLOAT64 "


def parse_native_log(text):
    require(len(text.encode()) <= 16_000_000, "native log exceeds bounded 16 MB budget")
    lines = [line[len(PROOF_MARKER):] for line in text.splitlines() if line.startswith(PROOF_MARKER)]
    require(len(lines) == 1, "native log must contain exactly one WALKTHROUGH_NATIVE_FLOAT64 proof")
    require(any(line.startswith("WALKTHROUGH_EXPORT_OK:") for line in text.splitlines()),
            "native log lacks successful export marker")
    require(not any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in text.splitlines()),
            "native log contains engine/runtime errors")
    return json.loads(lines[0], object_pairs_hook=strict_pairs,
                      parse_constant=lambda token: (_ for _ in ()).throw(ValueError(token)))


def pointer_token(key):
    return key.replace("~", "~0").replace("/", "~1")


def parsed_float_paths(value, pointer=""):
    if type(value) is float:
        yield pointer
    elif type(value) is list:
        for index, child in enumerate(value):
            yield from parsed_float_paths(child, f"{pointer}/{index}")
    elif type(value) is dict:
        for key, child in value.items():
            yield from parsed_float_paths(child, pointer + "/" + pointer_token(key))


def resolve_pointer(data, pointer):
    require(type(pointer) is str and (pointer == "" or pointer.startswith("/")),
            f"invalid JSON pointer: {pointer!r}")
    value = data
    for token in pointer.split("/")[1:] if pointer else []:
        require(re.search(r"~(?![01])", token) is None, f"invalid JSON pointer escape: {pointer}")
        token = token.replace("~1", "/").replace("~0", "~")
        if type(value) is dict:
            require(token in value, f"missing native proof path: {pointer}")
            value = value[token]
        elif type(value) is list:
            require(re.fullmatch(r"0|[1-9][0-9]*", token) is not None,
                    f"invalid array index in proof: {pointer}")
            require(int(token) < len(value), f"missing native proof path: {pointer}")
            value = value[int(token)]
        else:
            raise ValueError(f"missing native proof path: {pointer}")
    return value


def verify_native_proof(data, proof, artifact_bytes):
    """Native pre-serialization bits versus independent Python JSON consumer."""
    finite_tree(data)
    require(type(proof) is dict and set(proof) == {
        "schema_version", "source_commit", "model_digest", "endianness", "float_count", "floats", "json_sha256"},
        "native proof keys")
    require(type(proof["schema_version"]) is int and proof["schema_version"] == 1, "native proof version")
    require(proof["source_commit"] == COMMIT == data["source_commit"], "native proof source commit")
    require(proof["model_digest"] == data["model_digest"], "native proof model digest")
    require(proof["endianness"] == "little", "native proof must be little-endian binary64")
    require(proof["json_sha256"] == hashlib.sha256(artifact_bytes).hexdigest(),
            "native log does not bind this exact JSON artifact")
    floats = proof["floats"]
    require(type(floats) is dict and floats and type(proof["float_count"]) is int
            and proof["float_count"] == len(floats), "native float proof count")
    missing = set(parsed_float_paths(data)) - floats.keys()
    require(not missing, f"parsed float paths missing from native proof: {sorted(missing)[:8]}")
    signed_zero = 0
    for pointer, native_hex in floats.items():
        require(type(native_hex) is str and re.fullmatch(r"[0-9a-f]{16}", native_hex) is not None,
                f"{pointer}: native bits must be 8-byte little-endian lowercase hex")
        native_bytes = bytes.fromhex(native_hex)
        native = struct.unpack("<d", native_bytes)[0]
        require(math.isfinite(native), f"{pointer}: nonfinite native float proof")
        actual = resolve_pointer(data, pointer)
        require(number(actual), f"{pointer}: proved native float is no longer numeric: {actual!r}")
        if type(actual) is int:
            require(int(float(actual)) == actual, f"{pointer}: integer cannot be represented exactly as binary64")
        actual_bytes = struct.pack("<d", actual)
        if native_bytes != actual_bytes:
            if native == 0.0 and actual == 0:
                signed_zero += 1
                continue
            def ordered(bits):
                raw = struct.unpack("<Q", bits)[0]
                return (~raw & ((1 << 64) - 1)) if raw >> 63 else raw | (1 << 63)
            ulps = abs(ordered(native_bytes) - ordered(actual_bytes))
            raise ValueError(f"{pointer}: nonzero float64 drift; native={native!r} ({native_hex}); "
                             f"consumer={actual!r} ({actual_bytes.hex()}); ULP difference={ulps}")
    return len(floats), signed_zero


def digest():
    hashes = [hashlib.sha256((ROOT / "game/model" / name).read_bytes()).hexdigest()
              for name in MODEL_FILES]
    return hashlib.sha256("".join(hashes).encode()).hexdigest()


def source_guards():
    text = EXPORTER.read_text()
    pairs = dict(re.findall(r'"(game/[^"\n]+)": "([0-9a-f]{64})"', text))
    require(len(pairs) == 11 and "game/play/main.gd" in pairs, "eleven native/UI dependency hashes required")
    for path, pinned in pairs.items():
        finalized = subprocess.check_output(["git", "show", f"{COMMIT}:{path}"], cwd=ROOT)
        require(hashlib.sha256(finalized).hexdigest() == pinned, f"pin not finalized: {path}")
        require(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == pinned,
                f"native source drift: {path}")
    require(f'const SOURCE_COMMIT := "{COMMIT}"' in text, "source commit pin")
    require(f'const MODEL_DIGEST := "{digest()}"' in text, "model digest pin")
    require("career.forecast(choice.policy, choice.follow)" in text, "native forecast delegation")
    for guard in ("career.model.nominal_gdp_ratio(career.state)",
                  "var_to_bytes(career.payload()) != payload_before",
                  "var_to_bytes(career.state) != state_before",
                  "var_to_bytes(native_entry) != entry_untouched",
                  "point.quarter != entry.decision_quarter + 1"):
        require(guard in text, "native handoff purity/timing guard: " + guard)
    require("Docket.policy_for(" in text and "Committee.proposals(" in text, "native docket delegation")
    require("workout.start_episode(" in text, "native priced workout initialization")
    require("JSON.stringify(document, \"\", true, true)" in text, "full-precision pure encoding")
    require("var_to_bytes(career.payload()) != original" in text, "forecast purity check")
    for forbidden in ("user://", "shocks[", "episodes[", ".restore(", ".save(", "OS.execute(", "OS.create_process("):
        require(forbidden not in text, "unexpected save/future/process access: " + forbidden)
    for diagnostic in ("source_paths", "duplicate lesson ID", "duplicate option ID",
                       "duplicate policy of option index", "expected quarter",
                       "nonfinite number", "unsupported JSON value",
                       "JSON key collision", "Native float64 proof collection failed"):
        require(diagnostic in text, "granular exporter diagnostic: " + diagnostic)
    require("func _json_tree(" in text and "normalized[text_key] = _json_tree(" in text,
            "lossless native textual-key canonicalization")
    require("JSON normalization mutated its native input" in text, "normalization purity guard")
    require("noncanonical JSON key" in text, "strict canonical string-key validation retained")
    require(text.index("if not _valid_document(document):") <
            text.index("FileAccess.open(destination, FileAccess.WRITE)"), "validate before writing")
    roundtrip_source_guards()
    return pairs


def strings(values, label):
    require(type(values) is list and values, label + " must be nonempty")
    require(all(type(v) is str and v.strip() for v in values), label + " must contain text")


def validate_native_entry(entry, start):
    require(type(entry) is dict and set(entry) == {"decision_quarter", "nominal_gdp_ratio"},
            "native entry metadata keys")
    require(type(entry["decision_quarter"]) is int and entry["decision_quarter"] == start,
            "native entry decision quarter")
    require(number(entry["nominal_gdp_ratio"]) and entry["nominal_gdp_ratio"] > 0,
            "native entry positive finite GDP ratio")


def validate(data, check_sources=True):
    finite_tree(data)
    require(set(data) == {"schema_version", "source_commit", "model_digest", "lessons"}, "document keys")
    require(type(data["schema_version"]) is int and data["schema_version"] == 1, "schema version")
    require(data["source_commit"] == COMMIT, "source commit")
    require(data["model_digest"] == digest(), "model digest")
    lessons = data["lessons"]
    require(type(lessons) is list and len(lessons) == 8, "eight lessons required")
    require({x["id"] for x in lessons} == set(STARTS), "lesson identities")
    lesson_keys = {"id", "title", "task", "scenario", "seed", "mode", "source_paths",
                   "before", "native_entry", "options", "takeaway", "native_steps"}
    for lesson in lessons:
        require(set(lesson) == lesson_keys, "lesson keys")
        ident = lesson["id"]
        scenario, seed, start = STARTS[ident]
        require(lesson["scenario"] == scenario and type(lesson["seed"]) is int
                and lesson["seed"] == seed, "explicit authored start: " + ident)
        require(lesson["mode"] == "conditional", "conditional mode")
        validate_native_entry(lesson["native_entry"], start)
        strings([lesson[k] for k in ("title", "task", "takeaway")], "narration")
        strings(lesson["native_steps"], "native steps")
        strings(lesson["source_paths"], "source paths")
        for source in lesson["source_paths"]:
            require(not source.startswith("/") and ".." not in Path(source).parts
                    and source.startswith("game/"), "repository-relative source")
            require((ROOT / source).is_file(), "missing source: " + source)
            if check_sources:
                subprocess.check_call(["git", "cat-file", "-e", f"{COMMIT}:{source}"], cwd=ROOT)
        require(set(lesson["before"]) == BEFORE, "before metrics")
        require(0 <= lesson["before"]["credibility"] <= 1
                and 0 <= lesson["before"]["support"] <= 100, "before native units")
        require(all(number(v) for v in lesson["before"].values()), "numeric before metrics")
        options = lesson["options"]
        require(type(options) is list and 2 <= len(options) <= 5, "bounded choices")
        require(len({o["id"] for o in options}) == len(options), "unique option IDs")
        policies = []
        for option in options:
            require(set(option) == {"id", "label", "action", "policy", "path", "notes"}
                    | ({"ledger"} if ident == "workout" else set()), "option keys")
            strings([option[k] for k in ("id", "label", "action")], "option text")
            strings(option["notes"], "limits")
            policy = option["policy"]
            require(set(policy) == REQUIRED_POLICY | SWITCHES, "raw normalized native controls")
            require(all(number(policy[k]) for k in REQUIRED_POLICY), "numeric policy")
            require(all(type(policy[k]) is bool for k in SWITCHES), "boolean switches")
            require(policy["liquidity_request_pct_initial_gdp"] >= 0, "nonnegative loan offer")
            require(policy not in policies, "policy choices must differ in actual tools")
            policies.append(policy)
            path = option["path"]
            require(type(path) is list and len(path) == 8, "eight native forecast quarters")
            for quarter, point in enumerate(path, start + 1):
                require(set(point) == METRICS, "exact metric names")
                require(all(number(v) for v in point.values()), "finite numeric metrics")
                require(point["quarter"] == quarter, "consecutive native quarters")
                require(0 <= point["credibility"] <= 1 and 0 <= point["support"] <= 100,
                        "native credibility/support units")
                require(all(point[k] >= 0 for k in ("uncovered_funding", "assets", "loans")), "nonnegative stocks/funding")
            if ident == "workout":
                ledger = option["ledger"]
                require(set(ledger) == LEDGER, "native ledger keys")
                require(all(type(v) is list and len(v) == 8 for v in ledger.values()), "eight ledger observations")
                for point, bank, context in zip(path, ledger["bank_states"], ledger["credit_contexts"]):
                    require(point["quarter"] == bank["quarter_index"], "macro/bank clock")
                    require(point["loans"] == bank["central_bank_loan"], "native principal reconciliation")
                    require(number(context["annual_rate_pct"]) and context["days"] in (90, 91, 92), "native APR/day count")
        by_id = {o["id"]: o["policy"] for o in options}
        if ident == "committee":
            require(set(by_id) == {"prices", "jobs", "funding"}, "three native priorities")
        elif ident == "rates":
            require(by_id["negative"]["policy_rate_request_pct"] < 0, "signed rate example")
        elif ident == "guidance":
            require(by_id["fixed"]["guidance_inflation_sensitivity"] == 0
                    and by_id["conditional"]["guidance_inflation_sensitivity"] != 0, "conditional response contrast")
        elif ident == "portfolio":
            require(by_id["purchase"]["asset_flow_request_pct_initial_gdp"] > 0
                    and by_id["sterilize"]["sterilize_purchases"] is True
                    and by_id["runoff"]["reinvest_principal"] is False
                    and by_id["reserves"]["maintain_ample_reserves"] is False, "all portfolio tools")
        elif ident == "liquidity":
            require(by_id["secured"]["liquidity_request_pct_initial_gdp"] > 0, "secured offer contrast")
    # A serialization round trip must be pure and contain no nonfinite extensions.
    before = copy.deepcopy(data)
    encoded = json.dumps(data, allow_nan=False, sort_keys=True, separators=(",", ":"))
    require(data == before, "pure JSON encoding")
    exact_json(data, json.loads(encoded))


class GuardTests(unittest.TestCase):
    """Negative tests use synthetic validator inputs, never economic expected values."""
    def test_nonfinite(self):
        for value in (float("nan"), float("inf"), -float("inf")):
            with self.assertRaises(ValueError):
                finite_tree({"nested": [value]})

    def test_native_entry_decision_units(self):
        for quarter, ratio in ((0, 1.0), (4, 1.037), (4, .93)):
            entry = {"decision_quarter": quarter, "nominal_gdp_ratio": ratio}
            before = copy.deepcopy(entry)
            validate_native_entry(entry, quarter)
            self.assertEqual(entry, before)

    def test_native_entry_refuses_invalid_or_future_metadata(self):
        valid = {"decision_quarter": 4, "nominal_gdp_ratio": 1.037}
        for ratio in (None, True, "1", 0, -.1, float("inf"), float("nan")):
            with self.subTest(ratio=ratio), self.assertRaises(ValueError):
                validate_native_entry(dict(valid, nominal_gdp_ratio=ratio), 4)
        for quarter in (True, 4.0, 5, -1, "4"):
            with self.subTest(quarter=quarter), self.assertRaises(ValueError):
                validate_native_entry(dict(valid, decision_quarter=quarter), 4)
        for entry in (None, {}, {"decision_quarter": 4}, dict(valid, future_ratio=1.1)):
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                validate_native_entry(entry, 4)

    def test_duplicate_key(self):
        with self.assertRaises(ValueError):
            json.loads('{"x":1,"x":2}', object_pairs_hook=strict_pairs)

    def test_not_json(self):
        with self.assertRaises(ValueError):
            finite_tree({"value": object()})

    def test_nested_finite_context(self):
        with self.assertRaisesRegex(ValueError, r"lessons\[0\]\.options\[0\]\.path\[0\]\.support"):
            finite_tree({"lessons": [{"options": [{"path": [{"support": float("inf")}]}]}]})

    def test_nontext_key_context(self):
        with self.assertRaisesRegex(ValueError, r"ledger: non-string JSON key"):
            finite_tree({"ledger": {7: 2.0}})

    def test_roundtrip_source_guards(self):
        # Reads only the owned exporter; no engine or Git calls.
        roundtrip_source_guards()

    def test_equal_integer_float(self):
        exact_json({"path": [{"quarter": 1, "value": 1.25}]},
                   {"path": [{"quarter": 1.0, "value": 1.25}]})
        exact_json(1.0, 1)
        exact_json(-(2**63), float(-(2**63)))

    def test_one_ulp_numeric_drift_rejected_with_path(self):
        with self.assertRaisesRegex(ValueError, r"\$\.path\[0\]\.value: numeric value drift; expected.*actual"):
            exact_json({"path": [{"value": 1.25}]},
                       {"path": [{"value": math.nextafter(1.25, math.inf)}]})

    def test_large_integer_bits_not_lost(self):
        for integer in (2**53 + 1, 2**63 - 1):
            with self.assertRaisesRegex(ValueError, "numeric value drift"):
                exact_json(integer, float(integer))
        with self.assertRaisesRegex(ValueError, "numeric value drift"):
            exact_json(1, 1.5)

    def test_array_order_and_length_exact(self):
        for actual in ([2, 1], [1]):
            with self.assertRaises(ValueError):
                exact_json([1, 2], actual)

    def test_dictionary_keys_exact_order_irrelevant(self):
        exact_json({"a": 1, "b": "x"}, {"b": "x", "a": 1.0})
        cases = [({"a": 1, "b": None}, {"a": 1}),
                 ({"a": 1}, {"a": 1, "b": None}),
                 ({"a": 1}, {"A": 1})]
        for expected, actual in cases:
            with self.assertRaisesRegex(ValueError, "dictionary keys differ"):
                exact_json(expected, actual)

    def test_strings_booleans_null_and_types_exact(self):
        for expected, actual in (("x", "X"), ("1", 1), (True, 1), (None, False)):
            with self.assertRaises(ValueError):
                exact_json(expected, actual)
        exact_json([True, False, None, "x"], [True, False, None, "x"])

    def test_roundtrip_finite_and_pure(self):
        expected = {"x": [1, 2.5, "a", True, None]}
        actual = {"x": [1.0, 2.5, "a", True, None]}
        originals = copy.deepcopy((expected, actual))
        exact_json(expected, actual)
        self.assertEqual((expected, actual), originals)
        with self.assertRaisesRegex(ValueError, "nonfinite roundtrip number"):
            exact_json(float("inf"), float("inf"))

    def proof_fixture(self):
        # Synthetic validator evidence only; never copied from native game output.
        data = {"source_commit": COMMIT, "model_digest": "synthetic-test-only",
                "values": [1.25, -0.0], "a/b~c": -2.5}
        artifact = json.dumps(data, allow_nan=False).encode()
        floats = {p: struct.pack("<d", resolve_pointer(data, p)).hex()
                  for p in parsed_float_paths(data)}
        proof = {"schema_version": 1, "source_commit": COMMIT,
                 "model_digest": data["model_digest"], "endianness": "little",
                 "float_count": len(floats), "floats": floats,
                 "json_sha256": hashlib.sha256(artifact).hexdigest()}
        return data, proof, artifact

    def rebind_fixture(self, data, proof):
        artifact = json.dumps(data, allow_nan=False).encode()
        proof["json_sha256"] = hashlib.sha256(artifact).hexdigest()
        return artifact

    def test_native_proof_bits_and_escaped_pointer(self):
        data, proof, artifact = self.proof_fixture()
        self.assertIn("/a~1b~0c", proof["floats"])
        self.assertEqual(verify_native_proof(data, proof, artifact), (3, 0))

    def test_native_proof_one_ulp_rejected(self):
        data, proof, _ = self.proof_fixture()
        data["values"][0] = math.nextafter(data["values"][0], math.inf)
        artifact = self.rebind_fixture(data, proof)
        with self.assertRaisesRegex(ValueError, r"/values/0: nonzero float64 drift.*ULP difference=1"):
            verify_native_proof(data, proof, artifact)

    def test_native_proof_only_signed_zero_equivalent(self):
        for zero in (0.0, 0):
            data, proof, _ = self.proof_fixture()
            data["values"][1] = zero
            artifact = self.rebind_fixture(data, proof)
            self.assertEqual(verify_native_proof(data, proof, artifact), (3, 1))
        data, proof, _ = self.proof_fixture()
        data["values"][1] = math.nextafter(0.0, 1.0)
        with self.assertRaisesRegex(ValueError, "nonzero float64 drift"):
            verify_native_proof(data, proof, self.rebind_fixture(data, proof))

    def test_native_proof_missing_float_path(self):
        data, proof, artifact = self.proof_fixture()
        proof["floats"].pop("/values/0")
        proof["float_count"] = len(proof["floats"])
        with self.assertRaisesRegex(ValueError, "float paths missing from native proof"):
            verify_native_proof(data, proof, artifact)

    def test_native_proof_missing_consumer_path(self):
        data, proof, _ = self.proof_fixture()
        data.pop("a/b~c")
        with self.assertRaisesRegex(ValueError, "missing native proof path"):
            verify_native_proof(data, proof, self.rebind_fixture(data, proof))

    def test_native_proof_count_hex_and_nonfinite(self):
        for change, message in (("count", "proof count"), ("hex", "lowercase hex"),
                                ("nonfinite", "nonfinite native float")):
            data, proof, artifact = self.proof_fixture()
            if change == "count":
                proof["float_count"] += 1
            else:
                proof["floats"]["/values/0"] = ("invalid" if change == "hex"
                                                else struct.pack("<d", float("inf")).hex())
            with self.assertRaisesRegex(ValueError, message):
                verify_native_proof(data, proof, artifact)

    def test_native_proof_not_numeric_or_wrong_artifact(self):
        data, proof, artifact = self.proof_fixture()
        with self.assertRaisesRegex(ValueError, "exact JSON artifact"):
            verify_native_proof(data, proof, artifact + b" ")
        data["values"][0] = True
        with self.assertRaisesRegex(ValueError, "no longer numeric"):
            verify_native_proof(data, proof, self.rebind_fixture(data, proof))

    def test_native_log_missing_duplicate_or_no_success(self):
        _, proof, _ = self.proof_fixture()
        line = PROOF_MARKER + json.dumps(proof) + "\n"
        log = line + "WALKTHROUGH_EXPORT_OK: synthetic\n"
        self.assertEqual(parse_native_log(log), proof)
        for invalid in ("", line, log + line):
            with self.assertRaises(ValueError):
                parse_native_log(invalid)

    def test_numeric_bool_excluded(self):
        self.assertFalse(number(True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path, nargs="?", default=ROOT / "walkthrough/dist/lessons.json")
    parser.add_argument("--native-log", type=Path, help="REQUIRED for dataset qualification: captured exporter console log")
    parser.add_argument("--source-only", action="store_true", help="static source guards only; no data/parity claim")
    parser.add_argument("--self-test", action="store_true", help="synthetic negative validator tests only")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(GuardTests))
        return 0 if result.wasSuccessful() else 1
    if not args.source_only and args.native_log is None:
        parser.error("--native-log is required for qualifying dataset validation")
    source_guards()
    if args.source_only:
        print("PASS: static source provenance/guard checks only; native export NOT RUN")
        return 0
    data = load(args.data)
    validate(data)
    require(args.native_log.stat().st_size <= 16_000_000, "native log exceeds bounded 16 MB budget")
    proof = parse_native_log(args.native_log.read_text())
    count, signed_zero = verify_native_proof(data, proof, args.data.read_bytes())
    print(f"PASS: schema/provenance/native float64 consumer proof; compared={count}; "
          f"signed_zero_equivalences={signed_zero}; nonzero_differences=0; not independent model parity")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
