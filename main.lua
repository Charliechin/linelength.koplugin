-- Line length. Two ways in:
--  * select text: adds one button to the dialog (Select, Highlight, Copy, ...) that shows the length of
--    the selection in characters and how that reads as a line of text. Tap it for the details: characters
--    with and without spaces, words, and the ranges.
--  * the whole page: "Line length: this page" in the Typeset menu (also an action you can put on a gesture)
--    shows the longest lines on the page that is on screen, rated by the longest one.
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Counter = require("linelength/counter")
local Layout = require("linelength/layout")
local Rating = require("linelength/rating")
local Report = require("linelength/report")
local AutoTune = require("linelength/autotune")
local Measure = require("linelength/measure")

local LineLength = WidgetContainer:extend{
    name = "linelength",
    is_doc_only = true,
}

-- The highlight dialog lists its buttons sorted by this key. The built-in ones run from
-- 01_select to 12_search (the QR code plugin sits at 12_generate_qr_code), so "13" puts ours last:
-- alone on a full-width row when the number of other buttons is even.
local SLOT = "13_line_length"

local LABELS = {
    too_long = _("Too long"),
    still_readable = _("Still readable"),
    comfortable = _("Comfortable"),
    excellent = _("Excellent"),
    short = _("Short"),
}

-- Count what Copy would copy: the same clean-up KOReader applies before it puts the selection
-- on the clipboard (trims the ends, collapses runs of spaces, keeps single line breaks).
local function countSelection(highlight)
    local selected = highlight and highlight.selected_text
    local text = selected and selected.text
    if type(text) ~= "string" then
        text = ""
    end
    return Counter.count(util.cleanupSelectedText(text))
end

local function n(value)
    return string.format("%d", value)
end

-- Colour only when KOReader is actually drawing in colour: that is true on a colour screen unless
-- the user turned "Color rendering" off. On a black-and-white screen, or with colour off, the card
-- uses the standard text colour.
local function colorEnabled()
    local ok, enabled = pcall(function() return Device.screen:isColorEnabled() end)
    return ok and enabled == true
end

