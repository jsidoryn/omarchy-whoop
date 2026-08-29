import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "io.github.jsidoryn.whoop"
  ipcTarget: "io.github.jsidoryn.whoop"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var whoopService: null
  property bool confirmDisconnect: false
  property double nowMs: Date.now()

  readonly property var fallbackSnapshot: ({
    state: "loading", mode: "demo", message: "Loading WHOOP",
    recovery: ({ score: null }), cycle: ({}), sleep: ({}), week: []
  })
  readonly property var service: whoopService
  readonly property var snapshotData: service && service.snapshot ? service.snapshot : fallbackSnapshot
  readonly property var recovery: snapshotData.recovery || ({})
  readonly property var cycle: snapshotData.cycle || ({})
  readonly property var sleep: snapshotData.sleep || ({})
  readonly property real recoveryScore: recovery.score === null || recovery.score === undefined ? -1 : Number(recovery.score)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showingDemo: snapshotData.mode === "demo"
  readonly property bool connected: service ? service.connected === true : false
  readonly property bool hasError: service && service.status === "error"
  readonly property bool refreshing: service ? service.refreshing === true : false

  function launchSetup() {
    if (!bar || !service || service.helper === "") return
    var command = "omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(service.helper) + " setup"
    bar.run(command)
    close()
  }

  function requestDisconnect() {
    if (!confirmDisconnect) {
      confirmDisconnect = true
      disconnectReset.restart()
      return
    }
    confirmDisconnect = false
    if (service) service.disconnect()
  }

  function setDemoSetting(enabled) {
    if (!hostWidget || !hostWidget.settings) return
    var entry = { id: moduleName }
    for (var key in hostWidget.settings) if (key !== "id") entry[key] = hostWidget.settings[key]
    entry.forceDemo = enabled
    hostWidget.settings = entry
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") bar.shell.updateEntryInline(moduleName, entry)
    if (service) settingsRefreshTimer.restart()
  }

  function useLiveData() {
    if (!service || !connected) return
    if (settings && settings.forceDemo === true) setDemoSetting(false)
    else service.refresh(true)
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    confirmDisconnect = false
    if (panelFlick) panelFlick.contentY = 0
    if (service) service.refresh(false)
    focusTimer.restart()
  }

  Timer {
    id: settingsRefreshTimer
    interval: 0
    repeat: false
    onTriggered: if (service) service.refresh(true)
  }

  Timer {
    id: focusTimer
    interval: 0
    repeat: false
    onTriggered: keyCatcher.forceActiveFocus()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: disconnectReset
    interval: 5000
    repeat: false
    onTriggered: root.confirmDisconnect = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(panelContent.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: connectButton.activeFocus || demoButton.activeFocus || liveButton.activeFocus || disconnectButton.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (service) service.refresh(false)
      onTextKey: function(text) {
        if ((text === "r" || text === "R") && service) service.refresh(false)
        else if ((text === "d" || text === "D") && service) service.nextDemo()
        else if ((text === "c" || text === "C") && root.showingDemo && !root.connected) root.launchSetup()
        else if ((text === "l" || text === "L") && root.showingDemo && root.connected) root.useLiveData()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: panelContent
          width: panelFlick.width
          spacing: Style.space(13)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(7)

                Text {
                  text: "WHOOP"
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                BorderSurface {
                  visible: root.showingDemo
                  implicitWidth: demoLabel.implicitWidth + Style.space(12)
                  implicitHeight: demoLabel.implicitHeight + Style.space(4)
                  radius: height / 2
                  color: Util.alpha(root.foreground, 0.08)
                  borderSpec: Border.flat(Util.alpha(root.foreground, 0.15), Style.spacing.hairline)

                  Text {
                    id: demoLabel
                    anchors.centerIn: parent
                    text: "DEMO"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Item { Layout.fillWidth: true }
              }

              Text {
                Layout.fillWidth: true
                text: root.hasError && service
                  ? service.message
                  : (root.refreshing ? "Refreshing…" : Model.freshness(root.snapshotData.fetchedAt, root.nowMs))
                textFormat: Text.PlainText
                color: root.hasError ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh · R"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.refreshing
              onClicked: if (service) service.refresh(false)
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Style.space(9)
            rowSpacing: Style.space(9)

            MetricTile {
              Layout.fillWidth: true
              label: "Recovery"
              value: Model.metric(root.recovery.score, "%")
              valueFontSize: Style.font.display
              foreground: root.foreground
            }

            MetricTile {
              Layout.fillWidth: true
              label: "Sleep"
              value: Model.metric(root.sleep.performance, "%")
              valueFontSize: Style.font.display
              foreground: root.foreground
            }

            MetricTile {
              Layout.fillWidth: true
              label: "Strain"
              value: Model.metric(root.cycle.strain, "", 1)
              valueFontSize: Style.font.display
              foreground: root.foreground
            }
          }

          BorderSurface {
            visible: root.showingDemo
            Layout.fillWidth: true
            implicitHeight: demoContent.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Util.alpha(Color.accent, 0.075)
            borderSpec: Border.flat(Util.alpha(Color.accent, 0.28), Style.spacing.hairline)

            ColumnLayout {
              id: demoContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: "Preview mode"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                text: root.connected
                  ? "Preview data is local. Your WHOOP connection is still saved; choose Use live data when you are ready."
                  : "Explore the panel now. Connect when your WHOOP developer app is ready. No sample value is written to your account."
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Button {
                  id: connectButton
                  visible: !root.connected
                  text: "Connect WHOOP"
                  iconText: "󰌷"
                  bordered: true
                  focusable: true
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.launchSetup()
                }

                Button {
                  id: demoButton
                  text: "Next preview"
                  iconText: "󰒭"
                  focusable: true
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  onClicked: if (service) service.nextDemo()
                }

                Item { Layout.fillWidth: true }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(7)

            PanelSectionHeader {
              text: "RECOVERY METRICS"
              textFormat: Text.PlainText
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            GridLayout {
              Layout.fillWidth: true
              columns: 2
              columnSpacing: Style.space(9)
              rowSpacing: Style.space(9)

              MetricTile {
                Layout.fillWidth: true
                label: "HRV"
                value: Model.metric(root.recovery.hrvMs, " ms", 1)
                detail: "RMSSD"
                foreground: root.foreground
              }

              MetricTile {
                Layout.fillWidth: true
                label: "Resting heart rate"
                value: Model.metric(root.recovery.restingHeartRate, " bpm")
                foreground: root.foreground
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(7)

            PanelSectionHeader {
              text: "SEVEN-DAY RECOVERY"
              textFormat: Text.PlainText
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            WeekStrip {
              Layout.fillWidth: true
              values: Model.safeWeek(root.snapshotData)
              foreground: root.foreground
              accent: Color.accent
              urgent: root.urgent
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: root.showingDemo
                ? (root.connected ? "D next preview · L live · R refresh" : "D next preview · C connect · R refresh")
                : "R refresh · Esc close"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Button {
              id: liveButton
              visible: root.showingDemo && root.connected
              text: "Use live data"
              focusable: true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.useLiveData()
            }

            Button {
              id: disconnectButton
              visible: root.connected
              text: root.confirmDisconnect ? "Confirm disconnect" : "Disconnect"
              focusable: true
              bordered: root.confirmDisconnect
              foreground: root.confirmDisconnect ? root.urgent : root.foreground
              accent: root.confirmDisconnect ? root.urgent : Color.accent
              fontFamily: root.fontFamily
              onClicked: root.requestDisconnect()
            }
          }
        }
      }
    }
  }
}
