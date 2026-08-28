import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root

  moduleName: "jsidoryn.whoop"

  readonly property var whoopService: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function syncService() {
    if (whoopService && typeof whoopService.configure === "function") whoopService.configure(settings)
    injectPanel()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("whoopService" in target) target.whoopService = root.whoopService
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: Qt.callLater(root.syncService)
  onSettingsChanged: Qt.callLater(root.syncService)
  onWhoopServiceChanged: Qt.callLater(root.syncService)
  Component.onCompleted: Qt.callLater(root.syncService)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.syncService)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : barContent.implicitWidth + Style.space(14)
    active: !!(root.whoopService && root.whoopService.state === "error")
    tooltipText: root.whoopService ? root.whoopService.tooltip : "WHOOP"
    onPressed: function(buttonCode) {
      if (!root.whoopService) return
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.whoopService.refresh()
      else root.toggle()
    }

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(5)

      RecoveryRing {
        width: Style.space(18)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        score: root.whoopService ? root.whoopService.recoveryScore : -1
        foreground: button.foreground
        accent: Color.accent
        urgent: button.activeColor
        lineWidth: Style.spaceReal(2)
        showValue: false
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.whoopService ? root.whoopService.barLabel : "—"
        textFormat: Text.PlainText
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        visible: !!(root.whoopService && root.whoopService.demoMode) && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: "D"
        textFormat: Text.PlainText
        color: Qt.darker(button.foreground, 1.45)
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}

