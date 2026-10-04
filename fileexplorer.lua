local Blitbuffer = require("ffi/blitbuffer")
local Cards = require("cards")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Paint = require("paint")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

local TEXT_COLOR = Blitbuffer.Color8(60)

-- Row font sizes to try, largest first (scaled with Cards.sc).
local ROW_SIZES = { 14, 13, 12, 11, 10, 9, 8 }

-- Visible books per page, not counting the fixed top row. On big screens
-- the font grows past ROW_SIZES until no more than MAX rows fit.
local MIN_PREFERRED_ROWS = 4
local MAX_PREFERRED_ROWS = 7

-- Hard limit for that growth (scaled units).
local MAX_GROWN_SIZE = 40
-- Size of the page navigation row (scaled units). It only grows when the
-- row font grows past the largest size in ROW_SIZES (big screens).
local NAV_BASE_SIZE = 7

local function navFace(row_size)
    local size = NAV_BASE_SIZE

    if row_size and row_size > ROW_SIZES[1] then
        size = NAV_BASE_SIZE * row_size / ROW_SIZES[1]
    end

    return Font:getFace("cfont", Cards.sc(size))
end

local Explorer = {}

local function lineHeight(text, face, max_width)
    return TextWidget:new{
        text = text,
        face = face,
        max_width = max_width,
    }:getSize().h
end

local function entryLabel(entry)
    return (entry.is_dir and "[D] " or "[F] ") .. entry.name
end

-- Folders plus the files KOReader can open as books.
function Explorer.getEntries(path)
    local entries = {}

    -- Follow KOReader's own "Show hidden files" setting.
    local show_hidden = G_reader_settings:isTrue("show_hidden")

    local ok, iterator, dir_obj = pcall(lfs.dir, path)

    if not ok then
        return entries
    end

    for name in iterator, dir_obj do
        local skip = name == "."
            or name == ".."
            or (not show_hidden and name:sub(1, 1) == ".")

        if not skip then
            local full_path = path .. "/" .. name
            local attr_ok, attr = pcall(lfs.attributes, full_path)

            if attr_ok and attr then
                local is_dir = attr.mode == "directory"

                -- book.sdr folders hold per-book metadata.
                local is_sdr = is_dir and name:lower():match("%.sdr$") ~= nil

                if not is_sdr
                    and (is_dir or DocumentRegistry:hasProvider(full_path)) then
                    table.insert(entries, {
                        name = name,
                        is_dir = is_dir,
                        path = full_path,
                    })
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then
            return a.is_dir
        end

        return a.name:lower() < b.name:lower()
    end)

    return entries
end

function Explorer.getPage(entries, page, per_page)
    local total = #entries

    if total == 0 then
        return {}, 1
    end

    local total_pages = math.ceil(total / per_page)

    page = math.max(1, math.min(page, total_pages))

    local first = ((page - 1) * per_page) + 1
    local last = math.min(first + per_page - 1, total)

    local result = {}

    for i = first, last do
        table.insert(result, entries[i])
    end

    return result, total_pages
end

-- Fixed first row: ".." in any folder, or a shortcut back to the library
-- at the filesystem root, where ".." no longer exists.
local function buildTopRow(path, home_path)
    if path ~= "/" then
        local parent = path:match("^(.*)/[^/]+$")

        if parent then
            if parent == "" then
                parent = "/"
            end

            return {
                text = "[D] ..",
                entry = { name = "..", is_dir = true, path = parent, shortcut = true },
            }
        end
    end

    if home_path and home_path ~= path then
        return {
            text = "[D] ~ Home",
            entry = { name = "Home", is_dir = true, path = home_path, shortcut = true },
        }
    end

    return nil
end

local function pickRowFont(entries_h, row_spacing, reserved_rows, text_w)
    -- Visible book rows at a given font size.
    local function measure(size)
        local face = Font:getFace("DroidSansMono", Cards.sc(size))
        local height = lineHeight("[D] Ag", face, text_w)
        local rows = math.floor(entries_h / (height + row_spacing))
            - reserved_rows

        return face, height, rows
    end

    local size = ROW_SIZES[1]
    local face, height, rows = measure(size)

    if rows > MAX_PREFERRED_ROWS then
        while rows > MAX_PREFERRED_ROWS and size < MAX_GROWN_SIZE do
            size = size + 1
            face, height, rows = measure(size)
        end

        return face, height, size
    end

    -- If no size leaves room for the minimum, keep the one that fits most.
    local best_face, best_h, best_size, best_rows

    for _, candidate in ipairs(ROW_SIZES) do
        local f, h, r = measure(candidate)

        if r >= MIN_PREFERRED_ROWS then
            return f, h, candidate
        end

        if not best_rows or r > best_rows then
            best_face, best_h, best_size, best_rows = f, h, candidate, r
        end
    end

    return best_face, best_h, best_size
