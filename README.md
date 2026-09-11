# thetinybuttons

One tiny button on every window corner. Toggles float and closes.

An [Omarchy](https://omarchy.org) shell plugin.

## What it does

Hover a window's top-right corner and a small solid circle appears. It does three things:

| Action | Result |
|--------|--------|
| Left-click (primary) or 1-finger tap | Toggle between tiling and float mode |
| Right-click or 2-finger tap | Close the window |
| 3-finger tap | Enter drag mode: the window follows the cursor; tap anywhere to drop it |

In drag mode the window is pinned to the cursor like SUPER+drag, but without holding SUPER — a full-screen overlay polls `hyprctl cursorpos` to track the pointer while you move the mouse, and the next tap (any button) releases the window where it is.

The drag respects the window's current mode:
- **Floating** windows are dragged freely (relative move), staying floating
- **Tiled** windows are rearranged within the tiling layout in the pointer's dominant direction (hyprctl `movewindow`), staying tiled

## See it in action

![preview](preview.jpg)

```
  click ● (left)   → toggles float/tiling
  click ● (right)  → closes the window
  3-finger tap ●   → drag mode, move the window, tap to drop
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

- A small layer-shell panel sits on each window's top-right corner, projected from the window's global coordinates
- The button is a solid circle filled with the window border color (active or inactive)
- The button spans exactly one touch target so it works with both mouse and touchpad
- A 3-finger tap on the button enters drag mode: a full-screen overlay polls `hyprctl cursorpos` to track the pointer and moves the window via `hl.dsp.window.move` (relative) for floating windows, or `movewindow` for tiled windows; the next tap anywhere drops it. The window's original tiling/float state is preserved
- Windows are polled every 400ms (80ms while dragging) so the button stays glued while windows move or resize

## Dependencies

No external dependencies. Just Hyprland and Quickshell (both ship with Omarchy).

## License

MIT
