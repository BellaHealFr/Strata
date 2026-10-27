# Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
# (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

"""Relève le territoire réel de chaque zone dans le terrain du client et génère Data/Territory.lua.

Usage : python -I tools/extract_territory.py <dossier Data du client 3.3.5>

Le terrain d'une carte est découpé en carrés de 33,3 yards (MCNK des fichiers ADT), et chacun
porte le numéro de sa zone (AreaTable.dbc). Un sous-lieu est remonté à sa zone parente ; une
ville, une micro-carte ou une zone que Strata ne dessine pas est rattachée à la plus petite zone
dessinée dont le rectangle (WorldMapArea.dbc) contient le carré : Hurlevent à la Forêt d'Elwynn,
le Val d'Ammen à l'Île de Brume-Azur. Un carré entièrement sous le niveau de la mer (fond de la
mer, MCVT) ne compte pas : la zone se limite à sa terre, comme dans OpenMap, et la mer, les
ornements et le cadre peints aux bords de sa carte (griffes des cartes du Norfendre) tombent dehors.
En Outreterre, sans mer, c'est le sol du Néant distordu (sous -500) qui ne compte pas : la
boussole et le bord déchiré peints aux coins des cartes de zone tombent dehors. Ce qui n'est pas
du terrain y compte aussi : les bâtiments posés au-dessus du Néant (MODF : le Donjon de la Tempête)
et ce que peignent les morceaux de la zone (leurs îles), hors des coins de la carte.
Pour chaque zone, l'outil garde sa forme en escalier, en px de sa carte (1002 x 668) : son
étendue est-ouest, puis, pour chacune des 4 colonnes de 256 px de la carte (celles des tuiles
de Blizzard), l'étendue nord-sud de ses carrés. Strata y coupe le fond et les morceaux de la
zone : le cadre et les noms des voisines que Blizzard peint au-delà du territoire tombent dehors
(OpenMap le fait avec des masques, absents de la 3.3.5).

Les archives sont lues sans être modifiées. La dernière archive du client qui contient un
fichier l'emporte ; un fichier qu'elle ne sait pas lire est repris dans la suivante.
Seules les zones dessinées par Strata (Data/Zones.lua, hors villes et micro-cartes) sont gardées.

Besoin de mpyq et Pillow : python -m pip install mpyq pillow
"""
import math
import re
import struct
import sys
from pathlib import Path

import mpyq

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_overlays import archives, dbc  # noqa: E402

MAP_W, MAP_H = 1002, 668
TILE = 1600 / 3            # yards d'un fichier ADT
CHUNK = TILE / 16          # yards d'un carré MCNK
ORIGIN = 32 * TILE         # le coin du monde, en yards
SEA = 0                    # niveau de la mer (yards) : un carré tout en dessous est le fond de la mer
# L'Outreterre n'a pas de mer : ses îles flottent, parfois sous 0 (Raz-de-Néant jusqu'à -200),
# au-dessus du sol du Néant distordu (-1 000 à -1 270). Seul ce sol tombe dehors.
FLOOR = {3: -500}
CORNER = 128               # px : coin d'une carte de zone, où Blizzard peint ses ornements


def underwater(raw, pos, head, level):
    """Le carré MCNK commençant à pos est-il entièrement sous l'altitude level ?"""
    ofs = struct.unpack("<I", head[20:24])[0]                 # MCVT, depuis le début du MCNK
    z = struct.unpack("<f", head[112:116])[0]                 # hauteur de base du carré
    at = pos + ofs
    if raw[at:at + 4] != b"TVCM":
        return False
    heights = struct.unpack("<145f", raw[at + 8:at + 8 + 145 * 4])
    return z + max(heights) < level


