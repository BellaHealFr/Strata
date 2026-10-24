# Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
# (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

"""Charge Strata dans un client 3.3.5 simulé (Lua 5.1, comme le client) et joue
scenario.lua. Usage, depuis la racine du dépôt : python tests/run.py [frFR|enUS]

Besoin de lupa : python -m pip install lupa
"""
import sys
from pathlib import Path

import lupa.lua51 as lua51

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent


def toc_files():
    for line in (ADDON / "Strata.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line.replace("\\", "/")


def main():
    locale = sys.argv[1] if len(sys.argv) > 1 else "frFR"
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / "stubs.lua").read_text(encoding="utf-8"))
    lua.execute(f'TEST.locale = "{locale}"')
    lua.execute("""
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
    """)
    ns = lua.eval("{}")
    for rel in toc_files():
        src = (ADDON / rel).read_text(encoding="utf-8")
        chunk = lua.eval("function(src, name) local f, err = loadstring(src, '@' .. name) if not f then error(err, 0) end return f end")(src, rel)
        chunk("Strata", ns)
        print(f"chargé {rel}")
    lua.execute("TEST.SetupMaps(Strata.Zones)")
    lua.execute((HERE / "scenario.lua").read_text(encoding="utf-8"))
    print(f"\nscénario réussi ({locale})")


if __name__ == "__main__":
    main()