end
-- Returns the "◀ page/total ▶" row and the page counter widget.
local function buildNavigationRow(page, total_pages, text_w, face)
    local prev_widget = TextWidget:new{
        text = "◀",
        face = face,
        fgcolor = TEXT_COLOR,
    }

    local page_widget = TextWidget:new{
        text = page .. "/" .. total_pages,
        face = face,
        fgcolor = TEXT_COLOR,
    }

    local next_widget = TextWidget:new{
        text = "▶",
        face = face,
        fgcolor = TEXT_COLOR,
    }

    local free_w = text_w
        - prev_widget:getSize().w
        - page_widget:getSize().w
        - next_widget:getSize().w

    local side_gap = math.max(0, math.floor(free_w / 2))

    local group = HorizontalGroup:new{
        align = "center",

        prev_widget,
        HorizontalSpan:new{ width = side_gap },
        page_widget,
        HorizontalSpan:new{ width = side_gap },
        next_widget,
    }

    return group, page_widget
end

local ExplorerWidget = InputContainer:extend{}

function ExplorerWidget:init()
    self.path = self.initial_path
    self.home_path = self.initial_path
    self.page = 1

    self:refresh()
end

function ExplorerWidget:refresh()
    self.entries = Explorer.getEntries(self.path)

    local pad = Cards.sc(15)
    local gap = Cards.sc(6)
    local row_spacing = Cards.sc(2)

    local width = self.width
    local text_w = width - (pad * 2)
    local nav_face = navFace(nil)

    local top_row = buildTopRow(self.path, self.home_path)
    self.has_parent_row = top_row ~= nil

    local reserved_rows = top_row and 1 or 0

    local nav_h = lineHeight("◀ 1/1 ▶", nav_face, text_w)
    local available_h = self.height - (pad * 2)
    local entries_h = available_h - (nav_h + gap)

        local row_face, row_h, row_size =
        pickRowFont(entries_h, row_spacing, reserved_rows, text_w)

    -- Big screen: the rows grew past ROW_SIZES, so the navigation row grows
    -- with them and the rows are fitted again in the space that is left.
    if row_size > ROW_SIZES[1] then
        nav_face = navFace(row_size)
        nav_h = lineHeight("◀ 1/1 ▶", nav_face, text_w)
        entries_h = available_h - (nav_h + gap)

        row_face, row_h =
            pickRowFont(entries_h, row_spacing, reserved_rows, text_w)
    end

    local possible_rows = math.floor(entries_h / (row_h + row_spacing))
        self.per_page = math.max(
        1,
        math.min(possible_rows - reserved_rows, MAX_PREFERRED_ROWS)
    )

    local page_entries, total_pages =
        Explorer.getPage(self.entries, self.page, self.per_page)

    self.total_pages = total_pages
    self.page = math.min(self.page, total_pages)

    local children = {}
    local y = pad

    self.touch_zones = {}
    self.row_text_widgets = {}

    local nav_group, page_widget =
        buildNavigationRow(self.page, self.total_pages, text_w, nav_face)

    local nav_real_h = nav_group:getSize().h

    self.navigation_zone = { y = y, h = nav_real_h }
    self.page_widget = page_widget

    table.insert(children, nav_group)
    table.insert(children, VerticalSpan:new{ width = gap })

    y = y + nav_real_h + gap

    local function addRow(text, entry, bold)
        local text_widget = TextWidget:new{
            text = text,
            face = row_face,
            max_width = text_w,
            fgcolor = TEXT_COLOR,
            bold = bold or false,
        }

        -- Fixed-size row, so every page has the exact same geometry.
        table.insert(children, FrameContainer:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            bordersize = 0,
            padding = 0,
            width = text_w,
            height = row_h,

            text_widget,
        })

        table.insert(children, VerticalSpan:new{ width = row_spacing })

        table.insert(self.row_text_widgets, text_widget)

        table.insert(self.touch_zones, {
            y = y,
            h = row_h + row_spacing,
            entry = entry,
        })

        y = y + row_h + row_spacing
    end

    if top_row then
        addRow(top_row.text, top_row.entry, true)
    end

    for i = 1, self.per_page do
        local entry = page_entries[i]

        addRow(entry and entryLabel(entry) or "", entry)
    end

    -- Region repainted on a page change: the page counter plus all rows.
    self.page_refresh_y = self.navigation_zone.y
    self.page_refresh_h = math.max(1, y - self.navigation_zone.y)

    local content = FrameContainer:new{
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        bordersize = 0,
        padding = 0,
        width = width - (pad * 2),
        height = available_h,

        VerticalGroup:new{
            align = "left",
            unpack(children),
        },
    }

    local outer = FrameContainer:new{
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        bordersize = 0,
        padding = pad,
        width = width,
        height = self.height,

        content,
    }

    local fixed_outer = WidgetContainer:new{
        dimen = { x = 0, y = 0, w = width, h = self.height },

        outer,
    }

    if self.on_path_change then
        self.on_path_change(self.path)
    end

    self[1] = Paint.addBorder(
        fixed_outer,
        Blitbuffer.COLOR_DARK_GRAY,
        Cards.sc(4),
        Cards.sc(4)
    )
