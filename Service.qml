// thetinybuttons — a single tiny corner button that does a lot.
//
// One button on the top-right corner of every window:
//   • Left-click  (primary) → toggle between tiling and float mode
//   • Right-click (context) → close the window
//   • Click-and-drag         → move the window
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

  // ── drag state (shared) ─────────────────────────────────────────────
  property bool dragging: false
  property int dragButton: Qt.NoButton
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

      screen: targetScreen
      visible: showable
      color: "transparent"

      WlrLayershell.namespace: "omarchy-tinybuttons"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      implicitWidth: service.dragging ? service.expandedSize : service.hitSize
      implicitHeight: service.dragging ? service.expandedSize : service.hitSize

      anchors { right: true; top: true }
      margins.right: showable ? Math.round(info.at[0] + info.size[0] - targetScreen.x - cornerWindow.width / 2) : 0
      margins.top: showable ? Math.round(info.at[1] - targetScreen.y - cornerWindow.height / 2) : 0

      HoverHandler {
        id: hover
        onHoveredChanged: if (hovered) cornerWindow.forceHidden = false
      }

      Rectangle {
        id: circle
        // Anchor to the top-right corner of the window regardless of
        // PanelWindow size — keeps the button visually fixed during a drag
        // expansion even though the PanelWindow itself moves.
        x: cornerWindow.width - service.circleSize - service.circleInset
          - (cornerWindow.width - service.hitSize) / 2
        y: service.circleInset + (cornerWindow.height - service.hitSize) / 2
        width: service.circleSize
        height: service.circleSize
        radius: width / 2
        readonly property bool pressedInside: tap.pressed
          && tap.point.position.x >= 0 && tap.point.position.y >= 0
          && tap.point.position.x <= width && tap.point.position.y <= height
        readonly property color pressedFillColor: service.mixColor(service.circleColor, Color.background, 0.5)
        readonly property color hoverFillColor: service.mixColor(pressedFillColor, Color.background, 0.5)
        color: pressedInside ? pressedFillColor : (innerHover.hovered ? hoverFillColor : Color.background)
        border.color: cornerWindow.isActiveWindow ? service.circleColor : service.inactiveBorderColor
        border.width: service.borderSize
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
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          // ReleaseWithinBounds keeps this grab (and point tracking) through
          // the whole drag even once the pointer leaves the circle.
          gesturePolicy: TapHandler.ReleaseWithinBounds

          // All logic happens here, at press and release, so we don't depend
          // on TapHandler's own onTapped/vs-pressedChanged signal ordering.
          //   • press            → begin drag tracking
          //   • release + drag   → move the window
          //   • release + tap    → fire the button action for the pressed
          //                        button: left toggles float, right closes
          onPressedChanged: {
            if (pressed) {
              service.dragging = true
              service.dragButton = tap.point.buttons
              service.dragStartX = tap.point.position.x + circle.x + cornerWindow.x
              service.dragStartY = tap.point.position.y + circle.y + cornerWindow.y
              service.dragModel = cornerWindow.modelData
              if (cornerWindow.info && cornerWindow.info.at) {
                service.dragWinOrigX = cornerWindow.info.at[0]
                service.dragWinOrigY = cornerWindow.info.at[1]
              }
              return
            }
            // Released.
            service.dragging = false
            var dx = tap.point.position.x + circle.x + cornerWindow.x - service.dragStartX
            var dy = tap.point.position.y + circle.y + cornerWindow.y - service.dragStartY
            var isDrag = Math.sqrt(dx * dx + dy * dy) > service.dragThreshold

            if (isDrag) {
              var newX = Math.round(service.dragWinOrigX + dx)
              var newY = Math.round(service.dragWinOrigY + dy)
              var addr = service.normalizedAddress(service.dragModel.address)
              Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ address = \"" + addr + "\", x = " + newX + ", y = " + newY + " })"])
            } else if (service.dragButton === Qt.RightButton) {
              service.closeWindow(cornerWindow.modelData.address)
            } else {
              service.toggleWindow(cornerWindow.modelData.address)
            }

            service.dragButton = Qt.NoButton
            // Hide when the pointer drifted outside the hit area.
            var absX = circle.x + tap.point.position.x
            var absY = circle.y + tap.point.position.y
            if (absX < 0 || absY < 0 || absX > cornerWindow.width || absY > cornerWindow.height) {
              cornerWindow.forceHidden = true
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
  }
}