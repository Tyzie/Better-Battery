# Better Battery

Omarchy shell bar widget for battery status, with a detailed keyboard panel.

## Features

- Bar icon with optional percentage (right-click icon toggles percentage, or use widget setting).
- Panel shows: charge, status, draw, estimated time, health, cycles, capacity, temperature.
- Custom CPU power profiles (no TLP, no omarchy-powerprofiles):
  - Econom: `powersave` governor, boost off.
  - Normal: `powersave` governor, boost on.
  - Power: `performance` governor, boost on.
  - Auto: AC -> Power, battery -> Econom; reapplied on AC/battery changes.
  - Requires a one-time root helper install (`install-profile-helper`) that adds a
    narrowly scoped NOPASSWD sudoers rule for a root-owned sysfs writer.
- Charging history: active session plus recorded sessions, averages, and a last-10 graph.
- Sleep statistics: count, average draw, last sleep duration/time/drop/draw, and a
  last-10 graph. Collected automatically by the user-level `battery-sleep-monitor`;
  no root access and no hook installation are needed. Sleeps that stay on AC are
  skipped.
- Legacy sleep hook cleanup: detects a stale root-run wrapper left by older
  installs, shows it in the panel, and removes it on demand after verifying its
  exact path, root ownership, and known wrapper contents.

## Install

Enabled through `~/.config/omarchy/shell.json`:

```json
{ "id": "tyzie.better-battery", "showPercentage": false }
```

Move it with:

```bash
omarchy bar move tyzie.better-battery --section right
```

Right-click the bar icon to toggle the on-bar percentage, or set `showPercentage`
in the widget settings. `pollIntervalSec` controls how often the open panel refreshes.

## Legacy sleep hook cleanup

Older installs could leave `/usr/lib/systemd/system-sleep/tyzie-battery-sleep`,
a root-run wrapper that executes a user-writable plugin path. This plugin checks
that exact path on every panel refresh and offers a one-click removal in the
"Legacy sleep hook" section of the panel. The removal is guarded: the file must
be a regular, root-owned, readable file containing the known legacy wrapper
strings; symlinks, unexpected files, and unexpected contents are never touched.
A single system authorization prompt is used to delete that one path. No new
privileged hook is installed.

It can also be removed from a terminal:

```bash
~/.config/omarchy/plugins/tyzie.better-battery/bin/battery-action cleanup-sleep-hook
```

Omit nothing for `pkexec`; add `--sudo` only inside an interactive terminal if
no polkit frontend is available (the action script forwards that flag).

## Security notes

- No script in this plugin installs a system-sleep wrapper or any other root-run
  file that references a path under `~/.config/omarchy/plugins/`. The only
  privileged operation is removing the exact verified legacy wrapper described
  above.
- `battery-sleep-monitor` listens to `org.freedesktop.login1.Manager.PrepareForSleep`
  over the system bus as the desktop user and writes only to the user's own state
  directory. A compromised desktop user account cannot gain root through it.
- The optional CPU profile helper is copied to a root-owned location and gated by a
  narrow sudoers rule with fixed arguments. It never executes plugin files as root.
- All dynamic text is normalized to plain text before reaching Omarchy-owned label
  and tooltip sinks; JSON from helper scripts is parsed into bounded, typed values.

## Requirements

- `bash`, `jq`, `awk`, `flock`, `gdbus`, and a battery exposed through
  `/sys/class/power_supply` (UPower is used as a fallback).
- Root access is only needed if you opt into the CPU profile helper. The basic
  widget and sleep tracking need no privileges.

## Files

- `Panel.qml` - bar widget + keyboard panel UI
- `Model.js` - parsing, validation, formatting, and plain-text helpers
- `i18n/en.json` - English strings (other languages fall back to English)
- `bin/battery-data` - validated JSON snapshot for the panel
- `bin/battery-action` - profile actions, helper install, clear stats
- `bin/battery-sleep-monitor` - user-level logind sleep tracker
- `bin/battery-profile-helper` - root-owned sysfs writer for CPU governor and boost
- `lib/common.sh` - shared shell helpers
- `tests/test-model.js` - model regression tests

## License

MIT — see [LICENSE](LICENSE).
