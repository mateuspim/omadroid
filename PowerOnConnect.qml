import QtQuick
import "DevicePower.js" as DevicePower

// Runs `device-power.sh connected` for devices that just became ready: their
// keepers come back (wireless reconnects change the adb serial), and the
// on-connect settings wake or unlock them. Lives in the shared discovery
// service so two bars don't act twice.
Item {
  id: root
  property var readySerials: []
  // False until discovery's first device list; devices in it were already
  // connected before the shell (re)started.
  property bool started: false
  property bool wake: false
  property bool unlock: false
  property var known: []
  property var queued: []
  property bool queuedAtStartup: false
  readonly property string powerScript: decodeURIComponent(Qt.resolvedUrl("scripts/device-power.sh").toString().replace(/^file:\/\//, ""))

  onReadySerialsChanged: {
    var fresh = DevicePower.newlyReady(known, readySerials);
    known = readySerials.slice();
    if (!fresh.length)
      return;
    queued = queued.concat(DevicePower.newlyReady(queued, fresh));
    queuedAtStartup = queuedAtStartup || !started;
    runQueued();
  }

  function runQueued() {
    if (command.busy || !queued.length)
      return;
    var args = DevicePower.connectedCommand(powerScript, queued, wake, unlock, queuedAtStartup);
    queued = [];
    queuedAtStartup = false;
    command.start(args, 60);
  }

  Command {
    id: command
    // Failures (an unreachable device, no saved PIN) are shown on the device page
    // when it opens; there is nothing to report here.
    onFinished: (code, output, error) => root.runQueued()
  }
}
