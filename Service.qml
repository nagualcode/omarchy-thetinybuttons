// thetinybuttons — tiny corner buttons that also let you drag windows.
//
// Top-right: close button (✕).
// Top-left:  toggle float/tiling button (◇).
//
// Both buttons reveal on hover, support click-and-drag to move the
// underlying window, and follow the current Hyprland theme colors.
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
  // windows.  The actual empty channel between two neighboring windows is
  // 2× that value; cornerGapRadius is 1 px smaller — the largest circle
  // that fits in the gap without clipping a neighbor.
  property int gapsIn: 5
  readonly property int cornerGapRadius: Math.max(1, service.gapsIn * 2 - 1)
  // Displayed circle is 150 % of cornerGapRadius, shifted inward so 2/3
  // of its diameter lands inside the window and 1/3 stays in the gap.
  readonly property int circleRadius: Math.round(service.cornerGapRadius * 1.5)
  readonly property int circleSize: service.circleRadius * 2
  // Pull the circle's center inward from the corner so the gap-side
  // protrusion stays at exactly cornerGapRadius.
  readonly property int circleInset: Math.round(service.circleRadius / 3)
  // The invisible hit/hover box in collapsed (hover-reveal) mode.
  readonly property int hitSize: 2 * (service.circleRadius + service.circleInset) + 8
  // Expanded hit area used while dragging so the pointer stays inside the
  // PanelWindow long enough for the drag threshold to be reached.
  readonly property int expandedSize: service.hitSize * 5
  // Minimum drag distance (px) before a press is treated as a window-move
  // rather than a button tap.
  readonly property int dragThreshold: 5

  // ── live Hyprland config ────────────────────────────────────────────
  property int borderSize: 2

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

  Process {
    id: borderSizeProc
    command: ["hyprctl", "-j", "getoption", "general:border_size"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var json = JSON.parse(text || "{}")
          var n = Number(json.int)
          if (isFinite(n) && n >= 0) service.borderSize = n
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

  Component.onCompleted: {
    gapsInProc.running = true
    borderSizeProc.running = true
    inactiveBorderProc.running = true
  }

  // ── theme-aware colors ──────────────────────────────────────────────
  readonly property color circleColor: Color.flatColor(Color.pick("hyprland.active-border", Color.accent), Color.accent)
  readonly property color glyphColor: Color.flatColor(Color.pick("hyprland.active-border-foreground", Color.foreground), Color.foreground)

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

  function toggleWindow(addr) {
    var normalized = service.normalizedAddress(addr)
    if (!normalized) return
    var script = "addr=\"$1\"; "
      + "orig=false; hyprctl -j getoption cursor:no_warps | grep -q '\"bool\": true' && orig=true; "
      + "hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null; "
      + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\" >/dev/null; "
      + "hyprctl dispatch togglefloating; "
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

  // ── drag state (per-button, shared across both corners) ─────────────
  property bool dragging: false
  property real dragStartX: 0
  property real dragStartY: 0
  property real dragWinOrigX: 0
  property real dragWinOrigY: 0
  property var dragModel: null

  // Poll toplevel geometry so buttons stay glued during edge-drag resize.
  Timer {
    interval: 400
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: Hyprland.refreshToplevels()
  }

  // ── per-window buttons ──────────────────────────────────────────────
  Variants {
    model: Hyprland.toplevels.values

    // ─── close button (top-right) ─────────────────────────────────────
    PanelWindow {
      id: closeWin
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

      screen: targetScreen
      visible: showable
      color: "transparent"

      WlrLayershell.namespace: "omarchy-window-close-button"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.dragging ? service.expandedSize : service.hitSize
      implicitHeight: service.dragging ? service.expandedSize : service.hitSize

      anchors { right: true; top: true }
      margins.right: showable ? Math.round(info.at[0] + info.size[0] - targetScreen.x - closeWin.width / 2) : 0
      margins.top: showable ? Math.round(info.at[1] - targetScreen.y - closeWin.height / 2) : 0

      HoverHandler {
        id: closeHover
        onHoveredChanged: if (hovered) closeWin.forceHidden = false
      }

      Rectangle {
        id: closeCircle
        // Anchor to the top-right corner of the window regardless of
        // PanelWindow size — keeps the button visually fixed during a drag
        // expansion even though the PanelWindow itself moves.
        x: closeWin.width - service.circleSize - service.circleInset
          - (closeWin.width - service.hitSize) / 2
        y: service.circleInset + (closeWin.height - service.hitSize) / 2
        width: service.circleSize
        height: service.circleSize
        radius: width / 2
        readonly property bool pressedInside: closeTap.pressed
          && closeTap.point.position.x >= 0 && closeTap.point.position.y >= 0
          && closeTap.point.position.x <= width && closeTap.point.position.y <= height
        readonly property color pressedFillColor: service.mixColor(service.circleColor, Color.background, 0.5)
        readonly property color hoverFillColor: service.mixColor(pressedFillColor, Color.background, 0.5)
        color: pressedInside ? pressedFillColor : (closeInnerHover.hovered ? hoverFillColor : Color.background)
        border.color: closeWin.isActiveWindow ? service.circleColor : service.inactiveBorderColor
        border.width: service.borderSize
        opacity: (closeHover.hovered && !closeWin.forceHidden) ? 1 : 0
        scale: closeHover.hovered ? 1 : 0.7

        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 80 } }

        HoverHandler {
          id: closeInnerHover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: {
            if (!hovered || !closeWin.modelData) return
            var addr = closeWin.modelData.address
            if (Hyprland.activeToplevel && Hyprland.activeToplevel.address === addr) return
            service.focusWindow(addr)
          }
        }

        TapHandler {
          id: closeTap
          acceptedButtons: Qt.LeftButton
          gesturePolicy: TapHandler.ReleaseWithinBounds
          onTapped: service.closeWindow(closeWin.modelData.address)
          onPressedChanged: {
            if (pressed) {
              service.dragging = true
              service.dragStartX = closeTap.point.position.x + closeCircle.x + closeWin.x
              service.dragStartY = closeTap.point.position.y + closeCircle.y + closeWin.y
              service.dragModel = closeWin.modelData
              if (closeWin.info && closeWin.info.at) {
                service.dragWinOrigX = closeWin.info.at[0]
                service.dragWinOrigY = closeWin.info.at[1]
              }
              return
            }
            // Released — check if this was a drag or a tap.
            var dx = closeTap.point.position.x + closeCircle.x + closeWin.x - service.dragStartX
            var dy = closeTap.point.position.y + closeCircle.y + closeWin.y - service.dragStartY
            if (Math.sqrt(dx * dx + dy * dy) > service.dragThreshold) {
              var newX = Math.round(service.dragWinOrigX + dx)
              var newY = Math.round(service.dragWinOrigY + dy)
              var addr = service.normalizedAddress(service.dragModel.address)
              Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ address = \"" + addr + "\", x = " + newX + ", y = " + newY + " })"])
            }
            service.dragging = false
            // Hide when the pointer drifted outside the hit area.
            var absX = closeCircle.x + closeTap.point.position.x
            var absY = closeCircle.y + closeTap.point.position.y
            if (absX < 0 || absY < 0 || absX > closeWin.width || absY > closeWin.height) {
              closeWin.forceHidden = true
            }
          }
        }

        Text {
          anchors.centerIn: parent
          text: "✕"
          color: service.glyphColor
          font.pixelSize: parent.width * 0.6
          font.bold: true
        }
      }
    }

    // ─── toggle-float button (top-left) ───────────────────────────────
    PanelWindow {
      id: toggleWin
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

      screen: targetScreen
      visible: showable
      color: "transparent"

      WlrLayershell.namespace: "omarchy-window-toggle-button"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.dragging ? service.expandedSize : service.hitSize
      implicitHeight: service.dragging ? service.expandedSize : service.hitSize

      anchors { left: true; top: true }
      margins.left: showable ? Math.round(info.at[0] - targetScreen.x - toggleWin.width / 2) : 0
      margins.top: showable ? Math.round(info.at[1] - targetScreen.y - toggleWin.height / 2) : 0

      HoverHandler {
        id: toggleHover
        onHoveredChanged: if (hovered) toggleWin.forceHidden = false
      }

      Rectangle {
        id: toggleCircle
        // Anchor to the top-left corner of the window — mirrors the close
        // button's approach so the button stays put during drag expansion.
        x: service.circleInset + (toggleWin.width - service.hitSize) / 2
        y: service.circleInset + (toggleWin.height - service.hitSize) / 2
        width: service.circleSize
        height: service.circleSize
        radius: width / 2
        readonly property bool pressedInside: toggleTap.pressed
          && toggleTap.point.position.x >= 0 && toggleTap.point.position.y >= 0
          && toggleTap.point.position.x <= width && toggleTap.point.position.y <= height
        readonly property color pressedFillColor: service.mixColor(service.circleColor, Color.background, 0.5)
        readonly property color hoverFillColor: service.mixColor(pressedFillColor, Color.background, 0.5)
        color: pressedInside ? pressedFillColor : (toggleInnerHover.hovered ? hoverFillColor : Color.background)
        border.color: toggleWin.isActiveWindow ? service.circleColor : service.inactiveBorderColor
        border.width: service.borderSize
        opacity: (toggleHover.hovered && !toggleWin.forceHidden) ? 1 : 0
        scale: toggleHover.hovered ? 1 : 0.7

        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 80 } }

        HoverHandler {
          id: toggleInnerHover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: {
            if (!hovered || !toggleWin.modelData) return
            var addr = toggleWin.modelData.address
            if (Hyprland.activeToplevel && Hyprland.activeToplevel.address === addr) return
            service.focusWindow(addr)
          }
        }

        TapHandler {
          id: toggleTap
          acceptedButtons: Qt.LeftButton
          gesturePolicy: TapHandler.ReleaseWithinBounds
          onTapped: service.toggleWindow(toggleWin.modelData.address)
          onPressedChanged: {
            if (pressed) {
              service.dragging = true
              service.dragStartX = toggleTap.point.position.x + toggleCircle.x + toggleWin.x
              service.dragStartY = toggleTap.point.position.y + toggleCircle.y + toggleWin.y
              service.dragModel = toggleWin.modelData
              if (toggleWin.info && toggleWin.info.at) {
                service.dragWinOrigX = toggleWin.info.at[0]
                service.dragWinOrigY = toggleWin.info.at[1]
              }
              return
            }
            var dx = toggleTap.point.position.x + toggleCircle.x + toggleWin.x - service.dragStartX
            var dy = toggleTap.point.position.y + toggleCircle.y + toggleWin.y - service.dragStartY
            if (Math.sqrt(dx * dx + dy * dy) > service.dragThreshold) {
              var newX = Math.round(service.dragWinOrigX + dx)
              var newY = Math.round(service.dragWinOrigY + dy)
              var addr = service.normalizedAddress(service.dragModel.address)
              Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ address = \"" + addr + "\", x = " + newX + ", y = " + newY + " })"])
            }
            service.dragging = false
            var absX = toggleCircle.x + toggleTap.point.position.x
            var absY = toggleCircle.y + toggleTap.point.position.y
            if (absX < 0 || absY < 0 || absX > toggleWin.width || absY > toggleWin.height) {
              toggleWin.forceHidden = true
            }
          }
        }

        Text {
          anchors.centerIn: parent
          text: "◇"
          color: service.glyphColor
          font.pixelSize: parent.width * 0.55
          font.bold: true
        }
      }
    }
  }
}
