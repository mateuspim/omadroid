import QtQuick
import QtQuick.Shapes
import qs.Commons

// Native rendering of icon.svg (24-unit grid): an Android head over a `>_`
// prompt. Drawn with Shapes rather than an Image so it follows the bar
// colour and stays crisp in small bar slots, like Omarchy's TailscaleIcon.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  readonly property real unit: iconSize / 24

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // Head: half disc with the eyes cut out by the odd-even fill.
    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      fillRule: ShapePath.OddEvenFill
      scale: Qt.size(root.unit, root.unit)
      PathSvg { path: "M3.5 13.5 A8.5 8.5 0 0 1 20.5 13.5 Z M7.35 9.6 A1.25 1.25 0 1 0 9.85 9.6 A1.25 1.25 0 1 0 7.35 9.6 Z M14.15 9.6 A1.25 1.25 0 1 0 16.65 9.6 A1.25 1.25 0 1 0 14.15 9.6 Z" }
    }

    // Antennas and the prompt chevron.
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: 1.6 * root.unit
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      scale: Qt.size(root.unit, root.unit)
      PathSvg { path: "M6.6 5.9 L4.9 3.2 M17.4 5.9 L19.1 3.2 M4.2 16.4 L6.8 18.4 L4.2 20.4" }
    }
  }

  // Cursor of the prompt.
  Rectangle {
    x: 9.5 * root.unit
    y: 19.2 * root.unit
    width: 11 * root.unit
    height: 2.2 * root.unit
    radius: root.unit
    color: root.color
  }
}
