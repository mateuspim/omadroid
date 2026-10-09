import QtQuick
import Quickshell.Io

// Argument arrays only; no shell interpolation. Each invocation has fresh and
// bounded output. Process.running = false is Quickshell's native SIGTERM path.
Item {
  id: root
  // Never drawn; hidden so a parent layout skips it instead of adding spacing
  // for it (seven of them left a gap above "Mirror with scrcpy").
  visible: false
  property bool busy: false
  property string output: ""
  property string errorOutput: ""
  // Lines are collected as chunks and joined on exit; rebuilding the string
  // per line made long outputs quadratic.
  property var outputChunks: []
  property var errorChunks: []
  property string input: ""
  property bool stopRequested: false
  property bool forceStopped: false
  // Only this owned child may receive the mirroring screen-power shortcuts.
  readonly property int childPid: process.running ? Number(process.processId) || 0 : 0
  signal finished(int code, string output, string error)

  function start(args, seconds, stdinText) {
    if (busy)
      return false;
    output = "";
    errorOutput = "";
    outputChunks = [];
    errorChunks = [];
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
    output = joined(outputChunks, 262144);
    errorOutput = joined(errorChunks, 8192);
    outputChunks = [];
    errorChunks = [];
    busy = false;
    finished(code, output, errorOutput);
  }

  function joined(chunks, limit) {
    return chunks.join("").slice(-limit);
  }

  // Keeps the tail within limit, compacting only past twice the limit so
  // appends stay amortized O(1).
  function append(chunks, line, limit) {
    chunks.push(line + "\n");
    chunks.size = (chunks.size || 0) + line.length + 1;
    if (chunks.size <= limit * 2)
      return;
    var tail = joined(chunks, limit);
    chunks.length = 0;
    chunks.push(tail);
    chunks.size = tail.length;
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
      onRead: data => root.append(root.outputChunks, data, 262144)
    }
    stderr: SplitParser {
      onRead: data => root.append(root.errorChunks, data, 8192)
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
