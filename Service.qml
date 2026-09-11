// thetinybuttons — a single tiny corner button that does a lot.
//
// One button on the top-right corner of every window:
//   • Left-click  (primary) → toggle between tiling and float mode
//   • Right-click (context) → close the window
//   • 3-finger tap → enter drag mode: the window follows the cursor;
//     tap anywhere on the monitor to drop it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

Item {
  id: service

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  // ── geometry constants ──────────────────────────────────────────────
  // "general:gaps_in" is Hyprland's own name for the space between tiled
  // windows. The button is sized to sit comfortably in that gap.
  property int gapsIn: 5
  readonly property int cornerGapRadius: Math.max(1, service.gapsIn * 2 - 1)
  readonly property int circleRadius: Math.round(service.cornerGapRadius * 1.5)
  readonly property int circleSize: service.circleRadius * 2
  // Extra padding around the circle so the invisible hit/hover box is
  // larger than the visible button.
  readonly property int circlePad: Math.round(service.circleRadius / 3)
  // The invisible hit/hover box (revealed on hover).
  readonly property int hitSize: 2 * (service.circleRadius + service.circlePad) + 8

  // ── live Hyprland config ────────────────────────────────────────────
  Process {
    id: gapsInProc
    command: ["hyprctl", "-j", "getoption", "general:gaps_in"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var parts = String(json.css || "").match(/-?\d+(?:\.\d+)?/g) || []
          var n = parts.length > 0 ? Number(parts[0]) : Number(json.int)
          if (isFinite(n) && n >= 0) service.gapsIn = n
        } catch (e) {
        }
      }
    }
  }

  property color inactiveBorderColor: Color.muted

  function firstGradientStopColor(raw) {
    var tokens = String(raw || "").trim().split(/\s+/)
    for (var i = 0; i < tokens.length; i++) {
      if (/^[0-9a-fA-F]{8}$/.test(tokens[i])) return "#" + tokens[i]
    }
    return null
  }

  Process {
    id: inactiveBorderProc
    command: ["hyprctl", "-j", "getoption", "general:col.inactive_border"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var color = service.firstGradientStopColor(json.gradient)
          if (color) service.inactiveBorderColor = color
        } catch (e) {
        }
      }
    }
  }

  // Whether the touchpad uses natural (inverted) scroll. When enabled,
  // the tiled drag direction is mirrored so the window follows the
  // fingers like it would in a natural-scroll setup.
  property bool naturalScroll: false
  Process {
    id: naturalScrollProc
    command: ["hyprctl", "-j", "getoption", "input:touchpad:natural_scroll"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          service.naturalScroll = json.bool === true
          service.dbg("naturalScroll=" + service.naturalScroll)
        } catch (e) {
        }
      }
    }
  }

  Component.onCompleted: {
    gapsInProc.running = true
    inactiveBorderProc.running = true
    naturalScrollProc.running = true
  }

  // ── theme-aware colors ──────────────────────────────────────────────
  readonly property color circleColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)

  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  // ── helpers ─────────────────────────────────────────────────────────
  // HyprlandToplevel.address is bare hex ("56538020a4f0"); normalize to
  // the "0x"-prefixed form hyprctl expects.
  function normalizedAddress(addr) {
    if (typeof addr !== "string") return null
    var hex = addr.indexOf("0x") === 0 ? addr.slice(2) : addr
    return /^[0-9a-fA-F]+$/.test(hex) ? "0x" + hex : null
  }

  // Omarchy's Hyprland build routes `hyprctl dispatch <args>` through a
  // Lua eval, so the classic dispatcher strings don't apply — dispatchers
  // are Lua calls under hl.dsp.*.
  function closeWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ address = \"" + normalized + "\" })"])
  }

  // Toggle floating state for a specific window. There's no classic
  // "togglefloating" dispatcher in Omarchy's Lua build — the floating
  // dispatcher is hl.dsp.window.float, and the targeted window is passed
  // with an "address:0x..." selector.
  function toggleWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"toggle\", window = \"address:" + normalized + "\" })"])
  }

  // Focus without warping the cursor — same trick as the original
  // axel.window-close-buttons plugin.
  function focusWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    var script = "addr=\"$1\"; "
      + "orig=false; hyprctl -j getoption cursor:no_warps | grep -q '\"bool\": true' && orig=true; "
      + "hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null; "
      + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\"; "
      + "hyprctl eval \"hl.config({ cursor = { no_warps = $orig } })\" >/dev/null"
    Quickshell.execDetached(["bash", "-lc", script, "bash", normalized])
  }

  function screenForMonitor(monitor) {
    if (!monitor || !monitor.name) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === monitor.name) return screens[i]
    }
    return null
  }

  // ── debug logging (tail journalctl or the per-run log.qslog) ───────
  function dbg(msg) {
    console.log("[TINYBTN] " + msg)
  }

  // ── drag mode (3-finger tap on button → move → tap to drop) ─────────
  // A 3-finger tap (middle click) on a button pins the window to the
  // cursor. While active, a full-screen overlay tracks the pointer and the
  // window follows via hl.dsp.window.move({ relative, x, y }) — the native
  // window.drag()/bindm APIs require a held mouse-bind, so they can't be
  // started from a button. The next tap anywhere on the monitor releases.
  property string dragAddr: ""
  property bool dragPrimed: false
  property bool dragWasFloating: false
  property var dragTargetScreen: null
  property real dragLastX: 0
  property real dragLastY: 0
  readonly property bool dragging: service.dragAddr !== ""
  readonly property int pollFastInterval: 80
  readonly property int pollInterval: 400

  function moveWindowRelative(addr, dx, dy) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    if (service.dragWasFloating) {
      // Floating window: free-form relative move.
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ x = " + dx + ", y = " + dy + ", relative = true, window = \"address:" + normalized + "\" })"])
    } else {
      // Tiled window: move it in the dominant axis's direction. The Lua
      // dispatcher hl.dsp.window.move accepts a `direction` argument —
      // it rearranges other tiles in the layout without floating.
      if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return
      var inv = service.naturalScroll
      var dir = Math.abs(dx) >= Math.abs(dy)
        ? (dx > 0 ? (inv ? "l" : "r") : (inv ? "r" : "l"))
        : (dy > 0 ? (inv ? "u" : "d") : (inv ? "d" : "u"))
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ direction = \"" + dir + "\", window = \"address:" + normalized + "\" })"])
    }
  }

  function startWindowDrag(addr, screen, isFloating) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized || service.dragging) return
    service.dragAddr = normalized
    service.dragTargetScreen = screen
    service.dragWasFloating = isFloating
    service.dragPrimed = false
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.bring_to_top({ window = \"address:" + normalized + "\" })"])
    if (isFloating) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"set\", window = \"address:" + normalized + "\" })"])
    }
    service.dbg("DRAG START addr=" + normalized + " floating=" + isFloating)
    glueTimer.restart()
    cursorPosProcA.running = true
  }

  function endWindowDrag() {
    if (!service.dragging) return
    if (!service.dragWasFloating) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"unset\", window = \"address:" + service.dragAddr + "\" })"])
    }
    service.dragAddr = ""
    service.dragTargetScreen = null
    service.dbg("DRAG END")
    cursorPosProcA.running = false
    cursorPosProcB.running = false
    glueTimer.restart()
  }

  function onCursorPos(x, y) {
    if (!service.dragging) return
    if (service.dragPrimed) {
      var dx = x - service.dragLastX
      var dy = y - service.dragLastY
      if (Math.abs(dx) >= 0.35 || Math.abs(dy) >= 0.35) {
        service.dbg("DRAG follow " + dx.toFixed(2) + "," + dy.toFixed(2))
        service.moveWindowRelative(service.dragAddr, dx.toFixed(2), dy.toFixed(2))
      }
    }
    service.dragLastX = x
    service.dragLastY = y
    service.dragPrimed = true
  }

  // Cursor polling chain runs continuously while dragging: cursorPosProcA
  // runs, its onStreamFinished starts cursorPosProcB, whose onStreamFinished
  // starts A again. This self-staggers the polls and avoids the kill/restart
  // race of a single Process (which produced huge spurious deltas).

  // Poll toplevel geometry so buttons stay glued as windows move/resize.
  // Polls faster while a drag mode is active (the window moves live).
  Timer {
    id: glueTimer
    interval: service.dragging ? service.pollFastInterval : service.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: Hyprland.refreshToplevels()
  }

  // ── drag-mode overlay ───────────────────────────────────────────────
  // Declared last so it maps on top of every button surface. While a
  // window is being dragged it covers the monitor: a full-screen overlay
  // window receives any tap (any button) to release the window, and a
  // 24ms Process polls `hyprctl cursorpos` to stream relative moves to
  // the dragged window. HoverHandler is not used because its position
  // reports (0,0) in overlay PanelWindows on this Qt/Wayland build.
  PanelWindow {
    id: dragOverlay
    readonly property var targetScreen: service.dragTargetScreen

    screen: targetScreen
    visible: service.dragging
    color: "transparent"
    anchors { right: true; top: true }
    implicitWidth: targetScreen ? targetScreen.width : 0
    implicitHeight: targetScreen ? targetScreen.height : 0

    WlrLayershell.namespace: "omarchy-tinybuttons"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    TapHandler {
      id: dropTap
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onPressedChanged: if (!pressed) service.endWindowDrag()
    }
  }

  function parseCursorPos(raw) {
    var s = String(raw || "").trim()
    var c = s.indexOf(",")
    if (c < 1) return null
    var x = parseFloat(s.substring(0, c))
    var y = parseFloat(s.substring(c + 1))
    if (!isFinite(x) || !isFinite(y)) return null
    return [x, y]
  }

  Process {
    id: cursorPosProcA
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = service.parseCursorPos(text)
        if (p) service.onCursorPos(p[0], p[1])
        if (service.dragging) cursorPosProcB.running = true
      }
    }
  }

  Process {
    id: cursorPosProcB
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = service.parseCursorPos(text)
        if (p) service.onCursorPos(p[0], p[1])
        if (service.dragging) cursorPosProcA.running = true
      }
    }
  }

  // ── per-window button (top-right) ───────────────────────────────────
  Variants {
    model: Hyprland.toplevels.values

    PanelWindow {
      id: cornerWindow
      required property var modelData

      readonly property var info: modelData ? modelData.lastIpcObject : null
      readonly property var targetScreen: service.screenForMonitor(modelData ? modelData.monitor : null)
      readonly property bool onActiveWorkspace: modelData !== null && modelData.workspace !== null
        && (modelData.workspace.active === true || (info !== null && info.pinned === true))
      readonly property bool showable: onActiveWorkspace
        && info !== null && info.mapped !== false && info.hidden !== true
        && info.at && info.at.length === 2 && info.size && info.size.length === 2
        && targetScreen !== null
      readonly property bool isActiveWindow: modelData !== null && Hyprland.activeToplevel !== null
        && Hyprland.activeToplevel.address === modelData.address
      property bool forceHidden: false

      // Hyprland reports window position in global coordinates, but some
      // builds report monitor-relative values; normalize to global so the
      // right/top margins land on the window's real top-right corner.
      readonly property real winRight: info && info.at && info.size && targetScreen
        ? (info.at[0] < targetScreen.x ? info.at[0] + targetScreen.x : info.at[0]) + info.size[0]
        : 0
      readonly property real winTop: info && info.at && targetScreen
        ? (info.at[1] < targetScreen.y ? info.at[1] + targetScreen.y : info.at[1])
        : 0

      screen: targetScreen
      visible: showable
      color: "transparent"

      WlrLayershell.namespace: "omarchy-tinybuttons"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.hitSize
      implicitHeight: service.hitSize

      // Anchored to the screen's top-right; the margins center the panel
      // on the window's top-right corner, so the circle (centered inside
      // the panel) is centered exactly on the window corner.
      anchors { right: true; top: true }
      margins.right: showable ? Math.round(targetScreen.x + targetScreen.width - cornerWindow.winRight - cornerWindow.width / 2) : 0
      margins.top: showable ? Math.round(cornerWindow.winTop - targetScreen.y - cornerWindow.height / 2) : 0

      // Hide the button again if the pointer drifted outside the panel.
      function maybeHideOutside(pointPos) {
        var absX = circle.x + pointPos.x
        var absY = circle.y + pointPos.y
        if (absX < 0 || absY < 0 || absX > cornerWindow.width || absY > cornerWindow.height) {
          cornerWindow.forceHidden = true
        }
      }

      HoverHandler {
        id: hover
        onHoveredChanged: if (hovered) cornerWindow.forceHidden = false
      }

      Rectangle {
        id: circle
        x: (cornerWindow.width - service.circleSize) / 2
        y: (cornerWindow.height - service.circleSize) / 2
        width: service.circleSize
        height: service.circleSize
        radius: width / 2
        readonly property bool pressPointInside:
          tap.pressed && pointFits(tap.point.position)
        function pointFits(p) {
          return p.x >= 0 && p.y >= 0 && p.x <= width && p.y <= height
        }
        readonly property bool pressedInside: pressPointInside
        readonly property color baseFillColor: cornerWindow.isActiveWindow
          ? service.circleColor : service.inactiveBorderColor
        readonly property color pressedFillColor: service.mixColor(baseFillColor, Color.background, 0.5)
        readonly property color hoverFillColor: service.mixColor(baseFillColor, Color.background, 0.35)
        color: pressedInside ? pressedFillColor : (innerHover.hovered ? hoverFillColor : baseFillColor)
        opacity: (hover.hovered && !cornerWindow.forceHidden) ? 1 : 0
        scale: hover.hovered ? 1 : 0.7

        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 80 } }

        HoverHandler {
          id: innerHover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: {
            if (!hovered || !cornerWindow.modelData) return
            var addr = cornerWindow.modelData.address
            if (Hyprland.activeToplevel && Hyprland.activeToplevel.address === addr) return
            service.focusWindow(addr)
          }
        }

        TapHandler {
          id: tap
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          gesturePolicy: TapHandler.ReleaseWithinBounds
          property int heldButton: Qt.NoButton

          // Button actions (tap without prior drag):
          //   left/1-finger → toggle float; right/2-finger → close;
          //   middle/3-finger → enter drag mode (move the window, tap to drop).
          onPressedChanged: {
            if (tap.pressed) {
              tap.heldButton = tap.point.pressedButtons
              return
            }
            var btn = tap.heldButton
            tap.heldButton = Qt.NoButton
            if (btn & Qt.RightButton) {
              service.closeWindow(cornerWindow.modelData.address)
              cornerWindow.maybeHideOutside(tap.point.position)
              return
            }
            if (btn & Qt.LeftButton) {
              service.toggleWindow(cornerWindow.modelData.address)
              cornerWindow.maybeHideOutside(tap.point.position)
              return
            }
            if (btn === Qt.MiddleButton) {
              service.startWindowDrag(
                cornerWindow.modelData.address,
                cornerWindow.targetScreen,
                cornerWindow.modelData.lastIpcObject
                  ? cornerWindow.modelData.lastIpcObject.floating === true
                  : false
              )
            }
          }
        }
      }
    }

    // Full-screen drag-mode overlay — see the service-level dragOverlay.
  }
}