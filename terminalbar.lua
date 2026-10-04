local Blitbuffer = require("ffi/blitbuffer")
local Cards = require("cards")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local TerminalBar = {}

-- Thin dark bar with one line of light text, like a terminal prompt.
-- Returns the bar and its text widget, so the text can be updated later.
function TerminalBar.build(text, width, height)
    local pad = Cards.sc(4)

    local text_widget = TextWidget:new{
        text = text,
        face = Font:getFace("DroidSansMono", Cards.sc(8)),
        fgcolor = Blitbuffer.COLOR_LIGHT_GRAY,
        max_width = width - (pad * 2),
    }

    local bar = WidgetContainer:new{
        dimen = { x = 0, y = 0, w = width, h = height },

        FrameContainer:new{
            background = Blitbuffer.Color8(80),
            bordersize = 0,
            padding = 0,
            width = width,
            height = height,

            LeftContainer:new{
                dimen = Geom:new{ w = width - (pad * 2), h = height },
                text_widget,
            },
        },
    }

    return bar, text_widget
end

return TerminalBar