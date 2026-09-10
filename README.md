# thetinybuttons

One tiny button on every window corner. Toggles float and closes.

An [Omarchy](https://omarchy.org) shell plugin.

## What it does

Hover a window's top-right corner and a small solid circle appears. It does two things:

| Action | Result |
|--------|--------|
| Left-click (primary) | Toggle between tiling and float mode |
| Right-click | Close the window |

## See it in action

![preview](preview.jpg)

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
- Windows are polled every 400ms so the button stays glued while windows move or resize

## Dependencies

No external dependencies. Just Hyprland and Quickshell (both ship with Omarchy).

## License

MIT
