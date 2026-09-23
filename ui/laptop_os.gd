class_name LaptopOS
extends Control

## The screen of the laptop on the desk: a small operating system with a few apps.
##
## Diegetic on purpose (docs/09-interface-time.md). This Control lives inside a
## SubViewport whose texture is the laptop's display, so it is readable from across
## the room and there is no second, floating interface layer over the world.
##
## It owns no state of its own. Money, the catalogue and the job queue live in the
## core behind EstateBridge; the free spots and the ordering live in the site handed
## in by the scene. A screen that remembers things is a screen that disagrees with
## the world, which is the one thing docs/09 says the interface is for.

# Read off a 300 mm panel from half a metre away, so the steps between them have to
# be wider than they would be on a monitor: anything subtler closes up to one flat
# rectangle at that size.
const BACK := Color(0.09, 0.10, 0.12)
const PANEL := Color(0.17, 0.19, 0.22)
const EDGE := Color(0.30, 0.34, 0.39)
const TEXT := Color(0.88, 0.92, 0.95)
const DIM := Color(0.60, 0.66, 0.71)
const ACCENT := Color(0.36, 0.86, 0.56)
const WARN := Color(0.96, 0.66, 0.28)

const APPS := [
	{"id": "shop", "title": "Магазин", "note": "серверы и шкафы", "ready": true},
	{"id": "term", "title": "Терминал", "note": "скоро", "ready": false},
	{"id": "mon", "title": "Мониторинг", "note": "скоро", "ready": false},
]

var _estate: EstateBridge
var _site: Object
var _bar: Label
var _desktop: Control
var _app_area: Control
var _open := ""


func setup(estate: EstateBridge, site: Object) -> void:
	_estate = estate
	_site = site
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = BACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(PANEL, 0, 1))
	column.add_child(bar)
	var bar_row := MarginContainer.new()
	bar_row.add_theme_constant_override("margin_left", 14)
	bar_row.add_theme_constant_override("margin_right", 14)
	bar_row.add_theme_constant_override("margin_top", 8)
	bar_row.add_theme_constant_override("margin_bottom", 8)
	bar.add_child(bar_row)
	_bar = _label("", 17, TEXT)
	bar_row.add_child(_bar)

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 22)
	body.add_theme_constant_override("margin_right", 22)
	body.add_theme_constant_override("margin_top", 18)
	body.add_theme_constant_override("margin_bottom", 18)
	column.add_child(body)

	_desktop = _make_desktop()
	body.add_child(_desktop)
	_app_area = Control.new()
	_app_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_app_area.visible = false
	body.add_child(_app_area)


func _make_desktop() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 16)
	wrap.add_child(_label("Приложения", 20, DIM))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	wrap.add_child(grid)
	for app in APPS:
		grid.add_child(_tile(app))
	return wrap


func _tile(app: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(196, 128)
	button.disabled = not app["ready"]
	button.flat = true
	button.add_theme_stylebox_override("normal", _box(PANEL, 6, 1))
	button.add_theme_stylebox_override("hover", _box(PANEL.lightened(0.10), 6, 1))
	button.add_theme_stylebox_override("pressed", _box(PANEL.lightened(0.16), 6, 1))
	button.add_theme_stylebox_override("disabled", _box(PANEL.darkened(0.25), 6, 1))
	button.pressed.connect(func(): _launch(app["id"]))

	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 6)
	inner.add_child(_label(app["title"], 22, TEXT if app["ready"] else DIM, HORIZONTAL_ALIGNMENT_CENTER))
	inner.add_child(_label(app["note"], 15, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	button.add_child(inner)
	return button


func open(id: String) -> void:
	## Opening an app without clicking it, which is how a screenshot of the shop is
	## taken and how a notification would open the thing it is about.
	_launch(id)


func _launch(id: String) -> void:
	_open = id
	for child in _app_area.get_children():
		child.queue_free()
	if id == "shop":
		var shop := ShopApp.new()
		shop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_app_area.add_child(shop)
		shop.setup(_estate, _site, func(): _launch(""))
	_desktop.visible = id.is_empty()
	_app_area.visible = not id.is_empty()


func _process(_delta: float) -> void:
	if _estate == null:
		return
	var running: int = _estate.JobsRunning()
	var queued: int = _estate.JobsQueued()
	var purse := ("∞ (тест: деньги не кончаются)" if _estate.Unlimited()
		else money(_estate.Balance()))
	_bar.text = "dc-01   ·   счёт: %s   ·   в работе: %d, в очереди: %d" % [
		purse, running, queued]


static func money(amount: int) -> String:
	## Space-grouped thousands. Godot has no locale-aware number format and the string
	## is read off a screen in the world, where "24000" reads as noise.
	var digits := str(absi(amount))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return ("-" if amount < 0 else "") + out + " ₽"


static func _label(text: String, size: int, colour: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", colour)
	node.horizontal_alignment = align
	return node


static func _box(fill: Color, radius: int, border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = EDGE
	box.set_border_width_all(border)
	return box
