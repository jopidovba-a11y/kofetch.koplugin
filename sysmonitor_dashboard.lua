local Blitbuffer = require("ffi/blitbuffer")
local BottomBar = require("bottombar")
local Cards = require("cards")
local CornerTexts = require("cornertexts")
local CpuInfo = require("cpuinfo")
local Device = require("device")
local EntryActions = require("entryactions")
local FileExplorer = require("fileexplorer")
local FileManager = require("apps/filemanager/filemanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local SystemInfo = require("systeminfo")
local TerminalBar = require("terminalbar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")

local Dashboard = InputContainer:extend{}

local live_dashboard = nil

-- Share of the usable height given to card 1; cards 2 and 3 split the rest.
local CARD1_SHARE = 0.50

-- Taps and holds are the gestures that can reach the hidden FileChooser and
-- open books. They only pass through inside the top band, where the
-- KOReader menu tap zone lives.
local TOP_PASS_RATIO = 0.08

local BLOCKED_OUTSIDE_TOP = {
    tap = true,
    double_tap = true,
    hold = true,
    hold_pan = true,
    hold_release = true,
}

-- While the dashboard is visible, the FileManager keeps receiving the events
-- we do not handle (Dispatcher actions such as ToggleNightMode), but its
-- hidden FileChooser must ignore gestures so the books below cannot open.
local function lockFileManager(fm)
    fm.is_always_active = true

    local fc = fm.file_chooser

    if fc and not fc.handleEvent_blocked then
        local original_handle = fc.handleEvent
        fc.handleEvent_blocked = true

        fc.handleEvent = function(this, event)
            -- Only block while the dashboard is on screen, so a leftover
            -- override can never freeze the real FileChooser.
            if event and event.handler == "onGesture"
                and live_dashboard
                and UIManager:isWidgetShown(live_dashboard) then
                return false
            end

            return original_handle(this, event)
        end
    end
end

local function unlockFileManager(fm)
    fm.is_always_active = nil

    local fc = fm.file_chooser

    if fc then
        fc.handleEvent = nil
        fc.handleEvent_blocked = nil
    end
end

-- Opens a book like KOReader's own file browser: close the dashboard and
-- the FileManager, then start the reader.
local function openBook(dashboard, path)
    local DocumentRegistry = require("document/documentregistry")

    local ok, supported = pcall(function()
        return DocumentRegistry:hasProvider(path)
    end)

    if ok and not supported then
        UIManager:show(InfoMessage:new{
            text = _("Unsupported file type"),
            timeout = 2,
        })

        return
    end

    local ReaderUI = require("apps/reader/readerui")

    UIManager:close(dashboard)

    if FileManager.instance then
        FileManager.instance:onClose()
    end

    ReaderUI:showReader(path)
end

-- Cards 2 and 3 are sized as if the bottom bar still had its original
-- height; card 1 takes everything the (smaller) bar frees up.
-- Returns the body height of cards 1, 2 and 3.
local function computeCardBodyHeights(screen_h, bottom_bar_h, bars_h, explorer_min_h)
    local available_h = screen_h - bottom_bar_h - bars_h

    local old_bottom_bar_h = Cards.sc(20) + (Cards.sc(5) * 2)
    local reference_h = screen_h - old_bottom_bar_h - bars_h
    local reference_card1_h = math.floor(reference_h * CARD1_SHARE)

    local equal_h = math.max(
        math.floor((reference_h - reference_card1_h) / 2),
        explorer_min_h
    )

    local card1_target_h = available_h - (equal_h * 2)

    return
        math.max(1, card1_target_h - (Cards.sc(15) * 2)),
        math.max(1, equal_h),
        math.max(1, equal_h)
end

function Dashboard:onGesture(ges)
    -- Our own zones first (TapClose, Card2).
    if InputContainer.onGesture(self, ges) then
        return true
    end

    -- Zones registered in the FileManager (gestures plugin, top menu...).
    local fm = FileManager.instance

    if fm and InputContainer.onGesture(fm, ges) then
        return true
    end

    -- Consume taps and holds below the top band so they never reach the
    -- FileChooser hidden underneath.
    if BLOCKED_OUTSIDE_TOP[ges.ges] and ges.pos then
        local top_limit = Device.screen:getHeight() * TOP_PASS_RATIO

        if ges.pos.y >= top_limit then
            return true
        end
    end

    -- Swipes, pans and the rest keep reaching the FileManager, so the top
    -- menu swipe still works.
    return false
end

function Dashboard:init()
    local screen_size = Device.screen:getSize()
    self.dimen = screen_size

    self._fm = FileManager.instance

    if self._fm then
        lockFileManager(self._fm)
    end

    local close_zone_size = Cards.sc(60)
    
    
    --Top right corner tap to close the dashboard
    --Change to true in case i need it for furture tests
    local ENABLE_TAP_CLOSE = false

self.ges_events = {}

if ENABLE_TAP_CLOSE then
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = screen_size.w - close_zone_size,
                y = 0,
                w = close_zone_size,
                h = close_zone_size,
            },
        },
    }
