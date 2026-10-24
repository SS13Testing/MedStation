#!/usr/bin/env python3
"""Generates _maps/shuttles/ambulance_medstation.dmm: the hospital ambulance, a small shuttle cut down from mining_box.

Run from the repo root:  python3 tools/medstation_mapgen/shuttle.py

The footprint, airlock and docking port are kept exactly as in mining_box (5 wide, 7 tall, airlock and port at the east
middle), so the same dock dimensions work: width 7, dwidth 3, height 5.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dmm import Dmm

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "_maps/shuttles/mining_box.dmm")
DST = os.path.join(ROOT, "_maps/shuttles/ambulance_medstation.dmm")


def convert(atom):
	atom = atom.replace("/area/shuttle/mining", "/area/shuttle/ambulance")
	if atom.startswith("/obj/machinery/computer/shuttle/mining"):
		return "/obj/machinery/computer/ambulance_shuttle"
	if atom.startswith("/obj/docking_port/mobile"):
		return ('/obj/docking_port/mobile{\n\tcallTime = 150;\n\tdir = 8;\n\tignitionTime = 40;\n\tname = "ambulance";\n'
			'\tport_direction = 4;\n\tshuttle_id = "ambulance"\n\t}')
	if atom.startswith("/obj/machinery/door/airlock/titanium"):
		return '/obj/machinery/door/airlock/titanium{\n\tname = "Ambulance Rear Doors"\n\t}'
	if atom.startswith("/obj/structure/closet/crate"):
		return "/obj/structure/closet/crate/medical"
	if atom.startswith("/obj/structure/ore_box"):
		return "/obj/structure/bed/medical/emergency"
	return atom


def main():
	m = Dmm.load(SRC)
	for key, atoms in list(m.tiles.items()):
		m.tiles[key] = tuple(convert(a) for a in atoms)
	# medical kit and analyzer on the two tables, a second stretcher where the crate was
	m.add(2, 6, "/obj/item/storage/medkit/regular")
	m.add(4, 6, "/obj/item/healthanalyzer")
	m.add(2, 2, "/obj/structure/bed/medical/emergency")
	# rescue gear for the field scenes' hazards: masks for fumes and smoke, hard hats for falling debris
	for thing in ("/obj/structure/closet/emcloset", "/obj/item/clothing/mask/gas", "/obj/item/clothing/mask/gas", "/obj/item/clothing/mask/gas",
			"/obj/item/clothing/head/utility/hardhat", "/obj/item/clothing/head/utility/hardhat", "/obj/item/clothing/head/utility/hardhat",
			"/obj/item/extinguisher", "/obj/item/crowbar"):
		m.add(2, 5, thing)
	m.save(DST)
	print("wrote", DST)


if __name__ == "__main__":
	main()
