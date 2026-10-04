local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Cards = require("cards")
local Paint = require("paint")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")

local CpuInfo = {}

local INTERVAL_SETTING_KEY = "sysmonitor_cpu_interval"
local DEFAULT_SAMPLE_INTERVAL = 120
local MIN_SAMPLE_INTERVAL = 2
local MAX_SAMPLE_INTERVAL = 120
local INITIAL_DELAY = 1
local MAX_SAMPLES = 1800
local MAX_PROCESSES = 3
local STATS_WINDOW_SEC = 3600

local TEXT_COLOR = Blitbuffer.Color8(60)

local BLOCKS = {
    "▁", "▂", "▃", "▄",
    "▅", "▆", "▇", "█",
}

local samples = {}
local stat_samples = {}
local last_top = {}

local previous_total = nil
local previous_idle = nil
local previous_proc_times = nil

local sampling_started = false
local suspended = false

local current_text_widget = nil
local current_on_sample = nil

local sample_task = nil
local initial_sample_task = nil

CpuInfo.on_refresh = nil


local function readCpuCounters()
    local file = io.open("/proc/stat", "r")
    if not file then
        return nil
    end

    local line = file:read("*l")
    file:close()

    if not line then
        return nil
    end

    local user, nice, system, idle, iowait, irq, softirq, steal =
        line:match(
            "^cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)"
        )

    user = tonumber(user)
    nice = tonumber(nice)
    system = tonumber(system)
    idle = tonumber(idle)
    iowait = tonumber(iowait)
    irq = tonumber(irq)
    softirq = tonumber(softirq)
    steal = tonumber(steal)

    if not (
        user and nice and system and idle
        and iowait and irq and softirq and steal
    ) then
        return nil
    end

    local total =
        user
        + nice
        + system
        + idle
        + iowait
        + irq
        + softirq
        + steal

    local idle_total = idle + iowait

    return total, idle_total
end


