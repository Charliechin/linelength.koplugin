package.path = "./?.lua;" .. package.path

-- ---- stubs --------------------------------------------------------------------------------
local shown, warns = {}, {}
local color_state = { on = true } -- true, false, or "error" (isColorEnabled raises)
local screen_state = { raises = false, scale_raises = false } -- raises: asking for the screen size raises
local details_opts = {}           -- what the card was asked to show
local actions = {}                -- Dispatcher actions registered

-- KOReader keeps a plugin's settings in the reader's own settings file, reached through this global.
-- A table of key and value stands in for it here.
G_reader_settings = {
    data = {},
    readSetting = function(self, key) return self.data[key] end,
    isTrue = function(self, key) return self.data[key] == true end,
    saveSetting = function(self, key, value) self.data[key] = value end,
    flush = function() end,
}

local function extend(base, t)
    t = t or {}
    t.__index = t
    setmetatable(t, { __index = base })
    t.extend = function(self, tt) return extend(self, tt) end
    t.new = function(self, o) o = o or {}; setmetatable(o, self); return o end
    return t
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local W = { extend = function(self, t) return extend(self, t) end }
    W.__index = W
    return W
end
package.preload["ui/widget/infomessage"] = function()
    local I = {}
    function I:new(o) o.is_infomessage = true; return o end
    return I
