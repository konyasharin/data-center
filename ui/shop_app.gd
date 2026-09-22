class_name ShopApp
extends Control

## Buying hardware. The first app on the laptop, because the first thing the economy
## has to do is turn money into something standing in the room (docs/12, step 6).
##
## Nothing is decided here. The catalogue and the price come from the core, whether
## there is room comes from the site, and the purchase is one call that charges and
## queues the work together — a shop that could charge without queueing would
## eventually do exactly that.

var _estate: EstateBridge
var _site: Object
var _close: Callable
var _list: VBoxContainer
var _detail: VBoxContainer
var _chosen := 0


func setup(estate: EstateBridge, site: Object, close: Callable) -> void:
	_estate = estate
	_site = site
	_close = close
	_build()
	_show(0)


func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	var back := Button.new()
	back.text = "‹ назад"
	back.flat = true
	back.add_theme_font_size_override("font_size", 17)
	back.pressed.connect(func(): _close.call())
	head.add_child(back)
	head.add_child(LaptopOS._label("Магазин", 22, LaptopOS.TEXT))

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	column.add_child(split)

	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 330
	_list.add_theme_constant_override("separation", 8)
	split.add_child(_list)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", LaptopOS._box(LaptopOS.PANEL, 6, 1))
	split.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	pad.add_child(_detail)

	for i in _estate.CatalogueCount():
		var item: Array = _estate.Item(i)
		var row := Button.new()
		row.custom_minimum_size.y = 56
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 18)
		row.add_theme_stylebox_override("normal", LaptopOS._box(LaptopOS.PANEL, 6, 1))
		row.add_theme_stylebox_override("hover",
			LaptopOS._box(LaptopOS.PANEL.lightened(0.10), 6, 1))
		row.text = "  %s      %s" % [item[1], LaptopOS.money(item[3])]
		var index := i
		row.pressed.connect(func(): _show(index))
		_list.add_child(row)


func _show(index: int) -> void:
	_chosen = index
	for child in _detail.get_children():
		child.queue_free()

	var item: Array = _estate.Item(index)
	var spots: Array = _site.free_spots(item[2])
	_detail.add_child(LaptopOS._label(item[1], 26, LaptopOS.TEXT))
	_detail.add_child(LaptopOS._label("цена %s" % LaptopOS.money(item[3]), 18, LaptopOS.DIM))
	if item[5] > 0:
		_detail.add_child(LaptopOS._label("%d Вт под нагрузкой" % item[5], 18, LaptopOS.DIM))
	_detail.add_child(LaptopOS._label("занимает %dU" % item[4], 18, LaptopOS.DIM))

	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_detail.add_child(gap)

	# Where it lands is the first thing worth knowing: a purchase with nowhere to go
	# is a purchase that should not be offered.
	if spots.is_empty():
		_detail.add_child(LaptopOS._label("ставить некуда — места заняты", 18, LaptopOS.WARN))
		return
	var spot: Dictionary = spots[0]
	_detail.add_child(LaptopOS._label("встанет: %s" % spot["label"], 18, LaptopOS.ACCENT))
	_detail.add_child(LaptopOS._label("свободных мест: %d" % spots.size(), 18, LaptopOS.DIM))

	var buy := Button.new()
	buy.text = "Купить"
	buy.custom_minimum_size = Vector2(160, 44)
	buy.add_theme_font_size_override("font_size", 20)
	buy.disabled = not _estate.CanAfford(index)
	buy.pressed.connect(func(): _buy(spot))
	_detail.add_child(buy)
	if buy.disabled:
		_detail.add_child(LaptopOS._label("не хватает денег", 17, LaptopOS.WARN))


func _buy(spot: Dictionary) -> void:
	var job: int = _site.order(_chosen, spot["place"], spot["slot"])
	if job < 0:
		_detail.add_child(LaptopOS._label("отказано", 17, LaptopOS.WARN))
		return
	_show(_chosen)
