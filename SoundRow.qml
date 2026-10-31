import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SoundVolume.js" as SoundVolume

// One row of the device page's Sound section: mute toggle, name, value and a
// slider, laid out like the Omarchy audio panel's app rows. Right-click on the slider mutes too.
// The wheel scrolls the page instead of changing the volume: on a page of
// sliders, scrolling past one shouldn't change it.
ColumnLayout {
  id: root
  property string label: ""
  property string detail: ""
  property int volume: 0
  property int minimum: 0
  property int maximum: 100
  property bool muted: false
  property bool canMute: true
  property bool hasSlider: true
  // The app's label is being read from its APK (device-volume.sh "naming").
  property bool naming: false
  // The Flickable the wheel scrolls; null leaves the wheel unused.
  property var scrollView: null
  // final is false while dragging; the last value of a drag comes with true.
  signal volumeChosen(int value, bool final)
  signal muteToggled
  spacing: Style.space(2)

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Text {
      objectName: "soundMute"
      Layout.preferredWidth: Style.space(22)
      textFormat: Text.PlainText
      text: root.muted ? "󰝟" : "󰕾"
      color: Commons.Color.foreground
      opacity: root.canMute ? (root.muted ? 0.5 : 1) : 0.3
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
      Accessible.role: Accessible.CheckBox
      Accessible.name: "Mute " + root.label
      Accessible.checkable: true
      Accessible.checked: root.muted
      MouseArea {
        anchors.fill: parent
        enabled: root.canMute
        cursorShape: Qt.PointingHandCursor
        onClicked: root.muteToggled()
      }
    }
    Label {
      Layout.fillWidth: true
      text: root.label + (root.detail ? " · " + root.detail : "")
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
    }
    // Shown while the name is fetched in the background, so the package name
    // above reads as temporary rather than as the app's name.
    RowLayout {
      objectName: "soundNaming"
      visible: root.naming
      spacing: Style.space(4)
      Accessible.role: Accessible.StaticText
      Accessible.name: "Reading the app's name"
      Text {
        textFormat: Text.PlainText
        text: "󰑓"
        color: Util.alpha(Commons.Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        RotationAnimation on rotation {
          running: root.naming && root.visible
          from: 0
          to: 360
          duration: 1000
          loops: Animation.Infinite
        }
      }
      Label {
        text: "reading name"
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        font.pixelSize: Style.font.bodySmall
        color: Util.alpha(Commons.Color.foreground, 0.6)
      }
    }
    Label {
      text: SoundVolume.volumeText(root.volume, root.maximum, root.muted)
      wrapMode: Text.NoWrap
      font.pixelSize: Style.font.bodySmall
      color: Util.alpha(Commons.Color.foreground, 0.7)
      visible: root.hasSlider || root.muted
    }
  }
  PanelSlider {
    Layout.fillWidth: true
    visible: root.hasSlider
    minimum: root.minimum
    maximum: root.maximum
    integer: true
    step: root.maximum > 20 ? 5 : 1
    value: root.volume
    opacity: root.muted ? 0.5 : 1
    trackColor: Util.alpha(Commons.Color.foreground, 0.15)
    fillColor: Commons.Color.accent
    knobColor: Commons.Color.foreground
    onMoved: value => root.volumeChosen(Math.round(value), false)
    onReleased: value => root.volumeChosen(Math.round(value), true)
    onRightClicked: if (root.canMute)
      root.muteToggled()
    // Above the slider's own MouseArea; NoButton lets presses and drags through.
    MouseArea {
      anchors.fill: parent
      z: 1
      acceptedButtons: Qt.NoButton
      onWheel: wheel => {
        var view = root.scrollView;
        if (!view)
          return;
        var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2;
        view.contentY = Math.max(0, Math.min(Math.max(0, view.contentHeight - view.height), view.contentY - delta));
      }
    }
  }
}
