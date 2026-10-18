import QtQuick
import qs.Commons
import qs.Commons as Commons
import "SendText.js" as SendText

// The Send text prompt's line: typed text as text, recorded keys as chips,
// then a blinking cursor. Wraps when it gets long.
Flow {
  id: root

  property var steps: []
  property string placeholder: ""
  property color foreground: Commons.Color.menu.text
  // After Ctrl+K: a dashed chip shows where the next key goes.
  property bool waiting: false
  readonly property int lineHeight: Math.ceil(metrics.height)

  spacing: Style.space(3)

  FontMetrics {
    id: metrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.heading
  }

  Text {
    visible: root.steps.length === 0 && !root.waiting
    textFormat: Text.PlainText
    text: root.placeholder
    color: root.foreground
    opacity: 0.58
    font: metrics.font
  }

  Repeater {
    model: root.steps

    Item {
      id: step
      required property var modelData
      readonly property bool isKey: "key" in modelData
      objectName: isKey ? "sendTextKey:" + modelData.key : "sendTextRun"
      width: isKey ? chip.width : Math.min(run.implicitWidth, root.width)
      height: isKey ? root.lineHeight : run.height

      Text {
        id: run
        visible: !step.isKey
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        text: step.isKey ? "" : step.modelData.text
        color: root.foreground
        font: metrics.font
      }

      Rectangle {
        id: chip
        visible: step.isKey
        anchors.verticalCenter: parent.verticalCenter
        width: chipLabel.implicitWidth + Style.space(12)
        height: chipLabel.implicitHeight + Style.space(6)
        radius: Style.space(4)
        color: Commons.Color.menu.selectedBackground
        border.width: 1
        border.color: Qt.alpha(Commons.Color.menu.selectedText, 0.5)

        Text {
          id: chipLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: step.isKey ? SendText.keyLabel(step.modelData.key) : ""
          color: Commons.Color.menu.selectedText
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  Rectangle {
    visible: root.waiting
    width: waitingLabel.implicitWidth + Style.space(12)
    height: root.lineHeight
    radius: Style.space(4)
    color: "transparent"
    border.width: 1
    border.color: Commons.Color.menu.selectedText

    Text {
      id: waitingLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "press a key…"
      color: Commons.Color.menu.selectedText
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
  }

  Rectangle {
    id: cursor
    width: Math.max(1, Style.space(2))
    height: root.lineHeight
    color: root.foreground

    SequentialAnimation on opacity {
      loops: Animation.Infinite
      NumberAnimation { to: 0; duration: 530; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1; duration: 530; easing.type: Easing.InOutQuad }
    }
  }
}
