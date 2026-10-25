# Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
# (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

"""Banc de simulation de Strata : fait tourner le vrai code de l'addon dans Lua 5.1 avec un
faux client 3.3.5, et joue les scénarios (fonctions, puis performances contre les budgets).

Utilisation, depuis la racine du dépôt :
    pip install lupa
    python tests/run.py frFR            # tous les scénarios
    python tests/run.py enUS perf.lua   # un scénario

Chaque scénario part d'un client neuf. Code de sortie 1 si une vérification échoue, si un
budget est dépassé ou si une erreur Lua survient.
"""
import os
import sys
from pathlib import Path

import lupa.lua51 as lua51

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent
SCENARIOS = ["scenario.lua", "perf.lua"]

# Variables globales que l'addon a le droit de créer ; toute autre est une fuite.
GLOBALS = ["Strata", "StrataDB", "StrataFrame", "Strata_Toggle", "SLASH_STRATA1", "SLASH_STRATA2",
           "BINDING_HEADER_STRATA", "BINDING_NAME_STRATA_TOGGLE"]

SETUP = """
    TEST.events = {}
    local Create = CreateFrame
    CreateFrame = function(...)
        local f = Create(...)
        f.RegisterEvent = function(self, e) TEST.events[e] = TEST.events[e] or {}; table.insert(TEST.events[e], self) end
        return f
    end
    function TEST.Fire(e, ...)
        for _, f in ipairs(TEST.events[e] or {}) do f.scripts.OnEvent(f, e, ...) end
    end
    -- Un ScrollFrame ancré par ses coins : donner la taille que le client calculerait.
    local Region = getmetatable(UIParent)
    local GetWidth, GetHeight = Region.GetWidth, Region.GetHeight
    Region.GetWidth = function(self) if self.kind == "ScrollFrame" and self.w == 0 then return 976 end return GetWidth(self) end
    Region.GetHeight = function(self) if self.kind == "ScrollFrame" and self.h == 0 then return 634 end return GetHeight(self) end
"""


def toc_files():
    for line in (ADDON / "Strata.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line.replace("\\", "/")


def read(path):
    return path.read_text(encoding="utf-8")


def run(locale, scenario):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(read(HERE / "stubs.lua"))
    lua.execute(f'TEST.locale = "{locale}"')
    lua.execute(SETUP)
    lua.execute(read(HERE / "helpers.lua"))
    lua.execute(read(HERE / "budgets.lua"))
    lua.execute("TEST.globals = {} for k in pairs(_G) do TEST.globals[k] = true end")

    load = lua.eval("function(src, name) local f, err = loadstring(src, '@' .. name) if not f then error(err, 0) end return f end")
    ns = lua.eval("{}")
    for rel in toc_files():
        load(read(ADDON / rel), rel)("Strata", ns)
    lua.execute("TEST.SetupMaps(Strata.Zones)")

    print(f"\n=== {scenario} ({locale})")
    lua.execute(read(HERE / scenario))

    allowed = lua.table_from({name: True for name in GLOBALS})
    leaks = lua.eval("""function(allowed)
        local leaks = {}
        for k in pairs(_G) do
            if not TEST.globals[k] and not allowed[k] then leaks[#leaks + 1] = tostring(k) end
        end
        table.sort(leaks)
        return table.concat(leaks, ", ")
    end""")(allowed)
    if leaks:
        raise SystemExit(f"ÉCHEC : variables globales créées par l'addon : {leaks}")
    print("ok   aucune variable globale en trop")

    return [dict(r) for r in lua.globals().TEST.report.values()]


def summary(locale, report):
    """Tableau des mesures dans le résumé de la vérification GitHub."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path or not report:
        return
    lines = [f"### Performances ({locale})", "", "| Mesure | Valeur | Budget | |", "|---|---:|---:|:-:|"]
    for r in report:
        lines.append(f"| {r['name']} | {r['value']:.1f} | {r['limit']} | {'✅' if r['ok'] else '❌'} |")
    with open(path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n\n")


def main():
    locale = sys.argv[1] if len(sys.argv) > 1 else "frFR"
    scenarios = sys.argv[2:] or SCENARIOS
    report = []
    for scenario in scenarios:
        report += run(locale, scenario)
    summary(locale, report)
    print(f"\nbanc réussi ({locale})")


if __name__ == "__main__":
    main()
