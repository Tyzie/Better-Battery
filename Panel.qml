import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "tyzie.battery"
  ipcTarget: "tyzie.battery"
  manageIpc: false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showPercentage: setting("showPercentage", false) === true
  readonly property int pollInterval: Math.max(2000, Math.min(60000, (Number(setting("pollIntervalSec", 5)) || 5) * 1000))

  property var snapshot: ({
    battery: { present: false, percent: 0, status: "Unknown", watts: 0, minutes: 0, health: 0, whFull: 0, whDesign: 0, cycles: 0, tempC: "", acOnline: 0 },
    profiles: { current: "unknown", auto: false, available: [] },
    sleep: { installed: false, samples: 0, avgDrawW: 0, totalSleepSec: 0, last: null }
  })
  property string debugError: ""
  property var wattHistory: []
  property int wattHistoryMax: 60

  function pushWattSample(w) {
    var n = Math.max(0, Number(w) || 0)
    var next = wattHistory.slice()
    next.push(n)
    while (next.length > wattHistoryMax) next.shift()
    wattHistory = next
  }
  function wattStat(kind) {
    if (!wattHistory.length) return 0
    var min = wattHistory[0], max = wattHistory[0], sum = 0
    for (var i = 0; i < wattHistory.length; i++) {
      var v = Number(wattHistory[i]) || 0
      if (v < min) min = v
      if (v > max) max = v
      sum += v
    }
    if (kind === "min") return min
    if (kind === "max") return max
    if (kind === "avg") return sum / wattHistory.length
    return wattHistory[wattHistory.length - 1]
  }

  readonly property var dev: UPower.displayDevice
  readonly property bool upowerPresent: !!(dev && dev.isPresent)
  readonly property int upowerPercent: !upowerPresent ? 0
    : ((dev.state === UPowerDeviceState.FullyCharged || dev.state === UPowerDeviceState.PendingCharge) && (Number(dev.percentage) || 0) >= 0.99)
      ? 100
      : Math.round((Number(dev.percentage) || 0) * 100)
  readonly property string upowerStatus: !upowerPresent ? "Unknown"
    : dev.state === UPowerDeviceState.Charging ? "Charging"
    : dev.state === UPowerDeviceState.Discharging ? "Discharging"
    : dev.state === UPowerDeviceState.FullyCharged ? "Full"
    : dev.state === UPowerDeviceState.PendingCharge ? "Not charging"
    : "Unknown"

  readonly property var rawB: snapshot.battery || ({})
  readonly property var b: ({
    present: rawB.present === true || upowerPresent,
    percent: rawB.present === true ? (Number(rawB.percent) || 0) : upowerPercent,
    status: rawB.present === true ? String(rawB.status || "Unknown") : upowerStatus,
    watts: rawB.present === true ? (Number(rawB.watts) || 0) : (upowerPresent ? Math.abs(Number(dev.changeRate) || 0) : 0),
    minutes: rawB.present === true ? (Number(rawB.minutes) || 0) : (upowerPresent ? Math.round(((upowerStatus === "Charging" ? (Number(dev.timeToFull) || 0) : (Number(dev.timeToEmpty) || 0)) / 60)) : 0),
    health: Number(rawB.health) || 0,
    whFull: Number(rawB.whFull) || 0,
    whDesign: Number(rawB.whDesign) || 0,
    cycles: Number(rawB.cycles) || 0,
    tempC: rawB.tempC === undefined ? "" : rawB.tempC,
    acOnline: rawB.present === true ? (Number(rawB.acOnline) || 0) : (UPower.onBattery ? 0 : 1)
  })
  readonly property var profiles: snapshot.profiles || ({})
  readonly property var sleep: snapshot.sleep || ({})
  readonly property var charge: snapshot.charge || ({})
  readonly property string activeMode: Model.activeProfileMode(profiles)
  readonly property bool hasBattery: b.present === true

  function refresh() {
    if (!dataProc.running) dataProc.running = true
  }

  function runAction(args) {
    if (actionProc.running) return
    actionProc.command = args
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !showPercentage })
    if (bar && bar.shell && bar.shell.updateEntryInline) bar.shell.updateEntryInline(moduleName, root.settings)
  }

  function scriptPath(name) {
    return Qt.resolvedUrl("bin/" + name).toString().replace(/^file:\/\//, "")
  }

  function setProfile(mode) {
    runAction([scriptPath("battery-action"), "profile", mode])
  }

  function installSleepHook() {
    runAction([scriptPath("battery-action"), "install-sleep-hook"])
  }

  function installProfileHelper() {
    runAction([scriptPath("battery-action"), "install-profile-helper"])
  }

  function clearSleepStats() {
    runAction([scriptPath("battery-action"), "clear-sleep"])
  }

  function clearChargeHistory() {
    runAction([scriptPath("battery-action"), "clear-charge"])
  }

  function syncAutoProfile() {
    runAction([scriptPath("battery-action"), "auto-sync"])
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  onBChanged: if (root.opened) pushWattSample(b.watts)

  Component.onCompleted: refresh()

  Timer {
    interval: root.opened ? root.pollInterval : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      if (root.activeMode === "auto") root.syncAutoProfile()
      root.refresh()
    }
  }

  Process {
    id: dataProc
    command: [root.scriptPath("battery-data")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && parsed.battery) {
            root.snapshot = parsed
            root.debugError = ""
          } else {
            root.debugError = "No battery data"
          }
        } catch (e) {
          root.debugError = "Parse error"
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && parsed.battery) root.snapshot = parsed
        } catch (e) { root.refresh() }
      }
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function togglePercentage(): void { root.togglePercentage() }
    function refresh(): void { root.refresh() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? (Model.batteryIcon(hasBattery ? b.percent : 0, b.status) + "  " + (hasBattery ? b.percent : 0) + "%")
      : Model.batteryIcon(hasBattery ? b.percent : 0, b.status)
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2.2 : 1)
    tooltipText: hasBattery
      ? ("Battery " + b.percent + "% · " + Model.statusLabel(b) + (b.watts > 0 ? " · " + Model.fmtWatts(b.watts) : ""))
      : ("No battery detected" + (debugError ? " · " + debugError : ""))
    onPressed: function(btn) {
      if (btn === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420), Style.space(460))
    contentHeight: Math.max(Style.space(180), panel.fittedContentHeight(contentColumn.implicitHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }
      onMoveRequested: function(dx, dy) {
        if (dy) flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + dy * Style.space(48)))
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentColumn
          width: flick.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: "Battery"
            meta: Model.statusLabel(b) + (b.status === "Charging" && b.minutes > 0 ? " · " + Model.fmtDuration(b.minutes) + " to full" : (b.status === "Discharging" && b.minutes > 0 ? " · " + Model.fmtDuration(b.minutes) + " left" : ""))
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: Model.batteryIcon(b.percent, b.status)
                color: b.percent <= 10 && b.status === "Discharging" ? root.urgent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Text {
                text: (b.percent || 0) + "%"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Style.space(8)
            Rectangle { anchors.fill: parent; radius: height / 2; color: root.faint }
            Rectangle {
              height: parent.height
              radius: height / 2
              width: Math.max(height, parent.width * Math.max(0, Math.min(1, (Number(b.percent) || 0) / 100)))
              color: b.percent <= 10 && b.status === "Discharging" ? root.urgent : root.fg
              Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
            }
          }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(14)
            rowSpacing: Style.space(8)

            Stat { label: "Charge"; value: (b.percent || 0) + "%" }
            Stat { label: "Status"; value: Model.statusLabel(b) }
            Stat { label: "Draw"; value: Model.fmtWatts(b.watts) }
            Stat { label: "Time"; value: b.status === "Charging" ? Model.fmtDuration(b.minutes) + " to full" : (b.status === "Discharging" ? Model.fmtDuration(b.minutes) + " left" : "—") }
            Stat { label: "Health"; value: b.health ? b.health + "%" : "—" }
            Stat { label: "Cycles"; value: b.cycles ? String(b.cycles) : "—" }
            Stat { label: "Capacity"; value: b.whFull > 0 ? (Number(b.whFull).toFixed(1) + " / " + Number(b.whDesign).toFixed(1) + " Wh") : "—" }
            Stat { label: "Temp"; value: Model.fmtTemp(b.tempC) }
          }

          PanelSeparator { foreground: root.fg }
          PanelSectionHeader { text: "POWER PROFILE"; foreground: root.fg; fontFamily: root.fontFamily }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            ProfileButton { label: "Econom"; mode: "econom" }
            ProfileButton { label: "Normal"; mode: "normal" }
            ProfileButton { label: "Power"; mode: "power" }
            ProfileButton { label: "Auto"; mode: "auto" }
          }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(14)
            rowSpacing: Style.space(8)

            Stat { label: "CPU governor"; value: String(profiles.governor || "unknown") }
            Stat { label: "Turbo boost"; value: Number(profiles.boost) === 1 ? "On" : (Number(profiles.boost) === 0 ? "Off" : "—") }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.activeMode === "auto"
              ? "Auto: AC -> Power, battery -> Econom. Custom CPU profiles."
              : ("Active: " + Model.profileLabel(root.activeMode) + " · " + String(profiles.governor || "unknown") + " · boost " + (Number(profiles.boost) === 1 ? "on" : "off"))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            visible: profiles.helperInstalled !== true
            text: "Install profile helper"
            bordered: true
            focusable: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.installProfileHelper()
          }

          PanelSeparator { foreground: root.fg }
          PanelSectionHeader { text: "POWER DRAW"; foreground: root.fg; fontFamily: root.fontFamily }

          Column {
            width: parent.width
            spacing: Style.space(8)

            GridLayout {
              width: parent.width
              columns: 4
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(6)
              MiniStat { label: "Now"; value: Model.fmtWatts(root.wattStat("now")) }
              MiniStat { label: "Avg"; value: Model.fmtWatts(root.wattStat("avg")) }
              MiniStat { label: "Min"; value: Model.fmtWatts(root.wattStat("min")) }
              MiniStat { label: "Max"; value: Model.fmtWatts(root.wattStat("max")) }
            }

            Rectangle {
              width: parent.width
              height: Style.space(140)
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
              border.color: root.faint
              border.width: 1

              Item {
                id: wattGraph
                anchors.fill: parent
                anchors.margins: Style.space(10)
                property real maxW: Math.max(1, root.wattStat("max"), 5)
                property real minW: 0

                Repeater {
                  model: 4
                  Rectangle {
                    required property int index
                    x: 0
                    width: parent.width
                    height: 1
                    y: parent.height * index / 3
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                  }
                }

                Row {
                  anchors.fill: parent
                  spacing: 2
                  property var rows: root.wattHistory
                  property real barW: rows.length > 0 ? Math.max(2, (width - spacing * Math.max(0, rows.length - 1)) / rows.length) : width

                  Repeater {
                    model: wattGraph.parent ? root.wattHistory : []
                    Item {
                      required property var modelData
                      width: Math.max(2, (wattGraph.width - 2 * Math.max(0, root.wattHistory.length - 1)) / Math.max(1, root.wattHistory.length))
                      height: wattGraph.height
                      Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        radius: 1
                        height: Math.max(2, parent.height * Math.max(0, Number(modelData) || 0) / wattGraph.maxW)
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.8)
                      }
                    }
                  }
                }

                Text {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  text: wattGraph.maxW.toFixed(1) + "W"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
                Text {
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  text: "0W"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
              }
            }

            Text {
              width: parent.width
              text: "Live samples while panel is open · " + root.wattHistory.length + "/" + root.wattHistoryMax
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.fg }
          PanelSectionHeader { text: "CHARGING HISTORY"; foreground: root.fg; fontFamily: root.fontFamily }

          Column {
            width: parent.width
            spacing: Style.space(8)

            GridLayout {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(14)
              rowSpacing: Style.space(8)

              Stat { visible: charge.active === true; label: "Session"; value: Model.fmtElapsed(charge.activeSec || 0) }
              Stat { visible: charge.active === true; label: "Gained"; value: Model.fmtGain(charge.activeCapGain || 0) + " / " + Model.fmtWh(charge.activeWhGain || 0) }
              Stat { visible: charge.active === true; label: "Rate"; value: Model.fmtWatts(charge.activeRateW || 0) }
              Stat { visible: Number(charge.samples || 0) > 0; label: "Sessions"; value: String(charge.samples || 0) }
              Stat { visible: Number(charge.samples || 0) > 0; label: "Avg rate"; value: Model.fmtWatts(charge.avgRateW || 0) }
              Stat { visible: Number(charge.samples || 0) > 0; label: "Total gained"; value: Model.fmtWh(charge.totalGainWh || 0) }
              Stat { visible: Number(charge.samples || 0) > 0; label: "Last session"; value: Model.fmtElapsed(charge.last ? charge.last.durationSec : 0) }
              Stat { visible: Number(charge.samples || 0) > 0; label: "Last gain"; value: charge.last ? (Model.fmtGain(charge.last.capGain) + " / " + Model.fmtWh(charge.last.whGain)) : "—" }
              Stat { visible: Number(charge.samples || 0) > 0; label: "Last rate"; value: charge.last ? Model.fmtWatts(charge.last.avgRateW) : "—" }
            }

            Item {
              width: parent.width
              height: Style.space(18)
              visible: Number(charge.samples || 0) > 0
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "LAST 10 CHARGE SESSIONS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "battery % gained"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(110)
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
              border.color: root.faint
              border.width: 1
              visible: Number(charge.samples || 0) > 0

              Row {
                id: chargeGraph
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(4)
                property var rows: (charge.recent || []).slice(-10)
                property real maxGain: {
                  var m = 1
                  for (var i = 0; i < rows.length; i++) m = Math.max(m, Number(rows[i].capGain) || 0)
                  return m
                }

                Repeater {
                  model: chargeGraph.rows
                  Item {
                    required property var modelData
                    required property int index
                    width: Math.max(Style.space(18), (chargeGraph.width - chargeGraph.spacing * Math.max(0, chargeGraph.rows.length - 1)) / Math.max(1, chargeGraph.rows.length))
                    height: chargeGraph.height

                    Rectangle {
                      width: parent.width
                      radius: Style.space(3)
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: valueLabel.top
                      anchors.bottomMargin: Style.space(4)
                      height: Math.max(Style.space(2), (parent.height - Style.space(34)) * Math.max(0, Number(modelData.capGain) || 0) / chargeGraph.maxGain)
                      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.75)
                    }

                    Text {
                      id: valueLabel
                      textFormat: Text.PlainText
                      anchors.bottom: idxLabel.top
                      anchors.bottomMargin: Style.space(2)
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Model.fmtGain(modelData.capGain)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                    }

                    Text {
                      id: idxLabel
                      textFormat: Text.PlainText
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: String(index + 1)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                    }
                  }
                }
              }
            }

            Button {
              visible: Number(charge.samples || 0) > 0
              text: "Clear charging history"
              bordered: true
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.clearChargeHistory()
            }

            Text {
              width: parent.width
              visible: charge.active !== true && Number(charge.samples || 0) === 0
              textFormat: Text.PlainText
              text: "No charging sessions recorded yet. Plug in to start tracking."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.fg }
          PanelSectionHeader { text: "SLEEP STATISTICS"; foreground: root.fg; fontFamily: root.fontFamily }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: sleep.installed === true && Number(sleep.samples || 0) > 0

            GridLayout {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(14)
              rowSpacing: Style.space(8)

              Stat { label: "Sleep count"; value: String(sleep.samples || 0) }
              Stat { label: "Avg draw"; value: Number(sleep.avgDrawW || 0) > 0 ? Number(sleep.avgDrawW).toFixed(2) + " W" : "—" }
              Stat { label: "Last sleep"; value: Model.fmtSleepDuration(sleep.last ? sleep.last.durationSec : 0) }
              Stat { label: "Last time"; value: sleep.last ? Model.fmtAgo(sleep.last.endIso) : "—" }
              Stat { label: "Last drop"; value: sleep.last ? (Number(sleep.last.capDrop || 0).toFixed(1) + "% / " + Number(sleep.last.whDrop || 0).toFixed(2) + " Wh") : "—" }
              Stat { label: "Last draw"; value: sleep.last ? (Number(sleep.last.drawW || 0).toFixed(2) + " W") : "—" }
            }

            Item {
              width: parent.width
              height: Style.space(18)
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LAST 10 SLEEPS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "battery % drop"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(110)
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
              border.color: root.faint
              border.width: 1

              Row {
                id: sleepGraph
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(4)
                property var rows: (sleep.recent || []).slice(-10)
                property real maxDrop: {
                  var m = 1
                  for (var i = 0; i < rows.length; i++) m = Math.max(m, Number(rows[i].capDrop) || 0)
                  return m
                }

                Repeater {
                  model: sleepGraph.rows
                  Item {
                    required property var modelData
                    required property int index
                    width: Math.max(Style.space(18), (sleepGraph.width - sleepGraph.spacing * Math.max(0, sleepGraph.rows.length - 1)) / Math.max(1, sleepGraph.rows.length))
                    height: sleepGraph.height

                    Rectangle {
                      width: parent.width
                      radius: Style.space(3)
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: valueLabel.top
                      anchors.bottomMargin: Style.space(4)
                      height: Math.max(Style.space(2), (parent.height - Style.space(34)) * Math.max(0, Number(modelData.capDrop) || 0) / sleepGraph.maxDrop)
                      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.75)
                    }

                    Text {
                      id: valueLabel
                      textFormat: Text.PlainText
                      anchors.bottom: idxLabel.top
                      anchors.bottomMargin: Style.space(2)
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: (Number(modelData.capDrop) || 0).toFixed(1) + "%"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                    }

                    Text {
                      id: idxLabel
                      textFormat: Text.PlainText
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: String(index + 1)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                    }
                  }
                }
              }
            }

            Button {
              visible: Number(sleep.samples || 0) > 0
              text: "Clear sleep stats"
              bordered: true
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.clearSleepStats()
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !(sleep.installed === true && Number(sleep.samples || 0) > 0)

            Text {
              width: parent.width
              text: sleep.installed ? "Sleep tracking installed. Stats appear after the next suspend/resume." : "Sleep tracking is not installed yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              visible: !sleep.installed
              text: "Install sleep tracking hook"
              bordered: true
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.installSleepHook()
            }
          }

          Text {
            width: parent.width
            text: "R refresh · Esc close · Right click icon toggles percentage"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component Stat: Item {
    id: stat
    property string label: ""
    property string value: ""
    Layout.fillWidth: true
    implicitHeight: Math.max(l.implicitHeight, v.implicitHeight)

    Text {
      id: l
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: stat.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: v
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.left: l.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: stat.value
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  component MiniStat: Rectangle {
    id: ms
    property string label: ""
    property string value: ""
    Layout.fillWidth: true
    implicitHeight: Style.space(42)
    radius: Style.cornerRadius
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
    border.color: root.faint
    border.width: 1
    Column {
      anchors.centerIn: parent
      spacing: 1
      Text { textFormat: Text.PlainText; text: ms.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption - 1; horizontalAlignment: Text.AlignHCenter; width: ms.width - 8 }
      Text { textFormat: Text.PlainText; text: ms.value; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; horizontalAlignment: Text.AlignHCenter; width: ms.width - 8; elide: Text.ElideRight }
    }
  }

  component ProfileButton: Button {
    id: pbtn
    property string mode: "normal"
    Layout.fillWidth: true
    text: pbtn.label
    property string label: ""
    bordered: true
    focusable: true
    foreground: root.fg
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    active: root.activeMode === pbtn.mode
    onClicked: root.setProfile(pbtn.mode)
  }
}
