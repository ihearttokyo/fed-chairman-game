extends SceneTree
## Independent expected residuals generated with Python Fraction.from_float,
## not the model's own arithmetic. Binary bytes avoid cross-parser decimal
## rounding differences. No stock roundoff changes contractual claims.
const Economy = preload("res://model/economy.gd")
const GOLDEN_BITS := [
	["c217265305a3e03f", "1312644433bbb03e", "4f808c6a07a3e03f", "00000000686f8f3c"],
	["c217265305a3e03f", "1312644433bbb0be", "35afbf3b03a3e03f", "00000000686f8fbc"],
	["0000000000003440", "1312644433bbb0be", "bccc44efffff3340", "000000c08404d93c"],
	["00000000000000c0", "1312644433bbb03e", "bacb4cf4feffffbf", "000000004c4890bc"],
	["5ae7ea7687f10b40", "5441f0702e3ab1bf", "4f656303b6670b40", "000000000000a8bc"],
	["f17347b386ae3840", "2596aca517c0ab3f", "3c4a1abf66bc3840", "000000000080b2bc"],
	["de500d53db01d73f", "f4ffc80dd4bcad3f", "dc70c6d475b9da3f", "00000000000080bc"],
	["5f38a7181df32340", "711700e10290b0bf", "3038e512fdd12340", "000000000000aebc"],
	["9e5927dd96682040", "0834a199a360b93f", "069c5a24589b2040", "000000000000a0bc"],
	["9d51626fdcc73440", "1d3b005704b5753f", "a1c1a7bf37c93440", "00000000008cd33c"],
	["683dd56f8e8f1a40", "23c72d382631b93f", "85f4b50853f41a40", "000000000000bd3c"],
	["49153762f4231940", "4a7c963341748a3f", "87e0d0822e311940", "000000000080a2bc"],
	["bfa69b1e01612740", "12e9516d0e4d963f", "b44fd2a5276c2740", "0000000000c0cd3c"],
	["bfafda0edf942f40", "2484b2e9f484a03f", "4362c40364a52f40", "000000000000b2bc"],
	["526f1d17c68b0140", "523b936e53658e3f", "8d028c6a2baa0140", "000000000080a4bc"],
	["b3f11e56796a2340", "d5de49147815b83f", "71854746a49a2340", "000000000080c53c"],
	["dd4aad0ae3282c40", "6c27c1036feab7bf", "8ec8a52c0ef92b40", "000000000000b4bc"],
	["70f4e74f56ac1240", "2f3c557f34e0acbf", "f849e9e695721240", "000000000080b73c"],
	["76e4dde17a2e1b40", "1b6a852d4252b3bf", "cece27d931e11a40", "000000000000bb3c"],
	["b82edd4ea4573940", "2db56a003ff8863f", "0f3cbd56835a3940", "000000000098d63c"],
	["a024509a7ab82240", "6709c71b9329b1bf", "8d96187427962240", "000000000000b9bc"],
	["90f76422d0393940", "2668efd0a43d7cbf", "99e817480c383940", "000000000068dfbc"],
	["6ce216a442393440", "9ac87d84c3d5903f", "de01f814783d3440", "000000000040c3bc"],
	["dab1229598e62040", "1836a6d8cf19b53f", "46fed334cc102140", "000000000000b8bc"]]
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func golden(bits: Array) -> Array:
	var values: Array = []
	for encoded in bits:
		values.append(String(encoded).hex_decode().decode_double(0))
	return values
func _initialize() -> void:
	for bits in GOLDEN_BITS:
		var row := golden(bits)
		var audit := {}
		var next: float = Economy._bw_credit_stock_shift(row[0], row[1], audit, "cash")
		check(next == row[2], "Stock booking equals ordinary correctly rounded addition")
		check(Economy._bw_parts_value(audit.get("cash", [NAN])) == row[3], "Signed stock residual matches independent exact-rational oracle")
		check(Economy._bw_parts_value(Economy._bw_rounding_parts([next, -row[0], -row[1], -row[3]])) == 0.0, "Booked stock minus exact flow minus disclosed roundoff reconciles exactly")
	for pair in [[1e20, 1.0], [1e20, 20000.0], [9007199254740992.0, 1.5], [1.0, 1e-14]]:
		var audit := {}
		check(is_nan(Economy._bw_credit_stock_shift(pair[0], pair[1], audit, "cash")) and audit.is_empty(), "Erased, coarse huge-stock or disproportionate flow refuses without partial audit")
	for pair in [[1e20, 1.0], [9007199254740992.0, 1.5]]:
		check(is_nan(Economy._bw_credit_shift(pair[0], pair[1])), "Contractual claim/principal fidelity is not relaxed")
	check(Economy._bw_parts_value(Economy._bw_rounding_parts([1e20, 1.0, -1e20])) == 1.0, "Expansion audit retains a small exact leg across huge cancellation")
	check(Economy._bw_parts_value(Economy._bw_rounding_parts([9007199254740992.0, 1.5, -9007199254740992.0])) == 1.5, "Audit expansion is not permission to book an unrepresentable principal")
	for row in [[[1e20, 1.0, 1e-15, -1e20, -1.0], 1e-15], [[1e100, 3.0, 1e-100, -1e100, -3.0], 1e-100], [[1e300, 1e-300, -1e300], 1e-300]]:
		check(Economy._bw_parts_value(Economy._bw_rounding_parts(row[0])) == row[1], "Multi-component cancellation preserves the actual tiny residual")
	check(is_nan(Economy._bw_parts_value(Economy._bw_rounding_parts([1e308, 1e308]))), "Audit intermediate overflow refuses")
	var audit := {}
	var cash := 0.5199
	var expected_parts: Array = []
	for i in range(8):
		var next: float = cash + golden(GOLDEN_BITS[0])[1]
		expected_parts.append(Economy._bw_parts_value(Economy._bw_rounding_parts([next, -cash, -golden(GOLDEN_BITS[0])[1]])))
		cash = Economy._bw_credit_stock_shift(cash, golden(GOLDEN_BITS[0])[1], audit, "cash")
	check(audit.cash == expected_parts, "Eight-period audit retains every signed component without claiming compounding income")
	if failures == 0:
		print("PASS: priced stock rounding ", checks, " checks; independent rational goldens and strict claim guards")
	quit(0 if failures == 0 else 1)
