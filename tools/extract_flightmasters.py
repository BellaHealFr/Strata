# Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
# (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

"""Extrait les maîtres de vol de la base de PNJ de Questie-335 et génère Data/FlightMasters.lua.

Usage : python tools/extract_flightmasters.py <dossier Questie-335>

Questie (GPL-3.0) donne pour chaque PNJ ses positions par zone (numéro AreaTable, coordonnées
en % de la carte de la zone), sa faction et ses fonctions (drapeau FLIGHT_MASTER = 8192). Les
numéros de zone sont convertis en noms de fichiers de carte (ceux de Data/Zones.lua) grâce au
nom anglais que Questie met en commentaire dans zoneTables.lua : chaque correspondance est
vérifiée, une erreur arrête l'outil au lieu de placer un PNJ au mauvais endroit.

Besoin de lupa (Lua 5.1) : python -m pip install lupa
"""
import re
import sys
from pathlib import Path

import lupa.lua51 as lua51

FLIGHT_MASTER = 8192

# Nom anglais de la zone (commentaires de zoneTables.lua) -> fichier de carte (Data/Zones.lua).
FILES = {
    # Kalimdor
    "Ashenvale": "Ashenvale", "Azshara": "Aszhara", "Azuremyst Isle": "AzuremystIsle",
    "The Barrens": "Barrens", "Bloodmyst Isle": "BloodmystIsle", "Darkshore": "Darkshore",
    "Darnassus": "Darnassis", "Desolace": "Desolace", "Durotar": "Durotar",
    "Dustwallow Marsh": "Dustwallow", "Felwood": "Felwood", "Feralas": "Feralas",
    "Moonglade": "Moonglade", "Mulgore": "Mulgore", "Orgrimmar": "Ogrimmar", "Silithus": "Silithus",
    "Stonetalon Mountains": "StonetalonMountains", "Tanaris": "Tanaris", "Teldrassil": "Teldrassil",
    "The Exodar": "TheExodar", "Thousand Needles": "ThousandNeedles", "Thunder Bluff": "ThunderBluff",
    "Un'Goro Crater": "UngoroCrater", "Winterspring": "Winterspring",
    # Royaumes de l'Est
    "Alterac Mountains": "Alterac", "Arathi Highlands": "Arathi", "Badlands": "Badlands",
    "Blasted Lands": "BlastedLands", "Burning Steppes": "BurningSteppes", "Deadwind Pass": "DeadwindPass",
    "Dun Morogh": "DunMorogh", "Duskwood": "Duskwood", "Eastern Plaguelands": "EasternPlaguelands",
    "Elwynn Forest": "Elwynn", "Eversong Woods": "EversongWoods", "Ghostlands": "Ghostlands",
    "Hillsbrad Foothills": "Hilsbrad", "The Hinterlands": "Hinterlands", "Ironforge": "Ironforge",
    "Loch Modan": "LochModan", "Redridge Mountains": "Redridge", "Searing Gorge": "SearingGorge",
    "Silvermoon City": "SilvermoonCity", "Silverpine Forest": "Silverpine", "Stormwind City": "Stormwind",
    "Stranglethorn Vale": "Stranglethorn", "Isle of Quel'Danas": "Sunwell", "Swamp of Sorrows": "SwampOfSorrows",
    "Tirisfal Glades": "Tirisfal", "Undercity": "Undercity", "Western Plaguelands": "WesternPlaguelands",
    "Westfall": "Westfall", "Wetlands": "Wetlands",
    # Outreterre
    "Blade's Edge Mountains": "BladesEdgeMountains", "Hellfire Peninsula": "Hellfire", "Nagrand": "Nagrand",
    "Netherstorm": "Netherstorm", "Shadowmoon Valley": "ShadowmoonValley", "Shattrath City": "ShattrathCity",
    "Terokkar Forest": "TerokkarForest", "Zangarmarsh": "Zangarmarsh",
    # Norfendre
    "Borean Tundra": "BoreanTundra", "Crystalsong Forest": "CrystalsongForest", "Dalaran - Dungeon?": "Dalaran",  # nom donné par Questie à la zone 4395
    "Dragonblight": "Dragonblight", "Grizzly Hills": "GrizzlyHills", "Howling Fjord": "HowlingFjord",
    "Hrothgar's Landing": "HrothgarsLanding", "Icecrown": "IcecrownGlacier", "Wintergrasp": "LakeWintergrasp",
    "Sholazar Basin": "SholazarBasin", "The Storm Peaks": "TheStormPeaks", "Zul'Drak": "ZulDrak",
}


