"""Real-world dimensions. Everything in metres; Blender and Godot both use 1 unit = 1 m."""

MM = 0.001

# EIA-310 rack geometry
U = 44.45 * MM
RACK_PANEL_WIDTH = 482.6 * MM          # 19"
RACK_HOLE_SPACING = 465.1 * MM         # centre-to-centre of mounting holes
RACK_OUTER_WIDTH = 600 * MM
RACK_OUTER_DEPTH = 1070 * MM
RACK_PLINTH = 50 * MM
RACK_ROOF = 40 * MM
RACK_UNITS_42 = 42

def rack_height(units: int = RACK_UNITS_42) -> float:
	return RACK_PLINTH + units * U + RACK_ROOF

# Server chassis
SERVER_WIDTH = 430 * MM
SERVER_DEPTH = 750 * MM
# Clearance between stacked chassis. Kept tiny on purpose: a 1.5 mm black slot
# repeated 42 times up a rack is a high-frequency pattern, and seen along the row it
# aliases into crawling bands that no amount of MSAA removes. Real racks are packed
# nearly flush too.
SERVER_GAP = 0.15 * MM

def server_height(units: int = 1) -> float:
	return units * U - 2 * SERVER_GAP

# 0U PDU strip. One strip per feed has to carry a rack, so it is a 24-outlet unit;
# src/showroom.gd and view/wiring.gd read the same numbers.
PDU_HEIGHT = 1.5
PDU_OUTLETS = 24
PDU_OUTLET_BASE = 80 * MM               # lowest outlet, from the strip foot
PDU_OUTLET_SPAN = 1.3                   # from the lowest outlet to the highest

# Vertical cable duct down the rear channel of a cabinet. src/wiring.gd mirrors these
# numbers to place the attachment points, so the two have to stay in step.
SPINE_HEIGHT = 1.8
SPINE_PITCH = 90 * MM
SPINE_BASE = 100 * MM                  # centre of the lowest gap, from the duct foot
SPINE_CLIPS = 18

# Drive carriers
LFF_W, LFF_H, LFF_D = 105 * MM, 29 * MM, 150 * MM   # 3.5" in caddy
SFF_W, SFF_H, SFF_D = 73 * MM, 17 * MM, 105 * MM    # 2.5" in caddy

# Human scale, drives door heights, desk heights, rack reach zones
HUMAN_HEIGHT = 1.75
DOOR_W, DOOR_H = 900 * MM, 2050 * MM
GATE_W, GATE_H = 3000 * MM, 2600 * MM
DESK_H = 740 * MM

# Phase 1 shed shell (interior clear dimensions)
SHED_W = 7.2
SHED_D = 5.4
SHED_WALL_H = 3.2
SHED_RIDGE_H = 4.1
WALL_T = 200 * MM
