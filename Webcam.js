.import "DeviceInfo.js" as DeviceInfo
// Webcam projections (camera list, options, presets, scrcpy camera command,
// setup steps): shared by QML and the Node fixture tests.

/** Parse `scrcpy --list-camera-sizes`. Example line pair:
 * "--camera-id=1    (front, 2032x1524, fps={10, 15, 30}, zoom-range=[1, 8])" then "- 1920x1080"
 * → [{ id: "1", facing: "front", sensor: "2032x1524", fps: [10, 15, 30], zoom: [1, 8], sizes: ["1920x1080"] }].
 * High-speed sizes are left out; OmaDroid does not use high-speed capture.
 */
function parseCameraList(output) {
  var cameras = [], current = null, highSpeed = false;
  String(output || "").split("\n").forEach(function(line) {
    var head = /--camera-id=([0-9A-Za-z_.-]+)\s+\(([^)]*)\)/.exec(line);
    if (head) {
      var fields = head[2], fps = /fps=[{\[]([^}\]]*)[}\]]/.exec(fields), zoom = /zoom-range=\[([^\]]*)\]/.exec(fields);
      var sensor = /(\d+x\d+)/.exec(fields);
      current = {
        id: head[1],
        facing: (/^\s*(front|back|external)/.exec(fields) || [, "external"])[1],
        sensor: sensor ? sensor[1] : "",
        fps: fps ? fps[1].split(",").map(Number).filter(function(n) { return n > 0; }) : [],
        zoom: zoom ? zoom[1].split(",").map(Number) : null,
        sizes: []
      };
      highSpeed = false;
      cameras.push(current);
      return;
    }
    if (!current) return;
    if (/high.speed/i.test(line)) { highSpeed = true; return; }
    var size = /^\s*-\s*(\d+x\d+)\s*$/.exec(line);
    if (size && !highSpeed && current.sizes.indexOf(size[1]) < 0) current.sizes.push(size[1]);
  });
  return cameras;
}

/** Example: cameraLabel({ id: "2", facing: "front", sensor: "4000x3000" }) → "Front · 4000×3000 · camera 2" */
function cameraLabel(camera) {
  var facing = camera.facing.charAt(0).toUpperCase() + camera.facing.slice(1);
  return [facing, camera.sensor.replace("x", "×"), "camera " + camera.id].filter(Boolean).join(" · ");
}

/** Camera choices: every listed camera by id, else the two facings. Values are "id:N", "front" or "back". */
function cameraOptions(cameras) {
  if (!cameras || !cameras.length) return [{ value: "front", label: "Front" }, { value: "back", label: "Back" }];
  return cameras.map(function(camera) { return { value: "id:" + camera.id, label: cameraLabel(camera) }; });
}

/** The listed camera a choice names: by id, or the first with that facing (what scrcpy picks). */
function chosenCamera(cameras, choice) {
  if (!cameras) return null;
  var id = /^id:(.+)$/.exec(choice || "");
  return cameras.find(function(camera) { return id ? camera.id === id[1] : camera.facing === choice; }) || null;
}

var sizeNames = { "3840x2160": "4K", "2560x1440": "1440p", "1920x1080": "1080p", "1280x720": "720p" };

/** Example: sizeLabel("3840x2160") → "3840×2160 · 16:9 · 4K" */
function sizeLabel(size) {
  var parts = size.split("x").map(Number);
  return [size.replace("x", "×"), DeviceInfo.aspectRatio(parts[0], parts[1]), sizeNames[size] || ""].filter(Boolean).join(" · ");
}

/** Sizes worth offering for a webcam, largest first: the camera's list from
 * 640 px wide up, else common sizes when the camera is unknown. */
function cameraSizeOptions(camera) {
  var sizes = camera && camera.sizes.length ? camera.sizes : ["1920x1080", "1280x720", "640x480"];
  sizes = sizes.filter(function(size) { return Number(size.split("x")[0]) >= 640; }).sort(function(a, b) {
    var pa = a.split("x").map(Number), pb = b.split("x").map(Number);
    return pb[0] * pb[1] - pa[0] * pa[1] || pb[0] - pa[0];
  });
  return [{ value: "auto", label: "Automatic · camera default" }].concat(sizes.map(function(size) { return { value: size, label: sizeLabel(size) }; }));
}

/** Frame rates the camera lists (Android's default is 30), else 15, 24 and 30. */
function cameraFpsOptions(camera) {
  var rates = camera && camera.fps.length ? camera.fps.filter(function(n) { return n >= 10; }) : [15, 24, 30];
  // A camera listing only slow rates still offers them.
  if (!rates.length) rates = camera.fps.slice();
  return rates.slice().sort(function(a, b) { return b - a; }).map(function(n) { return { value: String(n), label: n + " fps" }; });
}

