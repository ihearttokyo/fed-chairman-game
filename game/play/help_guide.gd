extends VBoxContainer
## A short entry point and lossless topic access to the complete current guide.
const TITLES := ["Play a quarter", "Proposals and follow-up", "Rates, guidance and staff", "Assets, reserves and liquidity", "Recovery and credibility", "Controls, scoring and model limits"]
const INTRO := "1. Read current conditions.\n2. Set rates and guidance.\n3. Adjust assets, reserves and secured lending.\n4. Check applied amounts and the Q+8 preview.\n5. Adopt when ready.\n\nUse Help topic for mechanics, controls and scoring."
var reference_text := ""
var pages: Array = []
var topics := OptionButton.new()
var body: TextEdit
static func partition(text: String) -> Array:
	var result: Array = []
	for title in TITLES:
		result.append({"title":title,"blocks":[]})
	for block in text.split("\n\n", false):
		var destination := 5 # Unknown future paragraphs remain accessible, never dropped.
		if block.begins_with("Start a career\n") or block.begins_with("1. Read the dispatch"):
			destination = 0
		elif block.begins_with("Policy committee\n") or block.begins_with("Routine follow-up"):
			destination = 1
		elif block.begins_with("Staff estimates") or block.begins_with("The full-information benchmark") or block.begins_with("Rates and guidance\n"):
			destination = 2
		elif block.begins_with("Securities and runoff\n") or block.begins_with("Reserves and sterilization\n") or block.begins_with("Liquidity\n"):
			destination = 3
		elif block.begins_with("Recovery\n") or block.begins_with("Credibility affects"):
			destination = 4
		result[destination].blocks.append(block)
	return result
func build(text: String, reader: TextEdit) -> void:
	reference_text = text
	pages = partition(text)
	body = reader
	add_theme_constant_override("separation", 10)
	var caption := Label.new()
	caption.text = "Help topic"
	add_child(caption)
	topics.accessibility_name = "Help topic"
	topics.accessibility_description = "Choose a topic. Tab moves to its readable text; Escape closes help."
	topics.fit_to_longest_item = false
	topics.clip_text = true
	for title in TITLES:
		topics.add_item(title)
	add_child(topics)
	body.custom_minimum_size = Vector2.ZERO
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	topics.item_selected.connect(show_topic)
	show_topic(0)
func show_topic(index: int) -> void:
	if index < 0 or index >= pages.size():
		return
	topics.select(index)
	body.text = TITLES[index] + "\n\n" + (INTRO if index == 0 else "\n\n".join(pages[index].blocks))
	# Starting mechanics stay in the same topic without front-loading their detail.
	if index == 0:
		body.text += "\n\nDetails\n\n" + "\n\n".join(pages[index].blocks)
	body.accessibility_description = body.text
	body.deselect()
	body.set_caret_line(0)
	body.scroll_vertical = 0.0
	body.scroll_horizontal = 0.0
