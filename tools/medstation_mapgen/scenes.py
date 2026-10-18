#!/usr/bin/env python3
"""Generates the field scene maps in _maps/templates/medstation_scenes/ (the places the ambulance drives to).

Run from the repo root:  python3 tools/medstation_mapgen/scenes.py

Every scene has the same bones: an outer wall, a clear docking zone along the bottom (the ambulance parks in a 7x5 block
with its airlock at the top centre of that block, on the tile marked by the scene_dock landmark) and scattered patient
landmarks. Each theme is generated in several variants (seeded random props and rooms) so repeat calls look different;
the game also picks a random subset of the patient landmarks, so the same variant is never quite the same twice.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dmm import Dmm

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "_maps/templates/medstation_scenes")

W, H = 27, 17           # whole map including the outer wall
DOCK_X, DOCK_Y = 14, 6  # the dock landmark: airlock tile, top centre of the 7x5 parking block (x 11..17, y 2..6)
VARIANTS = 3


def atom(path, **v):
	if not v:
		return path
	return "%s{\n%s\n\t}" % (path, ";\n".join("\t%s = %s" % (k, val) for k, val in v.items()))


class Scene:
	def __init__(self, area, floor, wall, rng):
		self.m = Dmm()
		self.m.width, self.m.height, self.m.depth = W, H, 1
		self.area, self.floor, self.wall, self.rng = area, floor, wall, rng
		self.taken = set()  # tiles with something on them
		for x in range(1, W + 1):
			for y in range(1, H + 1):
				if x in (1, W) or y in (1, H):
					self.m.set(x, y, (wall, area))
				else:
					self.m.set(x, y, (floor, area))
		# the docking zone is sacred: nothing is ever placed on it
		self.dock_zone = {(x, y) for x in range(DOCK_X - 4, DOCK_X + 4) for y in range(2, DOCK_Y + 2)}
		self.m.add(DOCK_X, DOCK_Y, "/obj/effect/landmark/ambulance_scene_dock")

	def free(self, x, y):
		return 2 <= x <= W - 1 and 2 <= y <= H - 1 and (x, y) not in self.dock_zone and (x, y) not in self.taken

	def put(self, x, y, *objs):
		for o in objs:
			self.m.add(x, y, o)
		self.taken.add((x, y))

	def scatter(self, paths, count, min_y=8):
		placed = 0
		for _ in range(count * 6):
			if placed >= count:
				break
			x, y = self.rng.randint(2, W - 1), self.rng.randint(min_y, H - 1)
			if self.free(x, y):
				self.put(x, y, self.rng.choice(paths))
				placed += 1

	def walls(self, count):
		"""A few short interior wall segments to break up the space (never touching the dock zone or the outer wall)."""
		for _ in range(count):
			horizontal = self.rng.random() < 0.5
			length = self.rng.randint(3, 6)
			x, y = self.rng.randint(4, W - 4), self.rng.randint(9, H - 3)
			tiles = [(x + i, y) if horizontal else (x, y + i) for i in range(length)]
			if all(self.free(tx, ty) and 3 <= tx <= W - 2 and 3 <= ty <= H - 2 for tx, ty in tiles):
				for tx, ty in tiles[:-1] if length > 3 else tiles:  # leave a gap
					self.m.set(tx, ty, (self.wall, self.area))
					self.taken.add((tx, ty))

	def patients(self, count):
		placed = 0
		for _ in range(count * 20):
			if placed >= count:
				break
			x, y = self.rng.randint(3, W - 2), self.rng.randint(9, H - 2)
			if self.free(x, y):
				self.put(x, y, "/obj/effect/landmark/scene_patient")
				placed += 1

	def lights(self):
		for x in range(4, W, 6):
			self.m.add(x, H - 1, "/obj/machinery/light/small/directional/north") if (x, H - 1) not in self.taken else None
		for x in range(6, W, 8):
			self.m.add(x, 2, "/obj/machinery/light/small/directional/south") if self.free(x, 2) else None

	def save(self, name):
		os.makedirs(OUT, exist_ok=True)
		self.m.save(os.path.join(OUT, name))


def maintenance(rng):
	s = Scene("/area/medstation_scene/maintenance", "/turf/open/floor/plating", "/turf/closed/wall", rng)
	s.walls(4)
	s.scatter(["/obj/structure/girder", "/obj/structure/girder/displaced", "/obj/structure/closet/crate", "/obj/structure/rack"], 12)
	s.scatter(["/obj/effect/decal/cleanable/dirt", "/obj/effect/decal/cleanable/blood/old", "/obj/item/stack/rods"], 14, min_y=3)
	s.patients(6)
	s.lights()
	return s


def cargo(rng):
	s = Scene("/area/medstation_scene/cargo", "/turf/open/floor/iron", "/turf/closed/wall", rng)
	s.walls(2)
	s.scatter(["/obj/structure/closet/crate", "/obj/structure/closet/crate/large", "/obj/structure/closet/crate/wooden", "/obj/structure/rack"], 16)
	s.scatter(["/obj/effect/decal/cleanable/dirt", "/obj/effect/decal/cleanable/blood/old", "/obj/item/stack/package_wrap"], 10, min_y=3)
	s.patients(6)
	s.lights()
	return s


def hydroponics(rng):
	s = Scene("/area/medstation_scene/hydroponics", "/turf/open/floor/iron/white", "/turf/closed/wall", rng)
	s.walls(2)
	s.scatter(["/obj/machinery/hydroponics/constructable", "/obj/structure/table", "/obj/structure/flora/bush/style_random"], 18)
	s.scatter(["/obj/effect/decal/cleanable/dirt", "/obj/effect/decal/cleanable/vomit/old", "/obj/item/seeds/potato"], 10, min_y=3)
	s.patients(6)
	s.lights()
	return s


def observation(rng):
	s = Scene("/area/medstation_scene/observation", "/turf/open/floor/iron/dark", "/turf/closed/wall", rng)
	s.walls(1)
	s.scatter(["/obj/structure/chair", "/obj/structure/table", "/obj/structure/chair/comfy"], 16)
	s.scatter(["/obj/item/shard", "/obj/structure/grille/broken", "/obj/effect/decal/cleanable/glass", "/obj/effect/decal/cleanable/blood/old"], 14, min_y=3)
	s.patients(6)
	s.lights()
	return s


def fire(rng):
	s = Scene("/area/medstation_scene/fire", "/turf/open/floor/iron", "/turf/closed/wall", rng)
	s.walls(3)
	s.scatter(["/obj/structure/table", "/obj/structure/chair", "/obj/structure/rack", "/obj/structure/closet"], 12)
	s.scatter(["/obj/effect/decal/cleanable/ash", "/obj/effect/decal/cleanable/molten_object", "/obj/effect/decal/cleanable/dirt"], 20, min_y=3)
	s.patients(6)
	s.lights()
	return s


THEMES = {
	"maintenance": maintenance,
	"cargo": cargo,
	"hydroponics": hydroponics,
	"observation": observation,
	"fire": fire,
}


def main():
	for name, builder in THEMES.items():
		for i in range(1, VARIANTS + 1):
			scene = builder(random.Random("%s-%d" % (name, i)))
			scene.save("%s_%d.dmm" % (name, i))
	print("wrote %d scenes to %s" % (len(THEMES) * VARIANTS, OUT))


if __name__ == "__main__":
	main()
