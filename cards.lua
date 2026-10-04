local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ColoredTextBoxWidget = require("coloredtextboxwidget")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Paint = require("paint")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")

local ascii_art = require("ascii_art")

local Cards = {}

-- Scales a size by the screen density.
function Cards.sc(n)
    return math.floor(Device.screen:scaleBySize(n))
end

function Cards.getBattery()
    local ok, powerd = pcall(function()
        return Device:getPowerDevice()
    end)

    if ok and powerd then
        local ok2, capacity = pcall(function()
            return powerd:getCapacity()
        end)

        if ok2 and capacity then
            return capacity .. "%"
        end
    end

    return "N/D"
end

-- Returns the width of the widest line and the real height of the art,
-- measured the way it will be drawn.
local function measureArtSize(text, face_name, size, bold)
    local widest = 0
    local face = Font:getFace(face_name, size)

    for line in (text .. "\n"):gmatch("(.-)\n") do
        local w = TextWidget:new{
            text = line,
            face = face,
            bold = bold,
        }:getSize().w

        if w > widest then
            widest = w
        end
    end

    -- TextBoxWidget gives the natural (compressed) line spacing.
    local probe = TextBoxWidget:new{
        text = text,
        face = face,
        bold = bold,
        width = widest + Cards.sc(2),
    }

    return widest, probe:getSize().h
end

-- Largest font size at which the art fits in max_w x max_h.
local function pickArtFontSize(text, face_name, max_w, max_h, max_size, min_size, bold)
    for size = max_size, min_size, -1 do
        local w, h = measureArtSize(text, face_name, size, bold)

        if w <= max_w and h <= max_h then
            return size
        end
    end

    return min_size
end

local cached_art_size = nil
local cached_art_key = nil

-- Returns the card, the art widget and its height.
function Cards.buildLibraryCard(width, height)
    local pad = Cards.sc(15)

    local max_w = width - (pad * 2)
    local max_h = height

    local cache_key = max_w .. "x" .. max_h

    if cached_art_key ~= cache_key then
        cached_art_size = pickArtFontSize(
            ascii_art,
            "infont",
            max_w,
            max_h,
            Cards.sc(16),
            2,
            true
        )

        cached_art_key = cache_key
    end

    local art_w = measureArtSize(ascii_art, "infont", cached_art_size, true)

    -- Fixed pseudo-random pattern: each line is either black or dark gray.
    local line_colors = {}
    local line_count = select(2, ascii_art:gsub("\n", "")) + 1
    local pattern_seed = 12345

    for i = 1, line_count do
        local value = (i * 7919 + pattern_seed * 104729) % 1000

        if value < 500 then
            line_colors[i] = Blitbuffer.COLOR_BLACK
        else
            line_colors[i] = Blitbuffer.Color8(80)
        end
    end

    local art_widget = ColoredTextBoxWidget:new{
        text = ascii_art,
        face = Font:getFace("infont", cached_art_size),
        bold = true,
        width = art_w + Cards.sc(2),
        line_colors = line_colors,
        bgcolor = Blitbuffer.COLOR_LIGHT_GRAY,
    }

    local centered_art = CenterContainer:new{
        dimen = Geom:new{
            w = max_w,
            h = max_h,
        },

        art_widget,
    }

    local card = FrameContainer:new{
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        bordersize = 0,
        padding = pad,
        width = width,

        centered_art,
    }

    Paint.addBorder(
        card,
        Blitbuffer.COLOR_DARK_GRAY,
        Cards.sc(4),
        Cards.sc(4)
    )

    return card, art_widget, art_widget:getSize().h
end

return Cards