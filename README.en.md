# PetAssistant · 总裁小助理

[简体中文](README.md) | **English**

A quiet desktop cat for macOS. Click it to view and hear today's Apple Calendar schedule and to-do list. Between clicks, it stays where you left it.

![The current cat](Resources/cat_idle.png)

## Features

- Native SwiftUI + AppKit menu bar app, with no Dock icon.
- A static cat image you can drag; its position is saved.
- Click cycle: schedule → to-do list → cat without captions → schedule.
- Each page is read aloud once. Its caption stays visible until your next click.
- Schedule times use a 12-hour clock with AM/PM and your computer's current time zone.
- Chinese and English text use separate speech voices, with a choice of voices installed on your Mac.
- The schedule page greets you according to your computer's current time.
- Add, complete, and delete to-do items. Lists are stored locally by date and switch automatically when the day changes.
- Global show/hide shortcut: **Control + Option + Command + P (⌃⌥⌘P)**.
- Reopening the app also restores a hidden cat, without starting speech.

## Build and run

### Compatibility

| Platform | Current status |
|---|---|
| Mac with Apple silicon, macOS 14 or later | Current build target; verified on the target system |
| Intel Mac | No Intel or universal app bundle provided yet; untested |
| macOS 13 or earlier | Unsupported by the current build |
| Windows / Linux | Unsupported by the current version |

Xcode Command Line Tools are required. The repository currently provides a source build; a ready-to-download app release has not been published.

```bash
./scripts/build.sh
codesign --force --deep --sign - build/PetAssistant.app
open build/PetAssistant.app
```

The project compiles directly with `swiftc`, without Swift Package Manager. `Package.swift` is a legacy placeholder.

The app requests calendar access on first launch. It starts with the cat visible and no automatic narration. Calendar access can be managed in System Settings → Privacy & Security → Calendars.

## Usage

Click the cat to cycle through your schedule, to-do list, and the caption-free page. The third page shows only the cat.

Right-click to edit your to-do list, hide the pet, or quit. The menu bar panel contains your schedule, to-do list, voice options, and a show/hide button. If the menu bar is crowded, use ⌃⌥⌘P or reopen the app.

Hiding the cat stops any speech in progress. Showing it again preserves its position and caption.

## Launch at login

```bash
./scripts/install-login.sh install
./scripts/install-login.sh status
./scripts/install-login.sh uninstall
```

The LaunchAgent points to the app's current build location. Reinstall it after moving the project. Launching at login remains silent.

## Data

Calendar events are read locally through Apple EventKit. Speech uses the system AVSpeechSynthesizer. The app currently has no cloud sync or AI chat.

To-do files are stored at `~/Library/Application Support/PetAssistant/todos/YYYY-MM-DD.json`. Voice preferences and window position are saved in UserDefaults. Personal calendar events, to-do files, runtime logs, build caches, and local handoff notes are excluded from this repository.

## Project layout

```text
Sources/PetAssistant/     SwiftUI views, AppKit windows, calendar, speech, and to-do logic
Resources/               Cat images and Info.plist
scripts/build.sh         Direct swiftc build and app packaging
scripts/install-login.sh Launch-at-login management
```

## Current limitations

The cat uses a static image; walking, sleeping, and other frame animations are not implemented. The app uses local ad-hoc signing. Developer ID signing, Apple notarization, and automatic updates for public distribution are not in place yet. The current version is primarily intended for personal use.
