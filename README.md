# thetinybuttons

One tiny button on every window corner. Toggles float, closes, and drags.

An [Omarchy](https://omarchy.org) shell plugin.

## What it does

Hover a window's top-right corner and a small circle appears. It does three things:

| Action | Result |
|--------|--------|
| Left-click (primary) | Toggle between tiling and float mode |
| Right-click | Close the window |
| Click-and-drag | Move the window (drag wins over click) |

## See it in action

```
  ┌──────────────────────────────┐
  │                            ✕ │  ← hover to reveal
  │                              │
  │   your window goes here      │
  │                              │
  │                              │
  └──────────────────────────────┘

  click ✕ (left)   → toggles float/tiling
  click ✕ (right)  → closes the window
  drag ✕  ──→      → moves the window
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

- A small layer-shell panel sits on each window's top-right corner
- The panel expands its hit area when pressed so you have room to drag
- Drag distance is measured from the initial press point; anything beyond a 5px threshold counts as a drag — a drag never triggers the button action
- Colors match your current Hyprland theme (active border, inactive border, foreground)
- Windows are polled every 400ms so the button stays glued during edge-drag resize

## Dependencies

No external dependencies. Just Hyprland and Quickshell (both ship with Omarchy).

## License

MIT