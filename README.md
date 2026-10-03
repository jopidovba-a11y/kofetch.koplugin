# KOFETCH

A Linux/system-monitor-style dashboard for KOReader, inspired by tools such as neofetch and Linux terminal interfaces.

The plugin replaces the standard Koreader homepage with a system-monitor-style dashboard containing device information, a built-in file browser, and a CPU monitor.
<table>
<tr>
<td align="center">
<a href="https://github.com/user-attachments/assets/c3295c1d-b1d9-42a5-9357-a7ad0a6a357b">
<img src="https://github.com/user-attachments/assets/c3295c1d-b1d9-42a5-9357-a7ad0a6a357b" alt="1" width="250">
</a>
</td>
<td align="center">
<a href="https://github.com/user-attachments/assets/e5092346-5453-43b1-9056-32710ece82ce">
<img src="https://github.com/user-attachments/assets/e5092346-5453-43b1-9056-32710ece82ce" alt="2" width="250">
</a>
</td>
<td align="center">
<a href="https://github.com/user-attachments/assets/27369662-d91b-438a-9f48-e141110e3fc5">
<img src="https://github.com/user-attachments/assets/27369662-d91b-438a-9f48-e141110e3fc5" alt="3" width="250">
</a>
</td>
</tr>
<tr>
<td align="center">
<a href="https://github.com/user-attachments/assets/9a23f7f6-09b8-41d4-bcc3-58e8f5185d8e">
<img src="https://github.com/user-attachments/assets/9a23f7f6-09b8-41d4-bcc3-58e8f5185d8e" alt="4" width="250">
</a>
</td>
<td align="center">
<a href="https://github.com/user-attachments/assets/367ad5ca-a81b-4ef6-b6fb-74ffd78b4306">
<img src="https://github.com/user-attachments/assets/367ad5ca-a81b-4ef6-b6fb-74ffd78b4306" alt="5" width="250">
</a>
</td>
<td align="center">
<a href="https://github.com/user-attachments/assets/ef90ab0b-1333-4f62-84c3-deb0745aa430">
<img src="https://github.com/user-attachments/assets/ef90ab0b-1333-4f62-84c3-deb0745aa430" alt="6" width="250">
</a>
</td>
</tr>
</table>

## Features

### System information

The first card displays information about the device and Koreader, including:

* Device model
* KOReader version
* Screen resolution
* Kernel version
* System uptime
* Available RAM
* Available storage
* Device temperature

### File browser

The second card provides a lightweight file browser directly inside the dashboard.

It allows you to:

* Browse folders
* Navigate back to the parent directory
* Return to the home directory
* Open supported books directly
* Change pages when a directory contains many files
* Long-press files or folders to delete or set directory as home folder.
* Hidden files are shown according to your Koreader setting's. 

### CPU monitor

The third card displays:

* Current CPU usage
* A CPU usage histogram
* Top 3 CPU-consuming processes
* Average CPU usage
* Peak CPU usage
* Idle CPU percentage

The default sampling interval is **2 minutes**. This can be changed through the plugin settings.

The histogram keeps up to 1800 samples in memory. CPU statistics use a rolling window of up to **1 hour**.

For example, with the default 120-second interval, the statistics contain approximately 30 samples covering the most recent hour once the window is fully populated.

> Setting the sampling interval to 2 seconds can be useful for watching the histogram update in real time, but it is intended mainly for testing or demonstration. A longer interval is recommended for normal e-reader use.

## Custom ASCII Art

Kofetch allows you to replace the ASCII art displayed in Card 1 with your own artwork.

The default artwork is stored inside kofetch.koplugin as:

```text
ascii_art.lua
```

To use your own ASCII art:

1. Open `ascii_art.lua` with any code editor.
2. Replace the existing ASCII art between the `[=[` and `]=]` markers with your own.
3. Save the file and restart Kofetch.

Example:

```lua
return [=[ \(0-0)/ ]=]
```

#### Tips

* Keep the `[=[` and `]=]` markers exactly as they are.
* The line break immediately after `[=[` is ignored.
* Keep the final empty line before `]=]`; it is part of the vertical layout.
* Do not include the sequence `]=]` anywhere inside your artwork, as it marks the end of the text.
* Use a monospaced ASCII art design for the best results.
* You can use any code editor to make the change; no programming knowledge is required.
* 
## Compatibility

The first realease is a **beta** plugin.

It has primarily been developed and tested on a **Kobo Clara BW** running Koreader.

Koreader supports many different devices through device-specific implementations, so some information may behave differently depending on the e-reader.

In particular, the CPU/process monitor relies on Linux `/proc` information. Devices with different system implementations or restrictions may not provide all of the same information.

If you test the plugin on another device, feedback about compatibility is very welcome.

Useful information to report:

* Device model
* KOReader version
* Which information shows `?`
* Whether the CPU monitor works
* Whether the file browser works
* Any crashes or unexpected behavior

## Android

The plugin is **not expected to provide the same functionality on Android**.

KOReader on Android runs under Android's permission and sandbox restrictions, which prevent it from accessing some of the low-level Linux information used by the CPU/process monitor.

Some parts of the dashboard may still work, but CPU and process information can be incomplete or unavailable.

A separate Android-oriented version may be possible in the future using Android APIs while keeping the same system-monitor aesthetic.

## Battery considerations

The plugin is designed with e-readers in mind.

The CPU monitor does not continuously update at a high frequency by default. The default sampling interval is **120 seconds**, reducing unnecessary CPU activity and battery consumption.

The most expensive part of a CPU sample is reading the individual process statistics from `/proc`. With the default interval, this happens relatively infrequently.

During device suspension, CPU sampling is stopped and resumes when KOReader becomes active again.

## Data persistence

CPU history is kept in memory while the Koreader session is running.

Closing the dashboard does not clear the histogram, so the history can continue accumulating while reading a book and will still be available when the dashboard is opened again.

The history is lost when KOReader itself is restarted or its Lua modules are reloaded.

This is intentional; the plugin does not continuously write CPU history to storage.

## Installation

Copy the plugin directory into KOReader's plugins directory:

```text
koreader/
└── plugins/
    └── sysmonitor.koplugin/
```

Restart Koreader then go to menu -> file manager -> kofetch. 

## License

See the repository license for details.
