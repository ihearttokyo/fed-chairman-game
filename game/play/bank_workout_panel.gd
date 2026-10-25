extends VBoxContainer
## Read-only bank snapshot. All accounting and settlement live in Economy.
signal details_requested

const MINT := Color("75d4c0")
const GOLD := Color("e9b76e")
const MUTED := Color("a4babe")
const INK := Color("e7eee9")
const FIELDS := ["quarter_index", "cash", "securities_value", "deposits", "central_bank_loan", "withdrawal_queue", "loan_arrears", "equity", "payment_due", "payments_made"]

var details_button := Button.new()
var heading := Label.new()
var body := VBoxContainer.new()
var units_label := Label.new()
var balance_flow := HFlowContainer.new()
var assets_column := VBoxContainer.new()
var liabilities_column := VBoxContainer.new()
var cash_label := Label.new()
var securities_label := Label.new()
var deposits_label := Label.new()
var loan_label := Label.new()
var queue_label := Label.new()
var arrears_label := Label.new()
var equity_label := Label.new()
var payment_label := Label.new()
var payment_meter := ProgressBar.new()
var snapshot: Dictionary = {}

static func _valid(source: Dictionary) -> bool:
	for key in FIELDS:
		var value: Variant = source.get(key)
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
		if key != "equity" and value < 0:
			return false
	return source.quarter_index == floorf(source.quarter_index) and source.withdrawal_queue <= source.deposits and source.loan_arrears <= source.central_bank_loan

static func _amount(value: float) -> String:
	# Match Career.funding_amount_text, including nonzero amounts below precision.
	var amount := absf(value)
	var text := ""
	if amount > 0 and amount < 0.0001:
		text = "<0.0001"
	elif amount >= 1000000:
		text = String.num_scientific(amount)
	else:
		text = ("%.4f" if amount > 0 and amount < 0.01 else "%.2f") % amount
	return ("-" if value < 0 else "") + text

static func present(source: Dictionary) -> Dictionary:
	if not _valid(source):
		return {"ok": false, "title": "Bank data unavailable"}
	var due: float = source.payment_due
	var made: float = source.payments_made
	var equity: float = source.equity
	var applicable := due > 0
	var fraction := made / due if applicable else 0.0
	var payment_status := "No depositor payments due" if not applicable else "Depositor payments short" if made < due else "Depositor payments met"
	var made_text := _amount(made)
	var due_text := _amount(due)
	if applicable and made < due and made_text == due_text and not made_text.begins_with("<"):
		# Do not make a small shortfall look like equality after display rounding.
		# A numeric '<' is truthful only when made is below that rounded number.
		made_text = "<" + made_text if made < float(made_text) else "<due (~%s)" % made_text
	var quarter := String.num(float(source.quarter_index), 0) if source.quarter_index < 1e12 else String.num_scientific(float(source.quarter_index))
	return {
		"ok": true, "title": "Bank workout · Q" + quarter,
		"cash_text": _amount(source.cash), "securities_text": _amount(source.securities_value),
		"deposits_text": _amount(source.deposits), "loan_text": _amount(source.central_bank_loan),
		"queue_text": _amount(source.withdrawal_queue), "arrears_text": _amount(source.loan_arrears),
		"equity_text": ("+" if equity > 0 else "") + _amount(equity),
		"equity_status": "Negative equity" if equity < 0 else "Positive equity" if equity > 0 else "Zero equity",
		"equity_negative": equity < 0,
		"payment_text": "Depositor payments made %s / due %s%s" % [made_text, due_text, " · n.a." if not applicable else ""],
		"payment_status": payment_status, "payment_applicable": applicable,
		# Preserve the source ratio; only the graphic is bounded. Extreme finite
		# amounts can overflow that ratio: report unavailable, not infinity.
		# Divide after min for the bounded meter independently.
		"payment_fraction": fraction if is_finite(fraction) else null,
		"payment_fraction_representable": is_finite(fraction),
		"payment_meter_fraction": minf(made, due) / due if applicable else 0.0,
		"payment_short": applicable and made < due,
	}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	accessibility_name = "Bank balance and depositor payments"
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)
	_style_label(heading, 13, INK)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	details_button.text = "Details"
	details_button.add_theme_font_size_override("font_size", 12)
	details_button.accessibility_name = "Bank workout details"
	details_button.tooltip_text = "Read bank accounting, settlement and lending limits."
	details_button.accessibility_description = details_button.tooltip_text
	details_button.pressed.connect(func():
		if snapshot.get("ok", false): details_requested.emit())
	header.add_child(details_button)
	body.add_theme_constant_override("separation", 4)
	add_child(body)
	_style_label(units_label, 12, MUTED)
	units_label.text = "Amounts: % initial GDP"
	units_label.accessibility_name = "All bank amounts are percent of initial annual GDP"
	body.add_child(units_label)
	balance_flow.add_theme_constant_override("h_separation", 12)
	balance_flow.add_theme_constant_override("v_separation", 6)
	body.add_child(balance_flow)
	for pair in [[assets_column, "Assets"], [liabilities_column, "Liabilities"]]:
		var column: VBoxContainer = pair[0]
		column.custom_minimum_size.x = 150
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		balance_flow.add_child(column)
		var name_label := Label.new()
		_style_label(name_label, 12, MUTED)
		name_label.text = pair[1]
		column.add_child(name_label)
	for pair in [[assets_column, cash_label], [assets_column, securities_label], [liabilities_column, deposits_label], [liabilities_column, queue_label], [liabilities_column, loan_label], [liabilities_column, arrears_label], [body, equity_label], [body, payment_label]]:
		_style_label(pair[1], 12, INK)
		pair[0].add_child(pair[1])
	payment_meter.custom_minimum_size.y = 10
	payment_meter.max_value = 1.0
	payment_meter.step = 0.0
	payment_meter.show_percentage = false
	payment_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color("243c44")
	payment_meter.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MINT
	payment_meter.add_theme_stylebox_override("fill", fill)
	body.add_child(payment_meter)
	update_snapshot({})

