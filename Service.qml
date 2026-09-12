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
  // Edge buttons: a small square (smaller than the corner circle) centered
  // on each edge of the focused tiled window.
  readonly property int edgeButtonSize: Math.max(3, Math.round(service.circleSize * 0.05))

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

  // ── focused-window tracking ─────────────────────────────────────────
  // In this Omarchy build Hyprland.activeToplevel is always null and the
  // "activewindow" raw event carries no address (only class,title), so the
  // focused window's address is re-read from `hyprctl activewindow` every
  // time focus changes. Stored in normalized "0x…" form.
  property string focusedAddress: ""

  function trackFocusFrom(addrJson) {
    try {
      var j = JSON.parse(addrJson || "{}")
      var n = service.normalizedAddress(j && j.address ? j.address : "")
      service.focusedAddress = n ? n : ""
    } catch (e) {
    }
  }

  Process {
    id: focusedProc
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.trackFocusFrom(text)
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
    focusedProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activewindow" || event.name === "activewin") {
        focusedProc.running = true
      }
    }
  }

  // ── cursor proximity (edge-button reveal) ────────────────────────────
  // Edge buttons appear only while the pointer is within a band around the
  // edge they belong to. In this Omarchy build `hyprctl cursorpos` returns
  // global logical coordinates (screen.universalScale, clamped to the
  // screen's logical size), matching the window geometry space.
  readonly property int edgeReveal: 40

  property bool cursorKnown: false
  property int cursorX: 0
  property int cursorY: 0

  function cursorNearEdge(g, screen, edge, tolerance) {
    if (!g || !screen || !service.cursorKnown) return false
    var t = tolerance > 0 ? tolerance : service.edgeReveal
    var cx = service.cursorX - screen.x
    var cy = service.cursorY - screen.y
    if (edge === "left") return Math.abs(cx - g.x) <= t && cy >= g.y - t && cy <= g.bottom + t
    if (edge === "right") return Math.abs(cx - g.right) <= t && cy >= g.y - t && cy <= g.bottom + t
    if (edge === "top") return Math.abs(cy - g.y) <= t && cx >= g.x - t && cx <= g.right + t
    if (edge === "bottom") return Math.abs(cy - g.bottom) <= t && cx >= g.x - t && cx <= g.right + t
    return false
  }

  Process {
    id: cursorPosProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = service.parseCursorPos(text)
        if (p) {
          service.cursorX = p[0]
          service.cursorY = p[1]
          service.cursorKnown = true
        }
      }
    }
  }

  Timer {
    id: cursorEdgeTimer
    interval: 150
    repeat: true
    running: true
    onTriggered: cursorPosProc.running = true
  }

  // ── theme-aware colors ──────────────────────────────────────────────
  readonly property color circleColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)

  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

