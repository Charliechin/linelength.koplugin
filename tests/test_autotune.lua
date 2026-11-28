package.path = "./?.lua;" .. package.path
local AutoTune = require("linelength/autotune")

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

local function expectNil(name, got)
    if got ~= nil then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want nil", name, tostring(got)))
    end
end

-- The screen of a Kobo Libra Colour, in KOReader's units: 1264 px at 2 px per unit.
local WIDTH = 632

expect("band min", AutoTune.BAND_MIN, 56)
expect("band max", AutoTune.BAND_MAX, 60)
expect("margin min", AutoTune.MARGIN_MIN, 10)
expect("margin max", AutoTune.MARGIN_MAX, 50)
expect("characters per step", AutoTune.MAX_CHARS_PER_STEP, 6)
expect("target", AutoTune.TARGET, 58)

expect("in band: 56", AutoTune.inBand(56), true)
expect("in band: 60", AutoTune.inBand(60), true)
expect("in band: 60", AutoTune.inBand(60), true)
expect("out of band: 55", AutoTune.inBand(55), false)
expect("out of band: 61", AutoTune.inBand(61), false)
expect("out of band: nothing", AutoTune.inBand(nil), false)
expect("out of band: text", AutoTune.inBand("x"), false)

-- The limits are the tune's own, and the only two a reader sets are the margins: a margin outside
-- the range the menu offers is brought back to its edge, because the settings file is a plain table a
-- reader can edit by hand.
local limits = AutoTune.limits()
expect("the band is the tune's own", limits.band_min, AutoTune.BAND_MIN)
expect("the band is the tune's own", limits.band_max, AutoTune.BAND_MAX)
expect("the target is the tune's own", limits.target, AutoTune.TARGET)
expect("the step is the tune's own", limits.max_chars_per_step, AutoTune.MAX_CHARS_PER_STEP)
expect("the steps are the tune's own", limits.max_steps, AutoTune.MAX_STEPS)
expect("the margins default to their bounds", limits.margin_min, AutoTune.MARGIN_MIN)
expect("the margins default to their bounds", limits.margin_max, AutoTune.MARGIN_MAX)

local set_margins = AutoTune.limits({ margin_min = 20, margin_max = 40 })
expect("the smallest margin is a setting", set_margins.margin_min, 20)
expect("the biggest margin is a setting", set_margins.margin_max, 40)

-- The reader can leave a pair the wrong way round in the settings file: the smallest margin cannot
-- be bigger than the biggest one, so the pair is put the right way round.
local swapped = AutoTune.limits({ margin_min = 140, margin_max = 0 })
expect("the margins are put the right way round", swapped.margin_min, 0)
expect("the margins are put the right way round", swapped.margin_max, 140)

-- The settings file is a plain table, so a reader can leave anything in it: a margin out of range is
-- brought back to the edge of its range, and one that is not a number falls back to the default.
local wild = AutoTune.limits({ margin_min = -3, margin_max = -1 })
expect("a negative margin comes back to nothing", wild.margin_min, AutoTune.MARGIN_FLOOR)
expect("a negative margin comes back to nothing", wild.margin_max, AutoTune.MARGIN_FLOOR)
expect("a wild setting still gives a margin inside the bounds",
    AutoTune.nextMargin(30, 70, WIDTH) >= AutoTune.MARGIN_FLOOR, true)

local text = AutoTune.limits({ margin_min = "x", margin_max = "y" })
expect("a setting that is not a number falls back", text.margin_min, AutoTune.MARGIN_MIN)
expect("a setting that is not a number falls back", text.margin_max, AutoTune.MARGIN_MAX)

-- The step aims at the target of the band it is given: with a band of 65 to 70 and a target of 68,
-- the same lines are made longer towards 68 and the margins come in, where the default band of 56 to
-- 60 sends them the other way, towards 58.
local narrow_band = { band_min = 65, band_max = 70, target = 68 }
local aimed_band = AutoTune.nextMargin(30, 72, WIDTH, narrow_band)
expect("the step aims at the band it is given", aimed_band > 30, true)
expect("the step aims at the band it is given, not at the default one",
    aimed_band < AutoTune.nextMargin(30, 72, WIDTH), true)

local wider = AutoTune.nextMargin(10, 80, WIDTH)
expect("too long: the margins widen", wider > 10, true)
expect("too long: by at least a step", wider >= 12, true)

local narrower = AutoTune.nextMargin(40, 40, WIDTH)
expect("too short: the margins come in", narrower < 40, true)
expect("too short: by at least a step", narrower <= 38, true)

expectNil("margins at their limit: nothing to try", AutoTune.nextMargin(50, 100, WIDTH))
expectNil("margins at their minimum: nothing to try", AutoTune.nextMargin(10, 30, WIDTH))

-- A wide margin and very long lines: the bound is what stops the margins.
local capped = AutoTune.nextMargin(40, 120, WIDTH, { margin_max = 50 })
expect("the bound stops the margins", capped, 50)
local uncapped = AutoTune.nextMargin(40, 120, WIDTH, { margin_max = 140 })
expect("a wider bound lets the margins go further", uncapped > capped, true)
-- The step is bounded in characters: a small step moves the margins a little at a time, a big one
-- moves them further in the same go.
local small_step = AutoTune.nextMargin(40, 54, WIDTH, { max_chars_per_step = 2, target = 58 })
local big_step = AutoTune.nextMargin(40, 54, WIDTH, { max_chars_per_step = 20, target = 58 })
expect("a bigger step moves further", big_step < small_step, true)
expect("a small step moves a little", small_step > 20, true)