class Client:
    """Les fichiers du client, par nom, de l'archive la plus prioritaire à la moins prioritaire."""

    def __init__(self, data):
        self.where = {}
        for path in archives(data):
            try:
                arc = mpyq.MPQArchive(str(path), listfile=True)
            except Exception:
                continue
            for f in arc.files or []:
                self.where.setdefault(f.decode("latin-1").lower(), []).append((arc, f, path.name))

    def read(self, name):
        for arc, f, src in self.where.get(name.lower(), []):
            try:
                raw = arc.read_file(f)
            except Exception:
                continue
            if raw:
                return raw, src
        return None, None

    def names(self, pattern):
        return [(n, m) for n in self.where for m in [pattern.match(n)] if m]


def land_zones(root):
    """Les zones dessinées : fichier de carte -> continent (Data/Zones.lua, hors micro-cartes)."""
    src = (root / "Data/Zones.lua").read_text(encoding="utf-8")
    cities = {"Stormwind", "Ironforge", "Darnassis", "TheExodar", "Ogrimmar", "Undercity", "ThunderBluff",
              "SilvermoonCity", "ShattrathCity", "Dalaran"}
    out = {}
    for m in re.finditer(r"^\t\[(\d+)\] = \{.*?\n\t\} \},", src, re.M | re.S):
        for z in re.finditer(r"^\t\t(\w+) = \{[^}\n]*\}", m.group(0), re.M):
            if not z.group(0).rstrip().endswith("true }") and z.group(1) not in cities:
                out[z.group(1)] = int(m.group(1))
    return out


def read_overlays(root):
    """Les morceaux des cartes de zone (Data/Overlays.lua) : fichier -> [(texture, w, h, x, y)]."""
    src = (root / "Data/Overlays.lua").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r"^\t(\w+) = \{\n(.*?)^\t\},", src, re.M | re.S):
        out[m.group(1)] = [(t, int(w), int(h), int(x), int(y)) for t, w, h, x, y in
                           re.findall(r'\{ "(\w+)", (\d+), (\d+), (\d+), (\d+) \}', m.group(2))]
    return out


