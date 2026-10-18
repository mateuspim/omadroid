import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Webcam.js" as Webcam

// "Quality and adjustments" of the webcam form: folded by default with a
// one-line summary, unfolding to resolution, rate, bitrate, codec,
// orientation, zoom, smoothing and torch.
//
// Usage: WebcamDetails { options: webcamOptions }  // a WebcamOptions
ColumnLayout {
  id: root
  required property var options
  readonly property var webcam: options.webcam
  spacing: Style.space(6)

  // Buttons never elide, so the summary is a label that does; a long
  // button widened the popup.
  RowLayout {
    objectName: "omadroidWebcamDetailsToggle"
    Layout.fillWidth: true
    ActionButton {
      text: (root.options.webcamDetailsOpen ? "▾ " : "▸ ") + "Adjust"
      tooltipText: "Resolution, frame rate, bitrate, codec, orientation, zoom, smoothing and torch"
      Accessible.role: Accessible.Button
      Accessible.checkable: true
      Accessible.checked: root.options.webcamDetailsOpen
      Accessible.name: "Quality and adjustments"
      onClicked: root.options.webcamDetailsOpen = !root.options.webcamDetailsOpen
    }
    Label {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      text: Webcam.webcamSummary(root.webcam)
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
      color: Util.alpha(Commons.Color.foreground, 0.6)
      font.pixelSize: Style.font.bodySmall
      Accessible.name: "Current settings: " + text
    }
  }
  GridLayout {
    objectName: "omadroidWebcamDetails"
    Layout.fillWidth: true
    visible: root.options.webcamDetailsOpen
    columns: 2
    columnSpacing: Style.space(6)
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Resolution"
      value: root.webcam.size
      options: Webcam.cameraSizeOptions(root.options.currentCamera)
      Accessible.name: "Camera capture size"
      onChanged: value => root.options.setWebcam({ size: value })
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Frame rate"
      value: root.webcam.fps
      options: Webcam.cameraFpsOptions(root.options.currentCamera)
      Accessible.name: "Camera frame rate"
      onChanged: value => root.options.setWebcam({ fps: value })
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Bitrate"
      value: root.webcam.bitRate
      options: ["4", "6", "8", "12", "16", "24", "32", "40"].map(n => ({ value: n, label: n + " Mbps" }))
      Accessible.name: "Video bitrate"
      onChanged: value => root.options.setWebcam({ bitRate: value })
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Codec"
      value: root.webcam.codec
      options: [{ value: "h265", label: "H.265 · sharper" }, { value: "h264", label: "H.264 · compatible" }]
      Accessible.name: "Video codec"
      onChanged: value => root.options.setWebcam({ codec: value })
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Orientation"
      value: root.webcam.orientation
      options: [{ value: "0", label: "Normal" }, { value: "90", label: "Rotate 90°" }, { value: "180", label: "Rotate 180°" }, { value: "270", label: "Rotate 270°" }, { value: "flip0", label: "Mirror" }, { value: "flip90", label: "Mirror · 90°" }, { value: "flip180", label: "Mirror · 180°" }, { value: "flip270", label: "Mirror · 270°" }]
      Accessible.name: "Camera orientation"
      onChanged: value => root.options.setWebcam({ orientation: value }, true)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Zoom"
      value: root.webcam.zoom
      options: Webcam.cameraZoomOptions(root.options.currentCamera)
      Accessible.name: "Camera zoom"
      onChanged: value => root.options.setWebcam({ zoom: value }, true)
    }
    Dropdown {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      label: "Smoothing"
      value: root.webcam.buffer
      options: [{ value: "0", label: "Off" }, { value: "50", label: "50 ms" }, { value: "100", label: "100 ms" }, { value: "200", label: "200 ms" }]
      Accessible.name: "Wi-Fi smoothing buffer"
      Controls.ToolTip.text: "Delay frames a little to hide Wi-Fi stutter"
      Controls.ToolTip.visible: smoothingHover.hovered
      HoverHandler {
        id: smoothingHover
      }
      onChanged: value => root.options.setWebcam({ buffer: value }, true)
    }
    ActionButton {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.alignment: Qt.AlignBottom
      text: (root.webcam.torch ? "✓ " : "") + "Torch"
      selected: root.webcam.torch
      tooltipText: "Turn on the camera light while the webcam runs, on cameras that have one"
      Accessible.role: Accessible.Button
      Accessible.checkable: true
      Accessible.checked: root.webcam.torch
      onClicked: root.options.setWebcam({ torch: !root.webcam.torch }, true)
    }
  }
}
