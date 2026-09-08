import QtQuick
import Quickshell.Io

// Argument arrays only; no shell interpolation. Each invocation has fresh and
// bounded output. Process.running = false is Quickshell's native SIGTERM path.
Item {
  id: root
  property bool busy: false
  property string output: ""
  property string errorOutput: ""
  property string input: ""
  property bool stopRequested: false
  property bool forceStopped: false
  signal finished(int code, string output, string error)

  function start(args, seconds, stdinText) {
    if (busy)
      return false;
    output = "";
    errorOutput = "";
    input = stdinText || "";
    stopRequested = false;
    forceStopped = false;
    process.stdinEnabled = input.length > 0;
    process.command = (seconds > 0 ? ["/usr/bin/timeout", "--signal=TERM", "--kill-after=2s", seconds + "s"] : []).concat(args);
    busy = true;
    process.running = true;
    startupCheck.restart();
    return true;
  }

  function complete(code) {
    if (!busy)
      return;
    startupCheck.stop();
    forceStop.stop();
    input = "";
    busy = false;
    finished(code, output, errorOutput);
  }

  function interrupt() {
    if (!process.running)
      return;
    stopRequested = true;
    // Quickshell guarantees this sends SIGTERM to the exact Process command.
    forceStop.restart();
    process.running = false;
  }

  Process {
    id: process
    onStarted: {
      startupCheck.stop();
      if (root.input)
        write(root.input);
      root.input = "";
      stdinEnabled = false;
    }
    stdout: SplitParser {
      onRead: data => root.output = (root.output + data + "\n").slice(-262144)
    }
    stderr: SplitParser {
      onRead: data => root.errorOutput = (root.errorOutput + data + "\n").slice(-8192)
    }
    onExited: (exitCode, exitStatus) => root.complete(exitStatus === 0 ? exitCode : (exitCode || 1))
  }
  Timer {
    id: startupCheck
    interval: 2000
    onTriggered: if (!process.running)
      root.complete(127)
  }
  Timer {
    id: forceStop
    interval: 4000
    onTriggered: if (root.busy && process.running) {
      root.forceStopped = true;
      process.signal(9);
    }
  }
}
