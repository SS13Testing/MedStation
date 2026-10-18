#!/usr/bin/env python3
"""Generates _maps/map_files/debug/medstation.dmm: a hospital carved out of the Runtime Station chassis.

Run from the repo root:  python3 tools/medstation_mapgen/hospital.py

Layout (x right, y up). Wall lines are shared between neighbouring rooms.

    y=78 +--------+----------+---------+-----------+--------+-------+
         |Pharmacy| Surg A   | Surg B  | ICU       | Morgue | Virol |   north band
    y=61 +--------+----------+---------+-----------+--------+-------+
         |                    corridor (y 58..60)                   |
    y=57 +--------+----------+---------+-----------+--------+-------+
         |Waiting | Triage   | ER      | Ward      | Diagnostics    |   south band
    y=45 +--------+----------+---------+-----------+--------+-------+
         |Lounge  | Ambulance bay       | Lockers   |                  far south band
    y=33 +--------+---------------------+-----------+
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dmm import Dmm

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "_maps/map_files/debug/runtimestation.dmm")
DST = os.path.join(ROOT, "_maps/map_files/debug/medstation.dmm")

SPACE = ("/turf/open/space/basic", "/area/space")


def atom(path, **v):
	if not v:
		return path
	body = ";\n".join("\t%s = %s" % (k, val) for k, val in v.items())
	return "%s{\n%s\n\t}" % (path, body)


def S(s):
	return '"%s"' % s


AREA = "/area/station/medical/hospital"
FLOOR = "/turf/open/floor/iron/white"
DARK = "/turf/open/floor/iron/dark"
WALL = "/turf/closed/wall"
RWALL = "/turf/closed/wall/r_wall"


class Gen:
	def __init__(self):
		self.m = Dmm.load(SRC)
		self.kept = []
		self.lights = []
		self.rooms = {}

	# ---------------------------------------------------------------- wipe
	def wipe(self, x1, y1, x2, y2):
		for x in range(x1, x2 + 1):
			for y in range(y1, y2 + 1):
				self.m.set(x, y, SPACE)

	# ---------------------------------------------------------------- primitives
	def floor(self, x, y, area, turf=FLOOR, *objs):
		self.m.set(x, y, tuple(objs) + (turf, area))

	def wall(self, x, y, turf=WALL):
		self.m.set(x, y, (turf, "/area/station/medical/hospital"))

	def window(self, x, y):
		self.m.set(x, y, ("/obj/structure/grille", "/obj/structure/window/reinforced/fulltile",
			"/turf/open/floor/plating", "/area/station/medical/hospital"))

	def door(self, x, y, area, glass=True):
		d = "/obj/machinery/door/airlock/medical/glass" if glass else "/obj/machinery/door/airlock/medical"
		self.m.set(x, y, (d, FLOOR, area))

	def put(self, x, y, *objs):
		for o in objs:
			self.m.add(x, y, o)

	# ---------------------------------------------------------------- rooms
	def room(self, key, x1, y1, x2, y2, area_suffix, turf=FLOOR, lit=True):
		"""Walls on the rectangle outline, floor inside."""
		area = AREA + area_suffix
		for x in range(x1, x2 + 1):
			for y in range(y1, y2 + 1):
				if x in (x1, x2) or y in (y1, y2):
					self.wall(x, y)
				else:
					self.floor(x, y, area, turf)
		self.rooms[key] = (x1, y1, x2, y2, area)
		if lit:
			self.light_room(x1, y1, x2, y2)

	def light_room(self, x1, y1, x2, y2):
		for x in range(x1 + 2, x2 - 1, 4):
			self.lights.append((x, y2 - 1, "/obj/machinery/light/directional/north"))
			self.lights.append((x, y1 + 1, "/obj/machinery/light/directional/south"))

	def ix(self, key):
		x1, y1, x2, y2, _ = self.rooms[key]
		return x1 + 1, y1 + 1, x2 - 1, y2 - 1

	def finish_lights(self):
		for x, y, p in self.lights:
			t = self.m.get(x, y)
			if t[-1].startswith(AREA) and "wall" not in t[-2] and not any("light" in a for a in t):
				self.put(x, y, p)


def build():
	g = Gen()
	# Wipe the old station interior. Keep clear of the emergency (63,43) and cargo (70,56) docks.
	ports = {(x, y): [a for a in g.m.get(x, y) if a.startswith("/obj/docking_port")] for x, y in ((70, 56), (63, 43))}
	g.wipe(1, 26, 71, 80)
	for (x, y), atoms in ports.items():
		g.m.set(x, y, tuple(atoms) + SPACE)

	# ---- south band y 45..57
	g.room("lobby", 6, 45, 20, 57, "/lobby")
	g.room("triage", 20, 45, 30, 57, "/triage")
	g.room("er", 30, 45, 46, 57, "/emergency_room")
	g.room("ward", 46, 49, 58, 57, "/ward")
	g.room("diag", 58, 49, 68, 57, "/diagnostics")
	# ---- north band y 61..78
	g.room("pharm", 6, 61, 20, 78, "/pharmacy")
	g.room("surga", 20, 61, 30, 78, "/surgery_a")
	g.room("surgb", 30, 61, 40, 78, "/surgery_b")
	g.room("icu", 40, 61, 54, 78, "/icu")
	g.room("morgue", 54, 61, 62, 78, "/morgue", turf=DARK)
	g.room("viro", 62, 61, 68, 78, "/virology")
	# ---- far south band y 33..45
	g.room("lounge", 6, 33, 20, 45, "/lounge")
	g.room("bay", 20, 33, 46, 45, "/ambulance_bay", turf="/turf/open/floor/iron")
	g.room("locker", 46, 33, 52, 44, "/lockers")
	# ---- departure lounge: the emergency shuttle docks to its south wall (airlocks at x 55, 57, 63, 65)
	g.room("depart", 46, 44, 67, 49, "/departures")
	for x in (55, 57, 63, 65):
		g.m.set(x, 44, ("/obj/machinery/door/airlock/external/ruin", "/turf/open/floor/plating", g.rooms["depart"][4]))
	# ---- corridor y 58..60 (walls are the bands' shared y=57 / y=61 lines)
	for x in range(7, 68):
		for y in range(58, 61):
			g.floor(x, y, AREA + "/corridor", "/turf/open/floor/iron")
	for y in range(57, 62):  # west / east end caps
		g.wall(6, y)
		g.wall(68, y)
	g.light_room(6, 57, 68, 61)

	# ---- doors: corridor <-> rooms
	for key, x in (("lobby", 13), ("triage", 25), ("er", 38), ("ward", 52), ("diag", 63)):
		g.door(x, 57, g.rooms[key][4])
	for key, x in (("pharm", 13), ("surga", 25), ("surgb", 35), ("icu", 47), ("morgue", 58), ("viro", 65)):
		g.door(x, 61, g.rooms[key][4])
	# ---- interior doors
	g.door(20, 51, g.rooms["triage"][4])           # waiting <-> triage
	g.door(30, 51, g.rooms["er"][4])               # triage <-> ER
	g.door(46, 51, g.rooms["ward"][4])             # ER <-> ward
	g.door(58, 51, g.rooms["diag"][4])             # ward <-> diagnostics
	g.door(25, 45, g.rooms["bay"][4])              # bay <-> triage
	g.door(38, 45, g.rooms["bay"][4])              # bay <-> ER
	g.door(13, 45, g.rooms["lounge"][4])           # lounge <-> waiting
	g.door(49, 44, g.rooms["locker"][4])           # lockers <-> departure lounge
	g.door(55, 49, g.rooms["depart"][4])           # departure lounge <-> ward
	g.door(63, 49, g.rooms["depart"][4])           # departure lounge <-> diagnostics
	g.door(20, 39, g.rooms["lounge"][4])           # lounge <-> bay
	g.door(46, 39, g.rooms["locker"][4])           # bay <-> lockers
	g.door(30, 70, g.rooms["surga"][4])            # surgery A <-> B
	g.door(40, 70, g.rooms["surgb"][4])            # surgery B <-> ICU
	g.door(54, 70, g.rooms["icu"][4])              # ICU <-> morgue
	g.door(20, 70, g.rooms["pharm"][4])            # pharmacy <-> surgery A
	g.door(62, 70, g.rooms["morgue"][4])           # morgue <-> isolation lab
	# observation windows into the ER and the ICU from the corridor
	for x in (33, 34, 42, 43):
		g.window(x, 57)
	for x in (43, 44, 50, 51):
		g.window(x, 61)

	# ---- waiting room entrance (bolted: patients just appear inside it, the outside is space)
	g.door(6, 51, g.rooms["lobby"][4])
	g.put(6, 51, "/obj/effect/mapping_helpers/airlock/locked")
	g.put(7, 51, "/obj/effect/landmark/patient_walkin")

	furnish(g)
	g.finish_lights()
	g.m.save(DST)
	print("wrote", DST)


# ====================================================================== furnishings
def row(g, x1, x2, y, *objs):
	for x in range(x1, x2 + 1):
		g.put(x, y, *objs)


def furnish(g):
	bed = "/obj/structure/bed/medical/anchored"
	chair = "/obj/structure/chair"
	table = "/obj/structure/table/glass"
	rtable = "/obj/structure/table/reinforced"

	# ------------------------------------------------ waiting room
	x1, y1, x2, y2 = g.ix("lobby")
	for x in range(x1 + 1, x2, 2):
		g.put(x, y1 + 2, atom(chair, dir=1))
		g.put(x, y1 + 6, atom(chair, dir=2))
	g.put(x1 + 1, y2, "/obj/machinery/vending/coffee")
	g.put(x1 + 2, y2, "/obj/machinery/vending/snack")
	g.put(x2, y2, "/obj/machinery/medical_kiosk")
	g.put((x1 + x2) // 2, y2, "/obj/effect/landmark/observer_start")
	g.put(x2, y1 + 4, "/obj/structure/filingcabinet")

	# ------------------------------------------------ triage
	x1, y1, x2, y2 = g.ix("triage")
	row(g, x1 + 1, x2 - 1, y2 - 1, rtable)           # reception desk
	g.put(x1 + 1, y2, "/obj/machinery/computer/records/medical")
	g.put(x1 + 4, y2, "/obj/machinery/computer/crew")
	g.put(x1 + 6, y2, "/obj/machinery/computer/hospital_terminal")
	g.put(x1 + 3, y2 - 1, "/obj/item/clothing/neck/stethoscope")
	g.put(x1 + 7, y2 - 1, "/obj/item/healthanalyzer")
	g.put(x1 + 2, y2 - 1, "/obj/item/triage_tagger")
	g.put(x1 + 5, y2 - 1, "/obj/item/triage_tagger")
	g.put(x1 + 3, y2 - 2, atom("/obj/structure/chair/office", dir=1))
	g.put(x2, y1 + 1, "/obj/machinery/fax")
	g.put(x1, y1 + 1, "/obj/machinery/vending/wallmed")
	for x in (x1 + 1, x1 + 3, x1 + 5):               # triage beds
		g.put(x, y1 + 1, bed)
		g.put(x, y1 + 3, bed)
	g.put(x2 - 1, y1 + 5, "/obj/machinery/iv_drip")

	# ------------------------------------------------ emergency room
	x1, y1, x2, y2 = g.ix("er")
	for i, x in enumerate(range(x1 + 1, x2, 3)):     # trauma bays
		g.put(x, y2 - 1, "/obj/machinery/stasis")
		g.put(x, y2 - 3, "/obj/machinery/iv_drip")
		g.put(x, y1 + 1, bed)
		g.put(x, y1 + 3, "/obj/machinery/iv_drip")
	g.put(x1, y2, "/obj/machinery/vending/medical")
	g.put(x2, y2, "/obj/structure/closet/crate/freezer", "/obj/item/reagent_containers/blood/o_minus", "/obj/item/reagent_containers/blood/o_minus", "/obj/item/reagent_containers/blood/o_minus", "/obj/item/reagent_containers/blood/o_plus", "/obj/item/reagent_containers/blood/o_plus", "/obj/item/reagent_containers/blood/a_plus", "/obj/item/reagent_containers/blood/b_plus")  # starting blood stock
	g.put(x2, y2 - 1, "/obj/machinery/defibrillator_mount")
	g.put(x1 + 9, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/defibrillator/loaded")
	g.put(x1 + 10, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/defibrillator/loaded")
	g.put(x1 + 11, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/storage/medkit/brute", "/obj/item/storage/medkit/fire")
	g.put(x1 + 12, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/storage/medkit/toxin", "/obj/item/storage/medkit/o2")
	g.put(x1 + 6, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/storage/medkit/regular")
	g.put(x1 + 7, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/healthanalyzer")
	g.put(x1 + 8, y1 + 6, "/obj/structure/table/reinforced", "/obj/item/stack/medical/gauze")
	g.put(x2, y1 + 6, "/obj/structure/closet/secure_closet/medical3")

	# ------------------------------------------------ inpatient ward
	x1, y1, x2, y2 = g.ix("ward")
	for x in range(x1 + 1, x2, 2):
		for y in (y1 + 1, y1 + 3, y1 + 5):
			g.put(x, y, bed)
		g.put(x + 1 if x + 1 < x2 else x, y1 + 2, "/obj/machinery/iv_drip")
	g.put(x2, y2, "/obj/structure/closet/secure_closet/medical1")
	g.put(x1, y2, "/obj/machinery/vending/wallmed")

	# ------------------------------------------------ diagnostics
	x1, y1, x2, y2 = g.ix("diag")
	g.put(x1 + 1, y2, "/obj/machinery/sleeper")
	g.put(x1 + 3, y2, "/obj/machinery/sleeper")
	g.put(x1 + 5, y2, "/obj/machinery/computer/operating")
	g.put(x1 + 1, y1 + 1, "/obj/machinery/medical_kiosk")
	g.put(x1 + 3, y1 + 1, "/obj/machinery/computer/crew")
	g.put(x2, y1 + 1, "/obj/machinery/computer/pandemic")
	g.put(x1 + 8, y2, "/obj/structure/sink")

	# ------------------------------------------------ pharmacy
	x1, y1, x2, y2 = g.ix("pharm")
	g.put(x1 + 1, y2, "/obj/machinery/chem_dispenser")
	g.put(x1 + 3, y2, "/obj/machinery/chem_dispenser")
	g.put(x1 + 5, y2, "/obj/machinery/chem_master")
	g.put(x1 + 7, y2, "/obj/machinery/chem_heater")
	g.put(x1 + 9, y2, "/obj/machinery/chem_heater")
	g.put(x2, y2, "/obj/machinery/smartfridge/chemistry/preloaded")  # starting epinephrine and multiver
	row(g, x1 + 1, x2 - 1, y2 - 2, rtable)
	g.put(x1 + 2, y2 - 2, "/obj/item/storage/box/beakers")
	g.put(x1 + 4, y2 - 2, "/obj/item/storage/pill_bottle", "/obj/item/storage/pill_bottle")
	g.put(x1 + 6, y2 - 2, "/obj/item/storage/box/syringes")
	g.put(x1 + 8, y2 - 2, "/obj/item/reagent_containers/cup/beaker/large", "/obj/item/reagent_containers/cup/beaker/large")
	g.put(x1 + 1, y1 + 1, "/obj/structure/closet/secure_closet/chemical")
	g.put(x1 + 2, y1 + 1, "/obj/structure/closet/secure_closet/chemical")
	g.put(x2, y1 + 1, "/obj/machinery/vending/drugs")
	g.put(x2, y1 + 3, "/obj/structure/closet/crate/medical")
	g.put(x1 + 6, y1 + 5, "/obj/machinery/rnd/production/techfab/department/medical")
	g.put(x1 + 1, y1 + 5, "/obj/structure/sink")
	# supply shelves along the west wall: dressings for the first busy hours (the vending machines hold few)
	for i, items in enumerate((
		("/obj/item/stack/medical/gauze", "/obj/item/stack/medical/gauze"),
		("/obj/item/stack/medical/suture", "/obj/item/stack/medical/suture"),
		("/obj/item/stack/medical/mesh", "/obj/item/stack/medical/mesh"),
		("/obj/item/stack/medical/bone_gel", "/obj/item/stack/medical/ointment", "/obj/item/stack/medical/bruise_pack"),
	)):
		g.put(x1, y1 + 8 + i, "/obj/structure/rack", *items)

	# ------------------------------------------------ operating theatres
	for key, sw in (("surga", "/obj/effect/landmark/start/medical_doctor"), ("surgb", None)):
		x1, y1, x2, y2 = g.ix(key)
		cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
		g.put(cx, cy, "/obj/structure/table/optable")
		g.put(cx, cy + 1, "/obj/machinery/stasis")
		g.put(cx + 1, cy, "/obj/machinery/computer/operating")
		g.put(cx - 1, cy, "/obj/machinery/iv_drip")
		g.put(x1, y2, "/obj/structure/sink")
		g.put(x1 + 1, y2, "/obj/structure/closet/secure_closet/medical2")
		g.put(x2, y2, "/obj/structure/table/reinforced", "/obj/item/scalpel", "/obj/item/hemostat")
		g.put(x2, y2 - 1, "/obj/structure/table/reinforced", "/obj/item/retractor", "/obj/item/cautery")
		g.put(x2, y2 - 2, "/obj/structure/table/reinforced", "/obj/item/circular_saw", "/obj/item/surgicaldrill")
		g.put(x2, y2 - 3, "/obj/structure/table/reinforced", "/obj/item/surgical_drapes", "/obj/item/bonesetter", "/obj/item/blood_filter", "/obj/item/stack/medical/bone_gel")
		g.put(x1, y1 + 1, "/obj/structure/closet/l3closet")
		g.put(x2, y1 + 1, "/obj/machinery/defibrillator_mount")

	# ------------------------------------------------ ICU
	x1, y1, x2, y2 = g.ix("icu")
	for x in range(x1 + 1, x2, 3):
		g.put(x, y2 - 1, "/obj/machinery/stasis")
		g.put(x, y2 - 3, "/obj/machinery/iv_drip")
		g.put(x, y1 + 5, "/obj/machinery/stasis")
		g.put(x, y1 + 3, "/obj/machinery/iv_drip")
	g.put(x1, y1 + 1, "/obj/machinery/computer/crew")
	g.put(x2, y1 + 1, "/obj/machinery/vending/medical")
	g.put(x2, y2, "/obj/machinery/smartfridge/organ")
	g.put(x2 - 1, y2, "/obj/structure/closet/crate/freezer", "/obj/item/reagent_containers/blood/o_minus", "/obj/item/reagent_containers/blood/o_minus", "/obj/item/reagent_containers/blood/o_minus", "/obj/item/reagent_containers/blood/o_plus", "/obj/item/reagent_containers/blood/o_plus", "/obj/item/reagent_containers/blood/a_plus", "/obj/item/reagent_containers/blood/b_plus")

	# ------------------------------------------------ morgue
	x1, y1, x2, y2 = g.ix("morgue")
	for x in range(x1, x2 + 1, 2):
		g.put(x, y2, atom("/obj/structure/bodycontainer/morgue", dir=2))
	g.put(x1 + 1, y1 + 3, "/obj/structure/table/optable")
	g.put(x2, y1 + 1, "/obj/structure/closet/crate/freezer")
	g.put(x1, y1 + 1, "/obj/structure/sink")

	# ------------------------------------------------ isolation lab (contagious patients go here)
	x1, y1, x2, y2 = g.ix("viro")
	g.put(x1, y2, "/obj/machinery/computer/pandemic")
	g.put(x1 + 2, y2, "/obj/machinery/chem_heater")
	g.put(x2, y2, "/obj/machinery/smartfridge/chemistry/virology/preloaded")  # starting antivirals
	g.put(x1 + 1, y2 - 2, "/obj/structure/table/reinforced", "/obj/item/clothing/mask/surgical", "/obj/item/clothing/gloves/latex")
	g.put(x1 + 3, y2 - 2, "/obj/structure/table/reinforced", "/obj/item/clothing/mask/surgical", "/obj/item/healthanalyzer")
	for y in (y1 + 4, y1 + 7, y1 + 10):
		g.put(x1 + 3, y, bed)
		g.put(x1 + 2, y, "/obj/machinery/iv_drip")
	g.put(x1, y1 + 4, "/obj/structure/sink")
	g.put(x1, y1 + 7, "/obj/structure/sink")
	g.put(x2, y1 + 1, "/obj/structure/closet/l3closet")
	g.put(x1, y1 + 1, "/obj/structure/closet/l3closet")

	# ------------------------------------------------ ambulance bay
	# The ambulance (3x3, facing east) parks centred on the landmark; patients are wheeled off its rear (west side).
	x1, y1, x2, y2 = g.ix("bay")
	g.put(36, 36, "/obj/effect/landmark/ambulance_park")
	g.put(25, 39, "/obj/docking_port/stationary/ambulance_home")  # the real ambulance shuttle docks here (7x5 block, airlock on top)
	for y in (35, 36, 37):
		g.put(34, y, "/obj/effect/landmark/patient_spawn")
	g.put(x2 - 2, y1 + 6, "/obj/effect/landmark/supply_drop")
	g.put(x2, y1, "/obj/structure/closet/emcloset")
	g.put(x2, y1 + 2, "/obj/structure/closet/firecloset")
	g.put(x1, y2, "/obj/machinery/vending/wallmed")
	g.put(x1 + 5, y2, "/obj/machinery/computer/ambulance_dispatch")
	for i in range(4):
		g.put(x1 + 14 + i * 2, y2, bed)               # parked stretchers
	for x in (x1 + 2, x1 + 4):
		g.put(x, y2, "/obj/machinery/iv_drip")

	# ------------------------------------------------ staff lounge (job spawns)
	x1, y1, x2, y2 = g.ix("lounge")
	jobs = ["medical_doctor", "medical_doctor", "medical_doctor", "paramedic", "paramedic", "chemist",
		"virologist", "psychologist", "geneticist", "chief_medical_officer"]
	px, py = x1 + 1, y1 + 1
	for i, j in enumerate(jobs):
		g.put(x1 + 1 + (i % 6) * 2, y1 + 1 + (i // 6) * 2, "/obj/effect/landmark/start/" + j)
	for i in range(3):
		g.put(x1 + 2 + i * 3, y1 + 5, "/obj/effect/landmark/latejoin")
	for i in range(2):
		g.put(x1 + 5 + i * 4, y1 + 7, "/obj/effect/landmark/start")
	g.put(x1 + 8, y2, "/obj/machinery/computer/hospital_terminal")
	g.put(x1 + 10, y2, "/obj/machinery/computer/ambulance_dispatch")
	g.put(x1 + 1, y2, "/obj/machinery/coffeemaker")
	g.put(x1 + 3, y2, "/obj/machinery/microwave")
	g.put(x2, y2, "/obj/machinery/vending/coffee")
	g.put(x2, y2 - 2, "/obj/machinery/vending/snack")
	for x in (x1 + 3, x1 + 5, x1 + 7):
		g.put(x, y2 - 3, table)
		g.put(x, y2 - 4, atom(chair, dir=1))

	# ------------------------------------------------ departure lounge
	x1, y1, x2, y2 = g.ix("depart")
	for x in range(x1 + 1, x2, 3):
		g.put(x, y2 - 1, atom(chair, dir=2))
		g.put(x, y1 + 1, atom(chair, dir=1))
	g.put(x2, y2, "/obj/machinery/vending/coffee")
	g.put(x1, y2, "/obj/structure/closet/emcloset")

	# ------------------------------------------------ locker room
	x1, y1, x2, y2 = g.ix("locker")
	for y in range(y1, y2 + 1, 2):
		g.put(x1, y, "/obj/structure/closet/wardrobe/white")
		g.put(x2, y, "/obj/structure/closet/secure_closet/medical1")
	g.put(x1 + 3, y2, "/obj/machinery/washing_machine")


if __name__ == "__main__":
	build()