/** Initial zoom steps within the camera's range; 1× when the range is unknown. */
function cameraZoomOptions(camera) {
  var range = camera && camera.zoom && camera.zoom.length === 2 ? camera.zoom : [1, 1];
  return [1, 1.5, 2, 3, 4, 6, 8, 10].filter(function(z) { return z >= range[0] && z <= range[1]; }).map(function(z) {
    return { value: String(z), label: z + "×" };
  });
}

/** Quality presets: a target size (the closest the camera supports is used), fps, Mbps and codec. */
function webcamPresets() {
  return [
    { value: "call", label: "Call · 1080p · 30 fps · 12 Mbps", size: "1920x1080", fps: "30", bitRate: "12", codec: "h265" },
    { value: "sharp", label: "Sharp · 4K · 30 fps · 24 Mbps", size: "3840x2160", fps: "30", bitRate: "24", codec: "h265" },
    { value: "saver", label: "Saver · 720p · 24 fps · 6 Mbps", size: "1280x720", fps: "24", bitRate: "6", codec: "h264" }
  ];
}

/** The target size if the camera lists it, else its largest size of the same
 * aspect no larger than the target, else "auto". Unknown cameras get the target. */
function pickCameraSize(camera, target) {
  if (!camera || !camera.sizes.length) return target;
  if (camera.sizes.indexOf(target) >= 0) return target;
  var t = target.split("x").map(Number), want = DeviceInfo.aspectRatio(t[0], t[1]);
  var fits = camera.sizes.filter(function(size) {
    var p = size.split("x").map(Number);
    return p[0] <= t[0] && p[1] <= t[1] && DeviceInfo.aspectRatio(p[0], p[1]) === want;
  });
  // Not cameraSizeOptions: with nothing left it offers generic sizes.
  fits.sort(function(a, b) { return Number(b.split("x")[0]) * Number(b.split("x")[1]) - Number(a.split("x")[0]) * Number(a.split("x")[1]); });
  return fits.length ? fits[0] : "auto";
}

/** The highest listed rate no faster than `target`, else the camera's slowest. */
function pickCameraFps(camera, target) {
  var rates = cameraFpsOptions(camera).map(function(o) { return Number(o.value); });
  if (!rates.length) rates = camera.fps.slice().sort(function(a, b) { return b - a; });
  var fit = rates.find(function(n) { return n <= Number(target); });
  return String(fit || rates[rates.length - 1] || target);
}

/** Example: webcamSummary({ size: "1920x1080", fps: "30", bitRate: "12", codec: "h265", orientation: "flip0", zoom: "2", torch: true, buffer: "0" })
 * → "1080p · 30 fps · 12 Mbps · H.265 · Mirror · 2× · Torch" */
function webcamSummary(o) {
  var size = o.size === "auto" ? "Auto size" : sizeNames[o.size] || o.size.replace("x", "×");
  var turn = { "0": "", "90": "90°", "180": "180°", "270": "270°", flip0: "Mirror", flip90: "Mirror 90°", flip180: "Mirror 180°", flip270: "Mirror 270°" }[o.orientation] || "";
  return [size, o.fps + " fps", o.bitRate + " Mbps", o.codec === "h265" ? "H.265" : o.codec === "h264" ? "H.264" : o.codec.toUpperCase(), turn,
    Number(o.zoom) !== 1 ? o.zoom + "×" : "", o.torch ? "Torch" : "", o.buffer !== "0" ? o.buffer + " ms" : ""].filter(Boolean).join(" · ");
}

var webcamDefaults = { camera: "front", orientation: "0", preset: "call", size: "1920x1080", fps: "30", bitRate: "12", codec: "h265", zoom: "1", torch: false, buffer: "0" };

/** Saved webcam settings over the defaults; unknown keys and bad JSON are dropped. */
function webcamSettings(json) {
  var saved = {};
  try { saved = JSON.parse(json || "{}") || {}; } catch (e) { saved = {}; }
  var out = {};
  Object.keys(webcamDefaults).forEach(function(key) {
    out[key] = saved[key] !== undefined && typeof saved[key] === typeof webcamDefaults[key] ? saved[key] : webcamDefaults[key];
  });
  return out;
}

/** Build a camera sink command from webcamSettings-shaped options.
 * Example: webcamCommand('USB', { camera: 'id:2', orientation: '0', size: '1920x1080', fps: '30', bitRate: '12', codec: 'h265', zoom: '1', torch: false, buffer: '0' }, '/dev/video10')
 */