-- The lines are far too long for the band: the step is capped, so the margins move towards the band
-- a step at a time, they end at their bound, and there is nothing more to try.
local wanted = AutoTune.nextMargin(20, 80, WIDTH)
expect("the step moves towards the band", wanted > 20, true)
expect("the step stays inside the bounds", wanted <= AutoTune.MARGIN_MAX, true)
local bound, bound_steps = 20, 0
while bound_steps < 20 do
    local next_margin = AutoTune.nextMargin(bound, 80, WIDTH)
    if not next_margin then break end
    bound = next_margin
    bound_steps = bound_steps + 1
end
expect("the margins go to their bound", bound, AutoTune.MARGIN_MAX)
expectNil("and then there is nothing more to try", AutoTune.nextMargin(bound, 80, WIDTH))

expectNil("no margin", AutoTune.nextMargin(nil, 60, WIDTH))
expectNil("no measurement", AutoTune.nextMargin(10, 0, WIDTH))
expectNil("no measurement, as text", AutoTune.nextMargin(10, "x", WIDTH))
expectNil("no width", AutoTune.nextMargin(10, 60, nil))

expect("start: a margin below the bound comes up", AutoTune.startMargin(5), 10)
expect("start: a margin above the bound comes down", AutoTune.startMargin(90), 50)
expect("start: a margin inside the bounds stays", AutoTune.startMargin(25), 25)
expect("start: a margin is rounded", AutoTune.startMargin(25.6), 26)
expect("start: no margin at all", AutoTune.startMargin(nil), 10)

-- A margin outside the bounds comes back inside them first.
expect("a margin below the bound comes back in", AutoTune.nextMargin(0, 70, WIDTH), 10)
expect("a margin above the bound comes back in", AutoTune.nextMargin(90, 40, WIDTH), 50)

-- The loop the way the plugin runs it: the margins move by steps, each one measured, until the line
-- length is in the band. The screen is 632 units wide.
-- The characters a line holds, from the real relation measured on a book: a line of 59 characters
-- in a block of 612 units. The block is the screen minus the margins.
local function chars_in(block)
    return math.floor(block * 59 / 612 + 0.5)
end

local function simulate(start_margin, measured, chars_at_margin)
    chars_at_margin = chars_at_margin or chars_in
    local margin = AutoTune.startMargin(start_margin)
    local steps, inside = 0, true
    while not AutoTune.inBand(measured) and steps < 20 do
        local next_margin = AutoTune.nextMargin(margin, measured, WIDTH)
        if not next_margin then break end
        margin = next_margin
        steps = steps + 1
        measured = chars_at_margin(WIDTH - 2 * margin)
        inside = inside and margin >= AutoTune.MARGIN_MIN and margin <= AutoTune.MARGIN_MAX
    end
    return margin, measured, steps, inside
end

-- The step aims at the target: the same book, a different target, a different margin.
local aimed = AutoTune.nextMargin(40, 53, WIDTH, { target = 55 })
expect("the step aims at the target", aimed < 40, true)
local aimed60 = AutoTune.nextMargin(40, 53, WIDTH, { target = 60 })
expect("a higher target means wider margins", aimed60 < aimed, true)

-- A target outside the band does not make the loop wander: the step aims at the edge of the band.
-- The lines are too long, so the margins widen; a target of 90 would ask for even longer lines, so
-- the step stops at the edge of the band instead.
expect("a target above the band aims at the edge", AutoTune.nextMargin(30, 70, WIDTH, { target = 90 }), 50)
-- The lines are too short, so the margins come in; a target of 20 would ask for even shorter lines.
expect("a target below the band aims at the edge", AutoTune.nextMargin(40, 45, WIDTH, { target = 20 }), 10)

-- Already at the target: there is nothing to try.
expectNil("already at the target: nothing to try", AutoTune.nextMargin(20, 58, WIDTH, { target = 58 }))

-- The margins come in when the lines are too short, and widen when they are too long.
expect("too short: the margins come in", AutoTune.nextMargin(40, 45, WIDTH, { target = 55 }), 10)
expect("too long: the margins widen", AutoTune.nextMargin(20, 70, WIDTH, { target = 55 }), 45)

local margin, chars, steps, inside = simulate(10, 80)
expect("the loop ends in the band", AutoTune.inBand(chars), true)
expect("the loop ends in a few steps", steps <= 3, true)
expect("the loop widened the margins", margin > 10, true)
expect("every step stayed inside the bounds", inside, true)

local margin2, chars2, steps2, inside2 = simulate(60, 40)
expect("the loop ends in the band from the other side", AutoTune.inBand(chars2), true)
expect("the loop brought the margins in", margin2 < 60, true)
expect("the loop ends in a few steps there too", steps2 <= 3, true)
expect("every step stayed inside the bounds there either", inside2, true)

-- A book whose lines cannot reach the band at any margin: the loop makes progress, stops at the
-- bound of the margins, and the lines stay outside the band.
-- The first count comes from the same relation the later counts come from, so that the loop really
-- walks through the margins instead of starting on a count no margin could have given.
local function long_chars_in(block)
    return math.floor(block * 70 / 612 + 0.5)
end
local start = 35
local margin3, chars3, steps3, inside3 = simulate(start, long_chars_in(WIDTH - 2 * start), long_chars_in)
expect("an unreachable band still moves the margins", steps3 > 0, true)
expect("an unreachable band stops at the bound", margin3, AutoTune.MARGIN_MAX)
expect("an unreachable band leaves the lines outside it", AutoTune.inBand(chars3), false)
expect("an unreachable band keeps every move inside the bounds", inside3, true)

if failures > 0 then
    error(failures .. " autotune test(s) failed")
end
print("autotune: all tests passed")
