-- The part of reading lines that has to talk to KOReader: which page is drawn, in what buffer, and
-- where the reader is put back. What a line is made of stays in pagelines.lua and sample.lua.
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")

local PageLines = require("linelength/pagelines")
local Report = require("linelength/report")
local Sample = require("linelength/sample")

local Measure = {}

-- How many of the longest lines of a page are listed.
local TOP_LINES = 3

-- The report for the page on screen: nil and a reason when there is nothing to measure.
function Measure.page(ui, labels)
    local doc = ui and ui.document
    -- Only books that reflow (EPUB and the like) have lines of text to read; a PDF or a comic does not.
    if not (ui and ui.rolling and doc and doc.getTextFromPositions and doc.getScreenPositionFromXPointer
            and doc.getTextFromXPointers) then
        return nil, "unsupported"
    end
    local screen = Device.screen
    local lines = PageLines.collect(doc, screen:getWidth(), screen:getHeight(), util.cleanupSelectedText)
    local top = PageLines.longest(lines, TOP_LINES)
    if #top == 0 then
        return nil, "empty"
    end
    return Report.buildPage(top, labels)
end

-- Two reports say the same: the same longest line, and the same three lines in the same places.
function Measure.same(a, b)
    if a == nil or b == nil then
        return a == b
    end
    if a.chars ~= b.chars or #a.lines ~= #b.lines then
        return false
    end
    for i, line in ipairs(a.lines) do
        if line.number ~= b.lines[i].number or line.chars ~= b.lines[i].chars then
            return false
        end
    end
    return true
end

-- How many times the page is drawn and measured again, at most, to get a measurement that holds still.
local SETTLE_TRIES = 3

-- A way to let KOReader draw the page without anything reaching the screen. KOReader's reader view paints the page into
-- whatever buffer it is given, and that paint is also what renders a book that is only rendered when drawn and puts the
-- page back where it was. So it is given a buffer nobody sees: no refresh is asked of the e-ink panel (on a colour
-- Kobo each whole-screen refresh is a visible blink). Returns the function that draws and the one that gives the buffer
-- back. If there is no reader view or no buffer to be had, drawing falls back to a draw on the screen.
-- nil instead of a draw on the screen when `off_screen_only` is set and no off-screen buffer can be had.
function Measure.drawer(ui, off_screen_only)
    local view = ui and ui.view
    if view and view.paintTo then
        local screen = Device.screen
        local ok, buffer = pcall(function()
            return Blitbuffer.new(screen:getWidth(), screen:getHeight(), screen.bb and screen.bb:getType())
        end)
        if ok and buffer then
            local off_screen = true
            local given_up = false
            local function draw()
                if given_up then
                    return false
                end
                if off_screen then
                    local painted, err = pcall(view.paintTo, view, buffer, 0, 0)
                    if painted then
                        return true
                    end
                    logger.warn("linelength: could not draw the page off screen:", err)
                    if off_screen_only then
                        -- Drawing off screen failed: the sample stops there rather than painting every
                        -- page on the e-ink panel, which is what the reader would see.
                        given_up = true
                        off_screen = false
                        return false
                    end
                    off_screen = false
                end
                UIManager:forceRePaint()
                return true
            end
            local function release() buffer:free() end
            return draw, release
        end
        logger.warn("linelength: could not get a buffer to draw the page off screen, drawing it on the screen:", buffer)
    end
    if off_screen_only then
        return nil
    end
    return function() UIManager:forceRePaint() end, function() end
end

-- The report for the page on screen after the layout was changed (or when it may have changed).
-- KOReader renders only the chapter on screen when a setting changes ("partial rerendering": on by default for
-- EPUBs with several chapters, so a setting can be tried quickly) and does it when it next DRAWS the page. Until then
-- the lines are those of the old layout, and a measurement made right after the change is one change behind.
-- So when KOReader says the rendering is delayed, the page is drawn first, with KOReader's own paint (which does the
-- rendering and puts the page back where it was), into a buffer that is not on the screen, and measured again until two
-- measurements agree. When the book is fully rendered by the time the change returns, there is nothing to wait for and
-- nothing is drawn at all.
function Measure.settled(ui, labels)
    local report, reason = Measure.page(ui, labels)
    local ok, delayed = pcall(function() return ui.document:isRerenderingDelayed() end)
    if not (ok and delayed) then
        return report, reason
    end
    local draw, release = Measure.drawer(ui)
    local ok_loop, err = pcall(function()
        for _i = 1, SETTLE_TRIES do
            draw()
            local again, again_reason = Measure.page(ui, labels)
            local settled = Measure.same(report, again)
            report, reason = again, again_reason
            if settled then
                break
            end
        end
    end)
    release()
    if not ok_loop then
        error(err, 0)
    end
    return report, reason
end

