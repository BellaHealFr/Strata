# Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
# (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

"""Extrait la table WorldMapSize d'Astrolabe (3.3.5) et génère Data/Zones.lua.

Usage : python -I tools/extract_zones.py <Astrolabe.lua> [<Astrolabe.lua de référence>]

Avec une référence (Astrolabe d'un client 3.3.5 non patché), les zones absentes de la
référence sont marquées comme micro-cartes (sub) : on s'en sert pour placer le joueur,
on ne les dessine pas.

Astrolabe (LGPL 2.1, Esamynn) donne, en yards, la taille de chaque continent et zone et
son décalage (coin haut-gauche) dans le parent. Ce sont les valeurs de WorldMapArea.dbc.
"""
import re
import sys
from pathlib import Path

TOKEN = re.compile(r"""
    (?P<comment>--\[\[.*?\]\]|--[^\n]*)
  | (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<str>"[^"]*")
  | (?P<sym>[{}\[\]=,;])
  | (?P<ws>\s+)
""", re.S | re.X)


def tokens(src):
    for m in TOKEN.finditer(src):
        kind = m.lastgroup
        if kind in ("comment", "ws"):
            continue
        yield kind, m.group(kind)


def parse_table(toks):
    """Parse depuis juste après '{' ; renvoie un dict (clés positionnelles 1..n)."""
    out, pos = {}, 1
    while True:
        kind, val = next(toks)
        if val == "}":
            return out
        if val in (",", ";"):
            continue
        if val == "[":
            _, key = next(toks)
            key = int(key) if key.lstrip("-").isdigit() else key.strip('"')
            next(toks)  # ]
            next(toks)  # =
            out[key] = parse_value(toks, next(toks))
        elif kind == "name":
            k2, v2 = next(toks)
            if v2 == "=":
                out[val] = parse_value(toks, next(toks))
            else:
                raise ValueError(f"inattendu après {val}: {v2}")
        else:
            out[pos] = parse_value(toks, (kind, val))
            pos += 1


def parse_value(toks, tok):
    kind, val = tok
    if val == "{":
        return parse_table(toks)
    if kind == "num":
        return float(val)
    if kind == "str":
        return val.strip('"')
    return val


def load(path):
    src = Path(path).read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^\s*WorldMapSize\s*=\s*{", src, re.M)
    if not m:
        sys.exit(f"WorldMapSize introuvable dans {path}")
    toks = tokens(src[m.end():])
    return parse_table(toks)


def rect(d):
    return tuple(round(d.get(k, 0.0), 3) for k in ("width", "height", "xOffset", "yOffset"))


def compare(a, b):
    diffs = 0
    for c in sorted(set(a) | set(b)):
        za = a.get(c, {}).get("zoneData", {})
        zb = b.get(c, {}).get("zoneData", {})
        for z in sorted(set(za) | set(zb)):
            if z not in za or z not in zb:
                print(f"  continent {c}: {z} seulement dans {'A' if z in za else 'B'}")
                diffs += 1
            elif rect(za[z]) != rect(zb[z]):
                print(f"  continent {c}: {z} diffère {rect(za[z])} / {rect(zb[z])}")
                diffs += 1
    print(f"{diffs} différence(s)")


def fmt(v):
    return repr(round(v, 3))


def write_lua(data, out, ref=None):
    lines = [
        "-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires",
        "-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.",
        "",
        "-- Taille et position de chaque continent et zone, en yards (WorldMapArea.dbc, client 3.3.5a).",
        "-- Valeurs reprises de la table WorldMapSize d'Astrolabe (Esamynn, LGPL 2.1).",
        "-- Généré par tools/extract_zones.py ; régénérer plutôt que modifier à la main.",
        "-- [continent] = { w, h, x, y, zones = { [fichier de carte] = { w, h, x, y [, sub] } } }",
        "-- x, y : coin haut-gauche dans le parent (le monde pour un continent, le continent pour une zone).",
        "-- sub = true : micro-carte ajoutée par un patch de serveur (grotte, zone de départ, étage) ;",
        "-- sert à placer le joueur, pas dessinée.",
        "",
        "local _, ns = ...",
        "",
        "ns.Zones = {",
    ]
    for c in sorted(data):
        d = data[c]
        lines.append(f"\t[{c}] = {{ w = {fmt(d.get('width', 0))}, h = {fmt(d.get('height', 0))}, "
                     f"x = {fmt(d.get('xOffset', 0))}, y = {fmt(d.get('yOffset', 0))}, "
                     f"parent = {int(d.get('parentContinent', c))}, zones = {{")
        refzones = ref.get(c, {}).get("zoneData", {}) if ref else None
        for z in sorted(d.get("zoneData", {})):
            w, h, x, y = rect(d["zoneData"][z])
            sub = ", true" if refzones is not None and z not in refzones else ""
            lines.append(f"\t\t{z} = {{ {w}, {h}, {x}, {y}{sub} }},")
        lines.append("\t} },")
    lines.append("}")
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main():
    a = load(sys.argv[1])
    for c in sorted(a):
        print(f"continent {c}: {len(a[c].get('zoneData', {}))} zones")
    ref = None
    if len(sys.argv) > 2:
        ref = load(sys.argv[2])
        compare(a, ref)
    out = Path(__file__).resolve().parent.parent / "Data" / "Zones.lua"
    write_lua(a, out, ref)
    print(f"écrit {out}")


if __name__ == "__main__":
    main()
