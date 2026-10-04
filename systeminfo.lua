local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local Version = require("version")
local util = require("ffi/util")

local SystemInfo = {}

local function readMemory()
    local mem_total, mem_free, mem_avail = "?", "?", "?"

    local file = io.open("/proc/meminfo", "r")

    if not file then
        return mem_total, mem_free, mem_avail
    end

    for line in file:lines() do
        local total = line:match("^MemTotal:%s+(%d+)%s+kB")
        local free = line:match("^MemFree:%s+(%d+)%s+kB")
        local avail = line:match("^MemAvailable:%s+(%d+)%s+kB")

        if total then
            mem_total = total
        elseif free then
            mem_free = free
        elseif avail then
            mem_avail = avail
        end

        if mem_total ~= "?" and mem_free ~= "?" and mem_avail ~= "?" then
            break
        end
    end

    file:close()

    return mem_total, mem_free, mem_avail
end

local function readFreeStorage()
    local df = io.popen("df -k /mnt/onboard 2>/dev/null")

    if not df then
        return "?"
    end

    df:read("*l") -- skip the header line

    local line = df:read("*l")
    df:close()

    -- Columns: filesystem, blocks, used, available.
    local available = line and line:match("^%S+%s+%d+%s+%d+%s+(%d+)")

    if not available then
        return "?"
    end

    return string.format("%.1f GB", tonumber(available) / 1024 / 1024)
end

local function readTemperature()
    local thermal_dir = "/sys/class/thermal"

    local ok, iterator, dir_obj = pcall(lfs.dir, thermal_dir)

    if not ok then
        return "?"
    end

    for name in iterator, dir_obj do
        if name:match("^thermal_zone") then
            local file = io.open(thermal_dir .. "/" .. name .. "/temp", "r")

            if file then
                local value = file:read("*l")
                file:close()

                local temp = tonumber(value)

                if temp then
                    return string.format("%.1f°C", temp / 1000)
                end
            end
        end
    end

    return "?"
end

local function formatDuration(seconds)
    seconds = math.floor(seconds)

    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400

    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600

    local minutes = math.floor(seconds / 60)

    if days > 0 then
        return string.format("%dd %02dh %02dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end

    return string.format("%dm", minutes)
end

local function readUptime()
    local file = io.open("/proc/uptime", "r")

    if not file then
        return "?"
    end

    local value = file:read("*l")
    file:close()

    local seconds = tonumber(value and value:match("^(%S+)"))

    return seconds and formatDuration(seconds) or "?"
end

local function readKernel()
    local uname = io.popen("uname -r 2>/dev/null")

    if not uname then
        return "?"
    end

    local value = uname:read("*l")
    uname:close()

    if value and value ~= "" then
        return value
    end

    return "?"
end

local function readKOReaderVersion()
    local ok, version = pcall(function()
        return Version:getNormalizedCurrentVersion()
    end)

    if ok and version then
        return tostring(version)
    end

    return "?"
end

-- Returns { mem_total, mem_free, mem_avail, storage, temperature }.
function SystemInfo.getMemoryInfo(home_dir)
    local mem_total, mem_free, mem_avail = readMemory()

    return {
        mem_total = mem_total,
        mem_free = mem_free,
        mem_avail = mem_avail,
        storage = readFreeStorage(home_dir),
        temperature = readTemperature(),
    }
end

-- Returns { kernel, screen, device, uptime, koreader }.
function SystemInfo.getSystemDetails(screen_size)
    return {
        kernel = readKernel(),
        screen = string.format("%dx%d", screen_size.w, screen_size.h),
        device = Device.model or "?",
        uptime = readUptime(),
        koreader = readKOReaderVersion(),
    }
end

return SystemInfo