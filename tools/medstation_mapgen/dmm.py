"""Minimal reader/writer for TGM-format .dmm maps (the format tgstation maps are stored in).

A tile is a tuple of atom strings, objects first, then the turf, then the area, exactly as stored in the key
definitions. Round-trips an unmodified map byte-for-byte.
"""
import re
from itertools import product
from string import ascii_lowercase, ascii_uppercase

HEADER = "//MAP CONVERTED BY dmm2tgm.py THIS HEADER COMMENT PREVENTS RECONVERSION, DO NOT REMOVE\n"
_KEY_CHARS = ascii_lowercase + ascii_uppercase
_DEF_RE = re.compile(r'^"(\w+)" = \(\n(.*?)\)\n(?="|\n)', re.S | re.M)
_COL_RE = re.compile(r'^\((\d+),1,(\d+)\) = \{"\n(.*?)\n"\}\n', re.S | re.M)


def _split_atoms(body):
	# atoms are separated by ",\n/" at the top level; var blocks never contain that sequence
	body = body.rstrip("\n")
	parts = re.split(r',\n(?=/)', body)
	return tuple(parts)


class Dmm:
	def __init__(self):
		self.tiles = {}  # (x, y, z) -> tuple of atoms
		self.width = self.height = self.depth = 0

	@classmethod
	def load(cls, path):
		text = open(path).read()
		m = cls()
		defs = {k: _split_atoms(body) for k, body in _DEF_RE.findall(text)}
		for x, z, col in _COL_RE.findall(text):
			x, z = int(x), int(z)
			rows = col.split("\n")
			m.height = max(m.height, len(rows))
			m.width = max(m.width, x)
			m.depth = max(m.depth, z)
			for i, key in enumerate(rows):
				m.tiles[(x, len(rows) - i, z)] = defs[key]
		return m

	def get(self, x, y, z=1):
		return self.tiles[(x, y, z)]

	def set(self, x, y, atoms, z=1):
		self.tiles[(x, y, z)] = tuple(atoms)

	def fill(self, x1, y1, x2, y2, atoms, z=1):
		for x in range(min(x1, x2), max(x1, x2) + 1):
			for y in range(min(y1, y2), max(y1, y2) + 1):
				self.set(x, y, atoms, z)

	def add(self, x, y, atom, z=1):
		"""Add an object on top of a tile (before the turf)."""
		t = list(self.tiles[(x, y, z)])
		t.insert(len(t) - 2, atom)
		self.tiles[(x, y, z)] = tuple(t)

	def set_area(self, x, y, area, z=1):
		t = list(self.tiles[(x, y, z)])
		t[-1] = area
		self.tiles[(x, y, z)] = tuple(t)

	def save(self, path):
		uniq = sorted(set(self.tiles.values()), key=lambda t: "\n".join(t))
		# keys: 2 chars is enough for everything we do (2704 combos)
		keys = ["".join(p) for p in product(_KEY_CHARS, repeat=2)]
		if len(uniq) > len(keys):
			raise ValueError("too many unique tiles for 2-char keys")
		# keep original-looking order: stable by first appearance
		order = {}
		for z in range(1, self.depth + 1):
			for x in range(1, self.width + 1):
				for y in range(self.height, 0, -1):
					t = self.tiles.get((x, y, z))
					if t is not None and t not in order:
						order[t] = None
		ordered = list(order)
		key_of = {t: keys[i] for i, t in enumerate(ordered)}
		out = [HEADER]
		for t in ordered:
			out.append('"%s" = (\n%s)\n' % (key_of[t], ",\n".join(t)))
		out.append("\n")
		for z in range(1, self.depth + 1):
			for x in range(1, self.width + 1):
				col = [key_of[self.tiles[(x, y, z)]] for y in range(self.height, 0, -1)]
				out.append('(%d,1,%d) = {"\n%s\n"}\n' % (x, z, "\n".join(col)))
			out.append("\n")
		open(path, "w").write("".join(out).rstrip("\n") + "\n")