end
-- show() and forceRePaint() (which counts, and can run a hook: KOReader's paint is what renders a book that is only
-- rendered when drawn). The button schedules and refreshes nothing: any leftover use of tickAfterNext/nextTick/setDirty
-- in main.lua would raise here.
local repaints = { n = 0, hook = nil }
package.preload["ui/uimanager"] = function()
    return {
        show = function(_self, w) shown[#shown + 1] = w end,
        -- The message the reader is shown waits for the next tick, so that it is on the screen
        -- before the work starts. Here the tick comes right away.
        tickAfterNext = function(_self, fn) fn() end,
        forceRePaint = function()
            repaints.n = repaints.n + 1
            if repaints.hook then repaints.hook() end
        end,
    }
end
-- The page is drawn into a buffer of its own (never on the screen) to settle the layout: a Blitbuffer that records what it
-- was asked for and how often it was given back, and a reader view whose paint is that draw.
local draws = { n = 0, hook = nil, last = nil }
local buffers = { created = {}, raises = false }
package.preload["ffi/blitbuffer"] = function()
    return { new = function(w, h, t)
        if buffers.raises then error("no memory") end
        local b = { w = w, h = h, type = t, freed = 0 }
        function b:free() self.freed = self.freed + 1 end
        buffers.created[#buffers.created + 1] = b
        return b
    end }
end
package.preload["device"] = function()
    return { screen = {
        isColorEnabled = function()
            if color_state.on == "error" then error("no screen") end
            return color_state.on == true
        end,
        getWidth = function()
            if screen_state.raises then error("no screen size") end
            return 1264
        end,
        getHeight = function() return 1680 end,
        bb = { getType = function() return "the screen's type" end },
        -- 2 pixels per KOReader unit, so the screen is 632 units wide
        scaleBySize = function(_self, n)
            if screen_state.scale_raises then error("no scale") end
            return n * 2
        end,
    } }
end
-- KOReader's Event: a name, the handler it dispatches to ("on" .. name) and the arguments
package.preload["ui/event"] = function()
    return { new = function(_self, name, ...) return { name = name, handler = "on" .. name, args = { ... } } end }
end
package.preload["dispatcher"] = function()
    return { registerAction = function(_self, name, def) actions[name] = def end }
end
package.preload["logger"] = function()
    return {
        dbg = function() end,
        info = function() end,
        warn = function(...) warns[#warns + 1] = { ... } end,
    }
end
package.preload["gettext"] = function() return function(s) return s end end
package.preload["ffi/util"] = function()
    return { template = function(str, ...)
        local args = { ... }
        return (str:gsub("%%([0-9]+)", function(i) return tostring(args[tonumber(i)]) end))
    end }
end
-- the real KOReader implementation (frontend/util.lua, v2026.07.1), copied verbatim
package.preload["util"] = function()
    local util = {}
    function util.cleanupSelectedText(text)
        text = text:gsub("^[\n%s]*", "")
        text = text:gsub("[\n%s]*$", "")
        text = text:gsub("%s*\n%s*", "\n")
        text = text:gsub("%s%s+", " ")
        return text
    end
    return util
end
-- the card is stubbed here (it is checked by rendering it in KOReader, see tests/render)
local DetailsStub = {}
function DetailsStub:new(o)
    details_opts[#details_opts + 1] = o
    local card = { is_details = true, opts = o, report = o.report, updates = {} }
    -- what the real card does when it is redrawn: it keeps the new report
    function card:update(report, controls, values)
        self.updates[#self.updates + 1] = { report = report, controls = controls, values = values }
        self.report = report
    end
    return card
end
package.preload["linelength/details"] = function() return DetailsStub end

local failures = 0
local function expect(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %q, want %q", name, tostring(got), tostring(want)))
    end
end

local LineLength = require("main")
expect("plugin name", LineLength.name, "linelength")
expect("only loads inside a book", LineLength.is_doc_only, true)

local function newHighlight()
    local h = { _highlight_buttons = {} }
    function h:addToHighlightDialog(idx, fn) self._highlight_buttons[idx] = fn end
    return h
end

local function makePlugin(opts)
    local p = LineLength:new({ document = opts.document, ui = opts.ui })
    p:init()
    return p
end

-- 1. exactly one button is registered in a book, in the last slot
local hl = newHighlight()
makePlugin({ document = {}, ui = { highlight = hl } })
expect("slot registered", type(hl._highlight_buttons["13_line_length"]), "function")
local registered = 0
for _k in pairs(hl._highlight_buttons) do registered = registered + 1 end
expect("only one button", registered, 1)

-- 2. nothing without a document, no crash without the highlight module
local hl2 = newHighlight()
makePlugin({ document = nil, ui = { highlight = hl2 } })
expect("no document: nothing registered", next(hl2._highlight_buttons), nil)
expect("no highlight module: init does not crash", (pcall(makePlugin, { document = {}, ui = {} })), true)

local button_fn = hl._highlight_buttons["13_line_length"]

-- 3. the button is as plain as the others: just a label and a tap handler, no colour hooks
local sample = { selected_text = { text = "  Hello   world,\n\n again  " } } -- cleaned: 18 characters
local btn = button_fn(sample)
expect("label", btn.text, "Line: 18 chars · Short")
local keys = {}
for k in pairs(btn) do keys[#keys + 1] = k end
table.sort(keys)
expect("button has only text and callback", table.concat(keys, ","), "callback,text")
expect("label follows the selection", button_fn({ selected_text = { text = "one" } }).text, "Line: 3 chars · Short")
expect("nil selected_text", button_fn({}).text, "Line: 0 chars · Short")
expect("nil text", button_fn({ selected_text = {} }).text, "Line: 0 chars · Short")
expect("nil highlight", button_fn(nil).text, "Line: 0 chars · Short")
expect("the card is not loaded until needed", package.loaded["linelength/details"], nil)

-- 4. the label at every band edge
local bands = {
    { 44, "Short" }, { 45, "Short" }, { 49, "Short" }, { 50, "Excellent" },
    { 66, "Excellent" }, { 67, "Comfortable" }, { 75, "Comfortable" }, { 76, "Still readable" },
    { 80, "Still readable" }, { 81, "Too long" }, { 200, "Too long" },
}
for _i, c in ipairs(bands) do
    local b = button_fn({ selected_text = { text = string.rep("a", c[1]) } })
    expect("label at " .. c[1], b.text, "Line: " .. c[1] .. " chars · " .. c[2])
end

-- 5. tapping shows the card with the report for that selection
local function tap(text, color)
    shown, warns, details_opts = {}, {}, {}
    color_state.on = color == nil and true or color
    button_fn({ selected_text = { text = text } }).callback()
end

tap(sample.selected_text.text)
expect("tap shows one widget", #shown, 1)
expect("it is the card", shown[1].is_details, true)
local report = shown[1].opts.report
expect("report chars", report.chars, 18)
expect("report chars without spaces", report.chars_no_spaces, 16)
expect("report words", report.words, 3)
expect("report verdict", report.tier.id, "short")
expect("report verdict label", report.tier.label, "Short")
expect("short has no colour", report.tier.color, nil)
expect("four ranges", #report.bands, 4)
expect("range label is translated text", report.bands[1].label, "Excellent")
expect("range 1", report.bands[1].range, "50–66")
expect("range 2", report.bands[2].range, "67–75")
expect("range 4", report.bands[4].range, "81+")

tap(string.rep("a", 60))
local r60 = shown[1].opts.report
expect("60: verdict", r60.tier.id, "excellent")
expect("60: colour from the spec", r60.tier.color, "#0072B2")
expect("60: Excellent is the current range", r60.bands[1].current, true)
expect("60: Comfortable is not", r60.bands[2].current, false)

-- 6. colour is requested only when KOReader is drawing in colour
tap(string.rep("a", 60), true)
expect("colour screen: use_color", shown[1].opts.use_color, true)
tap(string.rep("a", 60), false)
expect("no colour: use_color false", shown[1].opts.use_color, false)
tap(string.rep("a", 60), "error")
expect("colour check raised: use_color false", shown[1].opts.use_color, false)

-- 7. if the card cannot be shown, the same information appears as plain text
local PLAIN = "Characters, with spaces: 18\nCharacters, without spaces: 16\nWords: 3\n\n"
    .. "Characters per line (select one line):\n50–66  Excellent\n67–75  Comfortable\n76–80  Still readable\n81+  Too long"

-- 7a. the card module fails to load
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() error("boom") end
tap(sample.selected_text.text)
expect("load failure: one widget", #shown, 1)
expect("load failure: plain text popup", shown[1].is_infomessage, true)
expect("load failure: same information", shown[1].text, PLAIN)
expect("load failure: one warning", #warns, 1)

-- 7b. the card raises while it is being built
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function()
    return { new = function() error("kaboom") end }
end
tap(sample.selected_text.text)
expect("build failure: plain text popup", shown[1] and shown[1].is_infomessage, true)
expect("build failure: same information", shown[1] and shown[1].text, PLAIN)
expect("build failure: one warning", #warns, 1)

-- back to the normal stub: the card works again afterwards
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() return DetailsStub end
tap(sample.selected_text.text)
expect("recovers after a failure", shown[1] and shown[1].is_details, true)

-- 8. position: keys sort as strings; ours must come after every built-in one
local builtin = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "08_share_text", "09_view_html", "10_user_dict",
    "11_follow_link", "12_generate_qr_code", "12_search" }
for _i, key in ipairs(builtin) do
    expect("sorts after " .. key, "13_line_length" > key, true)
end

-- 9. layout: the same assembly ReaderHighlight:onShowHighlightMenu does (2 columns, sorted keys)
local function layout(ks)
    table.sort(ks)
    local rows = { {} }
    for _i, k in ipairs(ks) do
        if #rows[#rows] >= 2 then rows[#rows + 1] = {} end
        table.insert(rows[#rows], k)
    end
    return rows
end
local ks = { "01_select", "02_highlight", "03_copy", "04_add_note", "05_wikipedia",
    "06_dictionary", "07_translate", "09_view_html", "12_generate_qr_code", "12_search",
    "13_line_length" }
local rows = layout(ks)
expect("rows", #rows, 6)
expect("ours is alone on a full-width last row", #rows[#rows], 1)
expect("and it is ours", rows[#rows][1], "13_line_length")
expect("Search stays where it was", rows[5][2], "12_search")

-- ---------------------------------------------------------------------------------------------
-- 10. the whole-page measurement
local function fakeDoc(line_texts, opts)
    opts = opts or {}
    local NODE = "/b/p[1]/text()[1]"
    -- The lines of a page depend on the page: a test that measures the wrong page is caught.
    local page = 1
    local lines, offset = {}, 0
    local function layout()
        lines, offset = {}, 0
        for i, text in ipairs(line_texts) do
            local shown = text
            if opts.per_page then
                shown = string.rep(text:sub(1, 1), opts.per_page(page) or #text)
            end
            lines[i] = { s = shown, from = offset, to = offset + #shown, y = 71 + (i - 1) * 64 }
            offset = offset + #shown + 1
        end
    end
    layout()
    local d = {}
    function d:setPage(p) page = p; layout() end
    function d:getTextFromPositions(p0, _p1)
        if opts.raises then error("engine boom") end
        if p0.y == 0 then
            local boxes = {}
            for _i, l in ipairs(lines) do boxes[#boxes + 1] = { x = 43, y = l.y, w = 1180, h = 64 } end
            return { text = "page", pos0 = NODE .. ".0", pos1 = NODE .. "." .. offset, sboxes = boxes }
        end
        for _i, l in ipairs(lines) do
            if p0.y >= l.y and p0.y < l.y + 64 then
                return { text = l.s, pos0 = NODE .. "." .. l.from, pos1 = NODE .. "." .. l.to }
            end
        end
    end
    function d:getScreenPositionFromXPointer(xp)
        local off = tonumber(xp:match("%.(%d+)$"))
        for _i, l in ipairs(lines) do
            if off >= l.from and off <= l.to then return l.y, 43 end
        end
        return 0, 0
    end
    function d:getTextFromXPointers() return "" end
    return d
end

-- three lines: 59 characters ("word " x12 without the last space), 70, and 45
local L1 = ("word "):rep(12):sub(1, -2)
local L2 = ("b"):rep(70)
local L3 = ("c"):rep(45)
expect("test line 1 is 59 characters", #L1, 59)

local function newMenu()
    return { registered = {}, registerToMainMenu = function(self, p) self.registered[#self.registered + 1] = p end }
end
local function pagePlugin(doc, opts)
    opts = opts or {}
    actions = {}
    local menu = newMenu()
    local p = makePlugin({ document = {}, ui = { menu = menu, highlight = newHighlight(), document = doc, rolling = opts.rolling == nil and {} or opts.rolling } })
    return p, menu
end
local function reset() shown, warns, details_opts, screen_state.raises, color_state.on = {}, {}, {}, false, true end

-- 10a. registration: the action, the menu, and the selection button together
local plugin, menu = pagePlugin(fakeDoc({ L1, L2, L3 }))
-- the action id is still "wordcount_page", the plugin's old name, on purpose: gestures and profiles store it
local action = actions["wordcount_page"]
expect("action registered", type(action), "table")
expect("action event", action and action.event, "LinelengthPage")
expect("action title", action and action.title, "Line length: this page")
expect("action is only for books that reflow", action and action.rolling, true)
expect("and is not marked for every book type", action and action.reader, nil)
expect("action has no category", action and action.category, "none")
expect("registered with the menu once", #menu.registered, 1)
expect("registered as this plugin", menu.registered[1], plugin)
local items = {}
plugin:addToMainMenu(items)
expect("menu item text", items.linelength_page and items.linelength_page.text, "Line length: this page")
expect("menu item goes in the Typeset menu", items.linelength_page and items.linelength_page.sorting_hint, "typeset")
expect("sample menu item text", items.linelength_sample and items.linelength_sample.text, "Line length: this book (sample)")
expect("sample menu item goes in the Typeset menu", items.linelength_sample and items.linelength_sample.sorting_hint, "typeset")
local item_count = 0
for _k in pairs(items) do item_count = item_count + 1 end
expect("four menu items", item_count, 4)
expect("the tune menu item", items.linelength_tune and items.linelength_tune.text, "Line length: tune this book")
expect("the tune action is registered", type(actions["linelength_tune"]), "table")
expect("the tune action event", actions["linelength_tune"] and actions["linelength_tune"].event, "LinelengthTune")
expect("the settings menu item", items.linelength_settings and items.linelength_settings.text, "Line length: settings")
expect("the settings menu item goes in the Typeset menu", items.linelength_settings and items.linelength_settings.sorting_hint, "typeset")
expect("the settings menu has a sub menu", type(items.linelength_settings and items.linelength_settings.sub_item_table_func), "function")
expect("sample action registered", type(actions["linelength_sample"]), "table")
expect("sample action event", actions["linelength_sample"] and actions["linelength_sample"].event, "LinelengthSample")
expect("sample action title", actions["linelength_sample"] and actions["linelength_sample"].title,
    "Line length: this book (sample)")
expect("sample action is only for books that reflow", actions["linelength_sample"] and actions["linelength_sample"].rolling, true)

-- 10b. nothing in the file manager (no document); a bare ui does not crash and still offers the action
actions = {}
local bare_menu = newMenu()
makePlugin({ document = nil, ui = { menu = bare_menu } })
expect("no document: no action", next(actions), nil)
expect("no document: no menu", #bare_menu.registered, 0)
actions = {}
expect("no menu and no highlight: init does not crash", (pcall(makePlugin, { document = {}, ui = {} })), true)
expect("no menu and no highlight: the action is still registered", type(actions["wordcount_page"]), "table")
actions = {}
local only_menu = newMenu()
makePlugin({ document = {}, ui = { menu = only_menu } })
expect("a menu without the highlight module", #only_menu.registered, 1)

-- 10c. the menu item shows the card: the longest line sets the rating, three lines are listed
reset()
items = {}
plugin:addToMainMenu(items)
items.linelength_page.callback()
expect("menu item shows one widget", #shown, 1)
expect("it is the card", shown[1] and shown[1].is_details, true)
local pr = shown[1] and shown[1].opts.report
expect("page report: the longest line (70)", pr and pr.chars, 70)
expect("page report: verdict follows the longest line", pr and pr.tier.id, "comfortable")
expect("page report: colour of that band", pr and pr.tier.color, "#009E73")
expect("page report: Comfortable is the current range", pr and pr.bands[2].current, true)
expect("page report: Excellent is not", pr and pr.bands[1].current, false)
expect("page report: three lines listed", pr and #pr.lines, 3)
expect("page report: longest first (70)", pr and pr.lines[1].chars, 70)
expect("page report: then 59", pr and pr.lines[2].chars, 59)
expect("page report: then 45", pr and pr.lines[3].chars, 45)
expect("page report: long line cut to 32 characters and an ellipsis", pr and pr.lines[1].snippet, ("b"):rep(32) .. "…")
expect("page report: snippet shows the start of the text", pr and pr.lines[2].snippet, "word word word word word word wo…")
-- the page order is 59, 70, 45 (top to bottom), so by length the lines are the 2nd, the 1st and the 3rd
expect("page report: the longest is line 2 of the page", pr and pr.lines[1].number, 2)
expect("page report: the second longest is line 1 of the page", pr and pr.lines[2].number, 1)
expect("page report: the third is line 3 of the page", pr and pr.lines[3].number, 3)
expect("card asked for colour on a colour screen", shown[1].opts.use_color, true)

-- 10d. the gesture action does the same, and says it handled the event
reset()
expect("the action handler reports it handled the event", plugin:onLinelengthPage(), true)
expect("the action shows the card too", shown[1] and shown[1].is_details, true)

-- 10e. fewer than three lines: only those are listed
reset()
local small = pagePlugin(fakeDoc({ L2, L3 }))
small:onLinelengthPage()
expect("two lines on the page: two listed", shown[1] and #shown[1].opts.report.lines, 2)
reset()
local single = pagePlugin(fakeDoc({ L3 }))
single:onLinelengthPage()
expect("one line: 45 is Short, no colour", shown[1] and shown[1].opts.report.tier.id, "short")

-- 10f. nothing to measure
reset()
local unsupported = pagePlugin(fakeDoc({ L1 }), { rolling = false })
unsupported.ui.rolling = nil
unsupported:onLinelengthPage()
expect("a book that does not reflow: a message", shown[1] and shown[1].is_infomessage, true)
expect("and it says why", shown[1] and shown[1].text, "This only works in books that reflow, like EPUB.")
reset()
local no_methods = pagePlugin({})
no_methods:onLinelengthPage()
expect("an engine without the line functions: same message", shown[1] and shown[1].text, "This only works in books that reflow, like EPUB.")
reset()
local blank = pagePlugin(fakeDoc({}))
blank:onLinelengthPage()
expect("a page without text: a message", shown[1] and shown[1].is_infomessage, true)
expect("and it says so", shown[1] and shown[1].text, "There is no text on this page.")
reset()
local broken_engine = pagePlugin(fakeDoc({ L1 }, { raises = true }))
broken_engine:onLinelengthPage()
expect("an engine that raises reads as an empty page", shown[1] and shown[1].text, "There is no text on this page.")
expect("without a crash or a warning", #warns, 0)

-- an engine that has two of the three line functions is still not enough
for _i, missing in ipairs({ "getTextFromXPointers", "getScreenPositionFromXPointer", "getTextFromPositions" }) do
    reset()
    local doc = fakeDoc({ L1 })
    doc[missing] = nil
    pagePlugin(doc):onLinelengthPage()
    expect("an engine without " .. missing .. ": not supported", shown[1] and shown[1].text, "This only works in books that reflow, like EPUB.")
end

-- the page is read the way the highlight button reads a selection: spaces collapsed first
reset()
pagePlugin(fakeDoc({ ("x"):rep(10) .. "   " .. ("y"):rep(10) })):onLinelengthPage()
expect("three spaces count as one (10 + 1 + 10)", shown[1] and shown[1].opts.report.chars, 21)

-- 10g. anything unexpected is caught and reported, never raised into KOReader
reset()
screen_state.raises = true
plugin:onLinelengthPage()
expect("unexpected error: a message is shown", shown[1] and shown[1].is_infomessage, true)
expect("unexpected error: it says what failed", shown[1] and shown[1].text, "Could not read the lines of this page.")
expect("unexpected error: one warning", #warns, 1)
screen_state.raises = false

-- 10h. the card fails: the same information as plain text
local PLAIN_PAGE = "Longest lines on this page (characters):\n"
    .. "L2: " .. ("b"):rep(32) .. "…  70\n"
    .. "L1: word word word word word word wo…  59\n"
    .. "L3: " .. ("c"):rep(32) .. "…  45\n\n"
    .. "50–66  Excellent\n67–75  Comfortable\n76–80  Still readable\n81+  Too long"
reset()
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() error("boom") end
plugin:onLinelengthPage()
expect("card load failure: plain text popup", shown[1] and shown[1].is_infomessage, true)
expect("card load failure: the lines and the ranges", shown[1] and shown[1].text, PLAIN_PAGE)
expect("card load failure: one warning", #warns, 1)
package.loaded["linelength/details"] = nil
package.preload["linelength/details"] = function() return DetailsStub end

-- 10i. the selection button is unaffected by all this
reset()
tap(sample.selected_text.text)
expect("selection button still shows the selection report", shown[1] and shown[1].opts.report.lines, nil)
expect("selection report keeps its counts", shown[1] and shown[1].opts.report.chars, 18)
expect("the selection card has no buttons for the margins", shown[1] and shown[1].opts.controls, nil)
expect("and nothing to call for them", shown[1] and shown[1].opts.on_control, nil)

-- ---------------------------------------------------------------------------------------------
-- 11. the buttons on the page card: margins, text size, and Cancel (the plugin gets "cancel" from the full card and "revert" from the shrunk one).
-- A fake reader: it stores a ConfigChange the way KOReader does and records every event it gets. The page it shows
-- depends on the layout: the longest line has 70 + (10 - left margin) - 3 * (font size - 22) characters, the
-- other two are 11 and 25 shorter. The screen is 632 units wide (1264 px, 2 px per unit).
local function show(v)
    if type(v) == "table" then
        local parts = {}
        for i, x in ipairs(v) do parts[i] = tostring(x) end
        return table.concat(parts, ",")
    end
    return tostring(v)
end
local function layoutBook(conf, texts_for)
    local doc = { configurable = conf, fail = false }
    texts_for = texts_for or function(c)
        local longest = 70 + (10 - c.h_page_margins[1]) - 3 * (c.font_size - 22)
        return { ("w"):rep(longest - 11), ("b"):rep(longest), ("c"):rep(longest - 25) }
    end
    return setmetatable(doc, { __index = function(_t, key)
        local d = fakeDoc(texts_for(doc.configurable), { raises = doc.fail })
        local value = d[key]
        if type(value) == "function" then
            return function(_self, ...) return value(d, ...) end
        end
        return value
    end })
end
local function layoutPlugin(conf, texts_for)
    local doc = layoutBook(conf or { h_page_margins = { 10, 10 }, font_size = 22 }, texts_for)
    local events = {}
    local ui = { menu = newMenu(), highlight = newHighlight(), document = doc, rolling = {}, fail_event = false }
    function ui:handleEvent(ev)
        if self.fail_event then error("event boom") end
        local parts = {}
        for i, a in ipairs(ev.args) do parts[i] = show(a) end
        events[#events + 1] = ev.name .. ":" .. table.concat(parts, ":")
        if ev.name == "ConfigChange" then doc.configurable[ev.args[1]] = ev.args[2] end
        return true
    end
    actions = {}
    local p = makePlugin({ document = {}, ui = ui })
    return p, ui, doc, events
end
-- the four stepper buttons as "1111": margins narrower, margins wider, text smaller, text bigger
local function flags(c)
    local s = {}
    for i, id in ipairs({ "margins_less", "margins_more", "text_less", "text_more" }) do
        s[i] = c[id] and "1" or "0"
    end
    return table.concat(s)
end

-- 11a. the card opens with the buttons, and a tap changes the layout, measures again, redraws
reset()
local lp, lui, ldoc, levents = layoutPlugin()
lp:showPage()
local lcard = shown[1]
expect("page card: opened", lcard and lcard.is_details, true)
expect("page card: starts with the longest line (70)", lcard.opts.report.chars, 70)
-- from margins 10/10: wider -> 25/25, narrower -> 0/0 (10 - 15, held at 0); font 22 -> 21 or 23
expect("page card: all four steps usable", flags(lcard.opts.controls), "1111")
expect("page card: the controls have no undo", lcard.opts.controls.undo, nil)
expect("page card: a function to call for the buttons", type(lcard.opts.on_control), "function")
expect("page card: the steppers start at margins 10 and size 22", lcard.opts.values and (lcard.opts.values.margins .. "," .. lcard.opts.values.size), "10,22")

-- margins wider. text = 632 - 20 = 612; 2.5% = 15.3 -> 15 each side -> 25/25
lcard.opts.on_control("margins_more")
expect("margins wider: the events, in KOReader's order", table.concat(levents, "|"),
    "ConfigChange:h_page_margins:25,25|SetPageHorizMargins:25,25")
expect("margins wider: stored with the book", show(ldoc.configurable.h_page_margins), "25,25")
expect("margins wider: the card was redrawn once", #lcard.updates, 1)
-- the page is laid out again: longest = 70 + (10 - 25) = 55
expect("margins wider: measured again (55)", lcard.updates[1].report.chars, 55)
expect("margins wider: 55 is Excellent", lcard.updates[1].report.tier.id, "excellent")
expect("margins wider: the other two lines follow (44 and 30)", lcard.updates[1].report.lines[2].chars .. "," .. lcard.updates[1].report.lines[3].chars, "44,30")
expect("margins wider: the longest is line 2 of the page", lcard.updates[1].report.lines[1].number, 2)
expect("margins wider: all four steps still usable", flags(lcard.updates[1].controls), "1111")
expect("margins wider: the steppers show 25 and 22", lcard.updates[1].values.margins .. "," .. lcard.updates[1].values.size, "25,22")

-- text bigger: 22 -> 23 (5% of 22 is 1.1 -> 1); longest = 70 - 15 - 3 = 52
local before = #levents
lcard.opts.on_control("text_more")
expect("text bigger: the events", table.concat(levents, "|", before + 1), "ConfigChange:font_size:23|SetFontSize:23")
expect("text bigger: stored with the book", ldoc.configurable.font_size, 23)
expect("text bigger: measured again (52)", lcard.updates[2].report.chars, 52)
expect("text bigger: the steppers show 25 and 23", lcard.updates[2].values.margins .. "," .. lcard.updates[2].values.size, "25,23")

-- margins narrower from 25/25: text = 632 - 50 = 582; 14.55 -> 15 -> back to 10/10; longest = 70 + 0 - 3 = 67
before = #levents
lcard.opts.on_control("margins_less")
expect("margins narrower: the events", table.concat(levents, "|", before + 1), "ConfigChange:h_page_margins:10,10|SetPageHorizMargins:10,10")
expect("margins narrower: measured again (67)", lcard.updates[3].report.chars, 67)
expect("margins narrower: 67 is Comfortable", lcard.updates[3].report.tier.id, "comfortable")
expect("margins narrower: the steppers show 10 and 23", lcard.updates[3].values.margins .. "," .. lcard.updates[3].values.size, "10,23")

-- revert (Cancel on the shrunk card): how it was when the card opened is margins 10/10 and size 22. Only the size differs now (23).
before = #levents
lcard.opts.on_control("revert")
expect("revert: only what differs is set (the size), nothing for the margins", table.concat(levents, "|", before + 1), "ConfigChange:font_size:22|SetFontSize:22")
expect("revert: margins as at the start", show(ldoc.configurable.h_page_margins), "10,10")
expect("revert: size as at the start", ldoc.configurable.font_size, 22)
expect("revert: measured again, back to 70", lcard.updates[4].report.chars, 70)
expect("revert: all four steps usable", flags(lcard.updates[4].controls), "1111")
expect("revert: the steppers show 10 and 22 again", lcard.updates[4].values.margins .. "," .. lcard.updates[4].values.size, "10,22")
expect("revert: eight events in all, no more", #levents, 8)

-- 11b. revert after margins AND size changed: both are set back, margins first
reset()
local p2, _u2, d2, e2 = layoutPlugin()
p2:showPage()
local c2 = shown[1]
c2.opts.on_control("margins_more")
c2.opts.on_control("text_more")
c2.opts.on_control("text_more") -- 23 -> 24 (5% of 23 is 1.15 -> 1)
expect("two text steps: size 24", d2.configurable.font_size, 24)
local n2 = #e2
c2.opts.on_control("revert")
expect("revert of everything: margins first, then the size", table.concat(e2, "|", n2 + 1),
    "ConfigChange:h_page_margins:10,10|SetPageHorizMargins:10,10|ConfigChange:font_size:22|SetFontSize:22")
expect("revert of everything: layout as at the start", show(d2.configurable.h_page_margins) .. "/" .. d2.configurable.font_size, "10,10/22")
expect("revert of everything: card measured again (70)", c2.updates[#c2.updates].report.chars, 70)
-- a second revert does nothing
n2 = #e2
local u2 = #c2.updates
c2.opts.on_control("revert")
expect("a second revert sets nothing", #e2, n2)
expect("a second revert does not redraw", #c2.updates, u2)

-- 11c. a change and its reverse by hand: revert then has nothing to set but still clears itself
reset()
local p3, _u3, d3, e3 = layoutPlugin()
p3:showPage()
local c3 = shown[1]
c3.opts.on_control("text_more") -- 22 -> 23
c3.opts.on_control("text_less") -- 23 -> 22 (5% of 23 is 1.15 -> 1)
expect("by hand back to 22", d3.configurable.font_size, 22)
n2 = #e3
c3.opts.on_control("revert")
expect("revert when the layout is already the original: no event", #e3, n2)
expect("revert when the layout is already the original: card redrawn", #c3.updates, 3)
expect("revert when the layout is already the original: all four steps usable", flags(c3.updates[3].controls), "1111")

-- 11d. limits: margins 140/140 cannot go wider, size 255 cannot go bigger; nothing happens when they are tapped
reset()
local fixed = function() return { ("b"):rep(60) } end
local p4, _u4, d4, e4 = layoutPlugin({ h_page_margins = { 140, 140 }, font_size = 255 }, fixed)
p4:showPage()
local c4 = shown[1]
-- narrower from 140: text = 632 - 280 = 352; 8.8 -> 9 -> 131. text smaller from 255: 12.75 -> 13 -> 242.
expect("limits: wider and bigger are off", flags(c4.opts.controls), "1010")
c4.opts.on_control("margins_more")
c4.opts.on_control("text_more")
expect("limits: tapping them sets nothing", #e4, 0)
expect("limits: and redraws nothing", #c4.updates, 0)
c4.opts.on_control("margins_less")
expect("limits: narrower from 140 -> 131", table.concat(e4, "|"), "ConfigChange:h_page_margins:131,131|SetPageHorizMargins:131,131")
-- 131 -> text = 632 - 262 = 370; 9.25 -> 9; wider is possible again (to 140), narrower to 122
expect("limits: after the step wider is possible again", flags(c4.updates[1].controls), "1110")

-- 11e. nothing to revert yet, unknown buttons
reset()
local p5, _u5, _d5, e5 = layoutPlugin()
p5:showPage()
local c5 = shown[1]
c5.opts.on_control("revert")
c5.opts.on_control("undo") -- the old Undo button is gone: an unknown id
c5.opts.on_control("no_such_button")
c5.opts.on_control(nil)
expect("revert with nothing changed sets nothing", #e5, 0)
expect("unknown buttons set nothing", #c5.updates, 0)

-- 11f. when the layout is not known there are no buttons at all
for label, conf in pairs({
    ["no configurable at all"] = false,
    ["no margins"] = { font_size = 22 },
    ["no font size"] = { h_page_margins = { 10, 10 } },
    ["margins with one side"] = { h_page_margins = { 10 }, font_size = 22 },
    ["margins as text"] = { h_page_margins = { "10", "10" }, font_size = 22 },
    ["font size as text"] = { h_page_margins = { 10, 10 }, font_size = "22" },
}) do
    reset()
    local doc
    if conf then
        -- a fixed page: only the layout values are incomplete
        doc = layoutBook(conf, function() return { L1, L2, L3 } end)
    else
        doc = fakeDoc({ L1, L2, L3 }) -- no `configurable` at all
    end
    local pl = pagePlugin(doc)
    pl:showPage()
    expect("unknown layout (" .. label .. "): the card still opens", shown[1] and shown[1].is_details, true)
    expect("unknown layout (" .. label .. "): no buttons", shown[1] and shown[1].opts.controls, nil)
    expect("unknown layout (" .. label .. "): nothing to call", shown[1] and shown[1].opts.on_control, nil)
    expect("unknown layout (" .. label .. "): no steppers to fill", shown[1] and shown[1].opts.values, nil)
end
reset()
screen_state.scale_raises = true
local pl6 = layoutPlugin()
pl6:showPage()
expect("the screen scale cannot be read: the card opens without buttons", shown[1] and shown[1].is_details and shown[1].opts.controls == nil, true)
screen_state.scale_raises = false

-- 11g. a failure while changing: logged, KOReader goes on, revert (Cancel on the shrunk card) is there
reset()
local p7, u7, d7, e7 = layoutPlugin()
p7:showPage()
local c7 = shown[1]
u7.fail_event = true
c7.opts.on_control("margins_more")
expect("an event that fails: one warning", #warns, 1)
expect("an event that fails: nothing redrawn", #c7.updates, 0)
expect("an event that fails: nothing was stored", show(d7.configurable.h_page_margins), "10,10")
u7.fail_event = false
c7.opts.on_control("revert")
expect("after the failure revert is there: the card is redrawn", #c7.updates, 1)
expect("after the failure revert is there: all four steps usable", flags(c7.updates[1].controls), "1111")
expect("after the failure nothing was set that was not different", #e7, 0)

-- 11h. the engine cannot read the page after the change: the old numbers stay, the buttons still update
reset()
local p8, _u8, d8 = layoutPlugin()
p8:showPage()
local c8 = shown[1]
d8.fail = true
c8.opts.on_control("margins_more")
expect("engine fails after the change: the layout did change", show(d8.configurable.h_page_margins), "25,25")
expect("engine fails after the change: card redrawn once", #c8.updates, 1)
expect("engine fails after the change: the old report is kept (70)", c8.updates[1].report.chars, 70)
expect("engine fails after the change: the buttons still update", flags(c8.updates[1].controls), "1111")

-- 11i. the card does not get buttons in a book it cannot measure
reset()
local p9 = pagePlugin(fakeDoc({ L1 }), { rolling = false })
p9.ui.rolling = nil
p9:showPage()
expect("a book that does not reflow: no card at all", shown[1] and shown[1].is_infomessage, true)

-- 11j. reading the page raises after the change (here KOReader's clean-up of the text does): the layout did
-- change, so it is logged, the old numbers stay on the card, and the buttons still update
reset()
local p10, _u10, d10 = layoutPlugin()
p10:showPage()
local c10 = shown[1]
local util_module = require("util")
local real_clean = util_module.cleanupSelectedText
util_module.cleanupSelectedText = function() error("clean boom") end
c10.opts.on_control("margins_more")
util_module.cleanupSelectedText = real_clean
expect("a measurement that raises: the layout did change", show(d10.configurable.h_page_margins), "25,25")
expect("a measurement that raises: one warning", #warns, 1)
expect("a measurement that raises: the warning says what failed", warns[1] and tostring(warns[1][1]), "linelength: could not read the lines of this page:")
expect("a measurement that raises: the card is redrawn once", #c10.updates, 1)
expect("a measurement that raises: with the old numbers (70)", c10.updates[1].report.chars, 70)
expect("a measurement that raises: the buttons still update", flags(c10.updates[1].controls), "1111")

-- 11k. currentLayout never raises: it says nil when KOReader does not tell the layout
for label, conf in pairs({ ["none"] = false, ["no margins"] = { font_size = 22 }, ["margins as text"] = { h_page_margins = { "1", "2" }, font_size = 22 } }) do
    local pl = pagePlugin(conf and layoutBook(conf, function() return { L1 } end) or fakeDoc({ L1 }))
    local ok_layout, layout = pcall(pl.currentLayout, pl)
    expect("currentLayout (" .. label .. ") does not raise", ok_layout, true)
    expect("currentLayout (" .. label .. ") is nil", layout, nil)
end
local pl_ok = layoutPlugin()
local good_layout = pl_ok:currentLayout()
expect("currentLayout reads the margins", good_layout and good_layout.margins[1] .. "," .. good_layout.margins[2], "10,10")
expect("currentLayout reads the size", good_layout and good_layout.size, 22)

-- 11k2. Nothing in the tests above drew the page: the books there are rendered when the layout changes
expect("no page was drawn by the tests that use a fully rendered book", draws.n, 0)

-- 11n. A book that KOReader renders only when it next DRAWS it (partial rerendering, on by default for EPUBs with
-- several chapters): right after a change the lines are still the old layout, and the first measurement is one change
-- behind. The plugin draws the page (KOReader's paint renders it) and measures again until two measurements agree.
-- Here `rendered` is the layout the page was last drawn with; the paint brings it up to date.
local function layoutTexts(c)
    local longest = 70 + (10 - c.h_page_margins[1]) - 3 * (c.font_size - 22)
    return { ("w"):rep(longest - 11), ("b"):rep(longest), ("c"):rep(longest - 25) }
end
local function copyLayout(c) return { h_page_margins = { c.h_page_margins[1], c.h_page_margins[2] }, font_size = c.font_size } end
local function delayedPlugin(delayed, texts_for)
    local conf = { h_page_margins = { 10, 10 }, font_size = 22 }
    local rendered = copyLayout(conf)
    texts_for = texts_for or layoutTexts
    -- a book that is rendered when drawn shows the layout it was last drawn with; a fully rendered one shows the new one at once
    local doc = layoutBook(conf, function() return texts_for(delayed and rendered or conf) end)
    rawset(doc, "isRerenderingDelayed", function() return delayed end)
    local function render() rendered.h_page_margins, rendered.font_size = { conf.h_page_margins[1], conf.h_page_margins[2] }, conf.font_size end
    draws.n, draws.hook, draws.last, repaints.n, repaints.hook = 0, render, nil, 0, render
    buffers.created, buffers.raises = {}, false
    local events = {}
    local ui = { menu = newMenu(), highlight = newHighlight(), document = doc, rolling = {} }
    ui.view = { paintTo = function(_self, bb, x, y)
        draws.n = draws.n + 1
        draws.last = { bb = bb, x = x, y = y }
        if draws.hook then draws.hook() end
    end }
    function ui:handleEvent(ev)
        local parts = {}
        for i, a in ipairs(ev.args) do parts[i] = show(a) end
        events[#events + 1] = ev.name .. ":" .. table.concat(parts, ":")
        if ev.name == "ConfigChange" then conf[ev.args[1]] = ev.args[2] end
        return true
    end
    actions = {}
    return makePlugin({ document = {}, ui = ui }), doc, rendered, events, conf
end

reset()
local dp, ddoc, drendered, devents = delayedPlugin(true)
dp:showPage()
local dcard = shown[1]
expect("delayed: the card opens with the page as drawn (70)", dcard.opts.report.chars, 70)
expect("delayed: opening the card draws nothing", draws.n, 0)
dcard.opts.on_control("margins_more") -- 10 -> 25: longest 55 once drawn; until then still 70
expect("delayed: the card shows the NEW layout (55), not the old one (70)", dcard.updates[1].report.chars, 55)
expect("delayed: the other two lines are the new layout's too (44 and 30)", dcard.updates[1].report.lines[2].chars .. "," .. dcard.updates[1].report.lines[3].chars, "44,30")
expect("delayed: the page was drawn twice (the first measurement was stale, the second agreed with the third)", draws.n, 2)
expect("delayed: one redraw of the card", #dcard.updates, 1)
dcard.opts.on_control("text_more") -- 22 -> 23: 55 - 3 = 52
expect("delayed: the next step is right too (52), not one behind (55)", dcard.updates[2].report.chars, 52)
expect("delayed: two more draws for it", draws.n, 4)
dcard.opts.on_control("margins_less") -- 25 -> 10: 70 - 3 = 67
expect("delayed: and the next (67)", dcard.updates[3].report.chars, 67)
expect("delayed: 67 is Comfortable", dcard.updates[3].report.tier.id, "comfortable")

-- Accept measures again. Something changed under the card (the page as drawn is now another one): the full card has to show it
local before_accept, draws_before = #dcard.updates, draws.n
ddoc.configurable.font_size = 24; drendered.font_size = 24 -- 70 - 6 = 64 with margins 10
local events_before = #devents
dcard.opts.on_control("accept")
expect("accept: the card is redrawn once", #dcard.updates, before_accept + 1)
expect("accept: with what the page holds now (64), not what it held at the last step (67)", dcard.updates[#dcard.updates].report.chars, 64)
expect("accept: the buttons and steppers are given too", dcard.updates[#dcard.updates].values.size .. "," .. flags(dcard.updates[#dcard.updates].controls), "24,1111")
expect("accept: it changes nothing in the book", #devents, events_before)
expect("accept: a book that is rendered when drawn gets its page drawn first", draws.n > draws_before, true)

-- not delayed: nothing is drawn, the change is already in the lines
reset()
local np, _ndoc, _nr, nevents = delayedPlugin(false)
np:showPage()
local ncard = shown[1]
ncard.opts.on_control("margins_more")
expect("not delayed: the card shows the new layout (55)", ncard.updates[1].report.chars, 55)
expect("not delayed: the page is not drawn by the plugin", draws.n, 0)
ncard.opts.on_control("accept")
expect("not delayed: accept measures again too (55)", ncard.updates[2].report.chars, 55)
expect("not delayed: and draws nothing", draws.n, 0)

-- asking KOReader whether the rendering is delayed fails: treated as not delayed, the card still updates
reset()
local fp, fdoc = delayedPlugin(true)
rawset(fdoc, "isRerenderingDelayed", function() error("no such thing") end)
fp:showPage()
local fcard = shown[1]
fcard.opts.on_control("margins_more")
expect("delayed? raises: the card is still redrawn", #fcard.updates, 1)
expect("delayed? raises: nothing is drawn", draws.n, 0)
expect("delayed? raises: no warning (it is a question, not a failure)", #warns, 0)

-- a page that never holds still (every draw changes it): bounded, 3 draws, the last measurement is shown
reset()
local sp, sdoc, srendered = delayedPlugin(true)
sp:showPage()
local scard = shown[1]
local flip = 0
draws.hook = function() flip = flip + 1; srendered.font_size = 22 + flip end -- another size every draw
scard.opts.on_control("margins_more")
expect("never settles: stops after 3 draws", draws.n, 3)
expect("never settles: the card is redrawn once, with the last measurement (font 25 -> 70 - 10 - 9 = 51 with margins 25)", scard.updates[1].report.chars, 70 + (10 - 10) - 3 * (25 - 22))
expect("never settles: one redraw", #scard.updates, 1)
expect("never settles: one buffer for the three draws, given back", #buffers.created .. "/" .. (buffers.created[1] and buffers.created[1].freed or "none"), "1/1")
expect("never settles: nothing on the screen", repaints.n, 0)

-- the longest line stays the same but the other lines move: that is not settled yet (the lines are compared, not
-- just the longest)
reset()
local lp2 = delayedPlugin(true, function(c)
    if c.font_size == 22 then return { ("w"):rep(59), ("b"):rep(70), ("c"):rep(45) } end
    return { ("w"):rep(65), ("b"):rep(70), ("c"):rep(40) }
end)
lp2:showPage()
local lcard2 = shown[1]
expect("same longest line: the card opens with the lines as drawn (59 and 45 behind the 70)", lcard2.opts.report.lines[2].chars .. "," .. lcard2.opts.report.lines[3].chars, "59,45")
lcard2.opts.on_control("text_more")
expect("same longest line, other lines move: the card shows the settled lines (65 and 40)", lcard2.updates[1].report.lines[2].chars .. "," .. lcard2.updates[1].report.lines[3].chars, "65,40")
expect("same longest line, other lines move: so a second draw was needed to see it hold", draws.n, 2)
-- the same lines but in other places (the page moved by a line): not settled either
reset()
local lp3, _d3, r3 = delayedPlugin(true, function(c)
    if c.font_size == 22 then return { ("w"):rep(59), ("b"):rep(70), ("c"):rep(45) } end
    return { ("c"):rep(45), ("w"):rep(59), ("b"):rep(70) }
end)
lp3:showPage()
local lcard3 = shown[1]
expect("same lengths in other places: before, the longest is line 2", lcard3.opts.report.lines[1].number, 2)
lcard3.opts.on_control("text_more")
expect("same lengths in other places: the card shows the settled places (the longest is line 3)", lcard3.updates[1].report.lines[1].number, 3)
expect("same lengths in other places: a second draw was needed", draws.n, 2)

-- the page has one more line after the draw (the first lines are the same): not settled either, the lengths of the
-- lists are compared too
reset()
local lp4 = delayedPlugin(true, function(c)
    if c.font_size == 22 then return { ("b"):rep(70), ("w"):rep(59) } end
    return { ("b"):rep(70), ("w"):rep(59), ("c"):rep(45) }
end)
lp4:showPage()
local lcard4 = shown[1]
expect("one more line after the draw: before, two lines are listed", #lcard4.opts.report.lines, 2)
lcard4.opts.on_control("text_more")
expect("one more line after the draw: the card lists three", #lcard4.updates[1].report.lines, 3)
expect("one more line after the draw: a second draw was needed", draws.n, 2)

-- the page is empty once it is drawn (a change that pushed the text off it): the old numbers stay, and two empty
-- measurements in a row count as settled (no draws without end)
reset()
local lp5 = delayedPlugin(true, function(c)
    if c.font_size == 22 then return { ("b"):rep(70), ("w"):rep(59), ("c"):rep(45) } end
    return {}
end)
lp5:showPage()
local lcard5 = shown[1]
lcard5.opts.on_control("text_more")
expect("an empty page after the draw: the card is redrawn once", #lcard5.updates, 1)
expect("an empty page after the draw: the old numbers stay (70)", lcard5.updates[1].report.chars, 70)
expect("an empty page after the draw: settled after 2 draws, not 3", draws.n, 2)

-- measuring raises while settling (here KOReader's clean-up of the text does): logged, the old numbers stay, the card
-- is still redrawn
reset()
local rp = delayedPlugin(true)
rp:showPage()
local rcard = shown[1]
local util_real = require("util").cleanupSelectedText
require("util").cleanupSelectedText = function() error("clean boom") end
rcard.opts.on_control("margins_more")
require("util").cleanupSelectedText = util_real
expect("settling with a page that cannot be read: one warning", #warns, 1)
expect("settling with a page that cannot be read: the old numbers stay (70)", rcard.updates[1].report.chars, 70)
expect("settling with a page that cannot be read: the card is redrawn", #rcard.updates, 1)
expect("settling with a page that cannot be read: nothing was drawn (it failed on the first measurement)", draws.n, 0)
-- the page can be read at first and fails after the draw: the old numbers stay as well
reset()
local rp2 = delayedPlugin(true)
rp2:showPage()
local rcard2 = shown[1]
local calls = 0
require("util").cleanupSelectedText = function(...) calls = calls + 1; if calls > 4 then error("late boom") end return util_real(...) end
draws.hook = function() calls = 100 end
rcard2.opts.on_control("margins_more")
require("util").cleanupSelectedText = util_real
expect("a page that fails after the draw: one warning", #warns, 1)
expect("a page that fails after the draw: the old numbers stay", rcard2.updates[1].report.chars, 70)
expect("a page that fails after the draw: the buffer is still given back", #buffers.created .. "/" .. (buffers.created[1] and buffers.created[1].freed or "none"), "1/1")

-- Cancel on the shrunk card (revert) also gets the settled page
reset()
local cp, cdoc, crendered = delayedPlugin(true)
cp:showPage()
local ccard = shown[1]
ccard.opts.on_control("margins_more")
ccard.opts.on_control("text_more")
expect("revert (delayed): before, the card shows margins 25 / size 23 (52)", ccard.updates[2].report.chars, 52)
ccard.opts.on_control("revert")
expect("revert (delayed): back to the start's 70, not one behind (52)", ccard.updates[3].report.chars, 70)
expect("revert (delayed): the steppers show 10 and 22", ccard.updates[3].values.margins .. "," .. ccard.updates[3].values.size, "10,22")
-- Cancel on the full card (cancel) closes the card: nothing is measured, so nothing is drawn
local draws_cancel = draws.n
ccard.opts.on_control("margins_more")
local draws_step = draws.n
ccard.opts.on_control("cancel")
expect("cancel (delayed): the card is closing, so the page is not drawn for a measurement", draws.n, draws_step)
draws.hook = nil

-- 11o. Settling puts nothing on the screen: the page is drawn (by the reader's own paint) into a buffer of its own
do
reset()
local op = delayedPlugin(true)
op:showPage()
local ocard = shown[1]
ocard.opts.on_control("margins_more") -- 10 -> 25: 55 once drawn
expect("off screen: the new layout is measured (55)", ocard.updates[1].report.chars, 55)
expect("off screen: nothing was drawn on the screen", repaints.n, 0)
expect("off screen: the page was drawn twice by the reader's paint (to see it hold)", draws.n, 2)
expect("off screen: into one buffer for the whole settle", #buffers.created, 1)
local ob = buffers.created[1]
expect("off screen: the buffer is as big as the screen", ob.w .. "x" .. ob.h, "1264x1680")
expect("off screen: and of the screen's type", ob.type, "the screen's type")
expect("off screen: painted at the top left", draws.last.x .. "," .. draws.last.y, "0,0")
expect("off screen: into that buffer", draws.last.bb, ob)
expect("off screen: and the buffer is given back, once", ob.freed, 1)
ocard.opts.on_control("text_more")
expect("off screen: the next tap gets a buffer of its own, given back too", #buffers.created .. "/" .. buffers.created[2].freed, "2/1")
ocard.opts.on_control("accept")
expect("off screen: so does accept", #buffers.created .. "/" .. buffers.created[3].freed, "3/1")
expect("off screen: still nothing on the screen after three redraws of the card", repaints.n, 0)
ocard.opts.on_control("margins_more")
ocard.opts.on_control("cancel") -- the card closes: nothing is measured, so no buffer
expect("off screen: cancel (full) makes no buffer", #buffers.created, 4)

-- a book that is rendered by the time the change returns: no buffer at all
reset()
local op2 = delayedPlugin(false)
op2:showPage()
shown[1].opts.on_control("margins_more")
expect("fully rendered: no buffer is made", #buffers.created, 0)
expect("fully rendered: nothing is drawn, on or off the screen", draws.n .. "/" .. repaints.n, "0/0")

-- no reader view to ask: the page is drawn on the screen, as KOReader would, and the numbers are right
reset()
local op3 = delayedPlugin(true)
op3:showPage()
op3.ui.view = nil
shown[1].opts.on_control("margins_more")
expect("no reader view: the numbers are right (55)", shown[1].updates[1].report.chars, 55)
expect("no reader view: the page was drawn on the screen (twice)", repaints.n, 2)
expect("no reader view: no buffer", #buffers.created, 0)
expect("no reader view: no warning (nothing went wrong)", #warns, 0)

-- the reader's paint raises: one warning, the rest of the settle draws on the screen, the numbers are right, the buffer is given back
reset()
local op4 = delayedPlugin(true)
op4:showPage()
op4.ui.view.paintTo = function() error("paint boom") end
shown[1].opts.on_control("margins_more")
expect("paint raises: the numbers are right (55)", shown[1].updates[1].report.chars, 55)
expect("paint raises: one warning for the settle", #warns, 1)
expect("paint raises: then the page is drawn on the screen (twice)", repaints.n, 2)
expect("paint raises: the buffer was given back", buffers.created[1].freed, 1)

-- no buffer to be had (out of memory): one warning, drawn on the screen, the numbers are right
reset()
local op5 = delayedPlugin(true)
op5:showPage()
buffers.raises = true
shown[1].opts.on_control("margins_more")
expect("no buffer: the numbers are right (55)", shown[1].updates[1].report.chars, 55)
expect("no buffer: one warning", #warns, 1)
expect("no buffer: drawn on the screen (twice)", repaints.n, 2)
expect("no buffer: and nothing was created", #buffers.created, 0)
buffers.raises = false
end

-- 11l. pageValues: what the steppers show. nil when the layout is not known; two numbers when the sides differ
local pl_v = layoutPlugin({ h_page_margins = { 10, 14 }, font_size = 22.5 })
local v_ok, v = pcall(pl_v.pageValues, pl_v)
expect("pageValues does not raise", v_ok, true)
expect("pageValues: different margins show both, a half size shows the half", v and (v.margins .. "," .. v.size), "10/14,22.5")
for label, conf in pairs({ ["none"] = false, ["no margins"] = { font_size = 22 }, ["margins as text"] = { h_page_margins = { "1", "2" }, font_size = 22 } }) do
    local pl = pagePlugin(conf and layoutBook(conf, function() return { L1 } end) or fakeDoc({ L1 }))
    local ok_values, values = pcall(pl.pageValues, pl)
    expect("pageValues (" .. label .. ") does not raise", ok_values, true)
    expect("pageValues (" .. label .. ") is nil", values, nil)
end

-- 11m. Cancel: everything is put back as it was when the card opened (the card closes itself, so there is nothing
-- to measure or redraw)
reset()
local p11, _u11, d11, e11 = layoutPlugin()
p11:showPage()
local c11 = shown[1]
c11.opts.on_control("margins_more") -- 10 -> 25
c11.opts.on_control("text_more") -- 22 -> 23
local n11, redraws11 = #e11, #c11.updates
c11.opts.on_control("cancel")
expect("cancel: margins first, then the size, as at the start", table.concat(e11, "|", n11 + 1),
    "ConfigChange:h_page_margins:10,10|SetPageHorizMargins:10,10|ConfigChange:font_size:22|SetFontSize:22")
expect("cancel: the book is as it was", show(d11.configurable.h_page_margins) .. "/" .. d11.configurable.font_size, "10,10/22")
expect("cancel: the card is not redrawn (it is closing)", #c11.updates, redraws11)
-- the same card, asked again: nothing is left to put back
n11 = #e11
c11.opts.on_control("cancel")
expect("cancel twice: nothing more is set", #e11, n11)

-- only the margins changed: only the margins are set back
reset()
local p12, _u12, d12, e12 = layoutPlugin()
p12:showPage()
local c12 = shown[1]
c12.opts.on_control("margins_more")
local n12 = #e12
c12.opts.on_control("cancel")
expect("cancel with only the margins changed: only the margins", table.concat(e12, "|", n12 + 1), "ConfigChange:h_page_margins:10,10|SetPageHorizMargins:10,10")

-- nothing was changed: nothing is set
reset()
local p13, _u13, _d13, e13 = layoutPlugin()
p13:showPage()
shown[1].opts.on_control("cancel")
expect("cancel with nothing changed: no event", #e13, 0)
expect("cancel with nothing changed: no redraw", #shown[1].updates, 0)

-- after a revert everything is as it was: Cancel has nothing to do
reset()
local p14, _u14, _d14, e14 = layoutPlugin()
p14:showPage()
local c14 = shown[1]
c14.opts.on_control("text_more")
c14.opts.on_control("revert")
local n14 = #e14
c14.opts.on_control("cancel")
expect("cancel after revert: no event", #e14, n14)

-- changed by hand back to the original, then Cancel: the layout is the same, so nothing is set
reset()
local p15, _u15, _d15, e15 = layoutPlugin()
p15:showPage()
local c15 = shown[1]
c15.opts.on_control("text_more") -- 22 -> 23
c15.opts.on_control("text_less") -- 23 -> 22
local n15 = #e15
c15.opts.on_control("cancel")
expect("cancel when the layout is already the original: no event", #e15, n15)

-- the old Undo id does nothing even with something to put back (Undo was removed: Cancel on the shrunk card does it)
reset()
local p17, _u17, d17, e17 = layoutPlugin()
p17:showPage()
local c17 = shown[1]
c17.opts.on_control("margins_more")
local n17, redraws17 = #e17, #c17.updates
c17.opts.on_control("undo")
expect("the old undo id sets nothing", #e17, n17)
expect("the old undo id does not redraw", #c17.updates, redraws17)
expect("the old undo id leaves the layout alone", show(d17.configurable.h_page_margins), "25,25")
-- Cancel still finds the layout from before, so the unknown id did not clear it
c17.opts.on_control("cancel")
expect("cancel after the old undo id: margins put back", show(d17.configurable.h_page_margins), "10,10")

-- the reader fails while putting it back: logged, no error reaches KOReader
reset()
local p16, u16, _d16 = layoutPlugin()
p16:showPage()
local c16 = shown[1]
c16.opts.on_control("margins_more")
u16.fail_event = true
local cancel_ok = pcall(c16.opts.on_control, "cancel")
expect("cancel with a failing reader: no error escapes", cancel_ok, true)
expect("cancel with a failing reader: it is logged", #warns, 1)

local function tests_autotune()
    local AutoTune = require("linelength/autotune")
    -- The auto-tune loop, run against a book that is simulated: the counts of the pages, the layout,
    -- and the number of times the layout was changed. What the loop does with them is the plugin's.
    local function tuneBook(opts)
        opts = opts or {}
        local tuned = LineLength:new{ document = {}, ui = { menu = newMenu(), highlight = newHighlight() } }
        tuned:init()
        local margins = opts.margins or { 40, 40 }
        local measured = opts.measure
        local applied = {}
        tuned.currentLayout = function() return { margins = { margins[1], margins[2] }, size = 22 } end
        -- The layout the book really has follows what was applied to it, or the measurements would
        -- always be the ones of the first layout.
        tuned.applyLayout = function(_self, new_margins)
            applied[#applied + 1] = new_margins
            margins = { new_margins[1], new_margins[2] }
        end
        tuned.measureSample = function()
            local value = measured(#applied, margins)
            if value == nil then return nil, "error" end
            return { median = value, values = { value }, min = value, max = value, total = 100 }
        end
        local settings = {
            band_min = 56, band_max = 60, target = 58,
            margin_min = 20, margin_max = 50, max_chars_per_step = 6,
        }
        for key, value in pairs(opts.settings or {}) do settings[key] = value end
        return tuned:autoTune(settings), applied
    end

    -- The book starts at a margin outside the bounds: both margins come back inside them.
    local result, applied = tuneBook({
        margins = { 30, 80 },
        measure = function() return 58 end,
    })
    expect("an uneven layout out of the bounds is pulled back in", #applied > 0, true)
    expect("both margins are set", applied[1] and applied[1][1] == applied[1][2], true)
    expect("and they stay inside the bounds", applied[1][1] >= 20 and applied[1][1] <= 50, true)
    expect("the book is reported as tuned", result and result.chars ~= nil, true)

    -- The book cannot be measured again after the margins moved: no count is reported, and the
    -- margins go back to where they were, so a failed tune leaves the book as the reader had it.
    result, applied = tuneBook({
        margins = { 40, 40 },
        measure = function(measure_count)
            if measure_count == 0 then return 75 end -- too long: the loop moves the margins
            return nil -- and then the book cannot be measured any more
        end,
    })
    expect("a book that cannot be measured again has no count", result and result.chars, nil)
    expect("and nothing is reported as changed", result and result.changed, false)
    expect("the margins are put back where they were", applied[#applied] and applied[#applied][1], 40)
    expect("and back on both sides", applied[#applied] and applied[#applied][2], 40)

    -- The book can be measured but the band is out of reach: the lines stay too long at every margin,
    -- so the margins go as far as they can and stop at the bound, and the count that is left is the
    -- one of that last layout, outside the band.
    result, applied = tuneBook({
        margins = { 30, 30 },
        measure = function(_calls, current) return 120 - current[1] end,
    })
    expect("a book whose band is out of reach moves the margins", #applied > 0, true)
    expect("it stops at the bound", applied[#applied][1], 50)
    expect("a book whose band is out of reach still reports a count", type(result and result.chars), "number")
    expect("and the count is outside the band", AutoTune.inBand(result.chars), false)
    -- The count is the one of the last layout, not the one of the layout the book started with: the
    -- two differ here, since the margins moved from 30 to 50.
    expect("the count is the one of the last layout", result.chars, 120 - applied[#applied][1])

    -- The band is the auto-tune's own, so a bag of settings cannot move it: a book that measures 58
    -- is inside it even when the rest of the settings say otherwise.
    result, applied = tuneBook({
        margins = { 40, 40 },
        settings = { band_min = 65, band_max = 70, target = 68 },
        measure = function() return 58 end,
    })
    expect("the band is the auto-tune's own", #applied, 0)
    expect("and its count is reported", result and result.chars, 58)
    expect("nothing is reported as changed", result and result.changed, false)

    -- The same book with the default band is out of it, so the margins move.
    result, applied = tuneBook({
        margins = { 40, 40 },
        measure = function() return 68 end,
    })
    expect("the same book with the default band is tuned", #applied > 0, true)
    expect("and it is reported as changed", result and result.changed, true)
end

local function tests_sample()
    -- 12. a sample of pages: the page on screen first, the other pages drawn off screen, the reader put back.
    local function sampleBook(opts)
        opts = opts or {}
        -- A different length per line, and the lines of the page come from the document, so a
        -- measurement of the wrong page is caught instead of passing on the same numbers.
        local lines = opts.lines or { ("w"):rep(60), ("x"):rep(55), ("y"):rep(50) }
        local doc = fakeDoc(lines, { raises = opts.raises, per_page = opts.per_page })
        doc.pages = opts.pages or 100
        doc.current = opts.current or 1
        doc.gotos = {}
        function doc:getPageCount() return self.pages end
        function doc:getCurrentPage() return self.current end
        function doc:gotoPage(page)
            self.gotos[#self.gotos + 1] = page
            self.current = page
            -- The lines of the page are the lines of the page the reader is on now: a fixture that
            -- kept the lines of the first page would measure the wrong page and pass on its numbers.
            self:setPage(page)
        end
        doc:setPage(doc.current)
        if opts.no_page_count then
            doc.getPageCount = nil
        end
        local ui = { menu = newMenu(), highlight = newHighlight(), document = doc, rolling = {},
            view = { paintTo = function(_self, bb)
            bb.painted = (bb.painted or 0) + 1
            doc.drawn = (doc.drawn or 0) + 1
        end } }
        -- the reader answers a page turn the way ReaderRolling does: the document moves and the page is
        -- the one it is on, which is also the page the walk comes back to
        function ui:handleEvent(ev)
            doc.tried = doc.tried or {}
            doc.tried[#doc.tried + 1] = ev.name .. ":" .. tostring(ev.args[1])
            if opts.goto_raises then error("goto boom") end
            if ev.name == "GotoPage" then
                doc:gotoPage(ev.args[1])
                return true
            end
        end
        return makePlugin({ document = {}, ui = ui }), ui, doc
    end

    local function pageTurns(doc)
        local t = {}
        for i, page in ipairs(doc.gotos) do t[i] = tostring(page) end
        return table.concat(t, ",")
    end

    -- 12a. 6 first, 6 middle and 6 last pages; the page on screen is measured first and not visited again
    reset()
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp, _sui, sdoc = sampleBook({ pages = 100, current = 3 })
    local sample = sp:measureSample()
    expect("sample: measured", type(sample), "table")
    expect("sample: total pages", sample and sample.total, 100)
    -- The reader is on page 3, which is not one of the six sampled pages of the middle: it is left
    -- out, so that the median is the median of the sample and not of the sample and one more.
    expect("sample: the first sampled page is in the middle of the book", sample and sample.pages[1].page, 48)
    expect("sample: the sample is the six pages of the middle", #sample.values, 6)
    expect("sample: 6 pages read", sample and #sample.values, 6)
    expect("sample: only the six other pages are drawn", sdoc.drawn, 6)
    expect("sample: one buffer", #buffers.created, 1)
    expect("sample: the buffer is given back", buffers.created[1] and buffers.created[1].freed, 1)
    expect("sample: nothing is refreshed on the screen", repaints.n, 0)
    expect("sample: each page counts its longest line", sample and sample.values[1], 60)
    expect("sample: median", sample and sample.median, 60)
    expect("sample: min", sample and sample.min, 60)
    expect("sample: max", sample and sample.max, 60)
    expect("sample: 6 page turns and the way back", #sdoc.gotos, 7)
    expect("sample: back on the page it started from", sdoc.current, 3)
    expect("sample: the first sample page", sdoc.gotos[1], 48)
    expect("sample: the last sample page", sdoc.gotos[#sdoc.gotos - 1], 53)

    -- 12b. the page on screen outside the sample is measured too, and no page turn goes to a page twice
    reset()
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp2, _ui2, sdoc2 = sampleBook({ pages = 100, current = 20 })
    local sample2 = sp2:measureSample()
    expect("sample: the current page outside the sample is left out", sample2 and #sample2.values, 6)
    expect("sample: the first sampled page is in the middle of the book", sample2 and sample2.pages[1].page, 48)
    expect("sample: back where it started", sdoc2.current, 20)
    expect("sample: one page turn per sampled page, and the way back", #sdoc2.gotos, 7)

    -- 12c. a book shorter than the sample: every page once, no page turn out of the book
    reset()
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp3, _ui3, sdoc3 = sampleBook({ pages = 4, current = 1 })
    local sample3 = sp3:measureSample()
    expect("short book: every page once", sample3 and #sample3.values, 4)
    expect("short book: three page turns (pages 2 to 4) and one way back", #sdoc3.gotos, 4)
    expect("short book: the pages visited", pageTurns(sdoc3), "2,3,4,1")

    -- 12d. configured counts: 2 first, 2 middle, 2 last
    reset()
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp4, _ui4, sdoc4 = sampleBook({ pages = 50, current = 1 })
    local sample4 = sp4:measureSample({ first = 2, middle = 2, last = 2 })
    expect("configured counts: 6 pages", sample4 and #sample4.values, 6)
    expect("configured counts: the pages asked for", pageTurns(sdoc4), "2,25,26,49,50,1")

    -- 12e. a book that cannot be sampled: a reason, no crash
    reset()
    local sp5 = sampleBook({ pages = 0 })
    local nothing5, reason5 = sp5:measureSample()
    expect("no pages: nothing measured", nothing5, nil)
    expect("no pages: reason", reason5, "empty")
    reset()
    local sp6 = sampleBook({ pages = 100, no_page_count = true })
    local nothing6, reason6 = sp6:measureSample()
    expect("no page count: nothing measured", nothing6, nil)
    expect("no page count: unsupported", reason6, "unsupported")
    reset()
    local sp6b = makePlugin({ document = {}, ui = { menu = newMenu(), highlight = newHighlight(),
        document = fakeDoc({ L1 }) } })
    local nothing6b, reason6b = sp6b:measureSample()
    expect("no reader to turn pages: nothing measured", nothing6b, nil)
    expect("no reader to turn pages: unsupported", reason6b, "unsupported")

    -- A document that cannot read text by position is not a book the plugin can walk at all.
    reset()
    local sp6c, _ui6c, _sdoc6c = sampleBook({ pages = 100, current = 20 })
    sp6c.ui.document.getTextFromPositions = nil
    local nothing6c, reason6c = sp6c:measureSample()
    expect("no text by position: nothing measured", nothing6c, nil)
    expect("no text by position: unsupported", reason6c, "unsupported")

    -- 12f. the reader fails going to a page: no error escapes, the buffer is given back
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp7, _ui7 = sampleBook({ pages = 100, current = 1, goto_raises = true })
    local ok7, maybe7, reason7 = pcall(function() return sp7:measureSample() end)
    expect("goto fails: no error escapes the caller", ok7, true)
    expect("goto fails: nothing measured", maybe7, nil)
    expect("goto fails: the reason is logged as an error", reason7, "error")
    expect("goto fails: the buffer is still given back", buffers.created[1] and buffers.created[1].freed, 1)
    -- The way back is attempted even when the walk failed: the reader is not left on a sampled page.
    expect("goto fails: the reader is still sent back to its page",
        _ui7.document.tried[#_ui7.document.tried], "GotoPage:1")

    -- 12g. no page can be read: nothing measured, and the buffer is given back
    reset()
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp8 = sampleBook({ pages = 100, current = 1, raises = true })
    local sample8, reason8 = sp8:measureSample()
    expect("unreadable pages: nothing measured", sample8, nil)
    expect("unreadable pages: reason", reason8, "empty")
    expect("unreadable pages: the buffer is given back", buffers.created[1] and buffers.created[1].freed, 1)

    -- 12h. no off-screen buffer: nothing measured, and no page is ever painted on the e-ink panel
    reset()
    buffers.created, draws.n, repaints.n, buffers.raises = {}, 0, 0, true
    local sp9, _ui9, sdoc9 = sampleBook({ pages = 100, current = 1 })
    local sample9, reason9 = sp9:measureSample()
    buffers.raises = false
    expect("no buffer: nothing measured", sample9, nil)
    expect("no buffer: reason", reason9, "no_buffer")
    expect("no buffer: not one refresh of the screen", repaints.n, 0)
    expect("no buffer: the reader was not moved", #sdoc9.gotos, 0)

    -- 12i. the action and its handler reach the sample
    reset()
    local sp10 = sampleBook({ pages = 100, current = 1 })
    expect("sample action event", actions["linelength_sample"] and actions["linelength_sample"].event, "LinelengthSample")
    expect("sample event handler exists", type(sp10.onLinelengthSample), "function")
    -- The handler has to do the work: a handler that does nothing would pass a type check.
    local shown_count = 0
    sp10.showSample = function() shown_count = shown_count + 1 end
    sp10:onLinelengthSample()
    expect("the sample handler measures the book", shown_count, 1)

    -- 12j. a book whose lines differ from page to page: every page is measured on its own lines,
    -- and the reader is put back on the page it started from.
    reset()
    local sp11, _ui11, sdoc11 = sampleBook({ pages = 100, current = 1,
        per_page = function(page) return page end })
    local sample11 = sp11:measureSample()
    expect("per page: measured", type(sample11), "table")
    expect("per page: the six pages of the middle", #sample11.values, 6)
    -- Every page of the sample has lines of its own length, and the fixture makes that length the page
    -- number itself: each count is the page it came from, not the page the walk started on.
    local counts = {}
    for _i, page in ipairs(sample11.pages) do
        counts[#counts + 1] = page.chars
        expect("per page: the page is measured on its own lines", page.chars, page.page)
    end
    table.sort(counts)
    local all_different = true
    for i = 2, #counts do
        if counts[i] == counts[i - 1] then all_different = false end
    end
    expect("per page: every page counts its own lines", all_different, true)
    expect("per page: back on the page it started from", sdoc11.current, 1)

    -- 12k. the page on screen is one of the sampled pages: it is drawn and measured like the others,
    -- so a layout that was changed a moment ago cannot leave the numbers of the old layout in the
    -- sample, and the reader is still where it was.
    reset()
    buffers.created, draws.n, repaints.n = {}, 0, 0
    local sp12, _ui12, sdoc12 = sampleBook({ pages = 100, current = 50 })
    local sample12 = sp12:measureSample()
    expect("current page sampled: measured", type(sample12), "table")
    expect("current page sampled: the six pages of the middle", #sample12.values, 6)
    expect("current page sampled: the page on screen is one of them", sample12.pages[1].page, 50)
    expect("current page sampled: every sampled page is drawn", sdoc12.drawn, 6)
    expect("current page sampled: back where it started", sdoc12.current, 50)
    expect("current page sampled: nothing is refreshed on the screen", repaints.n, 0)

    -- 13. the auto-tune: the settings, the switch, and the numbers in the menu.
    G_reader_settings.data = {}
    local settings_plugin = LineLength:new{ document = {}, ui = { menu = newMenu(), highlight = newHighlight() } }
    settings_plugin:init()
    local settings = settings_plugin:settings()
    expect("the auto-tune is off by default", settings.enabled, false)
    expect("the margins start at 10", settings.margin_min, 10)
    expect("the margins end at 50", settings.margin_max, 50)


    -- The auto-tune does nothing when the reader has not asked for it. The book is opened at its start,
    -- which is the only place the tune runs.
    local auto_doc = fakeDoc({ L1, L2, L3 })
    auto_doc.current = 1
    function auto_doc:getCurrentPage() return self.current end
    local auto_plugin = LineLength:new{ document = {}, ui = { menu = newMenu(), highlight = newHighlight(),
        document = auto_doc } }
    auto_plugin:init()
    local called, tuned_with = false, nil
    auto_plugin.autoTune = function(_self, settings) called = true; tuned_with = settings end
    G_reader_settings.data = {}
    auto_plugin:onReaderReady()
    expect("the auto-tune stays off when it is not asked for", called, false)
    G_reader_settings.data = { linelength_auto_tune = true }
    auto_plugin:onReaderReady()
    expect("the auto-tune runs when it is asked for", called, true)
    expect("and it is given the margins the reader chose", tuned_with and tuned_with.margin_min, 10)

    -- The automatic tune is given the reader's margins and not the defaults: a book opened at its
    -- start is tuned with the bounds the reader set.
    G_reader_settings.data = { linelength_auto_tune = true, linelength_margin_min = 20, linelength_margin_max = 26 }
    auto_plugin:onReaderReady()
    expect("the automatic tune reads the margins from the reader", tuned_with and tuned_with.margin_min, 20)
    expect("the automatic tune reads the margins from the reader", tuned_with and tuned_with.margin_max, 26)

    -- It runs when the book is opened at its start, and nowhere else: a book picked up where it was
    -- left keeps the layout the reader is reading it with.
    local gate_doc = fakeDoc({ L1, L2, L3 })
    gate_doc.current = 1
    function gate_doc:getCurrentPage() return self.current end
    local gate_plugin = LineLength:new{ document = {}, ui = { menu = newMenu(), highlight = newHighlight(),
        document = gate_doc } }
    gate_plugin:init()
    local gate_called = false
    gate_plugin.autoTune = function() gate_called = true end
    gate_plugin:onReaderReady()
    expect("a book opened at its start is tuned", gate_called, true)
    gate_called = false
    gate_doc.current = 2
    gate_plugin:onReaderReady()
    expect("a book opened anywhere else is left alone", gate_called, false)
    G_reader_settings.data = {}

    -- The action that tunes the book now says what came of it, and says so when it could not be done.
    local tune_plugin = LineLength:new{ document = {}, ui = { menu = newMenu(), highlight = newHighlight() } }
    tune_plugin:init()
    shown = {}
    tune_plugin.autoTune = function() return { steps = 1, chars = 58, changed = true, margin = 30 } end
    tune_plugin:tuneNow()
    expect("the tune says what it did", shown[#shown].text, "Tuned to 58 characters.")
    shown = {}
    tune_plugin.autoTune = function() return { steps = 0, chars = 58, changed = false, margin = 30 } end
    tune_plugin:tuneNow()
    expect("the tune says when there was nothing to change", shown[#shown].text,
        "Already 58 characters, nothing to change.")
    shown = {}
    tune_plugin.autoTune = function() return nil end
    tune_plugin:tuneNow()
    expect("the tune says when it could not measure the book", shown[#shown].text, "Could not tune this book.")

    -- The settings menu: a switch and the numbers, each with a step of one.
    local menu = auto_plugin:settingsMenu()
    expect("the settings menu has exactly three entries", #menu, 3)
    local found_switch, found_numbers = false, 0
    for _i, item in ipairs(menu) do
        if item.text_func then
            local text = item.text_func()
            if type(text) == "string" and text:find("Auto%-tune") then
                found_switch = true
            end
        end
        if item.sub_item_table then
            found_numbers = found_numbers + 1
        end
    end
    expect("the settings menu has the switch", found_switch, true)
    expect("the settings menu has the numbers", found_numbers, 2)

    -- The switch flips the setting and keeps it.
    local before = settings_plugin:settings().enabled
    menu[1].callback()
    expect("the switch flips the setting", settings_plugin:settings().enabled, not before)
    menu[1].callback()
    expect("and flips it back", settings_plugin:settings().enabled, before)

    -- A number goes up and down by one.
    local margin_item = nil
    for _i, item in ipairs(menu) do
        if item.sub_item_table then
            local label = item.text_func()
            if label:find("Biggest margin") then margin_item = item end
        end
    end
    expect("the biggest margin is in the menu", margin_item ~= nil, true)
    local value = settings_plugin:settings().margin_max
    margin_item.sub_item_table[2].callback()
    expect("a number goes up by one", settings_plugin:settings().margin_max, value + 1)
    margin_item.sub_item_table[1].callback()
    expect("and back down", settings_plugin:settings().margin_max, value)

    -- The two ends of a pair never cross: the smallest margin cannot go past the biggest one.
    -- The menu reads the settings when it is built, so it is built again for each case.
    local function menuItem(label)
        for _i, item in ipairs(auto_plugin:settingsMenu()) do
            if item.sub_item_table and item.text_func():find(label) then return item end
        end
    end
    -- The margins.
    G_reader_settings.data = { linelength_margin_min = 50, linelength_margin_max = 50 }
    local biggest = menuItem("Biggest margin")
    expect("the biggest margin is in the menu", biggest ~= nil, true)
    biggest.sub_item_table[1].callback()
    expect("the biggest margin does not go below the smallest one", settings_plugin:settings().margin_max, 50)
    expect("and the step that would do it is not offered", biggest.sub_item_table[1].enabled_func(), false)
    G_reader_settings.data = { linelength_margin_min = 20, linelength_margin_max = 20 }
    local smallest = menuItem("Smallest margin")
    expect("the smallest margin is in the menu", smallest ~= nil, true)
    smallest.sub_item_table[2].callback()
    expect("the smallest margin does not go above the biggest one", settings_plugin:settings().margin_min, 20)
    expect("and the step that would do it is not offered", smallest.sub_item_table[2].enabled_func(), false)
    -- The settings are put back as they were.
    G_reader_settings.data = {}
end


-- 14. a drawer that could not draw off screen says so on every call, so a caller that keeps its
-- callback cannot end up painting on the panel it asked to stay off.
local function tests_drawer()
    local Measure = require("linelength/measure")
    local repaints, drawn = 0, 0
    local UIManagerStub = require("ui/uimanager")
    local real_repaint = UIManagerStub.forceRePaint
    UIManagerStub.forceRePaint = function() repaints = repaints + 1 end
    local ui = { view = { paintTo = function() drawn = drawn + 1; error("paint boom") end } }

    local draw, release = Measure.drawer(ui, true)
    expect("a strict drawer refuses a page it cannot draw off screen", draw(), false)
    expect("and it refuses again, rather than falling back to the screen", draw(), false)
    expect("and nothing was repainted", repaints, 0)
    expect("the page was attempted once and given up on", drawn, 1)
    release()

    repaints, drawn = 0, 0
    local loose_draw, loose_release = Measure.drawer(ui, false)
    expect("a drawer that may use the screen repaints instead", loose_draw(), true)
    expect("and the page was attempted once before that", drawn, 1)
    expect("the repaint was asked for", repaints, 1)
    loose_release()

    UIManagerStub.forceRePaint = real_repaint
end

tests_autotune()
tests_sample()
tests_drawer()

if failures > 0 then
    error(failures .. " main test(s) failed")
end
print("main: all tests passed")