func _style_label(label: Label, font_size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS

func _set_readout(label: Label, text: String, hint: String, tint: Color = INK) -> void:
	label.text = text
	label.accessibility_name = text
	label.tooltip_text = hint
	label.accessibility_description = hint
	label.add_theme_color_override("font_color", tint)

func update_snapshot(source: Dictionary) -> void:
	snapshot = present(source)
	heading.text = snapshot.title
	heading.accessibility_name = heading.text
	details_button.disabled = not snapshot.ok
	body.visible = snapshot.ok
	if not snapshot.ok:
		for label in [cash_label, securities_label, deposits_label, loan_label, queue_label, arrears_label, equity_label, payment_label]:
			_set_readout(label, "", "")
		payment_meter.value = 0
		payment_meter.hide()
		payment_meter.accessibility_name = ""
		payment_meter.accessibility_description = ""
		return
	_set_readout(cash_label, "Cash " + snapshot.cash_text, "Bank cash available at this snapshot; amounts are % initial annual GDP.")
	_set_readout(securities_label, "Securities " + snapshot.securities_text, "Market value of the bank's dated securities claims, not central-bank holdings.")
	_set_readout(deposits_label, "Deposits " + snapshot.deposits_text, "Total deposit liability, including queued withdrawals; do not add the queue again.")
	_set_readout(queue_label, "Queued %s (included in deposits)" % snapshot.queue_text, "Withdrawals still queued. This is a subset of deposits, not another liability.", GOLD if source.withdrawal_queue > 0 else MUTED)
	_set_readout(loan_label, "CB loan " + snapshot.loan_text, "Total central-bank loan principal, including overdue principal. New lending is debt, not bank capital.")
	_set_readout(arrears_label, "Overdue %s (included in CB loan)" % snapshot.arrears_text, "Overdue central-bank principal. This is a subset of the CB loan, not an additional liability.", GOLD if source.loan_arrears > 0 else MUTED)
	_set_readout(equity_label, "%s · Mark-to-market equity %s" % [snapshot.equity_status, snapshot.equity_text], "Signed mark-to-market equity from the model, not regulatory capital. Depositor payment progress does not establish solvency; central-bank lending does not create equity.", GOLD if snapshot.equity_negative else MINT if source.equity > 0 else MUTED)
	_set_readout(payment_label, snapshot.payment_text + " · " + snapshot.payment_status, "Depositor withdrawals: prior queue plus new requests due versus actually paid. Meter spans 0–100% of due, not central-bank refinancing. A filled meter does not establish solvency or erase overdue CB principal.", GOLD if snapshot.payment_short else MINT if snapshot.payment_applicable else MUTED)
	payment_meter.visible = snapshot.payment_applicable
	payment_meter.value = snapshot.payment_meter_fraction
	payment_meter.accessibility_name = payment_label.text
	payment_meter.accessibility_description = payment_label.tooltip_text
	var fill: StyleBoxFlat = payment_meter.get_theme_stylebox("fill")
	fill.bg_color = GOLD if snapshot.payment_short else MINT
