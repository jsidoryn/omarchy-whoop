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

  readonly property var days: values || []

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
            height: Math.max(Style.space(5), parent.height * Math.max(0.08, Number(modelData.score || 0) / 100))
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            radius: width / 2
            color: Number(modelData.score || 0) >= 67 ? root.accent
              : (Number(modelData.score || 0) < 34 ? root.urgent : root.foreground)
            opacity: 0.9
          }
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: String(Math.round(Number(modelData.score || 0)))
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
  }
}

