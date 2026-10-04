local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Cards = require("cards")

-- Corner texts of card 1: memory info (top-left) and system info
-- (bottom-right), drawn on top of the ASCII art.
local CornerTexts = {}

local TEXT_COLOR = Blitbuffer.Color8(80)

-- Font size limits, in scaled units (Cards.sc).
local MAX_SIZE = 20
local MIN_SIZE = 5

-- A 5-line block may use at most this share of the card's height.
local HEIGHT_SHARE = 0.3

local cache_key = nil
local cache_px = nil

-- Largest font (in pixels) at which the widest line fits beside the ASCII
-- art and the 5-line block stays within HEIGHT_SHARE of the card height.
function CornerTexts.pickFontPx(card_w, card_h, art_w)
    -- Uncomment to force the old fixed size while testing:
    -- return Cards.sc(7)

    local key = card_w .. "x" .. card_h .. "x" .. art_w

    if cache_key == key then
        return cache_px
    end

    local edge_margin = Cards.sc(10)   -- distance from the card edge to the text
    local art_overlap = Cards.sc(10)   -- how far the text may enter the art box

    local side_w =
        math.floor((card_w - art_w) / 2)
        - edge_margin
        + art_overlap

    -- Monospace font: any 22 characters measure the same, and the longest
    -- line ("KOReader: 202607000000") has 22.
    local widest_line = string.rep("W", 22)

    local chosen = Cards.sc(MIN_SIZE)

    for px = Cards.sc(MAX_SIZE), Cards.sc(MIN_SIZE), -1 do
        local face = Font:getFace("DroidSansMono", px)

        local size = TextWidget:new{
            text = widest_line,
            face = face,
        }:getSize()

        if size.w <= side_w
            and size.h * 5 <= card_h * HEIGHT_SHARE then
            chosen = px
            break
        end
    end

    cache_key = key
    cache_px = chosen

    return chosen
end

local function makeLine(text, face)
    return TextWidget:new{
        text = text,
        face = face,
        fgcolor = TEXT_COLOR,
    }
end

-- Bottom-right block. Returns card1 with the block drawn over it.
-- details = { kernel, screen, device, uptime, koreader }
function CornerTexts.buildSystemBlock(card1, card_w, font_px, details)
    local face = Font:getFace("DroidSansMono", font_px)

    local system_info =
        VerticalGroup:new{
            align = "right",

            makeLine("Kernel:   " .. details.kernel, face),
            makeLine("Screen:   " .. details.screen, face),
            makeLine("Device:   " .. details.device, face),
            makeLine("Uptime:   " .. details.uptime, face),
            makeLine("KOReader: " .. details.koreader, face),
        }

    local info_w = card_w - Cards.sc(10)
    local info_h = system_info:getSize().h

    local positioned =
        WidgetContainer:new{
            dimen = Geom:new{
                x = 0,
                y = card1:getSize().h - info_h - Cards.sc(5),
                w = info_w,
                h = info_h,
            },

            RightContainer:new{
                dimen = Geom:new{
                    x = 0,
                    y = 0,
                    w = info_w,
                    h = info_h,
                },

                system_info,
            },
        }

    return OverlapGroup:new{
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = card_w,
            h = card1:getSize().h,
        },

        card1,
        positioned,
    }
end

-- Top-left block. Returns a widget to place over the whole dashboard.
-- info = { mem_total, mem_free, mem_avail, storage, temperature }
function CornerTexts.buildMemoryBlock(screen_w, font_px, info)
    local face = Font:getFace("DroidSansMono", font_px)

    local memory_widget =
        VerticalGroup:new{
            align = "left",

            makeLine("MemTotal: " .. info.mem_total .. " kB", face),
            makeLine("MemFree:  " .. info.mem_free .. " kB", face),
            makeLine("MemAvail: " .. info.mem_avail .. " kB", face),
            makeLine("Storage:  " .. info.storage, face),
            makeLine("Temp:     " .. info.temperature, face),
        }

    return WidgetContainer:new{
        dimen = Geom:new{
            x = Cards.sc(10),
            y = Cards.sc(8),
            w = screen_w - Cards.sc(20),
            h = memory_widget:getSize().h,
        },

        memory_widget,
    }
end

return CornerTexts