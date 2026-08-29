import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string label: ""
  property string value: "—"
  property string detail: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real valueFontSize: Style.font.heading

  implicitHeight: content.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  color: Util.alpha(foreground, 0.045)
  borderSpec: Border.flat(Util.alpha(foreground, 0.11), Style.spacing.hairline)

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: Style.space(10)
    spacing: Style.space(2)

    Text {
      width: parent.width
      text: root.label.toUpperCase()
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.value
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: root.valueFontSize
      font.bold: true
    }

    Text {
      visible: root.detail !== ""
      width: parent.width
      text: root.detail
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.25)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