def zone_ids(questie):
    """Numéro AreaTable -> fichier de carte, d'après les commentaires de areaIdToUiMapId."""
    src = (questie / "Database/Zones/zoneTables.lua").read_text(encoding="utf-8")
    block = src[src.index("areaIdToUiMapId = {"):]
    block = block[:block.index("\n}")]
    # Un même nom peut porter plusieurs numéros (Orgrimmar : 1637 et 6020) : on les garde tous.
    names = {}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\d+,\s*--\s*(.+?)\s*$", block, re.M):
        names.setdefault(m.group(2), []).append(int(m.group(1)))
    missing = [name for name in FILES if name not in names]
    if missing:
        sys.exit(f"zones introuvables dans Questie : {', '.join(missing)}")
    return {zone: f for name, f in FILES.items() for zone in names[name]}


def drawn_files(root):
    """Les fichiers de carte dessinés par Strata (sans les micro-cartes), pour contrôle."""
    src = (root / "Data/Zones.lua").read_text(encoding="utf-8")
    return {m.group(1) for m in re.finditer(r"^\t\t(\w+) = \{[^}\n]*\}", src, re.M)
            if not m.group(0).rstrip().endswith("true }")}


def lua_table(lua, path, start, end):
    src = path.read_text(encoding="utf-8")
    i = src.index(start) + len(start)
    return lua.execute(src[i:src.index(end, i)])


def main():
    questie = Path(sys.argv[1])
    root = Path(__file__).resolve().parent.parent
    ids = zone_ids(questie)
    unknown = set(ids.values()) - drawn_files(root)
    if unknown:
        sys.exit(f"fichiers de carte inconnus de Data/Zones.lua : {', '.join(sorted(unknown))}")

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    npcs = lua_table(lua, questie / "Database/Wotlk/wotlkNpcDB.lua", "QuestieDB.npcData = [[", "]]")
    fr = lua.execute((questie / "Localization/lookups/Wotlk/lookupNpcs/frFR.lua").read_text(encoding="utf-8")
                     .replace('if GetLocale() ~= "frFR" then\n    return\nend', "")
                     .replace('local l10n = QuestieLoader:ImportModule("l10n")', "local l10n = { npcNameLookup = {} }")
                     + "\nreturn l10n.npcNameLookup.frFR")

    out = []
    for npc_id, npc in npcs.items():
        flags = npc[15] or 0
        if not (int(flags) & FLIGHT_MASTER) or not npc[13]:
            continue
        spawns = npc[7]
        if not spawns:
            continue
        for zone, coords in spawns.items():
            f = ids.get(int(zone))
            if not f or not coords[1]:
                continue
            x, y = coords[1][1], coords[1][2]
            if x < 0 or y < 0:
                continue
            name_fr = fr[npc_id][1] if fr[npc_id] else None
            out.append((int(npc_id), f, round(x / 100, 4), round(y / 100, 4), npc[13], npc[1], name_fr))
            break
    out.sort(key=lambda r: (r[1], r[0]))

    # Doublons de Questie (Doras 3310 et 31426 à Orgrimmar) : même nom, même zone, à moins de
    # 1 % de la carte l'un de l'autre. On garde le premier, avec les factions communes aux deux
    # (Doras 3310 « H » et sa copie « AH » : Horde seulement, l'Alliance ne vole pas d'Orgrimmar).
    kept = []
    for r in out:
        twin = next((k for k in kept if k[1] == r[1] and k[5] == r[5]
                     and abs(k[2] - r[2]) < 0.01 and abs(k[3] - r[3]) < 0.01), None)
        if twin:
            merged = "".join(sorted(set(twin[4]) & set(r[4]))) or twin[4]
            kept[kept.index(twin)] = twin[:4] + (merged,) + twin[5:]
        else:
            kept.append(r)
    out = kept

    def q(s):
        return "nil" if s is None else '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = [
        "-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires",
        "-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.",
        "",
        "-- Maîtres de vol : position dans leur zone (0-1), faction (\"A\", \"H\" ou \"AH\"), noms anglais et français.",
        "-- Tirés de la base de PNJ de Questie-335 (GPL-3.0) par tools/extract_flightmasters.py ;",
        "-- régénérer plutôt que modifier à la main.",
        "-- { identifiant du PNJ, fichier de carte, x, y, faction, nom anglais, nom français }",
        "",
        "local _, ns = ...",
        "",
        "ns.FlightMasters = {",
    ]
    for npc_id, f, x, y, faction, en, frn in out:
        lines.append(f'\t{{ {npc_id}, "{f}", {x}, {y}, "{faction}", {q(en)}, {q(frn)} }},')
    lines.append("}")
    (root / "Data/FlightMasters.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    by = {}
    for r in out:
        by[r[4]] = by.get(r[4], 0) + 1
    print(f"{len(out)} maîtres de vol : {by}")


if __name__ == "__main__":
    main()
