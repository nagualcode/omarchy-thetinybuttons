# thetinybuttons

Tiny buttons on every window: one on the top-right corner (toggles float, closes, drags) and direction arrows at the middle of each edge of the focused tiled window (moves the tile toward that edge).

An [Omarchy](https://omarchy.org) shell plugin.

## What it does

Hover a window's top-right corner and a small solid circle appears. It does three things:

| Action | Result |
|--------|--------|
| Left-click (primary) or 1-finger tap | Toggle between tiling and float mode |
| Right-click or 2-finger tap | Close the window |
| 3-finger tap | Enter drag mode: the window is floated, the pointer moves to its center, and the window follows the cursor; tap anywhere to release it |

In drag mode the window behaves like Hyprland's SUPER+drag, but without holding SUPER: the currently controlled window is **floated** (whatever its previous state), the pointer is warped to the window's center, and a full-screen overlay polls `hyprctl cursorpos` to track the pointer while you move the mouse. The next tap (any button) releases the window where it is — it stays floating until you toggle it back.

### Edge buttons (focused tiled windows only)

In addition to the corner button, the **focused** tiled window gets a small arrow at the middle of each edge, pointing toward that edge (`←` left, `→` right, `↑` up, `↓` down), in the same color as the corner button. Each arrow sits just outside the window, flush with the **outer** border of its edge so it never covers window content, and it only appears while the pointer is near that edge. Clicking an arrow moves the window one tiling step in that direction — the same as `SUPER+SHIFT+arrow`.

Arrows only appear when they can actually do something:

- only on the **focused** window, and only while it is **tiled** (never in float or fullscreen);
- only when there is **more than one tiled window** on the workspace (a lone tile has nothing to swap with);
- the arrow of an edge that is **flush against the screen border** stays hidden — it cannot be moved any further out (a window already in the rightmost slot of its row never shows a right arrow, and so on).

## See it in action

![preview](preview.jpg)

```
  click ● (corner, left)   → toggles float/tiling
  click ● (corner, right)  → closes the window
  3-finger tap ● (corner)  → floats the window, centers the pointer, drag, tap to release
  click ← → ↑ ↓ (an edge arrow) → moves the focused tiled window one step toward that edge
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
- An additional layer-shell panel per edge is created only for **tiled** windows and only while that window is **focused**; it draws a small arrow at the middle of the edge in the same color as the corner button, aligned with the **outer** border of the edge so it sits in the gap, outside the window. An edge's arrow is revealed only while the pointer is within a band around that edge (`hyprctl cursorpos` is polled every 150ms) **and** that edge can still move — it stays hidden when the edge is flush against the screen border (within `gaps_out + gaps_in + border`), when fewer than two tiled windows share the workspace, or when the window floats or is fullscreen. `hl.dsp.window.swap` acts on the focused window only, so the target is focused first (no cursor warp) and swapped via the same dispatch as `SUPER+SHIFT+arrow`
- In this Omarchy build `Hyprland.activeToplevel` is always null and the `activewindow` raw event carries no address, so the focused window is tracked by re-reading `hyprctl activewindow` whenever focus changes
- The button is a solid circle filled with the window border color (active or inactive)
- The button spans exactly one touch target so it works with both mouse and touchpad
- A 3-finger tap on the button enters drag mode: a full-screen overlay polls `hyprctl cursorpos` to track the pointer, the window is floated (if it was not already) and moved via `hl.dsp.window.move` (relative), and the pointer is warped to the window's center so the drag is as precise as SUPER+drag; the next tap anywhere releases it. The window stays floating
- Windows are polled every 400ms (80ms while dragging) so the button stays glued while windows move or resize

## Dependencies

No external dependencies. Just Hyprland and Quickshell (both ship with Omarchy).

## License

MIT
