local CpuInfo = require("cpuinfo")
local Dashboard = require("sysmonitor_dashboard")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Menu = {}

local function buildEnableItem(autostart_key)
    return {
        text = _("ENABLE_KOFETCH"),

        checked_func = function()
            return G_reader_settings:isTrue(autostart_key)
        end,

        callback = function(touchmenu_instance)
            -- Close the top menu first, so it cannot stay open (and catch
            -- the next tap) once the dashboard appears or disappears.
            if touchmenu_instance and touchmenu_instance.closeMenu then
                touchmenu_instance:closeMenu()
            end

            if G_reader_settings:isTrue(autostart_key) then
                G_reader_settings:saveSetting(autostart_key, false)
                Dashboard.close()
                CpuInfo.stop()
            else
                G_reader_settings:saveSetting(autostart_key, true)
                Dashboard.show()
            end
        end,
    }
end

local function showIntervalDialog(touchmenu_instance)
    local min_value = CpuInfo.MIN_SAMPLE_INTERVAL
    local max_value = CpuInfo.MAX_SAMPLE_INTERVAL
    local dialog

    local function applyValue()
        local value = tonumber(dialog:getInputText())

        if not value or value < min_value or value > max_value then
            -- Keep the dialog open so the value can be corrected.
            UIManager:show(InfoMessage:new{
                text = string.format(
                    _("Enter a number between %d and %d"),
                    min_value,
                    max_value
                ),
                timeout = 3,
            })

            return
        end

        G_reader_settings:saveSetting(
            CpuInfo.INTERVAL_SETTING_KEY,
            math.floor(value)
        )

        CpuInfo.applyInterval()
        UIManager:close(dialog)

        if touchmenu_instance then
            touchmenu_instance:updateItems()
        end
    end

    dialog = InputDialog:new{
        title = _("CPU update interval (seconds)"),
        input = tostring(CpuInfo.getSampleInterval()),
        input_type = "number",

        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Set"),
                    is_enter_default = true,
                    callback = applyValue,
                },
            },
        },
    }

    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function buildIntervalItem()
    return {
        keep_menu_open = true,

        text_func = function()
            return _("CPU_INTERVAL")
                .. " (" .. CpuInfo.getSampleInterval() .. " s)"
        end,

        callback = showIntervalDialog,
    }
end

local function buildResetItem()
    return {
        keep_menu_open = true,

        text_func = function()
            return _("RESET_CPU_INTERVAL")
                .. " (" .. CpuInfo.DEFAULT_SAMPLE_INTERVAL .. " s)"
        end,

        -- Greyed out when the interval is already the default.
        enabled_func = function()
            return CpuInfo.getSampleInterval() ~= CpuInfo.DEFAULT_SAMPLE_INTERVAL
        end,

        callback = function(touchmenu_instance)
            G_reader_settings:saveSetting(
                CpuInfo.INTERVAL_SETTING_KEY,
                CpuInfo.DEFAULT_SAMPLE_INTERVAL
            )

            CpuInfo.applyInterval()

            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }
end

-- Returns the "KoFetch" entry for KOReader's main menu.
function Menu.build(autostart_key)
    return {
        text = _("Kofetch"),
        sorting_hint = "filemanager_settings",

        sub_item_table = {
            buildEnableItem(autostart_key),
            buildIntervalItem(),
            buildResetItem(),
        },
    }
end

return Menu