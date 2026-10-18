import QtQuick
import qs.Commons

// Reads the loopback output like any video app would, so a working preview
// proves the camera reaches other programs. webcam-preview.sh runs ffmpeg,
// which keeps one small JPEG updated; this shows it about 12 times a second.
// Qt's own camera is not used: its cached format list could push a stale
// size onto the shared output and garble it for every app. Loaded on demand
// by ScrcpyPane; unloading it stops ffmpeg and closes the device.
Item {
  id: root
  property string device: ""
  // OmaDroid's per-user runtime folder, from ScrcpyPane's session path.
  property string runtimeDir: ""
  property int frames: 0
  property string error: ""
  // The driver's current format, e.g. "YU12:2032x1524@30", while a writer
  // streams to the output; empty otherwise. ffmpeg runs only then.
  property string streamFormat: ""
  // Restarts since the stream format last changed; capped so a stream that
  // never yields frames ends in an error instead of cycling forever.
  property int attempts: 0
  readonly property int maxAttempts: 3
  // ScrcpyPane lowers this while the next-session options are open.
  property real maxHeight: 320
  readonly property string token: Math.random().toString(36).slice(2, 10).replace(/[^a-z0-9]/g, "") || "frame"
  // A new file per run, so a frame left by the previous ffmpeg never counts
  // as the new one's; webcam-preview.sh deletes files older than a minute.
  property int run: 0
  readonly property string framePath: runtimeDir ? runtimeDir + "/preview-" + token + run + ".jpg" : ""
  readonly property string sysfs: "/sys/class/video4linux/" + device.replace(/^\/dev\//, "")
  readonly property string script: decodeURIComponent(Qt.resolvedUrl("webcam-preview.sh").toString().replace(/^file:\/\//, ""))
  property int tick: 0
  // Set while a restart waits for the previous ffmpeg to exit.
  property bool reopen: false
  implicitHeight: Math.min(frame.sourceSize.width > 0 ? width * frame.sourceSize.height / frame.sourceSize.width : width * 9 / 16, maxHeight)

  // Shrinks to the frame's shape when maxHeight caps the height, so a capped
  // preview is centered instead of pillarboxed across the full width.
  Rectangle {
    id: box
    anchors.centerIn: parent
    width: frame.sourceSize.height > 0 ? Math.min(root.width, root.height * frame.sourceSize.width / frame.sourceSize.height) : root.width
    height: root.height
    radius: Style.cornerRadius
    color: "black"
    clip: true

    Image {
      id: frame
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      cache: false
      asynchronous: true
      // Keeps the last frame up while the next one loads, so it never blinks.
      retainWhileLoading: true
      onStatusChanged: if (frame.status === Image.Ready && feeder.busy && root.frames < 2)
        root.frames++
    }
    // 12 reloads a second once frames flow; before that, twice a second, as
    // each load of a file ffmpeg has not written yet logs a warning.
    Timer {
      interval: root.frames > 0 ? 83 : 500
      repeat: true
      running: feeder.busy && !root.reopen && root.framePath !== ""
      onTriggered: frame.source = "file://" + root.framePath + "?" + (++root.tick)
    }
    PreviewSplash {
      id: splash
      anchors.fill: parent
      failed: root.error !== ""
      label: root.error || (root.streamFormat ? "Waiting for camera frames on " + root.device + "…" : "Waiting for scrcpy to stream to " + root.device + "…")
    }
  }

  Command {
    id: feeder
    onFinished: (code, output, error) => {
      if (root.reopen) {
        root.reopen = false;
        return root.open();
      }
      // A refusal (bad input, missing ffmpeg, a garbled output) is final.
      if (code === 2 || code === 3 || code === 127) {
        root.close();
        root.error = error.trim() || "The preview could not read " + root.device + ".";
        return;
      }
      // An ffmpeg that ended, even after frames flowed, is retried by the
      // watchdog within its attempt cap.
      if (root.streamFormat && !root.error) {
        root.close();
        watchdog.restart();
      }
    }
  }
  Command {
    id: probe
    onFinished: (code, output) => {
      var lines = output.trim().split("\n");
      var format = code === 0 && lines[0] === "capture" && lines[1] ? lines[1] : "";
      if (format !== root.streamFormat)
        root.streamFormat = format;
    }
  }
  // Fast until frames flow, then only to notice a format change.
  Timer {
    interval: root.frames >= 2 ? 5000 : 1000
    repeat: true
    triggeredOnStart: true
    running: root.device !== ""
    onTriggered: if (!probe.busy)
      probe.start(["cat", root.sysfs + "/state", root.sysfs + "/format"], 2)
  }
  // For a stream that yields no frames. Restarted by every open(), so it
  // never fires right after another restart.
  Timer {
    id: watchdog
    interval: 5000
    onTriggered: {
      if (root.frames >= 2 || root.error || !root.streamFormat)
        return;
      if (++root.attempts < root.maxAttempts)
        return root.open();
      root.close();
      root.error = "No frames from " + root.device + " after " + root.maxAttempts + " tries. Stop and start the webcam, then check Show log.";
    }
  }

  onStreamFormatChanged: {
    attempts = 0;
    if (streamFormat)
      splash.advance(0.85);
    open();
  }
  onRuntimeDirChanged: open()
  // An error replaces a frozen last frame with the splash and its message.
  onErrorChanged: if (error && splash.done)
    splash.start()
  Component.onDestruction: close()
  // A restart blanks the video, so the splash covers it again.
  onFramesChanged: {
    if (frames >= 2) {
      // A later ffmpeg exit gets the full set of retries again.
      attempts = 0;
      watchdog.stop();
      splash.finish();
    } else if (frames === 0 && splash.done)
      splash.start();
  }
  onDeviceChanged: streamFormat = ""

  function close() {
    watchdog.stop();
    frame.source = "";
    frames = 0;
    if (feeder.busy)
      feeder.interrupt();
  }
  // Restarts ffmpeg for the current stream; a running one is stopped first
  // and its exit starts the next.
  function open() {
    error = "";
    if (feeder.busy) {
      reopen = true;
      close();
      return;
    }
    close();
    if (!streamFormat || !runtimeDir)
      return;
    run++;
    watchdog.restart();
    feeder.start(["bash", script, device, framePath], 0);
  }
}
