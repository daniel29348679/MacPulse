# MacPulse

A tiny, native macOS menu bar app that shows your CPU, RAM, and network usage at a glance.

No Electron. No background daemon. Just a single Swift binary that sits quietly in the menu bar and gives you a live pulse of your machine.

```
┌─────────────────────────────┐
│ … CPU 12%  RAM 47%          │
│   ↓ 1.2M  ↑ 234K            │
└─────────────────────────────┘
```

Click the menu bar item to expand a popover with detailed breakdowns (user/system CPU, used/total memory, download/upload rates).

## Features

- **CPU usage** — total %, with user / system / idle breakdown
- **RAM usage** — % and `used / total` GB, computed the same way Activity Monitor does (active + wired + compressed)
- **Network** — live download / upload rates across all physical interfaces (loopback, `utun`, `awdl`, `bridge`, etc. are excluded)
- **Native** — pure Swift + AppKit, no third-party dependencies
- **Light** — single executable, no Electron, no helper processes
- **Hidden from Dock** — runs as an `accessory` app (menu bar only)

## Requirements

- macOS 13 (Ventura) or newer
- Swift 5.9+ toolchain (ships with Xcode 15 or the standalone Command Line Tools)

## Install & run

```bash
git clone https://github.com/<your-handle>/MacPulse.git
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

Sampling interval: **1.5 seconds** (tunable in `StatusBarController.swift`).

## Project layout

```
MacPulse/
├── Package.swift
└── Sources/MacPulse/
    ├── main.swift                  # NSApplication entry point
    ├── AppDelegate.swift
    ├── Monitors/
    │   ├── CPUMonitor.swift
    │   ├── MemoryMonitor.swift
    │   ├── NetworkMonitor.swift
    │   └── Formatter.swift
    └── UI/
        ├── StatusBarController.swift   # NSStatusItem + sampling timer
        └── StatsPopoverController.swift
```

## Roadmap

- [ ] GPU usage (Apple Silicon)
- [ ] Disk I/O
- [ ] Per-core CPU graph in the popover
- [ ] Configurable update interval and visible metrics
- [ ] Notarized `.app` bundle in releases

PRs welcome.

## License

[MIT](LICENSE)