-- The same information as the card, as plain text. Used if the card cannot be built.
local function plainText(report)
    local lines = {}
    for _i, band in ipairs(report.bands) do
        lines[#lines + 1] = band.range .. "  " .. band.label
    end
    if report.lines then
        local rows = {}
        for _i, line in ipairs(report.lines) do
            rows[#rows + 1] = (line.number and ("L" .. n(line.number) .. ": ") or "") .. line.snippet .. "  " .. n(line.chars)
        end
        return _("Longest lines on this page (characters):") .. "\n" .. table.concat(rows, "\n")
            .. "\n\n" .. table.concat(lines, "\n")
    end
    return T(_("Characters, with spaces: %1\nCharacters, without spaces: %2\nWords: %3"),
            n(report.chars), n(report.chars_no_spaces), n(report.words))
        .. "\n\n" .. _("Characters per line (select one line):") .. "\n" .. table.concat(lines, "\n")
end

-- `hooks` (optional, the page card only): { controls = which buttons are usable, values = what the steppers show,
-- on_control = function(card, id) }
local function showReport(report, hooks)
    -- The card is loaded on demand and guarded: whatever goes wrong with it, the button stays and
    -- the information is still shown.
    local ok, err = pcall(function()
        local Details = require("linelength/details")
        local card
        card = Details:new{
            report = report,
            use_color = colorEnabled(),
            controls = hooks and hooks.controls,
            values = hooks and hooks.values,
            on_control = hooks and hooks.controls and function(id) hooks.on_control(card, id) end,
        }
        UIManager:show(card)
    end)
    if not ok then
        logger.warn("linelength: could not show the details card, using plain text:", err)
        UIManager:show(InfoMessage:new{ text = plainText(report) })
    end
end

local function showDetails(counts)
    showReport(Report.build(counts, LABELS))
end

-- The page on screen and a sample of pages are read by linelength/measure.lua; these keep the two
-- passages main.lua has always had, so a caller does not have to know where the work moved.
function LineLength:pageReport()
    return Measure.page(self.ui, LABELS)
end

function LineLength:measureSettled()
    return Measure.settled(self.ui, LABELS)
end

function LineLength:measureSample(counts)
    return Measure.sample(self.ui, LABELS, counts)
end

-- The width of the screen in KOReader's "unscaled" units, the ones the margins and the font size are given in.
local function screenWidthUnits()
    local screen = Device.screen
    return screen:getWidth() / (screen:scaleBySize(100) / 100)
end

-- The margins and the font size the book is laid out with now, or nil when KOReader does not say.
function LineLength:currentLayout()
    local conf = self.ui and self.ui.document and self.ui.document.configurable
    local margins = conf and conf.h_page_margins
    local size = conf and conf.font_size
    if type(margins) == "table" and type(margins[1]) == "number" and type(margins[2]) == "number" and type(size) == "number" then
        return { margins = { margins[1], margins[2] }, size = size }
    end
    return nil
end

-- Which of the stepper buttons on the page card can be used now. nil (no buttons at all) when the layout is not known.
function LineLength:pageControls()
    local ok, controls = pcall(function()
        local layout = self:currentLayout()
        if not layout then
            return nil
        end
        return Layout.controls(layout, screenWidthUnits())
    end)
    return ok and controls or nil
end

-- What the steppers on the page card show: the margins and the text size as KOReader's own menus number them.
-- nil when the layout is not known.
function LineLength:pageValues()
    local ok, values = pcall(function()
        local layout = self:currentLayout()
        if not layout then
            return nil
        end
        return { margins = Layout.formatMargins(layout.margins), size = Layout.formatNumber(layout.size) }
    end)
    return ok and values or nil
end

-- Lays the book out again with new margins and/or a new text size, the way KOReader's own menu does it: a
-- ConfigChange (which is also what stores the value with the book) and then the event that sets it. Both are
-- sent straight to the reader: the card is a modal window and would swallow anything sent through UIManager.
function LineLength:applyLayout(margins, size)
    if margins then
        self.ui:handleEvent(Event:new("ConfigChange", "h_page_margins", margins))
        self.ui:handleEvent(Event:new("SetPageHorizMargins", margins))
    end
    if size then
        self.ui:handleEvent(Event:new("ConfigChange", "font_size", size))
        self.ui:handleEvent(Event:new("SetFontSize", size))
    end
end

-- Measures the page again and redraws the card with what it finds (if the page cannot be read the old numbers stay,
-- the buttons and the steppers still update).
function LineLength:redrawCard(card)
    local ok_report, report = pcall(function() return (self:measureSettled()) end)
    if not ok_report then
        logger.warn("linelength: could not read the lines of this page:", report)
        report = nil
    end
    card:update(report or card.report, self:pageControls(), self:pageValues())
end

-- A button on the page card was tapped: change the layout, measure the page again, redraw the card. "accept" changes
-- nothing: it measures the page again (it has been drawn by now) so the full card shows what the page really holds.
function LineLength:onControl(card, session, id)
    local ok, err = pcall(function()
        if id == "accept" then
            self:redrawCard(card)
            return
        end
        local layout = self:currentLayout()
        if not layout then
            return
        end
        local width = screenWidthUnits()
        local margins, size
        if id == "margins_less" then
            margins = Layout.stepMargins(layout.margins, -1, width)
        elseif id == "margins_more" then
            margins = Layout.stepMargins(layout.margins, 1, width)
        elseif id == "text_less" then
            size = Layout.stepFontSize(layout.size, -1)
        elseif id == "text_more" then
            size = Layout.stepFontSize(layout.size, 1)
        elseif id == "revert" or id == "cancel" then
            -- Puts the book back as it was when the card opened, whatever was changed since (also what was accepted).
            -- "revert" is the shrunk card's Cancel: the card stays and shows the page as it was. "cancel" is the full
            -- card's: the card closes itself afterwards.
            local before = session.baseline
            if not before then
                return
            end
            -- only what differs from now is set, so the book is not laid out again for nothing
            if before.margins[1] ~= layout.margins[1] or before.margins[2] ~= layout.margins[2] then
                margins = { before.margins[1], before.margins[2] }
            end
            if before.size ~= layout.size then
                size = before.size
            end
        else
            return
        end
        local restoring = id == "revert" or id == "cancel"
        if not restoring then
            if not (margins or size) then
                return -- at a limit
            end
            -- remembered before anything is changed, so Cancel can put it back even if the change fails half way
            session.baseline = session.baseline or layout
        end
        self:applyLayout(margins, size)
        if restoring then
            session.baseline = nil
        end
        if id == "cancel" then
            return -- the card is closing: nothing to measure or redraw
        end
        -- the page was laid out again: measure it again
        self:redrawCard(card)
    end)
    if not ok then
        logger.warn("linelength: could not change the layout:", err)
    end
end

-- The auto-tune: measures the line length of a sample of the book and, when it is outside the band the
-- tune aims at, moves the margins until it is inside. The size of the text is the reader's own and is
-- never touched. Every step is measured again, so the loop stops on what the book really holds and not
-- on what the formula predicts.
function LineLength:autoTune(settings)
    settings = settings or {}
    -- The band, the target and the bounds of the margins, as the tune has them: the reader sets the
    -- margins, the band and the target are the auto-tune's own. The loop stops on the band and the step
    -- aims at the target, so both helpers have to be given the same one.
    local limits = AutoTune.limits(settings)
    local width = screenWidthUnits()

    local sample, reason = self:measureSample()
    if not sample then
        logger.warn("linelength: could not measure the book for the auto-tune:", reason)
        return nil
    end
    local chars = sample.median
    local steps, changed = 0, false
    local layout = self:currentLayout()
    if not layout then
        return nil
    end
    -- The step works on the average of the two margins, so that an uneven layout is measured on the
    -- width it really has. Both margins are looked at: one of them out of the bounds is enough to pull
    -- the layout back in, even when the lines are already in the band.
    local left = tonumber(layout.margins[1]) or AutoTune.MARGIN_MIN
    local right = tonumber(layout.margins[2]) or left
    local margin = AutoTune.startMargin((left + right) / 2, limits)
    local inside = left >= limits.margin_min and left <= limits.margin_max
        and right >= limits.margin_min and right <= limits.margin_max

    -- Lays the book out at a margin and measures it again, so that the count belongs to the layout
    -- that is on the page: nil when the new layout could not be read, and the count of the old one
    -- then says nothing about the book any more.
    local function moveTo(next_margin)
        self:applyLayout({ next_margin, next_margin }, nil)
        margin = next_margin
        changed = true
        steps = steps + 1
        local again = self:measureSample()
        if not again then
            return nil
        end
        chars = again.median
        return chars
    end

    local function putBackAndFail()
        if changed then
            self:applyLayout({ left, right }, nil)
            margin = (left + right) / 2
            changed = false
        end
        return { steps = steps, chars = nil, changed = changed, margin = margin }
    end

    if not inside and not moveTo(margin) then
        return putBackAndFail()
    end
    while not AutoTune.inBand(chars, limits) and steps < AutoTune.MAX_STEPS do
        local next_margin = AutoTune.nextMargin(margin, chars, width, limits)
        if not next_margin then
            break -- nothing more can be tried: the book is as good as it can get
        end
        if not moveTo(next_margin) then
            return putBackAndFail()
        end
    end
    return { steps = steps, chars = chars, changed = changed, margin = margin }
end

-- The auto-tune when a book opens, if the reader asked for it. It runs every time a book is opened at
-- its first page: a book that is already within the band keeps the margins it has, and nothing is
-- shown when there was nothing to do.
function LineLength:onReaderReady()
    local settings = self:settings()
    if not settings.enabled then
        return
    end
    -- ReaderRolling schedules its partial rerendering a tick after it is ready, not before. Measuring
    -- here would make every margin change a full re-render on the UI thread at book open, so the tune
    -- waits for the reader's own tick; no message is shown, the automatic path is meant to be quiet.
    UIManager:tickAfterNext(function()
        -- Only when the book is opened at its start: a book picked up where it was left keeps its
        -- layout. The page is asked for here rather than before the tick, so that it holds where the
        -- layout would actually move.
        local doc = self.ui and self.ui.document
        local ok_page, page = pcall(doc and doc.getCurrentPage, doc)
        if (ok_page and tonumber(page)) ~= 1 then
            return
        end
        local ok_tune, result = pcall(function() return (self:autoTune(settings)) end)
        if not ok_tune then
            logger.warn("linelength: the auto-tune failed:", result)
            return
        end
        -- A book that could not be measured has no count: the tune gives up on it and the book keeps
        -- the layout it has.
        if not result or result.chars == nil then
            return
        end
        if result.changed then
            logger.info("linelength: auto-tuned to", result.chars, "characters in", result.steps, "steps")
        end
    end)
end

function LineLength:showPage()
    local ok, report, reason = pcall(self.pageReport, self)
    if not ok then
        logger.warn("linelength: could not read the lines of this page:", report)
        UIManager:show(InfoMessage:new{ text = _("Could not read the lines of this page.") })
        return
    end
    if not report then
        UIManager:show(InfoMessage:new{
            text = reason == "unsupported" and _("This only works in books that reflow, like EPUB.")
                or _("There is no text on this page."),
        })
        return
    end
    local session = {}
    showReport(report, {
        controls = self:pageControls(),
        values = self:pageValues(),
        on_control = function(card, id) self:onControl(card, session, id) end,
    })
end

-- The verdict is the one of the median line, not of any single page: dialogue and headings vary.
local function sampleText(sample)
    local tier = Rating.forChars(sample.median)
    local lines = {
        T(_("Median line: %1 chars - %2"), n(sample.median), LABELS[tier.id]),
        T(_("Pages measured: %1 of %2"), n(#sample.values), n(sample.total)),
    }
    if sample.min and sample.max then
        lines[#lines + 1] = T(_("Shortest and longest: %1 to %2"), n(sample.min), n(sample.max))
    end
    return table.concat(lines, "\n")
end

-- Measures a sample of the book's pages and shows the result. The book is laid out again on every page
-- that is measured, so this takes a few seconds on a device and the reader sees a "measuring" message.
-- The measurement waits for the next UI tick, so that message is on the screen before the walk starts
-- and is not replaced by the result without ever having been seen.
function LineLength:showSample(counts)
    UIManager:show(InfoMessage:new{ text = _("Measuring pages..."), timeout = 1 })
    UIManager:tickAfterNext(function()
        self:showSampleResult(counts)
    end)
end

function LineLength:showSampleResult(counts)
    local ok, sample, reason = pcall(function() return self:measureSample(counts) end)
    if not ok then
        logger.warn("linelength: could not measure a sample of pages:", sample)
        UIManager:show(InfoMessage:new{ text = _("Could not measure the pages of this book.") })
        return
    end
    if not sample then
        local text
        if reason == "unsupported" then
            text = _("This only works in books that reflow, like EPUB.")
        elseif reason == "no_buffer" then
            text = _("Not enough memory to measure a sample of pages.")
        elseif reason == "error" then
            -- The walk failed on the way: the reader could not be put back on its page, or the pages
            -- could not be drawn. There is nothing to report about the book.
            text = _("Could not measure the pages of this book.")
        else
            text = _("There is no text on these pages.")
        end
        UIManager:show(InfoMessage:new{ text = text })
        return
    end
    UIManager:show(InfoMessage:new{ text = sampleText(sample) })
end

function LineLength:onLinelengthSample()
    self:showSample()
    return true
end

-- Tunes the book now, and says what came of it. The book is measured again even when it is already
-- within the band: this is the action the reader reaches for when a book does not look right.
function LineLength:tuneNow()
    local settings = self:settings()
    UIManager:show(InfoMessage:new{ text = _("Tuning..."), timeout = 1 })
    UIManager:tickAfterNext(function()
        local ok_tune, result = pcall(function() return (self:autoTune(settings)) end)
        if not ok_tune then
            logger.warn("linelength: the auto-tune failed:", result)
            UIManager:show(InfoMessage:new{ text = _("Could not tune this book.") })
            return
        end
        -- A book that could not be measured has no count to show: the message about nothing to change
        -- is for a book that was measured and is already there.
        if not result or result.chars == nil then
            logger.warn("linelength: the auto-tune could not measure the book")
            UIManager:show(InfoMessage:new{ text = _("Could not tune this book.") })
            return
        end
        if result.changed then
            UIManager:show(InfoMessage:new{
                text = T(_("Tuned to %1 characters."), n(result.chars)),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Already %1 characters, nothing to change."), n(result.chars)),
            })
        end
    end)
end

function LineLength:onLinelengthTune()
    self:tuneNow()
    return true
end

-- The page measurement as an action, so it can be put on a gesture, a quick action or a profile.
function LineLength:onDispatcherRegisterActions()
    -- The id "wordcount_page" is the plugin's old name. KOReader stores it in gesture and profile settings, so it
    -- stays: renaming it would silently unassign every gesture set up with 0.5.x or 0.6.x.
    -- rolling = only offered while a book that reflows is open (KOReader's own font actions do the same);
    -- in a PDF or in the file manager the action is not listed and does not run.
    Dispatcher:registerAction("wordcount_page", {
        category = "none", event = "LinelengthPage", title = _("Line length: this page"), rolling = true,
    })
    Dispatcher:registerAction("linelength_sample", {
        category = "none", event = "LinelengthSample", title = _("Line length: this book (sample)"),
        rolling = true,
    })
    Dispatcher:registerAction("linelength_tune", {
        category = "none", event = "LinelengthTune", title = _("Line length: tune this book"),
        rolling = true,
    })
end

function LineLength:onLinelengthPage()
    self:showPage()
    return true
end

-- What the reader chose for the auto-tune: the switch, and how far the margins may go. These are the
-- only three, and they are kept the way KOReader keeps a plugin's settings, in the reader's own
-- settings file.
function LineLength:settings()
    return {
        enabled = G_reader_settings:isTrue("linelength_auto_tune"),
        margin_min = tonumber(G_reader_settings:readSetting("linelength_margin_min")) or AutoTune.MARGIN_MIN,
        margin_max = tonumber(G_reader_settings:readSetting("linelength_margin_max")) or AutoTune.MARGIN_MAX,
    }
end


-- The settings of the auto-tune, as a menu: a switch, and the numbers that decide what it does.
-- Each number is a step of 1, and the menu shows what it is set to now.
function LineLength:settingsMenu()
    local settings = self:settings()
    local function save()
        G_reader_settings:saveSetting("linelength_auto_tune", settings.enabled)
        G_reader_settings:saveSetting("linelength_margin_min", settings.margin_min)
        G_reader_settings:saveSetting("linelength_margin_max", settings.margin_max)
        G_reader_settings:flush()
    end
    -- A number, with a step of one. The bounds a number is given here are its own. A number that is
    -- one end of a pair also gets the other end of the pair as a bound, so that the two can never
    -- cross: `other_above` says the other end of the pair is the upper one.
    local function number(label, key, step, min, max, other_key, other_above)
        local function limit(direction)
            if not other_key then
                return direction > 0 and max or min
            end
            local other = tonumber(settings[other_key]) or (direction > 0 and max or min)
            -- The other end of the pair is above this one: it bounds the step up, and not down.
            if other_above then
                return direction > 0 and math.min(max, other) or min
            end
            return direction > 0 and max or math.max(min, other)
        end
        return {
            text_func = function()
                return T(_("%1: %2"), label, tostring(settings[key]))
            end,
            keep_menu_open = true,
            sub_item_table = {
                {
                    text = T(_("Less %1"), label),
                    enabled_func = function() return settings[key] > limit(-1) end,
                    callback = function()
                        settings[key] = math.max(limit(-1), settings[key] - step)
                        save()
                    end,
                },
                {
                    text = T(_("More %1"), label),
                    enabled_func = function() return settings[key] < limit(1) end,
                    callback = function()
                        settings[key] = math.min(limit(1), settings[key] + step)
                        save()
                    end,
                },
            },
        }
    end
    return {
        {
            text_func = function()
                return settings.enabled and _("Auto-tune when a book opens: on") or _("Auto-tune when a book opens: off")
            end,
            keep_menu_open = true,
            callback = function()
                settings.enabled = not settings.enabled
                save()
            end,
        },
        number(_("Smallest margin"), "margin_min", 1, 0, 140, "margin_max", true),
        number(_("Biggest margin"), "margin_max", 1, 0, 140, "margin_min", false),
    }
end

function LineLength:addToMainMenu(menu_items)
    menu_items.linelength_page = {
        text = _("Line length: this page"),
        sorting_hint = "typeset",
        callback = function() self:showPage() end,
    }
    menu_items.linelength_sample = {
        text = _("Line length: this book (sample)"),
        sorting_hint = "typeset",
        callback = function() self:showSample() end,
    }
    menu_items.linelength_tune = {
        text = _("Line length: tune this book"),
        sorting_hint = "typeset",
        callback = function() self:tuneNow() end,
    }
    menu_items.linelength_settings = {
        text = _("Line length: settings"),
        sorting_hint = "typeset",
        sub_item_table_func = function()
            return self:settingsMenu()
        end,
    }
end

function LineLength:init()
    -- Only in a book.
    if not self.document then
        return
    end
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    -- The selection button needs the highlight module; the page measurement does not.
    if not (self.ui and self.ui.highlight) then
        return
    end

    self.ui.highlight:addToHighlightDialog(SLOT, function(this)
        local c = countSelection(this)
        local tier = Rating.forChars(c.chars)
        return {
            text = T(_("Line: %1 chars · %2"), n(c.chars), LABELS[tier.id]),
            callback = function() showDetails(c) end,
        }
    end)
end

return LineLength
