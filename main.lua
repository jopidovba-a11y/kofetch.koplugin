local Dashboard = require("sysmonitor_dashboard")
local Menu = require("sysmonitor_menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local AUTOSTART_SETTING_KEY = "sysmonitor_autostart"

local did_initial_takeover = false
local expect_takeover = false
local takeover_token = 0
local exiting = false

-- Marks the next FileManager "show" as the moment to take over the screen,
-- for a limited time only.
local function announceTakeover(seconds)
    expect_takeover = true
    takeover_token = takeover_token + 1

    local my_token = takeover_token

    UIManager:scheduleIn(seconds, function()
        if takeover_token == my_token then
            expect_takeover = false
        end
    end)
end

local SysMonitor = WidgetContainer:extend{
    name = "kofetch",
    is_doc_only = false,
}

function SysMonitor:init()
    if self.ui.document then
        return
    end

    self.ui.menu:registerToMainMenu(self)

    if not did_initial_takeover then
        did_initial_takeover = true

        if G_reader_settings:isTrue(AUTOSTART_SETTING_KEY) then
            announceTakeover(10)
        end
    end
end

function SysMonitor:onShow()
    if self.ui.document or not expect_takeover then
        return
    end

    expect_takeover = false

    Dashboard.show()
end

function SysMonitor:onCloseDocument()
    if not G_reader_settings:isTrue(AUTOSTART_SETTING_KEY) then
        return
    end

    if (self.ui and self.ui.tearing_down) or exiting then
        return
    end

    announceTakeover(5)
end

-- Closing or restarting KOReader also closes the document; do not take
-- over the screen while the app is exiting.
function SysMonitor:onExit()
    exiting = true

    UIManager:scheduleIn(5, function()
        exiting = false
    end)
end

SysMonitor.onRestart = SysMonitor.onExit

function SysMonitor:onCloseWidget()
    if self.ui and self.ui.tearing_down then
        return
    end

    Dashboard.close()
end

function SysMonitor:addToMainMenu(menu_items)
    menu_items.sysmonitor = Menu.build(AUTOSTART_SETTING_KEY)
end

return SysMonitor