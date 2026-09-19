"""Run the addon's pure-logic tests outside WoW, against a real Lua 5.1 runtime.

    python tools/runtests.py
"""

import os
import sys

from lupa import lua51 as luamod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    lua = luamod.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = [[%s/?.lua;]] .. package.path" % ROOT.replace("\\", "/"))
    lua.execute("lfs_cwd = [[%s]]" % ROOT.replace("\\", "/"))

    for name in ("test_pricing.lua", "test_postprice.lua", "test_buying.lua",
                 "test_transfer.lua", "test_throttle.lua",
                 "test_verify.lua", "test_lossfloor.lua",
                 "test_quantity.lua", "test_stock.lua",
                 "test_silverstep.lua", "test_unitprice.lua",
                 "test_layout.lua", "test_rarity.lua"):
        script = os.path.join(ROOT, "tools", name).replace("\\", "/")
        lua.execute("dofile([[%s]])" % script)

    return 0


if __name__ == "__main__":
    sys.exit(main())