end
    
    local bar_h = Cards.sc(15)
    local card_w = screen_size.w

    local bottom_bar = BottomBar.build(screen_size)
    local bottom_bar_h = bottom_bar:getSize().h

    local home_dir = G_reader_settings:readSetting("home_dir") or "/mnt/onboard"

    local path_bar, path_text = TerminalBar.build(home_dir, card_w, bar_h)
    local cpu_bar = TerminalBar.build("cpu@koreader~#", card_w, bar_h)

    local function onPathChange(new_path)
        path_text:setText(new_path)

        if UIManager:isWidgetShown(self) then
            UIManager:setDirty(self, "ui", Geom:new{
                x = 0,
                y = self.path_bar_y,
                w = card_w,
                h = bar_h,
            })
        end
    end

    local card1_body_h, card2_body_h, card3_body_h =
        computeCardBodyHeights(
            screen_size.h,
            bottom_bar_h,
            bar_h * 2,
            FileExplorer.measureMinHeight(card_w)
        )

    -- Set by buildCards(), read when the memory block is created below.
    local side_font_px = Cards.sc(7)

    local function buildCards()
        local card1, art_widget = Cards.buildLibraryCard(card_w, card1_body_h)

        side_font_px = CornerTexts.pickFontPx(
            card_w,
            card1:getSize().h,
            art_widget:getSize().w
        )

        local card1_with_info = CornerTexts.buildSystemBlock(
            card1,
            card_w,
            side_font_px,
            SystemInfo.getSystemDetails(screen_size)
        )

        local card2 = FileExplorer.build(
            home_dir,
            card_w,
            card2_body_h,
            function(path) openBook(self, path) end,
            onPathChange
        )

        local card3 = CpuInfo.build(card_w, card3_body_h)

        return card1_with_info, card2, card3
    end

    local card1, card2, card3 = buildCards()

    local function usedHeight()
        return card1:getSize().h
            + bar_h
            + card2:getSize().h
            + bar_h
            + card3:getSize().h
            + bottom_bar_h
    end

    -- Absorb any leftover pixels in cards 2 and 3 (never in the bottom bar).
    -- Two passes at most: the second one fixes rounding left by the first.
    for attempt = 1, 2 do
        local delta = screen_size.h - usedHeight()

        if delta == 0 then
            break
        end

        local adjust = math.floor(delta / 2)

        card2_body_h = math.max(1, card2_body_h + adjust)
        card3_body_h = math.max(1, card3_body_h + (delta - adjust))

        card1, card2, card3 = buildCards()
    end

    local card2_y = card1:getSize().h + bar_h

    self.path_bar_y = card1:getSize().h
    self.card2 = card2
    self.card2_y = card2_y
    self.card3 = card3
    self.card3_y = card2_y + card2:getSize().h + bar_h

    CpuInfo.on_refresh = function()
        if not UIManager:isWidgetShown(self) then
            return
        end

        UIManager:setDirty(self, "ui", Geom:new{
            x = 0,
            y = self.card3_y,
            w = self.card3:getSize().w,
            h = self.card3:getSize().h,
        })
    end

    self.ges_events.Card2 = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = 0,
                y = card2_y,
                w = screen_size.w,
                h = card2:getSize().h,
            },
        },
    }
    
        self.ges_events.Card2Hold = {
        GestureRange:new{
            ges = "hold",
            range = Geom:new{
                x = 0,
                y = card2_y,
                w = screen_size.w,
                h = card2:getSize().h,
            },
        },
    }

    local dashboard_content = VerticalGroup:new{
        align = "left",

        card1,
        path_bar,
        card2,
        cpu_bar,
        card3,
        bottom_bar,
    }

    -- Built last so it uses the font size of the final cards.
    local memory_overlay = CornerTexts.buildMemoryBlock(
    screen_size.w,
    side_font_px,
    SystemInfo.getMemoryInfo(home_dir)
)

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = screen_size.w,
        height = screen_size.h,

        OverlapGroup:new{
            dimen = Geom:new{
                x = 0,
                y = 0,
                w = screen_size.w,
                h = screen_size.h,
            },

            dashboard_content,
            memory_overlay,
        },
    }
