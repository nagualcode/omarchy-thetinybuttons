# thetinybuttons

Two tiny buttons on every window corner. One closes, one floats, both let you drag.

An [Omarchy](https://omarchy.org) shell plugin.

## What it does

Hover a window's corner and two small circles appear:

| Corner | Button | Action |
|--------|--------|--------|
| Top-right | ✕ | Close the window |
| Top-left | ◇ | Toggle float / tiling |

**Click-and-drag** either button to move the window. The button only fires on a clean click — a drag moves the window instead.

## See it in action

```
  ┌──────────────────────────────┐
  │◇                           ✕│  ← hover to reveal
  │                              │
  │   your window goes here      │
  │                              │
  │                              │
  └──────────────────────────────┘

  click ✕       → closes the window
  click ◇       → toggles float/tiling
  drag ✕  ──→   → moves the window
  drag ◇  ──→   → moves the window
```

## Install

```
omarchy plugin add https://github.com/nagualcode/omarchy-thetinybuttons.git --enable
```

## Uninstall

```
omarchy plugin remove nagualcode.thetinybuttons
```

## How it works

- Small layer-shell panels sit on each window's top corners
- Panels expand their hit area when pressed so you have room to drag
- Drag distance is measured from the initial press point; anything beyond a 5px threshold counts as a drag
- Colors match your current Hyprland theme (active border, inactive border, foreground)
- Windows are polled every 400ms so buttons stay glued during edge-drag resize

## Dependencies

No external dependencies. Just Hyprland and Quickshell (both ship with Omarchy).

## License

MIT
