# Floating Clock Overlay

[![Downloads](https://img.shields.io/github/downloads/yousabinsadeque/FloatingClockOverlay/total?style=flat-square&color=blue&label=Downloads)](https://github.com/yousabinsadeque/FloatingClockOverlay/releases)
[![Latest Release](https://img.shields.io/github/v/release/yousabinsadeque/FloatingClockOverlay?style=flat-square&label=Latest)](https://github.com/yousabinsadeque/FloatingClockOverlay/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-12%2B-brightgreen?style=flat-square)](https://github.com/yousabinsadeque/FloatingClockOverlay)
[![License](https://img.shields.io/badge/License-Source--Available-orange?style=flat-square)](LICENSE)

A polished, transparent always-on-top clock overlay for macOS — built with Swift, SwiftUI, and AppKit.

**Created by Yousa Bin Sadeque**

![Floating Clock Overlay](screenshot.png)

---

## Features

- Transparent floating clock/timer/stopwatch overlay, always above every window
- Appears on every Space and over full-screen apps
- Click-through by default — clicks pass to apps behind it
- Draggable and resizable when click-through is OFF
- **7 visual themes:** Transparent, Glass (iOS 26 liquid glass), Dark, Light, Neon, Minimal, Custom
- **Font controls:** family (System / Rounded / Monospaced / Serif), weight, size, letter spacing
- **AM/PM toggle** with uppercase/lowercase style options
- **4 size presets:** Small, Medium, Large, Extra Large + free resize
- **Timer** and **Stopwatch** modes with lap support
- Optional pair of low meditation gong strikes, 10 seconds apart, when the timer or break ends
- Click-to-start break after the timer, with pause/resume and a 5-minute default
- Silent macOS notification when the countdown timer finishes
- **Three joined panes:** work time, primary timer/stopwatch, and side clock
- **Work-time pane:** `6:45 h` since the persisted first app launch or full screen wake of the day, with a one-click **Start now** override for the current day, rounded up to 15 minutes
- **Snap to Top Center:** one click moves the joined panes to the top edge, horizontally centered on the current display
- **Adaptive Color** — auto-adjusts text color based on background brightness
- **Burn-in Prevention** — slowly drifts the clock to protect your display
- **DVD Bounce Mode** — clock floats around the screen bouncing off edges
- **Multi-monitor support** — bounces and drags across all connected displays
- **Double-click to open Settings** — no need to find the menu bar icon
- **Position memory** — remembers its location after restart and restores it after sleep or display changes
- **Settings window** — every option live-updates the overlay
- **Menu bar icon** with full quick-access controls (Theme / Size / Mode submenus)
- Global keyboard shortcut **⌘ ⌥ C** to toggle click-through
- All settings saved to `UserDefaults` and restored on relaunch
- Menu bar app — keeps running even when the settings window is closed

---

## Installation for Normal Users

1. Download **[FloatingClockOverlay.dmg](https://github.com/yousabinsadeque/FloatingClockOverlay/releases/latest)**.
2. Open the DMG file.
3. Drag **FloatingClockOverlay.app** into the **Applications** folder.
4. Open **FloatingClockOverlay** from Applications or Launchpad.
5. The clock overlay will appear on your screen. Use the menu bar icon (🕐) to access settings and controls.

> **Note:** Because the app is not signed with an Apple Developer certificate, macOS may show a warning the first time you open it. To open it:
> - Right-click (or Control-click) the app → click **Open** → click **Open** again in the dialog.
> - Future signed and notarized releases will remove this warning.

---

## Developer Build Instructions

Requires macOS 12+, Xcode 14+, and Swift 5.7+.

```bash
cd ~/Desktop/FloatingClockOverlay

make build          # compile the app
make run            # compile + launch
make install-local  # copy .app into /Applications (prompts for sudo)
make package-dmg    # create dist/FloatingClockOverlay.dmg
make clean          # wipe build artefacts
make open-xcode     # open the Xcode project
```

### Local release routine (this fork)

Keep the workspace disposable — the source history is the rollback.

- Build and smoke-test in `/tmp` (separate derived data, copies with a unique
  bundle ID); never test on the installed app.
- Do not keep `.app` backups in `~/Applications`. Roll back by checking out the
  previous commit and rebuilding.
- Before swapping the installed app, read the running timer from the screen and
  restore it after the swap (rounded up to the minute); the timer state lives in
  memory only.
- After deploying, remove temp build dirs, test copies and DerivedData, then
  commit and push so the deployed state is reproducible from `main`.
- Close-out before saying "done": `/tmp` scratch, DerivedData, test `.app`
  copies, test `com.krispac.fcotest.*` defaults (plus the empty `.plist` stubs
  `defaults delete` leaves behind) and our own items in the Trash — moving to
  the Trash does not free any space.

---

## Using the App

Once running the app shows a **clock icon in the menu bar**.

### Click-through mode

| State | Behaviour |
|---|---|
| Click-Through **ON** ✓ (default) | Clicks pass through to apps below |
| Click-Through **OFF** | Overlay is draggable and resizable |

Toggle via menu bar → **Toggle Click-Through**, or press **⌘ ⌥ C**.

> ⌘ ⌥ C requires **System Settings → Privacy & Security → Accessibility → Floating Clock Overlay → enable**.

### Resizing the overlay

1. Turn off click-through (menu bar or ⌘ ⌥ C).
2. Drag any edge or corner of the overlay to resize.
3. Turn click-through back on when done.

Or use **Settings → Window → Size** to choose a preset (Small / Medium / Large / Extra Large).

### Moving the clock between displays

The small button in the bottom-left corner cycles the overlay through the
connected displays and keeps the same relative spot — top-centre on one screen
stays top-centre on the next. It only appears when more than one display is
connected. The saved display is restored after wake, including when the
external monitor reconnects a few seconds later.

When a countdown reaches zero, the overlay blinks and counts **up** the delay
until you click it to start the break, so a postponed break is visible.

The eye button in the bottom-right corner toggles click-through. It sits in its
own panel, so it keeps working while the clock itself ignores the mouse.

### Themes

Open **Settings → Appearance** and tap a theme card:

| Theme | Description |
|---|---|
| Transparent | Classic — black background at chosen opacity |
| Glass | iOS 26 liquid glass with blur, glare, and rim highlights |
| Dark | Solid dark rounded card |
| Light | Solid light rounded card |
| Neon | Dark background with glowing accent color |
| Minimal | Text only, no background |
| Custom | Full control: bg color, opacity, corner radius, border, shadow |

---

## Project Structure

```
FloatingClockOverlay/
├── FloatingClockOverlay.xcodeproj/
├── FloatingClockOverlay/                 Source files
│   ├── main.swift                        App entry point
│   ├── AppDelegate.swift                 App lifecycle, menu bar, shortcuts
│   ├── ClockSettings.swift               All settings (ObservableObject + UserDefaults)
│   ├── Theme.swift                       Theme/font/size/alignment enums + ThemeStyle
│   ├── ClockView.swift                   Overlay SwiftUI view (all modes, all themes)
│   ├── ClockWindowController.swift       NSWindow — sizing, position, resize
│   ├── SettingsView.swift                Full settings UI
│   ├── SettingsWindowController.swift    Settings NSWindow
│   ├── OverlayMode.swift                 Clock / Timer / Stopwatch enum
│   ├── TimeController.swift              Timer & stopwatch state
│   ├── TimerStopwatchControlsView.swift  Timer/stopwatch controls in settings
│   └── Assets.xcassets/                  App icon
├── scripts/
│   ├── create_icon.swift                 Icon generator
│   └── embed_icon.sh                     Post-build icon embedding
├── Makefile
├── README.md
├── LICENSE
├── NOTICE
└── CONTRIBUTING.md
```

---

## Credits

**Created by Yousa Bin Sadeque**

Built with Swift, SwiftUI, and AppKit. No Electron. No JavaScript. No web tech.

---

## License

Floating Clock Overlay is **source-available** and free for personal, educational, and non-commercial use.

Commercial use, business use, corporate use, resale, paid redistribution, SaaS use, internal company use, client work, contract work, monetized use, or use as a feature inside another app, product, platform, or service requires prior written permission from Yousa Bin Sadeque.

See [LICENSE](LICENSE) for full terms.

Copyright © 2026 Yousa Bin Sadeque. All rights reserved.
