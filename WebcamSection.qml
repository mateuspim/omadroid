import QtQuick
import QtQuick.Layouts

// The Webcam section of a device page: this device's running webcam (with
// Preview and Apply) and its next-session settings folded, a notice when
// another session runs, or the webcam settings.
//
// Public API (beyond SessionSection's serial, session, device, devices,
// panelOpen, optionsExpanded, previewOpen, sessionHere, sessionElsewhere,
// optionsTop, showSessionRequested(kind)):
//   options  the WebcamOptions form (webcam, setWebcam(), launchWebcam(), …)
//   panelOpen also gates the camera scan: pass true only while shown.
//
// Usage:
//   WebcamSection {
//     serial: page.serial
//     device: page.row
//     session: mirrorSession
//     panelOpen: popup.opened && page.section === "webcam"
//   }
SessionSection {
  id: root
  kind: "webcam"
  readonly property alias options: webcamOptions
  webcamChanged: webcamOptions.webcamChanged
  onApplyRequested: webcamOptions.applyWebcam()

  WebcamOptions {
    id: webcamOptions
    Layout.fillWidth: true
    serial: root.serial
    session: root.session
    ready: !!root.device && root.device.status === "device"
    panelOpen: root.panelOpen
  }
}
