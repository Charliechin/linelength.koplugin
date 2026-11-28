package.path = "./?.lua;" .. package.path
local Sample = require("linelength/sample")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

local function expectList(name, got, want)
    if type(got) ~= "table" then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want a list", name, tostring(got)))
        return
    end
    if #got ~= #want then
        failures = failures + 1
        print(string.format("FAIL %s: got %d pages (%s), want %d (%s)", name, #got,
            table.concat(got, ","), #want, table.concat(want, ",")))
        return
    end
    for i = 1, #want do
        if got[i] ~= want[i] then
            failures = failures + 1
            print(string.format("FAIL %s: page %d is %s, want %s", name, i, tostring(got[i]), tostring(want[i])))
            return
        end
    end
end

expectList("100 pages, defaults: six from the middle", Sample.pages(100), { 48, 49, 50, 51, 52, 53 })
expectList("101 pages, defaults", Sample.pages(101), { 48, 49, 50, 51, 52, 53 })
expectList("18 pages, defaults: the six middle pages", Sample.pages(18), { 7, 8, 9, 10, 11, 12 })
expectList("17 pages, defaults", Sample.pages(17), { 6, 7, 8, 9, 10, 11 })
expectList("1 page", Sample.pages(1), { 1 })
expectList("3 pages", Sample.pages(3), { 1, 2, 3 })
expectList("9 pages: the middle is clamped to the book", Sample.pages(9), { 2, 3, 4, 5, 6, 7 })
expectList("0 pages", Sample.pages(0), {})
expectList("negative pages", Sample.pages(-3), {})
expectList("nil pages", Sample.pages(nil), {})
expectList("text pages", Sample.pages("abc"), {})
expectList("fractional pages", Sample.pages(10.7), { 3, 4, 5, 6, 7, 8 })
expectList("custom 2/2/2", Sample.pages(50, 2, 2, 2), { 1, 2, 25, 26, 49, 50 })
expectList("middle off", Sample.pages(50, 6, 0, 6), { 1, 2, 3, 4, 5, 6, 45, 46, 47, 48, 49, 50 })
expectList("start off", Sample.pages(50, 0, 4, 6), { 24, 25, 26, 27, 45, 46, 47, 48, 49, 50 })
expectList("end off", Sample.pages(50, 6, 4, 0), { 1, 2, 3, 4, 5, 6, 24, 25, 26, 27 })
expectList("all off", Sample.pages(50, 0, 0, 0), {})
expectList("negative count = off", Sample.pages(50, -1, -1, -1), {})
expectList("nil counts use defaults", Sample.pages(50, nil, nil, nil), { 23, 24, 25, 26, 27, 28 })
expectList("text counts use defaults", Sample.pages(50, "x", "y", "z"), { 23, 24, 25, 26, 27, 28 })
expectList("fractional counts floor", Sample.pages(50, 2.9, 2.9, 2.9), { 1, 2, 25, 26, 49, 50 })
expectList("counts beyond the book clamp", Sample.pages(5, 100, 100, 100), { 1, 2, 3, 4, 5 })
expectList("10 pages, counts 8/2/1: every page once", Sample.pages(10, 8, 2, 1), { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
expectList("10 pages, counts 4/4/4: every page once", Sample.pages(10, 4, 4, 4), { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
expectList("6 pages, counts 3/3/3: every page once", Sample.pages(6, 3, 3, 3), { 1, 2, 3, 4, 5, 6 })
expectList("count of 1", Sample.pages(20, 1, 1, 1), { 1, 10, 20 })

local seen, repeated = {}, false
for _i, page in ipairs(Sample.pages(1000)) do
    if seen[page] then
        repeated = true
    end
    seen[page] = true
end
expect("1000 pages: no duplicates", repeated, false)
expect("1000 pages: 6 in sample", #Sample.pages(1000), 6)
expect("default first", Sample.DEFAULT_FIRST, 0)
expect("default middle", Sample.DEFAULT_MIDDLE, 6)
expect("default last", Sample.DEFAULT_LAST, 0)

expect("median odd", Sample.median({ 7, 1, 4 }), 4)
expect("median even", Sample.median({ 8, 1, 4, 2 }), 3)
expect("median single", Sample.median({ 55 }), 55)
expect("median already sorted", Sample.median({ 50, 55, 60, 65, 70 }), 60)
expect("median half stays", Sample.median({ 50, 61 }), 55.5)
expect("median of equal values", Sample.median({ 60, 60, 60 }), 60)
expect("median nil", Sample.median(nil), nil)
expect("median empty", Sample.median({}), nil)
expect("median no numbers", Sample.median({ "a", {} }), nil)
expect("median text mixed in", Sample.median({ 50, "x", 70 }), 60)
expect("median numeric strings", Sample.median({ "50", "70" }), 60)
expect("median not a table", Sample.median(42), nil)

local min, max = Sample.range({ 60, 50, 70 })
expect("range min", min, 50)
expect("range max", max, 70)
expect("range single", Sample.range({ 55 }), 55)
min, max = Sample.range({ "x", 61, "y", 59 })
expect("range skips text min", min, 59)
expect("range skips text max", max, 61)
min, max = Sample.range({})
expect("range empty min", min, nil)
expect("range empty max", max, nil)
min, max = Sample.range(nil)
expect("range nil min", min, nil)
expect("range nil max", max, nil)

-- A cross-module check: the auto-tune loop aims at a median the rating calls Excellent.
local Rating = require("linelength/rating")
local pages = {}
for page = 1, 18 do
    pages[page] = 50 + (page % 17)
end
expect("sample median rates Excellent", Rating.forChars(Sample.median(pages)).id, "excellent")

if failures > 0 then
    error(failures .. " sample test(s) failed")
end
print("sample: all tests passed")