local function readProcTimes()
    local lfs = require("libs/libkoreader-lfs")
    local result = {}

    pcall(function()
        for entry in lfs.dir("/proc") do
            local pid = tonumber(entry)

            if pid then
                local f =
                    io.open(
                        "/proc/" .. pid .. "/stat",
                        "r"
                    )

                if f then
                    local line = f:read("*l")
                    f:close()

                    if line then
                        local comm, rest =
                            line:match(
                                "^%d+%s+%((.-)%)%s+(.*)$"
                            )

                        if rest then
                            local fields = {}

                            for field in rest:gmatch("%S+") do
                                fields[#fields + 1] = field
                            end

                            local utime =
                                tonumber(fields[12])

                            local stime =
                                tonumber(fields[13])

                            if utime and stime then
                                result[pid] = {
                                    name = comm,
                                    time = utime + stime,
                                }
                            end
                        end
                    end
                end
            end
        end
    end)

    return result
end


local function topProcesses(proc_times, total_delta)
    if not previous_proc_times
        or total_delta <= 0 then
        return {}
    end

    local deltas = {}

    for pid, data in pairs(proc_times) do
        local prev = previous_proc_times[pid]

        if prev then
            local d = data.time - prev.time

            if d > 0 then
                deltas[#deltas + 1] = {
                    name = data.name,
                    cpu = 100 * d / total_delta,
                }
            end
        end
    end

    table.sort(
        deltas,
        function(a, b)
            return a.cpu > b.cpu
        end
    )

    while #deltas > MAX_PROCESSES do
        table.remove(deltas)
    end

    return deltas
end


local function updateStatSamples(usage)
    local now = os.time()

    stat_samples[#stat_samples + 1] = {
        time = now,
        usage = usage,
    }

    local cutoff = now - STATS_WINDOW_SEC
    local first_valid = 1

    for i = 1, #stat_samples do
        if stat_samples[i].time >= cutoff then
            first_valid = i
            break
        end
    end

    if first_valid > 1 then
        local new_samples = {}

        for i = first_valid, #stat_samples do
            new_samples[#new_samples + 1] =
                stat_samples[i]
        end

        stat_samples = new_samples
    end
end


local function getCpuStats()
    if #stat_samples == 0 then
        return nil, nil
    end

    local total = 0
    local peak = 0

    for _, sample in ipairs(stat_samples) do
        total = total + sample.usage

        if sample.usage > peak then
            peak = sample.usage
        end
    end

    local average = total / #stat_samples
    average = math.floor(average + 0.5)

    return average, peak
end


local function calculateCpuUsage()
    if suspended then
        return
    end

    local total, idle = readCpuCounters()
    local proc_times = readProcTimes()

    if not total then
        previous_proc_times = proc_times
        return
    end

    if previous_total and previous_idle then
        local total_delta = total - previous_total
        local idle_delta = idle - previous_idle

        if total_delta > 0 then
            local usage =
                100 * (1 - idle_delta / total_delta)

            usage =
                math.max(
                    0,
                    math.min(100, usage)
                )

            usage = math.floor(usage + 0.5)

            samples[#samples + 1] = usage

            while #samples > MAX_SAMPLES do
                table.remove(samples, 1)
            end

            updateStatSamples(usage)

            local top =
                topProcesses(
                    proc_times,
                    total_delta
                )

            last_top = top

            if current_text_widget
                and current_on_sample
                and not suspended then

                current_on_sample(
                    usage,
                    top
                )
            end
        end
    end

    previous_total = total
    previous_idle = idle
    previous_proc_times = proc_times
end


local function makeText(
    text,
    face,
    width,
    bold
)
    local widget =
        TextWidget:new{
            text = text,
            face = face,
            bold = bold or false,
            fgcolor = TEXT_COLOR,
        }

    return LeftContainer:new{
        dimen = {
            w = width,
            h = widget:getSize().h,
        },
        widget,
    }
end


local function makeCenteredText(
    text,
    face,
    width,
    bold
)
    local widget =
        TextWidget:new{
            text = text,
            face = face,
            bold = bold or false,
            fgcolor = TEXT_COLOR,
        }

    local widget_width =
        widget:getSize().w

    local widget_height =
        widget:getSize().h

    local container =
        WidgetContainer:new{
            dimen = {
                x = math.floor(
                    (width - widget_width) / 2
                ),
                y = 0,
                w = widget_width,
                h = widget_height,
            },

            widget,
        }

    return WidgetContainer:new{
        dimen = {
            x = 0,
            y = 0,
            w = width,
            h = widget_height,
        },

        container,
    }
end


local function historyGraph(
    width,
    face
)
    if #samples == 0 then
        return "--"
    end

    local probe =
        TextWidget:new{
            text = "█",
            face = face,
        }

    local char_width =
        probe:getSize().w

    if not char_width
        or char_width <= 0 then
        return "--"
    end

    local max_bars =
        math.floor(
            width / char_width
        )

    max_bars =
        math.max(
            1,
            math.min(
                MAX_SAMPLES,
                max_bars
            )
        )

    local first =
        math.max(
            1,
            #samples - max_bars + 1
        )

    -- Find the highest CPU usage
    -- among the samples currently visible.
    local max_usage = 0

    for i = first, #samples do
        if samples[i] > max_usage then
            max_usage = samples[i]
        end
    end

    -- Keep at least a 25% scale so that
    -- very low CPU usage is still visible.
    local max_scale =
        math.max(
            25,
            max_usage
        )

    local bars = {}

    for i = first, #samples do
        local level =
            math.floor(
                samples[i] / max_scale
                * (#BLOCKS - 1)
            ) + 1

        level =
            math.max(
                1,
                math.min(
                    #BLOCKS,
                    level
                )
            )

        bars[#bars + 1] =
            BLOCKS[level]
    end

    return table.concat(bars)
end

local function buildProcessColumn(
    width,
    face,
    top
)
    local rows = {}

    for _, p in ipairs(top) do
        local name = p.name

        if #name > 24 then
            name = name:sub(1, 24)
        end

        rows[#rows + 1] =
            makeCenteredText(
                string.format(
                    "%s: %.1f%%",
                    name,
                    p.cpu
                ),
                face,
                width,
                false
            )
    end

    while #rows < 3 do
        rows[#rows + 1] =
            makeCenteredText(
                "",
                face,
                width,
                false
            )
    end

    return VerticalGroup:new{
        align = "center",

        rows[1],
        rows[2],
        rows[3],
    }
end


local function buildStatsColumn(
    width,
    face
)
    local average, peak =
        getCpuStats()

    local idle =
        average
        and (100 - average)
        or nil

    local average_text =
        average
        and string.format(
            "Average: %d%%",
            average
        )
        or "Average: --"

    local peak_text =
        peak
        and string.format(
            "Peak: %d%%",
            peak
        )
        or "Peak: --"

    local idle_text =
        idle
        and string.format(
            "Idle: %d%%",
            idle
        )
        or "Idle: --"

    return VerticalGroup:new{
        align = "center",

        makeCenteredText(
            average_text,
            face,
            width,
            false
        ),

        makeCenteredText(
            peak_text,
            face,
            width,
            false
        ),

        makeCenteredText(
            idle_text,
            face,
            width,
            false
        ),
    }
end

local cached_font_size = nil
local cached_font_key = nil

-- Largest font size at which all the card text fits, so the card looks
-- right on any screen shape. Checks height (7 text lines plus spacing)
-- and the width of the longest process line.
local MAX_FONT_SIZE = 24
local MIN_FONT_SIZE = 8

local function pickFontSize(width, height)
    local key = width .. "x" .. height

    if cached_font_key == key then
        return cached_font_size
    end

    local pad = Cards.sc(15)
    local inner_w = width - (pad * 2)
    local inner_h = height - (pad * 2)
    local column_w = math.floor((inner_w - Cards.sc(8)) / 2)

    -- 15 characters is the longest process name Linux reports.
    local widest_line = "WWWWWWWWWWWWWWW: 100.0%"

    local chosen = MIN_FONT_SIZE

    for size = MAX_FONT_SIZE, MIN_FONT_SIZE, -1 do
        local face = Font:getFace("DroidSansMono", Cards.sc(size))

        local line_h = TextWidget:new{
            text = "Ag",
            face = face,
        }:getSize().h

        local line_w = TextWidget:new{
            text = widest_line,
            face = face,
        }:getSize().w

        -- 7 text lines plus the fixed gaps, with a small safety margin.
        local needed_h = (line_h * 7) + Cards.sc(16) + Cards.sc(4)

        if needed_h <= inner_h and line_w <= column_w then
            chosen = size
            break
        end
    end

    cached_font_key = key
    cached_font_size = chosen

    return chosen
end

local function buildContent(
    width,
    height,
    usage,
    top
)
    local pad = Cards.sc(15)

        local face =
        Font:getFace(
            "DroidSansMono",
            Cards.sc(pickFontSize(width, height))
        )

    local inner_width =
        width - pad * 2

    local usage_widget =
        TextWidget:new{
            text =
                usage
                and string.format(
                    "Usage: %d%%",
                    usage
                )
                or "Usage: --",

            face = face,
            bold = true,
            fgcolor = TEXT_COLOR,
        }

    local history_label =
        TextWidget:new{
            text = "History:",
            face = face,
            bold = true,
            fgcolor = TEXT_COLOR,
        }

    local graph_text =
        historyGraph(
            inner_width,
            face
        )

    local graph_text_widget =
        TextWidget:new{
            text = graph_text,
            face = face,
            fgcolor = TEXT_COLOR,
        }

    local graph_width =
        graph_text_widget:getSize().w

    local graph_height =
        graph_text_widget:getSize().h

    local graph_x =
        math.floor(
            (inner_width - graph_width) / 2
        )

    local graph_container =
        WidgetContainer:new{
            dimen = {
                x = graph_x,
                y = 0,
                w = graph_width,
                h = graph_height,
            },

            graph_text_widget,
        }

    local graph_widget =
        WidgetContainer:new{
            dimen = {
                x = 0,
                y = 0,
                w = inner_width,
                h = graph_height,
            },

            graph_container,
        }

    local separator_gap =
        Cards.sc(8)

    local column_width =
        math.floor(
            (inner_width - separator_gap) / 2
        )

    local process_header =
        makeCenteredText(
            "Top processes:",
            face,
            column_width,
            true
        )

    local stats_header =
        makeCenteredText(
            "CPU stats (1h):",
            face,
            column_width,
            true
        )

    local process_body =
        buildProcessColumn(
            column_width,
            face,
            top
        )

    local stats_body =
        buildStatsColumn(
            column_width,
            face
        )

    local process_column_height =
        process_header:getSize().h
        + Cards.sc(4)
        + process_body:getSize().h

    local stats_column_height =
        stats_header:getSize().h
        + Cards.sc(4)
        + stats_body:getSize().h

    local columns_height =
        math.max(
            process_column_height,
            stats_column_height
        )

    local process_column =
        WidgetContainer:new{
            dimen = {
                x = 0,
                y = 0,
                w = column_width,
                h = columns_height,
            },

            VerticalGroup:new{
                align = "center",

                process_header,

                VerticalSpan:new{
                    width = Cards.sc(4),
                },

                process_body,
            },
        }

    local stats_column =
        WidgetContainer:new{
            dimen = {
                x = 0,
                y = 0,
                w = column_width,
                h = columns_height,
            },

            VerticalGroup:new{
                align = "center",

                stats_header,

                VerticalSpan:new{
                    width = Cards.sc(4),
                },

                stats_body,
            },
        }

    local vertical_line =
        FrameContainer:new{
            background =
                TEXT_COLOR,

            bordersize = 0,

            width = Cards.sc(1),
            height = columns_height,

            VerticalSpan:new{
                width = Cards.sc(1),
            },
        }

    local half_gap =
        math.floor(
            separator_gap / 2
        )

    local remaining_gap =
        separator_gap - half_gap

    local columns =
        HorizontalGroup:new{
            align = "top",

            process_column,

            VerticalSpan:new{
                width = half_gap,
            },

            vertical_line,

            VerticalSpan:new{
                width = remaining_gap,
            },

            stats_column,
        }

    local column_spacing =
        Cards.sc(8)

    local column_top_spacing =
        math.floor(
            column_spacing / 2
        )

    local column_bottom_spacing =
        column_spacing
        - column_top_spacing

    return VerticalGroup:new{
        align = "left",

        usage_widget,

        VerticalSpan:new{
            width = Cards.sc(4),
        },

        history_label,

        graph_widget,

        VerticalSpan:new{
            width = column_top_spacing,
        },

        columns,

        VerticalSpan:new{
            width = column_bottom_spacing,
        },
    }
end


-- Seconds between samples, clamped to the allowed range.
local function getSampleInterval()
    local value = tonumber(G_reader_settings:readSetting(INTERVAL_SETTING_KEY))

    if not value then
        return DEFAULT_SAMPLE_INTERVAL
    end

    return math.max(
        MIN_SAMPLE_INTERVAL,
        math.min(MAX_SAMPLE_INTERVAL, math.floor(value))
    )
end

local function scheduleNextSample()
    UIManager:unschedule(sample_task)
    UIManager:scheduleIn(getSampleInterval(), sample_task)
end

CpuInfo.getSampleInterval = getSampleInterval
CpuInfo.INTERVAL_SETTING_KEY = INTERVAL_SETTING_KEY
CpuInfo.MIN_SAMPLE_INTERVAL = MIN_SAMPLE_INTERVAL
CpuInfo.MAX_SAMPLE_INTERVAL = MAX_SAMPLE_INTERVAL
CpuInfo.DEFAULT_SAMPLE_INTERVAL = DEFAULT_SAMPLE_INTERVAL

-- Called after the setting changes so the new interval applies right away
-- instead of after the current wait finishes.
function CpuInfo.applyInterval()
    if sampling_started and not suspended then
        scheduleNextSample()
    end
end

sample_task = function()
    if suspended then
        return
    end

    calculateCpuUsage()

    if suspended or not sampling_started then
        return
    end

    scheduleNextSample()
end

initial_sample_task = function()
    if suspended then
        return
    end

    calculateCpuUsage()

    if suspended or not sampling_started then
        return
    end

    scheduleNextSample()
end

-- Stops background sampling (used when the plugin is disabled).
function CpuInfo.stop()
    sampling_started = false

    UIManager:unschedule(initial_sample_task)
    UIManager:unschedule(sample_task)
end

local function startSampling()
    if sampling_started then return end

    sampling_started = true
    suspended = false

    UIManager:unschedule(initial_sample_task)
    UIManager:unschedule(sample_task)

    calculateCpuUsage()

    if suspended then return end

    UIManager:scheduleIn(INITIAL_DELAY, initial_sample_task)
end


function CpuInfo.build(width, height)
    startSampling()

    local pad = Cards.sc(15)

    local content =
        buildContent(
            width,
            height,
            samples[#samples],
            last_top
        )

    local content_widget =
        WidgetContainer:new{
            dimen = {
                x = 0,
                y = 0,
                w = width,
                h = height,
            },

            FrameContainer:new{
                background =
                    Blitbuffer.COLOR_LIGHT_GRAY,

                bordersize = 0,
                padding = pad,

                width = width,
                height = height,

                content,
            },
        }

    local card =
        Paint.addBorder(
            content_widget,
            Blitbuffer.COLOR_DARK_GRAY,
            Cards.sc(4),
            Cards.sc(4)
        )

    current_text_widget =
        content_widget

    current_on_sample =
        function(usage, top)
            if suspended then
                return
            end

            if current_text_widget
                ~= content_widget then
                return
            end

            local new_content =
                buildContent(
                    width,
                    height,
                    usage,
                    top
                )

            content_widget[1] =
                FrameContainer:new{
                    background =
                        Blitbuffer.COLOR_LIGHT_GRAY,

                    bordersize = 0,
                    padding = pad,

                    width = width,
                    height = height,

                    new_content,
                }

            if CpuInfo.on_refresh
                and not suspended then
                CpuInfo.on_refresh()
            end
        end

    local widget =
        WidgetContainer:new{
            dimen = {
                x = 0,
                y = 0,
                w = width,
                h = height,
            },

            card,
        }

    widget.onSuspend =
    function()
        suspended = true

        UIManager:unschedule(
            initial_sample_task
        )

        UIManager:unschedule(
            sample_task
        )

        previous_total = nil
        previous_idle = nil
        previous_proc_times = nil
    end
    widget.onResume =
        function()
            suspended = false

            UIManager:unschedule(
                initial_sample_task
            )

            UIManager:unschedule(
                sample_task
            )

            if not sampling_started then
                return
            end

            -- Take the baseline now, like startSampling does, so the
            -- sample taken INITIAL_DELAY seconds later is a real one.
            calculateCpuUsage()

            UIManager:scheduleIn(
                INITIAL_DELAY,
                initial_sample_task
            )
        end

        widget.onCloseWidget =
        function()
            -- Keep sampling in the background so the history also covers
            -- the time spent reading; only the screen updates stop.
            if current_text_widget == content_widget then
                current_text_widget = nil
                current_on_sample = nil
            end
        end
    return widget
end


return CpuInfo

       