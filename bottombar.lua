local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextWidget = require("ui/widget/textwidget")
local Paint = require("paint")

local Cards = require("cards")

local BottomBar = {}

function BottomBar.build(screen_size)
    local pad = Cards.sc(4)
    local row_h = Cards.sc(16)

    local inner_w = screen_size.w - (pad * 2)

    local bottom_bar = FrameContainer:new{
    background = Blitbuffer.COLOR_LIGHT_GRAY,
    bordersize = 0,
    padding = pad,
    width = screen_size.w,

        HorizontalGroup:new{
            LeftContainer:new{
                dimen = Geom:new{
                    w = inner_w / 2,
                    h = row_h,
                },

                CenterContainer:new{
                    dimen = Geom:new{
                        w = inner_w / 2,
                        h = row_h,
                    },

                    TextWidget:new{
                        text = "Battery: " .. Cards.getBattery(),
                        face = Font:getFace("DroidSansMono", Cards.sc(8)),
                        bold = true,
                        fgcolor = Blitbuffer.Color8(60), 
                    },
                },
            },

            RightContainer:new{
                dimen = Geom:new{
                    w = inner_w / 2,
                    h = row_h,
                },

                CenterContainer:new{
                    dimen = Geom:new{
                        w = inner_w / 2,
                        h = row_h,
                    },

                    TextWidget:new{
                        text = os.date("%H:%M  %d %b"),
                        face = Font:getFace("DroidSansMono", Cards.sc(8)),
                        bold = true,
                        fgcolor = Blitbuffer.Color8(60), 
                    },
                },
            },
        },
    }

           return bottom_bar
end

return BottomBar