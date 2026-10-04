local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

-- Long-press actions for the explorer rows: delete and set as home folder.
local EntryActions = {}

local function showMessage(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 3,
    })
end

-- True if the home folder is this folder or lives inside it.
local function containsHome(path)
    local home = G_reader_settings:readSetting("home_dir")

    return home ~= nil
        and (home == path or home:sub(1, #path + 1) == path .. "/")
end

-- Best-effort cleanup of the reading progress and history of a deleted book.
local function forgetBook(path)
    pcall(function()
        require("docsettings"):open(path):purge()
    end)

    pcall(function()
        require("readhistory"):removeItemByPath(path)
    end)
end

-- Returns true on success, or false and an error message.
local function deleteEntry(entry)
    local call_ok, err = pcall(function()
        if entry.is_dir then
            ffiutil.purgeDir(entry.path)
        else
            os.remove(entry.path)
        end
    end)

    -- Judge by the result: the path must be gone.
    if lfs.attributes(entry.path) then
        return false, call_ok and _("The item could not be deleted") or tostring(err)
    end

    if not entry.is_dir then
        forgetBook(entry.path)
    end

    return true
end

local function confirmDelete(entry, on_done)
    if entry.is_dir and containsHome(entry.path) then
        showMessage(_("The home folder cannot be deleted"))
        return
    end

    local question = entry.is_dir
        and _("Delete this folder and everything inside it?")
        or _("Delete this book?")

    UIManager:show(ConfirmBox:new{
        text = question .. "\n\n" .. entry.name,
        ok_text = _("Delete"),

        ok_callback = function()
            local ok, err = deleteEntry(entry)

            if not ok then
                showMessage(err)
            end

            on_done()
        end,
    })
end

local function setHome(entry, on_done)
    G_reader_settings:saveSetting("home_dir", entry.path)
    showMessage(_("Home folder set"))
    on_done()
end

-- Shows the action menu for an explorer entry. on_done() is called after
-- anything that changes the folder contents or the home folder.
function EntryActions.show(entry, on_done)
    local dialog

    local buttons = {
        {
            {
                text = _("Delete"),
                callback = function()
                    UIManager:close(dialog)
                    confirmDelete(entry, on_done)
                end,
            },
        },
    }

    if entry.is_dir then
        table.insert(buttons, {
            {
                text = _("Set as home folder"),
                callback = function()
                    UIManager:close(dialog)
                    setHome(entry, on_done)
                end,
            },
        })
    end

    dialog = ButtonDialog:new{
        title = entry.name,
        title_align = "center",
        buttons = buttons,
    }

    UIManager:show(dialog)
end

return EntryActions