def piece_content(client, file, o):
    """Ce que peint un morceau de carte en Outreterre (ses îles), en px de la carte : pour chaque
    colonne de 256 px, le rectangle de ses pixels visibles (alpha > 1/2), sans les coins de la
    carte, où Blizzard peint ses ornements (boussole, bord déchiré)."""
    from io import BytesIO
    from PIL import Image          # (python -m pip install pillow)
    name, w, h, x, y = o
    wide, tall = -(-w // 256), -(-h // 256)
    img = Image.new("RGBA", (wide * 256, tall * 256))
    n = 0
    for j in range(tall):
        for k in range(wide):
            n += 1
            raw, _ = client.read("\\".join(["Interface", "WorldMap", file, name + str(n) + ".blp"]))
            if raw:
                img.paste(Image.open(BytesIO(raw)).convert("RGBA"), (k * 256, j * 256))
    alpha = img.getchannel("A").load()
    rects = {}
    for py in range(min(h, MAP_H - y)):
        for px in range(min(w, MAP_W - x)):
            mx, my = x + px, y + py
            corner = (mx < CORNER or mx >= MAP_W - CORNER) and (my < CORNER or my >= MAP_H - CORNER)
            if alpha[px, py] > 128 and not corner:
                r = rects.setdefault(mx // 256, [mx, my, mx + 1, my + 1])
                r[0], r[1], r[2], r[3] = min(r[0], mx), min(r[1], my), max(r[2], mx + 1), max(r[3], my + 1)
    return [tuple(r) for r in rects.values()]


def main():
    data = Path(sys.argv[1])
    root = Path(__file__).resolve().parent.parent
    client = Client(data)

    raw, src_area = client.read("DBFilesClient\\WorldMapArea.dbc")
    rows, text, fields = dbc(raw)
    if fields != 11:
        sys.exit("WorldMapArea.dbc : %d champs, 11 attendus (3.3.5)" % fields)
    # ID, carte, zone (AreaTable), fichier, gauche, droite, haut, bas (yards du monde), ...
    wma = {}
    for r in rows:
        left, right, top, bottom = struct.unpack("<4f", struct.pack("<4I", *r[4:8]))
        wma[text(r[3])] = dict(map=r[1], area=r[2], left=left, right=right, top=top, bottom=bottom)
    raw, _ = client.read("DBFilesClient\\AreaTable.dbc")
    rows, _, _ = dbc(raw)
    parent = {r[0]: r[2] for r in rows}
    raw, _ = client.read("DBFilesClient\\Map.dbc")
    rows, text_m, _ = dbc(raw)
    folder = {r[0]: text_m(r[1]) for r in rows}

    land = land_zones(root)
    missing = [f for f in land if f not in wma]
    if missing:
        sys.exit("zones absentes de WorldMapArea.dbc : " + ", ".join(sorted(missing)))
    file_of_area = {wma[f]["area"]: f for f in land if wma[f]["area"]}

    def owner(area, map_id, wy, wx):
        seen = set()
        while area and area not in seen:
            seen.add(area)
            if area in file_of_area and wma[file_of_area[area]]["map"] == map_id:
                return file_of_area[area]
            area = parent.get(area, 0)
        best, size = None, math.inf
        for f in land:
            w = wma[f]
            a = (w["left"] - w["right"]) * (w["top"] - w["bottom"])
            if w["map"] == map_id and w["right"] <= wy <= w["left"] and w["bottom"] <= wx <= w["top"] and a < size:
                best, size = f, a
        return best

    # Les carrés de chaque zone : bords ouest et nord, en yards du monde.
    cells = {}
    unread = 0
    areas = {}        # (carte, gx, gy) -> zone du carré, même sous le niveau de la mer
    wmos = {}         # bâtiments placés (MODF) : identifiant -> (carte, boîte en yards du monde)
    for map_id in sorted({wma[f]["map"] for f in land}):
        name = folder[map_id].lower()
        pattern = re.compile(r"world\\maps\\%s\\%s_(\d+)_(\d+)\.adt$" % (re.escape(name), re.escape(name)))
        for path, m in client.names(pattern):
            tx, ty = int(m.group(1)), int(m.group(2))
            raw, _ = client.read(path)
            if not raw:
                unread += 1
                continue
            pos = raw.find(b"KNCM")
            while pos >= 0:
                head = raw[pos + 8:pos + 8 + 128]
                ix, iy = struct.unpack("<2I", head[4:12])
                area = struct.unpack("<I", head[0x34:0x38])[0]
                if ix < 16 and iy < 16:
                    wy = ORIGIN - (tx * 16 + ix) * CHUNK     # bord ouest du carré
                    wx = ORIGIN - (ty * 16 + iy) * CHUNK     # bord nord
                    areas[map_id, tx * 16 + ix, ty * 16 + iy] = area
                    f = owner(area, map_id, wy - CHUNK / 2, wx - CHUNK / 2)
                    if f and not underwater(raw, pos, head, FLOOR.get(land[f], SEA)):
                        cells.setdefault(f, []).append((wy, wx))
                pos = raw.find(b"KNCM", pos + 8)
            at = raw.find(b"FDOM")
            if at >= 0:
                size = struct.unpack("<I", raw[at + 4:at + 8])[0]
                for k in range(size // 64):
                    e = raw[at + 8 + 64 * k:at + 8 + 64 * (k + 1)]
                    uid = struct.unpack("<I", e[4:8])[0]
                    lo, hi = struct.unpack("<3f", e[32:44]), struct.unpack("<3f", e[44:56])
                    # (x, hauteur, z) du fichier : y du monde = ORIGIN - x, x du monde = ORIGIN - z
                    wmos[uid] = (map_id, ORIGIN - hi[0], ORIGIN - lo[0], ORIGIN - hi[2], ORIGIN - lo[2], hi[1])

    # En Outreterre, des îles ne sont que des bâtiments posés au-dessus du Néant, sans terrain
    # dessous (le Donjon de la Tempête) : leur boîte compte dans la zone du carré sous leur centre.
    for map_id, y0, y1, x0, x1, top in wmos.values():
        if y1 - y0 > 2000 or x1 - x0 > 2000:
            continue          # (ciel, décor géant)
        gx, gy = int((ORIGIN - (y0 + y1) / 2) // CHUNK), int((ORIGIN - (x0 + x1) / 2) // CHUNK)
        f = owner(areas.get((map_id, gx, gy), 0), map_id, (y0 + y1) / 2, (x0 + x1) / 2)
        if not f or land[f] not in FLOOR or top < FLOOR[land[f]]:
            continue
        for i in range(int((ORIGIN - y1) // CHUNK), int((ORIGIN - y0) // CHUNK) + 1):
            for j in range(int((ORIGIN - x1) // CHUNK), int((ORIGIN - x0) // CHUNK) + 1):
                cells.setdefault(f, []).append((ORIGIN - i * CHUNK, ORIGIN - j * CHUNK))

    pieces = read_overlays(root)
    out = {}
    for f, sq in cells.items():
        w = wma[f]
        sx, sy = MAP_W / (w["left"] - w["right"]), MAP_H / (w["top"] - w["bottom"])
        # chaque carré en px de la carte (x0, y0, x1, y1), gardé s'il touche la carte
        px = [((w["left"] - wy) * sx, (w["top"] - wx) * sy, (w["left"] - wy + CHUNK) * sx, (w["top"] - wx + CHUNK) * sy)
              for wy, wx in sq]
        if land[f] in FLOOR:
            for o in pieces.get(f, []):
                px += piece_content(client, f, o)
        px = [p for p in px if p[2] > 0 and p[0] < MAP_W and p[3] > 0 and p[1] < MAP_H]
        if not px:
            continue
        x0, x1 = max(0, math.floor(min(p[0] for p in px))), min(MAP_W, math.ceil(max(p[2] for p in px)))
        cols = []
        for k in range(4):
            a, b = max(x0, 256 * k), min(x1, 256 * (k + 1))
            ys = [p for p in px if p[2] > a and p[0] < b]
            if a < b and ys:
                cols.append((max(0, math.floor(min(p[1] for p in ys))), min(MAP_H, math.ceil(max(p[3] for p in ys)))))
            else:
                cols.append(None)
        out[f] = (x0, x1, cols)

    lines = [
        "-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires",
        "-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.",
        "",
        "-- Le territoire réel de chaque zone, en escalier, d'après son terrain (zone de chaque",
        "-- carré de 33,3 yards des fichiers ADT du client 3.3.5, AreaTable.dbc, %s)." % src_area,
        "-- Les villes et les micro-cartes comptent dans la zone qui les contient.",
        "-- Généré par tools/extract_territory.py : régénérer plutôt que modifier à la main.",
        "-- [fichier de carte] = { x0, x1, colonne 1, ..., colonne 4 }  (px de la carte, 1002 x 668)",
        "-- x0, x1 : étendue est-ouest ; colonne k (px 256 * (k - 1) à 256 * k) : { y0, y1 }, ou false.",
        "",
        "local _, ns = ...",
        "",
        "ns.Territory = {",
    ]
    for f in sorted(out):
        x0, x1, cols = out[f]
        lines.append("\t%s = { %d, %d, %s }," % (f, x0, x1, ", ".join("{ %d, %d }" % c if c else "false" for c in cols)))
    lines.append("}")
    (root / "Data/Territory.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    absent = sorted(set(land) - set(out))
    print("%d zones, %d fichiers de terrain illisibles, sans terrain : %s" % (len(out), unread, ", ".join(absent) or "aucune"))


if __name__ == "__main__":
    main()
