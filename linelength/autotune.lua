-- The auto-tune: how wide the margins have to be for a line to hold the right number of characters.
-- Pure Lua: no KOReader requires, so it is tested on a desktop Lua.
--
-- The size of the text is the reader's own: it is what they read at, and it is not ours to change.
-- The margins are the white space around the text, and they are what the line length is really made
-- of: a wider margin means a narrower block of text, so shorter lines. The auto-tune therefore only
-- moves the margins, and only between the bounds the reader set: the text size is left alone.
--
-- How many characters fit on a line does not depend on the size of the screen: KOReader scales the
-- text size and the margins with the screen, so the same numbers mean the same reading comfort on a
-- small screen as on a large one.
local AutoTune = {}

-- The margins the tune may use, and the range they are held to: the settings file is a plain Lua
-- table a reader can edit by hand, so a margin outside this range is brought back to its edge
-- rather than obeyed.
AutoTune.MARGIN_MIN = 10
AutoTune.MARGIN_MAX = 50
AutoTune.MARGIN_FLOOR = 0
AutoTune.MARGIN_CEILING = 200

-- How many characters the line length may change in one step.
AutoTune.MAX_CHARS_PER_STEP = 6

-- Where the line length should land: a band of good lengths, and the one to aim at inside it.
AutoTune.BAND_MIN = 56
AutoTune.BAND_MAX = 60
AutoTune.TARGET = 58

-- How many re-renders the tune may take.
AutoTune.MAX_STEPS = 6

-- A number from the settings, kept inside the range the menu offers: the settings file is a plain
-- Lua table a reader can edit, so a value outside the range is not a reason to stop.
local function within(value, default, min, max)
    local n = tonumber(value)
    if not n then
        return default
    end
    return math.max(min, math.min(max, n))
end

-- The limits with the defaults filled in for whatever was left out.
local function resolved(limits)
    limits = limits or {}
    return {
        band_min = limits.band_min or AutoTune.BAND_MIN,
        band_max = limits.band_max or AutoTune.BAND_MAX,
        target = tonumber(limits.target) or AutoTune.TARGET,
        margin_min = limits.margin_min or AutoTune.MARGIN_MIN,
        margin_max = limits.margin_max or AutoTune.MARGIN_MAX,
        max_chars_per_step = limits.max_chars_per_step or AutoTune.MAX_CHARS_PER_STEP,
        max_steps = limits.max_steps or AutoTune.MAX_STEPS,
    }
end

--- The limits of the tune: its own band, target and step, and the two margins the reader chose, held
--- to the range the menu offers so that the loop always has something to aim for.
--- @param settings table|nil the two margins the reader chose, as LineLength:settings returns them
--- @return table { band_min, band_max, target, margin_min, margin_max, max_chars_per_step, max_steps }
function AutoTune.limits(settings)
    settings = settings or {}
    local limits = resolved({
        margin_min = within(settings.margin_min, nil, AutoTune.MARGIN_FLOOR, AutoTune.MARGIN_CEILING),
        margin_max = within(settings.margin_max, nil, AutoTune.MARGIN_FLOOR, AutoTune.MARGIN_CEILING),
    })
    if limits.margin_min > limits.margin_max then
        limits.margin_min, limits.margin_max = limits.margin_max, limits.margin_min
    end
    limits.target = math.max(limits.band_min, math.min(limits.band_max, limits.target))
    return limits
end

--- Whether a line length is good enough: inside the band.
--- @param chars number the length of the longest line, in characters
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
--- @return boolean
function AutoTune.inBand(chars, limits)
    chars = tonumber(chars)
    if not chars then
        return false
    end
    limits = resolved(limits)
    return chars >= limits.band_min and chars <= limits.band_max
end

--- The margins to try next.
--- The step aims at the target the reader asked for, the length of line they want to read at. It never
--- moves the line length by more than a few characters at a time: a step that jumped over the band
--- would land outside it again and cost another measurement. The target is kept inside the band,
--- because the band is what the loop stops on: a target outside it would send the loop past the band.
--- @param margin number the margin now, on both sides
--- @param chars number the length of the longest line measured now
--- @param screen_width number the width of the screen in KOReader's units
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
--- @return number|nil the next margin; nil when nothing more can be tried
function AutoTune.nextMargin(margin, chars, screen_width, limits)
    margin = tonumber(margin)
    chars = tonumber(chars)
    local width = tonumber(screen_width)
    if not margin or not chars or not width or chars <= 0 then
        return nil
    end
    limits = resolved(limits)
    local max_chars = limits.max_chars_per_step

    -- The text block is what the lines are laid out in: how many characters fit on a line is the width
    -- of the block divided by the width of a character. So the length of the lines is proportional to
    -- the width of the block, and the block is the screen minus the margins.
    local text_width = math.max(width - 2 * margin, 1)

    -- The aim: the target the reader asked for, inside the band the reader asked for.
    local aim = math.min(math.max(limits.target, limits.band_min), limits.band_max)

    -- The step, in characters: the distance to the aim, capped at the step size the reader set.
    local step = math.max(-max_chars, math.min(max_chars, aim - chars))

    -- The margin that gives the text block the wanted number of characters.
    local next_margin = (width - text_width * (chars + step) / chars) / 2
    local new_margin = math.floor(next_margin + 0.5)

    -- A margin outside the bounds comes back inside them first: a step that stayed outside would
    -- measure the same thing again.
    if margin < limits.margin_min then
        new_margin = limits.margin_min
    elseif margin > limits.margin_max then
        new_margin = limits.margin_max
    else
        new_margin = math.max(limits.margin_min, math.min(limits.margin_max, new_margin))
    end
    if new_margin == margin then
        return nil
    end
    return new_margin
end

--- The margin the auto-tune starts from: the one the book is laid out with, pulled inside the bounds.
--- @param margin number the margin now
--- @param limits table|nil the limits, as AutoTune.limits returns them; nil uses the defaults
--- @return number
function AutoTune.startMargin(margin, limits)
    limits = resolved(limits)
    margin = tonumber(margin) or limits.margin_min
    margin = math.floor(margin + 0.5)
    return math.max(limits.margin_min, math.min(limits.margin_max, margin))
end

return AutoTune
