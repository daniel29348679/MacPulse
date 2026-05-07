# MacPulse

A tiny, native macOS menu bar app that shows your CPU, RAM, network, disk, and thermal state at a glance.

No Electron. No background daemon. Just a single Swift binary that sits quietly in the menu bar and gives you a live pulse of your machine.

```
┌─────────────────────────────┐
│ … CPU 12%  RAM 47%          │
│   ↓ 1.2M  ↑ 234K            │
└─────────────────────────────┘
```

**Left-click** the menu bar item to expand a popover with detailed breakdowns and 60-second
sparkline charts for CPU and network. **Right-click** for the context menu (settings, change
update interval, quit). A dedicated **Settings window** lets you toggle which metrics appear
in the menu bar and which appear in the popover.

## Features

- **CPU usage** — total %, with user / system / idle breakdown + 60-second history sparkline
- **RAM usage** — % and `used / total` GB, computed the same way Activity Monitor does (active + wired + compressed)
- **Network** — live download / upload rates across all physical interfaces (loopback, `utun`, `awdl`, `bridge`, etc. are excluded) + sparkline
- **Disk I/O** — read / write bytes per second across all `IOBlockStorageDriver` devices
- **Thermal state** — Apple's official thermal-pressure level (Cool / Warm / Hot / Critical) with color-coded indicator
- **Toggle each metric independently** in the menu bar and in the popover via the Settings window
- **Configurable update interval** — 1.0 / 1.5 / 2.0 / 3.0 / 5.0 s, persisted to `UserDefaults`
- **Native** — pure Swift + AppKit, no third-party dependencies
- **Light** — single executable, no Electron, no helper processes
- **Hidden from Dock** — runs as an `accessory` app (menu bar only)

## Requirements

- macOS 13 (Ventura) or newer
- Swift 5.9+ toolchain (ships with Xcode 15 or the standalone Command Line Tools)

## Install

### Option 1 — Download the prebuilt `.app` (easiest)

Grab the latest `MacPulse-vX.Y.Z.zip` from the [Releases page](../../releases),
unzip, and drag `MacPulse.app` into `/Applications`.

The binary is ad-hoc signed (not notarized), so the first launch needs:
**right-click `MacPulse.app` → Open → Open**.

### Option 2 — Build from source

```bash
git clone https://github.com/daniel29348679/MacPulse.git
cd MacPulse
swift run -c release
```

The first build takes ~30s; after that startup is instant.

To launch in the background and detach from the terminal:

```bash
swift build -c release
nohup ./.build/release/MacPulse >/dev/null 2>&1 &
```

To stop:

```bash
pkill MacPulse
```

## Auto-start at login (optional)

Build the release binary, then add it to **System Settings → General → Login Items**:

```bash
swift build -c release
open .build/release    # drag MacPulse from here into Login Items
```

## How it works

| Metric  | Source                                                            |
| ------- | ----------------------------------------------------------------- |
| CPU     | `host_statistics(HOST_CPU_LOAD_INFO)` — diff of user/system/idle ticks between samples |
| RAM     | `host_statistics64(HOST_VM_INFO64)` — `(active + wired + compressed) × page_size`      |
| Network | `getifaddrs()` + `if_data` — diff of `ifi_ibytes` / `ifi_obytes` between samples       |
| Disk    | IOKit `IOBlockStorageDriver.Statistics` — diff of `Bytes (Read)` / `Bytes (Write)`     |
| Thermal | `ProcessInfo.processInfo.thermalState` — Apple's official 4-level pressure indicator   |

> **Why no ºC?** Apple Silicon does not expose CPU/GPU temperature through any public API.
> The SMC keys that worked on Intel Macs (`TC0P`, `TC0H`, …) are gone or rearranged on M-series
> chips, and there's no documented replacement. `ProcessInfo.thermalState` is what Apple itself
> recommends for reflecting "how hot is the system." It maps to **Cool / Warm / Hot / Critical**.

Default sampling interval: **1.5 seconds**. Change it from the right-click menu or the
Settings window; the choice is persisted via `UserDefaults`.

## Project layout

```
MacPulse/
├── Package.swift
└── Sources/MacPulse/
    ├── main.swift                  # NSApplication entry point
    ├── AppDelegate.swift
    ├── Settings.swift              # UserDefaults-backed preferences + Metric enum
    ├── Monitors/
    │   ├── CPUMonitor.swift
    │   ├── MemoryMonitor.swift
    │   ├── NetworkMonitor.swift
    │   ├── DiskMonitor.swift
    │   ├── TemperatureMonitor.swift
    │   └── Formatter.swift
    └── UI/
        ├── StatusBarController.swift   # NSStatusItem + sampling timer + context menu
        ├── StatsPopoverController.swift
        ├── SettingsWindowController.swift
        └── SparklineView.swift         # 60-sample rolling line chart
```

## Roadmap

- [x] Disk I/O monitoring
- [x] Sparkline charts in the popover
- [x] Configurable update interval
- [x] Toggle which metrics show in the menu bar / popover
- [x] Thermal state indicator
- [ ] GPU usage (Apple Silicon)
- [ ] Per-core CPU breakdown
- [ ] Notarized `.app` bundle in releases

PRs welcome.

## License

[MIT](LICENSE)
