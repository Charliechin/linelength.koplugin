-- Which pages of a book to measure, and how to summarise their measurements. Pure Lua: no KOReader
-- requires, so it is tested on a desktop Lua.
local Sample = {}

-- Six pages from the middle: the middle is body text in any book, where the first and last pages can be
-- a cover, a title page or a table of contents. The counts stay settable for a book that needs more.
Sample.DEFAULT_FIRST = 0
Sample.DEFAULT_MIDDLE = 6
Sample.DEFAULT_LAST = 0

-- Unusable settings fall back to the default; a negative count switches its segment off.
local function count(value, default)
    local n = tonumber(value)
    if n == nil then
        return default
    end
    n = math.floor(n)
    if n < 0 then
        return 0
    end
    return n
end

--- The pages to measure, ascending and without duplicates: up to `first` pages from the start,
--- `middle` pages centred on the middle of the book and `last` pages from the end. A book shorter
--- than the three counts together yields every page once.
--- @param page_count number total pages in the book
--- @param first, middle, last number|nil pages per segment; nil uses the default
--- @return table list of page numbers from 1; empty when the book has no pages
function Sample.pages(page_count, first, middle, last)
    page_count = tonumber(page_count) or 0
    page_count = math.floor(page_count)
    if page_count < 1 then
        return {}
    end
    first = count(first, Sample.DEFAULT_FIRST)
    middle = count(middle, Sample.DEFAULT_MIDDLE)
    last = count(last, Sample.DEFAULT_LAST)
    local seen, out = {}, {}
    local function add(from, n)
        if n < 1 then
            return
        end
        from = math.max(1, math.min(math.floor(from), page_count))
        local stop = math.min(from + n - 1, page_count)
        for page = from, stop do
            if not seen[page] then
                seen[page] = true
                out[#out + 1] = page
            end
        end
    end
    add(1, first)
    -- Centred on the book: 100 pages and 6 wanted gives pages 48 to 53.
    add(math.floor((page_count - middle) / 2) + 1, middle)
    add(page_count - last + 1, last)
    table.sort(out)
    return out
end

--- The median of a list of numbers: the middle one when the count is odd, the mean of the two
--- middle ones when it is even. Values that are not numbers are ignored, so one unreadable page
--- does not spoil the summary.
--- @param values table list of numbers
--- @return number|nil the median; nil when no value in the list is a number
function Sample.median(values)
    if type(values) ~= "table" then
        return nil
    end
    local sorted = {}
    for _i, value in ipairs(values) do
        local n = tonumber(value)
        if n ~= nil then
            sorted[#sorted + 1] = n
        end
    end
    if #sorted == 0 then
        return nil
    end
    table.sort(sorted)
    local middle = math.floor((#sorted + 1) / 2)
    if #sorted % 2 == 1 then
        return sorted[middle]
    end
    return (sorted[middle] + sorted[middle + 1]) / 2
end

--- The smallest and the largest number in a list, for showing how far the pages differ.
--- @param values table list of numbers
--- @return number|nil min, max; nil, nil when no value is a number
function Sample.range(values)
    if type(values) ~= "table" then
        return nil, nil
    end
    local min, max
    for _i, value in ipairs(values) do
        local n = tonumber(value)
        if n ~= nil then
            if min == nil or n < min then
                min = n
            end
            if max == nil or n > max then
                max = n
            end
        end
    end
    return min, max
end

return Sample