end

function ExplorerWidget:updatePage(new_page)
    new_page = math.max(1, math.min(new_page, self.total_pages))

    if new_page == self.page then
        return false
    end

    self.page = new_page

    local page_entries =
        Explorer.getPage(self.entries, self.page, self.per_page)

    self.page_widget:setText(self.page .. "/" .. self.total_pages)

    -- The fixed top row does not change with the page.
    local first_row = self.has_parent_row and 2 or 1

    for i = 1, self.per_page do
        local index = first_row + i - 1
        local entry = page_entries[i]

        self.row_text_widgets[index]:setText(entry and entryLabel(entry) or "")
        self.touch_zones[index].entry = entry
    end

    return true
end

function ExplorerWidget:onPreviousPage()
    if self.page > 1 and self:updatePage(self.page - 1) then
        return "page"
    end

    return false
end

function ExplorerWidget:onNextPage()
    if self.page < self.total_pages and self:updatePage(self.page + 1) then
        return "page"
    end

    return false
end

function ExplorerWidget:onEntry(entry)
    if not entry then
        return false
    end

    if entry.is_dir then
        self.path = entry.path
        self.page = 1

        self:refresh()

        return "full"
    end

    if self.on_open_file then
        self.on_open_file(entry.path)
    end

    return false
end

-- Entry shown at a vertical position inside the card, or nil.
function ExplorerWidget:entryAt(y)
    for _, zone in ipairs(self.touch_zones) do
        if y >= zone.y and y < zone.y + zone.h then
            return zone.entry
        end
    end

    return nil
end

-- Rebuilds the list (e.g. after a delete), keeping the current page, and
-- picks up a home folder changed in the settings.
function ExplorerWidget:reload()
    self.home_path = G_reader_settings:readSetting("home_dir") or self.home_path
    self:refresh()
end

function ExplorerWidget:onTapAt(x, y)
    local navigation = self.navigation_zone

    if navigation
        and y >= navigation.y
        and y < navigation.y + navigation.h then

        if x < self.width / 3 then
            return self:onPreviousPage()
        elseif x > (self.width * 2) / 3 then
            return self:onNextPage()
        end

        return false
    end

    return self:onEntry(self:entryAt(y))
end

function Explorer.measureMinHeight(width)
    local pad = Cards.sc(15)
    local gap = Cards.sc(6)
    local row_spacing = Cards.sc(2)
    local text_w = width - (pad * 2)

    local nav_h = lineHeight(
        "◀ 1/1 ▶",
        Font:getFace("DroidSansMono", Cards.sc(9)),
        text_w
    )

    local row_h = lineHeight(
        "[D] Ag",
        Font:getFace("cfont", Cards.sc(10)),
        text_w
    )

    return (pad * 2) + nav_h + gap + (row_h + row_spacing) * 2
end

function Explorer.build(path, width, height, on_open_file, on_path_change)
    return ExplorerWidget:new{
        initial_path = path,
        width = width,
        height = height,
        on_open_file = on_open_file,
        on_path_change = on_path_change,
    }
end

return Explorer