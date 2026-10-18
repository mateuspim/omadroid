import QtQuick
import QtQuick.Layouts

// The Mirror section of a device page: the running mirror or audio session
// of this device with its next-session options folded, a notice when another
// session runs, or the mirror options.
//
// Public API (beyond SessionSection's serial, session, device, devices,
// panelOpen, optionsExpanded, sessionHere, sessionElsewhere, optionsTop,
// showSessionRequested(kind)):
//   options  the MirrorOptions form (profile, launch(audioOnly), …)
//
// Usage:
//   MirrorSection {
//     serial: page.serial
//     device: page.row
//     session: mirrorSession
//     panelOpen: popup.opened && page.section === "mirror"
//   }
SessionSection {
  id: root
  kind: "mirror"
  readonly property alias options: mirrorOptions

  MirrorOptions {
    id: mirrorOptions
    Layout.fillWidth: true
    serial: root.serial
    session: root.session
    ready: !!root.device && root.device.status === "device"
  }
}
