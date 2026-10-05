import QtQuick
import Quickshell.Io

// A long-running command whose output is handled as it arrives; Command.qml
// collects output until exit instead. Argument arrays only; no shell
// interpolation. `exited` reports only exits nobody asked for, so owners can
// retry; stop() and restarts are silent.
Item {
  id: root
  // "" passes stdout through in chunks as they are read, for framed output.
  property string splitMarker: "\n"
  property var pendingArgs: null
  property bool stopRequested: false
  readonly property bool running: process.running
  signal read(string data)
  signal errorRead(string line)
  signal exited(int code)

  // Restarts the command when it is already running.
  function start(args) {
    if (process.running) {
      pendingArgs = args;
      stopRequested = true;
      process.running = false;
      return;
    }
    launch(args);
  }

  function stop() {
    pendingArgs = null;
    startupCheck.stop();
    if (!process.running)
      return;
    stopRequested = true;
    process.running = false;
  }

  function launch(args) {
    pendingArgs = null;
    stopRequested = false;
    process.command = args;
    process.running = true;
    startupCheck.restart();
  }

  function finish(code) {
    startupCheck.stop();
    if (pendingArgs)
      return launch(pendingArgs);
    if (!stopRequested)
      exited(code);
    stopRequested = false;
  }

  Process {
    id: process
    onStarted: startupCheck.stop()
    // Output after a stop belongs to the old run ("Got SIGTERM, quitting.").
    stdout: SplitParser {
      splitMarker: root.splitMarker
      onRead: data => {
        if (!root.stopRequested)
          root.read(data);
      }
    }
    stderr: SplitParser {
      onRead: data => {
        if (!root.stopRequested)
          root.errorRead(data);
      }
    }
    onExited: (exitCode, exitStatus) => root.finish(exitStatus === 0 ? exitCode : (exitCode || 1))
  }
  // A missing executable never starts, so no exit is reported for it.
  Timer {
    id: startupCheck
    interval: 2000
    onTriggered: if (!process.running)
      root.finish(127)
  }
}
