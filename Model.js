.pragma library

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

var DISCHARGE = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
var CHARGE    = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"];

function batteryIcon(percent, status) {
  var i = clamp(Math.floor((Number(percent) || 0) / 10), 0, 9);
  if (status === "Full" || status === "Fully charged" || status === "Not charging") return "󰂅";
  if (status === "Charging") return CHARGE[i];
  if (status === "Discharging" && Number(percent) <= 10) return "󰂃";
  return DISCHARGE[i];
}

function fmtWatts(w) {
  var n = Number(w) || 0;
  if (n <= 0) return "—";
  return (n >= 10 ? n.toFixed(1) : n.toFixed(2)) + " W";
}

function fmtDuration(mins) {
  var m = Math.max(0, Math.round(Number(mins) || 0));
  if (!m) return "—";
  var h = Math.floor(m / 60);
  var r = m % 60;
  if (h > 0) return h + "h " + (r < 10 ? "0" : "") + r + "m";
  return r + "m";
}

function fmtWh(v) {
  var n = Number(v) || 0;
  return n > 0 ? n.toFixed(1) + " Wh" : "—";
}

function fmtGain(v) {
  var n = Number(v) || 0;
  return "+" + n.toFixed(1) + "%";
}

function fmtTemp(v) {
  if (v === undefined || v === null || v === "") return "—";
  return String(v) + "°C";
}

function fmtAgo(iso) {
  var t = Date.parse(iso || "");
  if (isNaN(t)) return "—";
  var sec = Math.max(0, Math.round((Date.now() - t) / 1000));
  if (sec < 60) return "just now";
  var min = Math.floor(sec / 60);
  if (min < 60) return min + "m ago";
  var hr = Math.floor(min / 60);
  if (hr < 48) return hr + "h ago";
  return Math.floor(hr / 24) + "d ago";
}

function fmtElapsed(sec) {
  var s = Math.max(0, Math.round(Number(sec) || 0));
  if (!s) return "—";
  var h = Math.floor(s / 3600);
  var m = Math.floor((s % 3600) / 60);
  var r = s % 60;
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m";
  if (m > 0) return m + "m " + (r < 10 ? "0" : "") + r + "s";
  return s + "s";
}

function fmtSleepDuration(sec) {
  var s = Math.max(0, Math.round(Number(sec) || 0));
  if (!s) return "—";
  var h = Math.floor(s / 3600);
  var m = Math.floor((s % 3600) / 60);
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m";
  return m + "m";
}

function statusLabel(b) {
  if (!b || !b.present) return "No battery";
  if (b.status === "Charging") return "Charging";
  if (b.status === "Discharging") return "On battery";
  if (b.status === "Full" || b.status === "Not charging") return "Fully charged";
  return "Unknown";
}

function profileLabel(mode) {
  if (mode === "auto") return "Auto";
  if (mode === "econom" || mode === "power-saver") return "Econom";
  if (mode === "normal" || mode === "balanced") return "Normal";
  if (mode === "power" || mode === "performance") return "Power";
  return String(mode || "");
}

function activeProfileMode(profiles) {
  if (!profiles) return "normal";
  if (profiles.auto) return "auto";
  var cur = String(profiles.mode || profiles.current || "");
  if (cur === "econom" || cur === "power-saver") return "econom";
  if (cur === "normal" || cur === "balanced") return "normal";
  if (cur === "power" || cur === "performance") return "power";
  if (cur === "auto") return "auto";
  return "normal";
}
