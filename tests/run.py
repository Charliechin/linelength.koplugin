#!/usr/bin/env python3
"""Runs tests/test_*.lua under lupa (Lua 5.5): there is no lua binary here.
Also cross-checks the character count against Python's own len() on random Unicode."""
import os, random, sys
from lupa import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
os.chdir(root)
status = 0

for name in ("test_counter.lua", "test_rating.lua", "test_report.lua", "test_pagelines.lua", "test_layout.lua", "test_sample.lua", "test_main.lua"):
    lua = LuaRuntime()
    try:
        lua.execute(open(os.path.join(here, name)).read())
    except Exception as e:
        print(name, e)
        status = 1

# Oracle: for text without invisible characters, chars must equal len(str) and
# chars_no_spaces must equal the number of non-whitespace code points.
lua = LuaRuntime(encoding=None)
lua.execute('package.path = "./?.lua;" .. package.path')
count = lua.eval('require("linelength/counter").count')
INVISIBLE = set([0xAD, 0xFEFF]) | set(range(0x200B, 0x2010)) | set(range(0x202A, 0x202F)) | set(range(0x2060, 0x2065))
SPACE = set([9, 10, 11, 12, 13, 32, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]) | set(range(0x2000, 0x200B))
random.seed(7)
pools = [range(0x20, 0x7F), range(0xA1, 0x24F), range(0x370, 0x3FF), range(0x4E00, 0x4E80), range(0x1F600, 0x1F640),
         [9, 10, 32, 0xA0, 0x2003, 0x3000, 0xAD, 0x200B, 0xFEFF]]
bad = 0
for _ in range(3000):
    cps = []
    for _j in range(random.randint(0, 40)):
        pool = random.choice(pools)
        cps.append(random.choice(list(pool)))
    text = "".join(chr(c) for c in cps)
    r = count(text.encode("utf-8"))
    visible = [c for c in cps if c not in INVISIBLE]
    want_chars = len(visible)
    want_nospace = len([c for c in visible if c not in SPACE])
    if r[b"chars"] != want_chars or r[b"chars_no_spaces"] != want_nospace:
        bad += 1
        if bad <= 3:
            print("MISMATCH", repr(text), dict(r), want_chars, want_nospace)
if bad:
    print(bad, "random cross-check mismatches")
    status = 1
else:
    print("cross-check: 3000 random Unicode strings agree with Python's len()")
sys.exit(status)
