# Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
# (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

"""Extrait tous les morceaux des cartes de zone de WorldMapOverlay.dbc et génère Data/Overlays.lua.

Usage : python -I tools/extract_overlays.py <dossier Data du client 3.3.5>

Le client ne donne que les morceaux découverts (GetMapOverlayInfo). La table du client les
contient tous : nom de texture, taille et place dans la carte de la zone (px de la carte de
1002 x 668), comme GetMapOverlayInfo les renvoie. Strata s'en sert pour révéler la carte quand
le brouillard est éteint, comme le « fog clear » de Mapster.

Les archives sont lues sans être modifiées. La dernière archive du client qui contient un
fichier l'emporte (patch-xxXX-z sur patch-xxXX sur locale-xxXX).
Seules les zones dessinées par Strata (Data/Zones.lua) sont gardées ; chaque nom de zone de la
table est vérifié, une zone inconnue arrête l'outil.

Besoin de mpyq : python -m pip install mpyq
"""
import re
import struct
import sys
from pathlib import Path

import mpyq


def patch_order(names, base):
    """Les correctifs du plus prioritaire au moins prioritaire : le client charge patch.mpq, puis
    patch-2 ... patch-9, puis patch-a ... patch-z, et le dernier chargé l'emporte."""
    def suffix(n):
        rest = n.lower()[len(base):-len(".mpq")]
        return rest[1:] if rest.startswith("-") else ""
    return sorted((n for n in names if n.lower().startswith(base) and n.lower().endswith(".mpq")
                   and (n.lower() == base + ".mpq" or n.lower().startswith(base + "-"))),
                  key=suffix, reverse=True)


def archives(data):
    """Les archives du client, de la plus prioritaire à la moins prioritaire."""
    out = []
    for folder in sorted(p for p in data.iterdir() if p.is_dir() and re.fullmatch(r"[a-z]{2}[A-Z]{2}", p.name, re.I)):
        loc = folder.name.lower()
        names = sorted(f.name for f in folder.glob("*.mpq"))
        out += [folder / n for n in patch_order(names, "patch-" + loc)]
        out += [folder / n for n in names if n.lower() == "locale-" + loc + ".mpq"]
    names = sorted(f.name for f in data.glob("*.mpq"))
    out += [data / n for n in patch_order(names, "patch")]
    out += [data / n for n in ("lichking.mpq", "expansion.mpq", "common-2.mpq", "common.mpq") if (data / n).exists()]
    return out


def read(data, name):
    for path in archives(data):
        try:
            arc = mpyq.MPQArchive(str(path), listfile=True)
        except Exception:
            continue
        for f in arc.files or []:
            if f.decode("latin-1").lower() == name.lower():
                return arc.read_file(f), path.name
    sys.exit("introuvable dans les archives : " + name)


def dbc(raw):
    magic, n, fields, size, _ = struct.unpack("<4s4I", raw[:20])
    if magic != b"WDBC":
        sys.exit("fichier DBC invalide")
    strings = raw[20 + n * size:]
    rows = [struct.unpack("<%dI" % fields, raw[20 + i * size:20 + (i + 1) * size]) for i in range(n)]

    def text(off):
        return strings[off:strings.index(b"\0", off)].decode("utf-8")
    return rows, text, fields


def drawn_files(root):
    src = (root / "Data/Zones.lua").read_text(encoding="utf-8")
    return {m.group(1) for m in re.finditer(r"^\t\t(\w+) = \{[^}\n]*\}", src, re.M)
            if not m.group(0).rstrip().endswith("true }")}


def main():
    data = Path(sys.argv[1])
    root = Path(__file__).resolve().parent.parent
    raw, src_area = read(data, "DBFilesClient\\WorldMapArea.dbc")
    areas, text_a, fields = dbc(raw)
    if fields != 11:
        sys.exit("WorldMapArea.dbc : %d champs, 11 attendus (3.3.5)" % fields)
    file_of = {r[0]: text_a(r[3]) for r in areas}
    raw, src_over = read(data, "DBFilesClient\\WorldMapOverlay.dbc")
    rows, text_o, fields = dbc(raw)
    if fields != 17:
        sys.exit("WorldMapOverlay.dbc : %d champs, 17 attendus (3.3.5)" % fields)

    drawn = drawn_files(root)
    by_lower = {f.lower(): f for f in drawn}
    zones = {}
    for r in rows:
        # ID, carte, zones x4, point x2, texture, largeur, hauteur, décalage x, y, rectangle x4
        name, w, h, x, y = text_o(r[8]), r[9], r[10], r[11], r[12]
        area = file_of.get(r[1])
        if not name or not area:
            continue
        f = by_lower.get(area.lower())
        if not f:
            continue          # carte que Strata ne dessine pas (continent, donjon, champ de bataille)
        zones.setdefault(f, {})[name.lower()] = (name, w, h, x, y)

    lines = [
        "-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires",
        "-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.",
        "",
        "-- Tous les morceaux des cartes de zone, découverts ou non (WorldMapOverlay.dbc du client 3.3.5,",
        "-- %s), pour révéler la carte quand le brouillard est éteint." % src_over,
        "-- Généré par tools/extract_overlays.py : régénérer plutôt que modifier à la main.",
        "-- [fichier de carte] = { { texture, largeur, hauteur, x, y }, ... }  (px de la carte, 1002 x 668)",
        "",
        "local _, ns = ...",
        "",
        "ns.Overlays = {",
    ]
    total = 0
    for f in sorted(zones):
        lines.append("\t%s = {" % f)
        for name, w, h, x, y in sorted(zones[f].values(), key=lambda o: (o[4], o[3], o[0])):
            lines.append('\t\t{ "%s", %d, %d, %d, %d },' % (name, w, h, x, y))
            total += 1
        lines.append("\t},")
    lines.append("}")
    (root / "Data/Overlays.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("%d morceaux pour %d zones (%s, %s)" % (total, len(zones), src_area, src_over))


if __name__ == "__main__":
    main()