// The corner button's fill color — the edge buttons reuse it so the small
  // squares match the main toggle button.
  readonly property color mainButtonColor: service.circleColor

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

  // ── edge-nub geometry helpers ───────────────────────────────────────
  // Window rect in global coordinates (normalized across monitor-relative
  // IPC builds, same as the corner button).
  function geomOf(info, screen) {
    if (!info || !info.at || !info.size || !screen) return null
    var x = info.at[0] < screen.x ? info.at[0] + screen.x : info.at[0]
    var y = info.at[1] < screen.y ? info.at[1] + screen.y : info.at[1]
    return {
      x: x,
      y: y,
      w: info.size[0],
      h: info.size[1],
      cx: x + info.size[0] / 2,
      cy: y + info.size[1] / 2,
      right: x + info.size[0],
      bottom: y + info.size[1]
    }
  }

  // Margins that center a hitSize-box on the middle of the given edge.
  function edgeMarginLeft(edge, g, screen, boxW) {
    return Math.round((edge === "left" ? g.x : g.cx) - screen.x - boxW / 2)
  }
  function edgeMarginRight(edge, g, screen, boxW) {
    return Math.round(screen.x + screen.width - g.right - boxW / 2)
  }
  function edgeMarginTop(edge, g, screen, boxH) {
    var mid = (edge === "left" || edge === "right") ? g.cy : g.y
    return Math.round(mid - screen.y - boxH / 2)
  }
  function edgeMarginBottom(edge, g, screen, boxH) {
    return Math.round(screen.y + screen.height - g.bottom - boxH / 2)
  }

  // Move a specific window one tiling step in a direction — the same
  // behavior as SUPER+SHIFT+ARROW. hl.dsp.window.swap only operates on the
  // focused window, so the target is focused first (without warping the
  // cursor), then swapped, then the cursor warp setting is restored.
  function swapWindow(addr, direction) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    var script = "addr=\"$1\"; dir=\"$2\"; "
      + "orig=false; hyprctl -j getoption cursor:no_warps | grep -q '\"bool\": true' && orig=true; "
      + "hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null; "
      + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\"; "
      + "hyprctl dispatch \"hl.dsp.window.swap({ direction = \\\"$dir\\\" })\"; "
      + "hyprctl eval \"hl.config({ cursor = { no_warps = $orig } })\" >/dev/null"
    Quickshell.execDetached(["bash", "-lc", script, "bash", normalized, direction])
  }

  // ── debug logging (tail journalctl or the per-run log.qslog) ───────
  function dbg(msg) {
    console.log("[TINYBTN] " + msg)
  }

  // ── drag mode (3-finger tap on button → move → tap to drop) ─────────
  // A 3-finger tap (middle click) on a button floats the window, warps the
  // pointer to its center, and pins it to the cursor. While active, the
  // window follows the pointer via hl.dsp.window.move({ relative, x, y }) —
  // the native window.drag()/bindm APIs require a held mouse-bind, so they
  // can't be started from a button. The next tap anywhere on the monitor
  // releases; the window stays floating.
  property string dragAddr: ""
  property bool dragPrimed: false
  property var dragTargetScreen: null
  property real dragLastX: 0
  property real dragLastY: 0
  // Cursor is warped to the window's center on drag start; polls within this
  // window only re-prime tracking so the pre-warp -> center jump never
  // dispatches a ghost move.
  property double dragWarpUntil: 0
  readonly property bool dragging: service.dragAddr !== ""
  readonly property int pollFastInterval: 80
  readonly property int pollInterval: 400

  function moveWindowRelative(addr, dx, dy) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ x = " + dx + ", y = " + dy + ", relative = true, window = \"address:" + normalized + "\" })"])
  }

  function startWindowDrag(addr, screen, info) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized || service.dragging) return
    service.dragAddr = normalized
    service.dragTargetScreen = screen
    service.dragPrimed = false
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.bring_to_top({ window = \"address:" + normalized + "\" })"])
    // Always float the window, unless it is already floating (calling set on an
    // already-floated window toggles it back to tiled).
    if (!info || info.floating !== true) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"set\", window = \"address:" + normalized + "\" })"])
    }
    // Warp the pointer to the window's center, mirroring Hyprland's native
    // SUPER+drag grab, so follow-up pointer motion yields precise movement.
    var at = info && info.at ? info.at : null
    var size = info && info.size ? info.size : null
    if (at && size && screen) {
      var gx = at[0] < screen.x ? at[0] + screen.x : at[0]
      var gy = at[1] < screen.y ? at[1] + screen.y : at[1]
      var cx = Math.round(gx + size[0] / 2)
      var cy = Math.round(gy + size[1] / 2)
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.cursor.move({ x = " + cx + ", y = " + cy + " })"])
      service.dragWarpUntil = Date.now() + 100
    }
    service.dbg("DRAG START addr=" + normalized + " floating=true")
    glueTimer.restart()
    cursorPosProcA.running = true
  }

  function endWindowDrag() {
    if (!service.dragging) return
    service.dragAddr = ""
    service.dragTargetScreen = null
    service.dbg("DRAG END")
    cursorPosProcA.running = false
    cursorPosProcB.running = false
    glueTimer.restart()
  }

  function onCursorPos(x, y) {
    if (!service.dragging) return
    if (Date.now() < service.dragWarpUntil) {
      service.dragLastX = x
      service.dragLastY = y
      service.dragPrimed = false
      return
    }
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
      readonly property bool isActiveWindow: modelData !== null && service.focusedAddress !== ""
        && service.normalizedAddress(modelData.address) === service.focusedAddress
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
            if (service.focusedAddress !== ""
              && service.normalizedAddress(addr) === service.focusedAddress) return
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
              )
            }
          }
        }
      }
    }

    // Full-screen drag-mode overlay — see the service-level dragOverlay.
  }

  // ── per-window edge buttons (focused, tiled windows only) ─────────────
  // A small square at the middle of each edge of the focused tiled window.
  // It uses the same color as the main corner button (the float/tiling
  // toggle), but is smaller. Left-click moves the tile one step in that
  // direction, the same as SUPER+SHIFT+arrow.
  Variants {
    model: Hyprland.toplevels.values

    delegate: Component {
      Item {
        required property var modelData

        readonly property var info: modelData ? modelData.lastIpcObject : null
        readonly property var edgeScreen: service.screenForMonitor(modelData ? modelData.monitor : null)
        readonly property var g: service.geomOf(info, edgeScreen)
        readonly property bool onActiveWorkspace: modelData !== null && modelData.workspace !== null
          && (modelData.workspace.active === true || (info !== null && info.pinned === true))
        readonly property bool isActiveWindow: modelData !== null && service.focusedAddress !== ""
          && service.normalizedAddress(modelData.address) === service.focusedAddress
        readonly property bool showable: onActiveWorkspace && isActiveWindow
          && info !== null && info.mapped !== false && info.hidden !== true
          && info.floating !== true && info.fullscreen !== true
          && info.at && info.at.length === 2 && info.size && info.size.length === 2
          && edgeScreen !== null && g !== null

        readonly property bool nearLeft: service.cursorNearEdge(g, edgeScreen, "left", 0)
        readonly property bool nearRight: service.cursorNearEdge(g, edgeScreen, "right", 0)
        readonly property bool nearTop: service.cursorNearEdge(g, edgeScreen, "top", 0)
        readonly property bool nearBottom: service.cursorNearEdge(g, edgeScreen, "bottom", 0)

        // ── left edge ────────────────────────────────────────────────────
        PanelWindow {
          screen: edgeScreen
          visible: showable && nearLeft
          color: "transparent"
          WlrLayershell.namespace: "omarchy-tinybuttons"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore
          implicitWidth: service.hitSize
          implicitHeight: service.hitSize
          anchors.left: true
          anchors.top: true
          margins.left: showable ? g.x - edgeScreen.x - service.hitSize / 2 : 0
          margins.top: showable ? g.cy - edgeScreen.y - service.hitSize / 2 : 0

          Rectangle {
            width: service.edgeButtonSize
            height: service.edgeButtonSize
            anchors.centerIn: parent
            color: hoverL.hovered
              ? service.mixColor(service.mainButtonColor, Color.background, 0.35)
              : service.mainButtonColor

            HoverHandler {
              id: hoverL
              cursorShape: Qt.PointingHandCursor
            }
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: service.swapWindow(modelData.address, "l")
          }
        }

        // ── right edge ───────────────────────────────────────────────────
        PanelWindow {
          screen: edgeScreen
          visible: showable && nearRight
          color: "transparent"
          WlrLayershell.namespace: "omarchy-tinybuttons"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore
          implicitWidth: service.hitSize
          implicitHeight: service.hitSize
          anchors.left: true
          anchors.top: true
          margins.left: showable ? g.right - edgeScreen.x - service.hitSize / 2 : 0
          margins.top: showable ? g.cy - edgeScreen.y - service.hitSize / 2 : 0

          Rectangle {
            width: service.edgeButtonSize
            height: service.edgeButtonSize
            anchors.centerIn: parent
            color: hoverR.hovered
              ? service.mixColor(service.mainButtonColor, Color.background, 0.35)
              : service.mainButtonColor

            HoverHandler {
              id: hoverR
              cursorShape: Qt.PointingHandCursor
            }
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: service.swapWindow(modelData.address, "r")
          }
        }

        // ── top edge ─────────────────────────────────────────────────────
        PanelWindow {
          screen: edgeScreen
          visible: showable && nearTop
          color: "transparent"
          WlrLayershell.namespace: "omarchy-tinybuttons"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore
          implicitWidth: service.hitSize
          implicitHeight: service.hitSize
          anchors.left: true
          anchors.top: true
          margins.left: showable ? g.cx - edgeScreen.x - service.hitSize / 2 : 0
          margins.top: showable ? g.y - edgeScreen.y - service.hitSize / 2 : 0

          Rectangle {
            width: service.edgeButtonSize
            height: service.edgeButtonSize
            anchors.centerIn: parent
            color: hoverT.hovered
              ? service.mixColor(service.mainButtonColor, Color.background, 0.35)
              : service.mainButtonColor

            HoverHandler {
              id: hoverT
              cursorShape: Qt.PointingHandCursor
            }
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: service.swapWindow(modelData.address, "u")
          }
        }

        // ── bottom edge ──────────────────────────────────────────────────
        PanelWindow {
          screen: edgeScreen
          visible: showable && nearBottom
          color: "transparent"
          WlrLayershell.namespace: "omarchy-tinybuttons"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore
          implicitWidth: service.hitSize
          implicitHeight: service.hitSize
          anchors.left: true
          anchors.top: true
          margins.left: showable ? g.cx - edgeScreen.x - service.hitSize / 2 : 0
          margins.top: showable ? g.bottom - edgeScreen.y - service.hitSize / 2 : 0

          Rectangle {
            width: service.edgeButtonSize
            height: service.edgeButtonSize
            anchors.centerIn: parent
            color: hoverB.hovered
              ? service.mixColor(service.mainButtonColor, Color.background, 0.35)
              : service.mainButtonColor

            HoverHandler {
              id: hoverB
              cursorShape: Qt.PointingHandCursor
            }
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: service.swapWindow(modelData.address, "d")
          }
        }
      }
    }
  }
}
