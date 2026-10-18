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
		self.blocked = set()  # tiles you can't walk through (walls, big props)
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
			if not o.startswith(("/obj/effect/", "/obj/item/")):
				self.blocked.add((x, y))
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

	def wall_at(self, x, y):
		self.m.set(x, y, (self.wall, self.area))
		self.taken.add((x, y))
		self.blocked.add((x, y))

	def structure(self, vertical_walls=2, extra_gaps=1):
		"""A loading corridor along the bottom (y 2..7, where the ambulance docks) and rooms above it (y 9..H-1).

		The wall between them (y=8) always has a 3-wide doorway straight ahead of the ambulance's airlock, plus some extra
		doorways. Vertical walls split the rooms and each has a 3-tall doorway, so every room can be reached with a stretcher.
		"""
		gap_starts = [DOCK_X - 1] + self.rng.sample([x for x in range(3, W - 4, 4) if abs(x - (DOCK_X - 1)) > 4], extra_gaps)
		gap_tiles = {(gx + i, 8) for gx in gap_starts for i in range(3)}
		for x in range(2, W):
			if (x, 8) in gap_tiles:
				self.taken.add((x, 8))
			else:
				self.wall_at(x, 8)
		# the loading corridor's gap tiles on y=7 stay clear too
		for gx in gap_starts:
			for i in range(3):
				self.taken.add((gx + i, 7))
		splits = sorted(self.rng.sample(range(7, W - 6, 5), vertical_walls)) if vertical_walls else []
		for vx in splits:
			door_y = self.rng.randint(10, H - 5)
			for y in range(9, H):
				if door_y <= y <= door_y + 2:
					self.taken.add((vx, y))
					self.taken.add((vx + 1, y))
					self.taken.add((vx - 1, y))
				else:
					self.wall_at(vx, y)

	def rows(self, ys, path_choices, density, x_from=3):
		"""Rows of props (crate stacks, planters) with random gaps, like aisles."""
		for y in ys:
			for x in range(x_from, W - 1):
				if self.rng.random() < density and self.free(x, y):
					self.put(x, y, self.rng.choice(path_choices))

	def window_wall(self):
		"""Intact windows along the top edge, so the lounge looks out over the void."""
		for x in range(3, W - 1):
			self.m.set(x, H, ("/obj/structure/grille", "/obj/structure/window/reinforced/fulltile", "/turf/open/floor/plating", self.area))
			self.taken.add((x, H))

	def reachable(self):
		"""Tiles you can walk to from the doorway in front of the ambulance (flood fill around walls and big props)."""
		start = (DOCK_X, 8)
		seen, queue = {start}, [start]
		while queue:
			x, y = queue.pop()
			for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
				if (nx, ny) in seen or not (2 <= nx <= W - 1 and 2 <= ny <= H - 1) or (nx, ny) in self.blocked:
					continue
				seen.add((nx, ny))
				queue.append((nx, ny))
		return seen

	def patients(self, count):
		"""Patient landmarks in the rooms, only where a stretcher can get to them."""
		reachable = self.reachable()
		candidates = [(x, y) for (x, y) in reachable if y >= 9 and self.free(x, y) and 3 <= x <= W - 2 and y <= H - 2]
		self.rng.shuffle(candidates)
		for x, y in candidates[:count]:
			self.put(x, y, "/obj/effect/landmark/scene_patient")

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
	s.structure(vertical_walls=2, extra_gaps=1)
	s.scatter(["/obj/structure/girder", "/obj/structure/girder/displaced", "/obj/structure/closet/crate", "/obj/structure/rack"], 14, min_y=9)
	s.scatter(["/obj/effect/decal/cleanable/dirt", "/obj/effect/decal/cleanable/blood/old", "/obj/item/stack/rods"], 18, min_y=2)
	s.patients(6)
	s.lights()
	return s


def cargo(rng):
	s = Scene("/area/medstation_scene/cargo", "/turf/open/floor/iron", "/turf/closed/wall", rng)
	s.structure(vertical_walls=1, extra_gaps=2)
	# aisles of crate stacks, with a few toppled crates in the aisles
	s.rows((10, 13, 16 - 1), ["/obj/structure/closet/crate", "/obj/structure/closet/crate/large", "/obj/structure/closet/crate/wooden"], 0.7)
	s.scatter(["/obj/structure/closet/crate", "/obj/item/stack/package_wrap", "/obj/effect/decal/cleanable/dirt", "/obj/effect/decal/cleanable/blood/old"], 14, min_y=9)
	s.patients(6)
	s.lights()
	return s


def hydroponics(rng):
	s = Scene("/area/medstation_scene/hydroponics", "/turf/open/floor/iron/white", "/turf/closed/wall", rng)
	s.structure(vertical_walls=1, extra_gaps=2)
	# long rows of planters with a spill in between
	s.rows((10, 13), ["/obj/machinery/hydroponics/constructable"], 0.75)
	s.scatter(["/obj/structure/flora/bush/style_random", "/obj/structure/table", "/obj/effect/decal/cleanable/vomit/old", "/obj/effect/decal/cleanable/dirt"], 16, min_y=9)
	s.patients(6)
	s.lights()
	return s


def observation(rng):
	s = Scene("/area/medstation_scene/observation", "/turf/open/floor/iron/dark", "/turf/closed/wall", rng)
	s.structure(vertical_walls=0, extra_gaps=2)
	s.window_wall()
	# rows of seating facing the windows, a counter at the back
	s.rows((11, 14), ["/obj/structure/chair", "/obj/structure/chair/comfy"], 0.55, x_from=4)
	s.rows((9,), ["/obj/structure/table"], 0.5, x_from=4)
	s.scatter(["/obj/item/shard", "/obj/structure/grille/broken", "/obj/effect/decal/cleanable/glass", "/obj/effect/decal/cleanable/blood/old"], 16, min_y=9)
	s.patients(6)
	s.lights()
	return s


def fire(rng):
	s = Scene("/area/medstation_scene/fire", "/turf/open/floor/iron", "/turf/closed/wall", rng)
	s.structure(vertical_walls=2, extra_gaps=1)
	s.scatter(["/obj/structure/table", "/obj/structure/chair", "/obj/structure/rack", "/obj/structure/closet"], 12, min_y=9)
	# scorch marks clustered around a few centres
	for _ in range(3):
		cx, cy = rng.randint(4, W - 4), rng.randint(10, H - 3)
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if rng.random() < 0.55 and s.free(cx + dx, cy + dy):
					s.put(cx + dx, cy + dy, rng.choice(["/obj/effect/decal/cleanable/ash", "/obj/effect/decal/cleanable/molten_object", "/obj/effect/decal/cleanable/dirt"]))
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
