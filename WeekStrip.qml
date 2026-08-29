import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

BorderSurface {
  id: root

  property var values: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property real maximum: 100
  property int digits: 0
  property string colorMode: "recovery"

  readonly property var days: values || []

  function pointValue(point) {
    var value = point && point.value !== undefined ? Number(point.value) : Number(point && point.score || 0)
    return isFinite(value) ? value : 0
  }

  function pointColor(point) {
    var value = pointValue(point)
    if (colorMode !== "recovery") return accent
    return value >= 67 ? accent : (value < 34 ? urgent : foreground)
  }

  function pointLabel(point) {
    return pointValue(point).toFixed(digits)
  }

  implicitHeight: Style.space(104)
  radius: Style.cornerRadius
  color: Util.alpha(foreground, 0.035)
  borderSpec: Border.flat(Util.alpha(foreground, 0.10), Style.spacing.hairline)

  RowLayout {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(7)

    Repeater {
      model: root.days

      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.space(3)

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Rectangle {
            width: Math.max(Style.space(5), parent.width * 0.42)
            height: Math.max(Style.space(5), parent.height * Math.max(0.08, Math.min(1, root.pointValue(modelData) / root.maximum)))
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            radius: width / 2
            color: root.pointColor(modelData)
            opacity: 0.9
          }
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: root.pointLabel(modelData)
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: Qt.formatDate(new Date(String(modelData.date || "")), "ddd").slice(0, 1)
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      visible: root.days.length === 0
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      text: "No scored data yet"
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: Qt.darker(root.foreground, 1.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