-- The longest line of each page of a sample of the book, measured off screen.
-- The pages are reached with a page turn and drawn into a buffer nobody sees (see newDrawer), then the
-- reader is put back where it was. Nothing is refreshed: KOReader marks the view as not drawn when the
-- page changes and leaves the e-ink panel alone until the next UIManager cycle, so a whole sample is
-- walked through without a single blink.
-- Returns nil and a reason when the book cannot be sampled; otherwise a table with `pages` (page number
-- and characters of each page that could be read), `values` (those character counts), `median`, `min`,
-- `max` and `total` (the number of pages in the book).
function Measure.sample(ui, labels, counts)
    local ui = ui
    local doc = ui and ui.document
    if not (doc and doc.getPageCount and ui.handleEvent) then
        return nil, "unsupported"
    end
    -- Only a book that reflows has lines of text to measure; a PDF or a comic has pages, not lines,
    -- and walking them would be a scan of nothing.
    if not (doc.getTextFromPositions and doc.getScreenPositionFromXPointer) then
        return nil, "unsupported"
    end
    local ok, total = pcall(doc.getPageCount, doc)
    if not ok or type(total) ~= "number" or total < 1 then
        return nil, "empty"
    end
    local pages = Sample.pages(total, counts and counts.first, counts and counts.middle,
        counts and counts.last)
    if #pages == 0 then
        return nil, "empty"
    end

    -- Without a page to come back to, the walk would leave the reader on a sampled page.
    local ok, current = pcall(doc.getCurrentPage, doc)
    current = ok and tonumber(current) or nil
    if not current or current < 1 then
        return nil, "no_position"
    end
    -- Without an off-screen buffer the walk would paint every page on the e-ink panel: do nothing instead.
    local draw, release = Measure.drawer(ui, true)
    if not draw then
        return nil, "no_buffer"
    end
    -- A page turn through the reader, not straight on the document: the reader keeps the page it is on
    -- and the view its state in step, so the page can be drawn and the reader put back afterwards.
    -- The walk itself stays page-based: that is what makes skipping to an off-screen sample cheap.
    local function turnTo(page)
        ui:handleEvent(Event:new("GotoPage", page))
    end
    local function returnTo()
        ui:handleEvent(Event:new("GotoPage", current))
    end
    local measured, values = {}, {}
    -- A page that could not be drawn off screen: the sample is then incomplete, and an incomplete
    -- sample must not be handed to the caller as if it were a whole one.
    local paint_failed = false
    -- The measurement of a page that has been drawn: a page that is still being laid out would give
    -- the numbers of the previous layout, so it is drawn and measured again until it holds still.
    -- nil and "paint" when the page could not be drawn at all.
    local function measureDrawn()
        if draw() == false then
            return nil, "paint"
        end
        local report = Measure.page(ui, labels)
        for _try = 1, SETTLE_TRIES do
            local ok_settled, delayed = pcall(function() return doc:isRerenderingDelayed() end)
            if not (ok_settled and delayed) then
                break
            end
            if draw() == false then
                return nil, "paint"
            end
            local again = Measure.page(ui, labels)
            if not Measure.same(report, again) then
                report = again
            end
        end
        return report
    end
    local ok_loop, err = pcall(function()
        -- The page the reader is on is measured first, when it is one of the sampled pages: it does
        -- not have to be visited again. A page outside the sample is left out, or it would weigh on
        -- the median of the sample.
        local current_is_sampled = false
        for _i, page in ipairs(pages) do
            if page == current then
                current_is_sampled = true
                break
            end
        end
        if current and current_is_sampled then
            -- The page on screen is drawn and settled like every other one: a layout that was
            -- changed a moment ago is still being laid out, and the numbers of the old layout would
            -- go into the sample with the numbers of the new one.
            local report, reason = measureDrawn()
            if reason == "paint" then
                paint_failed = true
                return
            end
            if report then
                measured[#measured + 1] = { page = current, chars = report.chars }
                values[#values + 1] = report.chars
            end
        end
        for _i, page in ipairs(pages) do
            if page ~= current then
                turnTo(page)
                local report, reason = measureDrawn()
                if reason == "paint" then
                    paint_failed = true
                    return
                end
                if report then
                    measured[#measured + 1] = { page = page, chars = report.chars }
                    values[#values + 1] = report.chars
                end
            end
        end
    end)
    -- The way back is its own step: a page that could not be read still leaves the reader where it was.
    -- A failure to go back is a failure of the sample: the reader would be left on a sampled page.
    -- The two statuses are kept apart: the buffer is given back either way, but a reader left on a
    -- sampled page is a failure of the sample, not a success with a warning.
    local ok_back, back_err = pcall(returnTo)
    local ok_release, release_err = pcall(release)
    if not ok_loop then
        logger.warn("linelength: could not walk the pages of the sample:", err)
        return nil, "error"
    end
    if not ok_back then
        logger.warn("linelength: could not put the reader back where it was:", back_err)
        return nil, "error"
    end
    if not ok_release then
        logger.warn("linelength: could not release the off-screen buffer:", release_err)
    end
    if paint_failed then
        logger.warn("linelength: could not draw the pages of the sample off screen")
        return nil, "error"
    end
    if #values == 0 then
        return nil, "empty"
    end
    local min, max = Sample.range(values)
    -- An even number of pages gives a median that ends in .5; a line is a whole number of characters, and
    -- the rating floors, so the median is rounded to the nearest whole count once, here.
    local median = Sample.median(values)
    if median then
        median = math.floor(median + 0.5)
    end
    return {
        pages = measured,
        values = values,
        median = median,
        min = min,
        max = max,
        total = total,
    }
end

return Measure