end

function Dashboard:onTapClose()
    self.card2 = nil

    UIManager:close(self)

    return true
end

function Dashboard:onCard2(arg, ges)
    if not self.card2 or not ges then
        return true
    end

    local changed = self.card2:onTapAt(ges.pos.x, ges.pos.y - self.card2_y)

    if UIManager:isWidgetShown(self) then
        if changed == "page" then
            UIManager:setDirty(self, "ui", Geom:new{
                x = 0,
                y = self.card2_y + self.card2.page_refresh_y,
                w = self.card2:getSize().w,
                h = self.card2.page_refresh_h,
            })
        elseif changed == "full" then
            UIManager:setDirty(self, "ui", Geom:new{
                x = 0,
                y = self.card2_y,
                w = self.card2:getSize().w,
                h = self.card2:getSize().h,
            })
        end
    end

    return true
end

function Dashboard:reloadExplorer()
    if not self.card2 then
        return
    end

    self.card2:reload()

    if UIManager:isWidgetShown(self) then
        UIManager:setDirty(self, "ui", Geom:new{
            x = 0,
            y = self.card2_y,
            w = self.card2:getSize().w,
            h = self.card2:getSize().h,
        })
    end
end

function Dashboard:onCard2Hold(arg, ges)
    if not self.card2 or not ges then
        return true
    end

    local entry = self.card2:entryAt(ges.pos.y - self.card2_y)

    if entry and not entry.shortcut then
        EntryActions.show(entry, function()
            self:reloadExplorer()
        end)
    end

    return true
end

function Dashboard:onCloseWidget()
    self.card2 = nil

    if self._fm then
        unlockFileManager(self._fm)
        self._fm = nil
    end

    if live_dashboard == self then
        live_dashboard = nil
    end
end

local M = {}

function M.isShown()
    return live_dashboard ~= nil and UIManager:isWidgetShown(live_dashboard)
end

function M.show()
    if M.isShown() then
        return
    end

    -- A plain Lua error in init() is shown on screen instead of crashing.
    local ok, result = pcall(function()
        return Dashboard:new{}
    end)

    if not ok then
        -- init() may have locked the FileManager; onCloseWidget will never
        -- run for a dashboard that was not shown, so undo it here.
        local fm = FileManager.instance

        if fm then
            unlockFileManager(fm)
        end

        UIManager:show(InfoMessage:new{
            text = "Dashboard error:\n" .. tostring(result),
            timeout = 20,
        })

        return
    end

    live_dashboard = result

    UIManager:show(live_dashboard)
end

function M.close()
    if M.isShown() then
        UIManager:close(live_dashboard)
    end
end

return M