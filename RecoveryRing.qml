import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property real score: -1
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property real lineWidth: Style.spaceReal(6)
  property bool showValue: true
  property real valueFontSize: Style.font.display

  readonly property var band: Model.recoveryBand(score >= 0 ? score : null)
  readonly property color scoreColor: band.colorRole === "positive" ? accent
    : (band.colorRole === "urgent" ? urgent
      : (band.colorRole === "warning" ? foreground : Color.muted))

  implicitWidth: Style.space(82)
  implicitHeight: implicitWidth

  onScoreChanged: ring.requestPaint()
  onScoreColorChanged: ring.requestPaint()
  onForegroundChanged: ring.requestPaint()
  onWidthChanged: ring.requestPaint()
  onHeightChanged: ring.requestPaint()

  Canvas {
    id: ring
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var size = Math.min(width, height)
      var radius = Math.max(1, size / 2 - root.lineWidth)
      var centerX = width / 2
      var centerY = height / 2
      var start = -Math.PI / 2
      ctx.lineWidth = root.lineWidth
      ctx.lineCap = "round"
      ctx.strokeStyle = Util.alpha(root.foreground, 0.13)
      ctx.beginPath()
      ctx.arc(centerX, centerY, radius, 0, Math.PI * 2)
      ctx.stroke()
      if (root.score >= 0) {
        ctx.strokeStyle = root.scoreColor
        ctx.beginPath()
        ctx.arc(centerX, centerY, radius, start, start + Math.PI * 2 * Math.max(0, Math.min(100, root.score)) / 100)
        ctx.stroke()
      }
    }
  }

  Text {
    visible: root.showValue
    anchors.centerIn: parent
    text: root.score >= 0 ? String(Math.round(root.score)) : "…"
    textFormat: Text.PlainText
    color: root.scoreColor
    font.family: Style.font.family
    font.pixelSize: root.valueFontSize
    font.bold: true
  }
}