function webcamCommand(serial, options, sink) {
  var o = options || {};
  if (!serial || /[\x00-\x1f\x7f]/.test(serial)) throw new Error("Select a ready Android device.");
  var id = /^id:([0-9A-Za-z_.-]+)$/.exec(o.camera || "");
  if (!id && ["front", "back", "external"].indexOf(o.camera) < 0) throw new Error("Invalid camera '" + o.camera + "'; choose a listed camera.");
  if (["0", "90", "180", "270", "flip0", "flip90", "flip180", "flip270"].indexOf(String(o.orientation)) < 0)
    throw new Error("Invalid camera orientation '" + o.orientation + "'; choose a listed rotation.");
  if (o.size !== "auto" && !/^[1-9][0-9]{1,4}x[1-9][0-9]{1,4}$/.test(o.size || ""))
    throw new Error("Invalid camera size '" + o.size + "'; choose a listed resolution.");
  if (!/^[1-9][0-9]{0,2}$/.test(o.fps || "")) throw new Error("Invalid frame rate '" + o.fps + "'; choose a listed rate.");
  if (!/^[1-9][0-9]?$/.test(o.bitRate || "")) throw new Error("Invalid bitrate '" + o.bitRate + "'; choose 1 to 99 Mbps.");
  if (["h264", "h265", "av1"].indexOf(o.codec) < 0) throw new Error("Invalid codec '" + o.codec + "'; choose H.264, H.265 or AV1.");
  if (!/^[0-9]+(\.[0-9]+)?$/.test(o.zoom || "") || Number(o.zoom) <= 0) throw new Error("Invalid zoom '" + o.zoom + "'.");
  if (!/^[0-9]{1,4}$/.test(o.buffer || "")) throw new Error("Invalid buffer '" + o.buffer + "'; choose a listed delay.");
  if (!/^\/dev\/video[0-9]+$/.test(sink)) throw new Error("Invalid webcam output '" + sink + "'; choose a listed /dev/videoN device.");
  // scrcpy refuses --camera-facing together with --camera-id.
  var args = ["scrcpy", "--serial=" + serial, "--video-source=camera", id ? "--camera-id=" + id[1] : "--camera-facing=" + o.camera,
    "--capture-orientation=" + o.orientation, "--no-audio", "--no-window", "--v4l2-sink=" + sink,
    "--camera-fps=" + o.fps, "--video-bit-rate=" + o.bitRate + "M", "--video-codec=" + o.codec];
  if (o.size !== "auto") args.push("--camera-size=" + o.size);
  if (Number(o.zoom) !== 1) args.push("--camera-zoom=" + o.zoom);
  if (o.torch === true) args.push("--camera-torch");
  if (o.buffer !== "0") args.push("--v4l2-buffer=" + o.buffer);
  return args;
}

/** Describe the next webcam setup step. Example: webcamSetup('missing-package'). */
function webcamSetup(issue) {
  var load = "sudo modprobe v4l2loopback devices=1 exclusive_caps=1\n"
    + "printf 'v4l2loopback\\n' | sudo tee /etc/modules-load.d/v4l2loopback.conf\n"
    + "printf 'options v4l2loopback devices=1 exclusive_caps=1\\n' | sudo tee /etc/modprobe.d/v4l2loopback.conf";
  switch (issue) {
  case "missing-package": return { title: "Virtual camera driver missing", detail: "Install the driver and enable one output, now and at every boot.", action: "Set up webcam", step: "install", commands: "omarchy pkg add v4l2loopback-dkms\n" + load };
  case "module-not-loaded": return { title: "Virtual camera is off", detail: "The driver is installed. Enable one output, now and at every boot, to use your phone as a camera.", action: "Enable output", step: "load", commands: load };
  case "module-unavailable": return { title: "Driver needs a build", detail: "The package is installed, but no module is available for this kernel. Check the DKMS build and matching kernel headers.", action: "", step: "", commands: "dkms status\npacman -Q linux-omarchy-headers v4l2loopback-dkms" };
  case "no-output": return { title: "No virtual camera output", detail: "The driver is loaded, but no output is visible. Check its devices and permissions.", action: "", step: "", commands: "ls -l /dev/video*" };
  case "scan-error": return { title: "Could not check camera outputs", detail: "Press Refresh to try again.", action: "", step: "", commands: "" };
  default: return { title: "No virtual camera output", detail: "Enable a v4l2loopback output, then press Refresh.", action: "", step: "", commands: "" };
  }
}
