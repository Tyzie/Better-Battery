.pragma library

var MAX_TEXT = 160
var MAX_STATUS = 32

var DISCHARGE = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
var CHARGE = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]

function plain(value, limit) {
  var text = value === undefined || value === null ? "" : String(value)
  text = text.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/[<>]/g, "")
  text = text.replace(/\s+/g, " ").trim()
  var max = limit > 0 ? limit : MAX_TEXT
  return text.length > max ? text.slice(0, max) + "\u2026" : text
}

function truthy(v) { return v === true }

function parseHook(h) {
  var src = h && typeof h === "object" && !Array.isArray(h) ? h : {}
  return {
    present: truthy(src.present),
    legacy: truthy(src.legacy),
    readable: truthy(src.readable),
    ownedByRoot: truthy(src.ownedByRoot)
  }
}

function parseHookResult(text) {
  try {
    var data = JSON.parse(String(text || ""))
    if (!data || typeof data !== "object" || Array.isArray(data)) return null
    if (["removed", "absent", "error"].indexOf(String(data.status || "")) < 0) return null
    return { status: String(data.status), message: plain(data.message, MAX_TEXT) }
  } catch (error) {
    return null
  }
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : (fallback === undefined ? 0 : fallback)
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, num(v))) }

function batteryIcon(percent, status) {
  var i = clamp(Math.floor(num(percent) / 10), 0, 9)
  var s = plain(status, MAX_STATUS)
  if (s === "Full" || s === "Fully charged" || s === "Not charging") return "󰂅"
  if (s === "Charging") return CHARGE[i]
  if (s === "Discharging" && num(percent) <= 10) return "󰂃"
  return DISCHARGE[i]
}

function boundedList(value, mapper, max) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length && out.length < (max || 10); i++) {
    var item = value[i]
    if (!item || typeof item !== "object" || Array.isArray(item)) continue
    out.push(mapper(item))
  }
  return out
}

function sleepSummary(s) {
  var src = s && typeof s === "object" ? s : {}
  var recent = boundedList(src.recent, function(r) {
    return {
      capDrop: clamp(r.capDrop, 0, 100),
      drawW: clamp(r.drawW, 0, 100000),
      durationSec: clamp(r.durationSec, 0, 1e9),
      endIso: plain(r.endIso, 40),
      startIso: plain(r.startIso, 40)
    }
  }, 10)
  var last = src.last && typeof src.last === "object" && !Array.isArray(src.last) ? src.last : {}
  return {
    installed: true,
    mode: "user",
    samples: clamp(src.samples, 0, 100000),
    avgDrawW: clamp(src.avgDrawW, 0, 100000),
    totalSleepSec: clamp(src.totalSleepSec, 0, 1e9),
    last: {
      capDrop: clamp(last.capDrop, 0, 100),
      whDrop: clamp(last.whDrop, 0, 100000),
      drawW: clamp(last.drawW, 0, 100000),
      durationSec: clamp(last.durationSec, 0, 1e9),
      endIso: plain(last.endIso, 40)
    },
    recent: recent
  }
}

function chargeSummary(c) {
  var src = c && typeof c === "object" ? c : {}
  var recent = boundedList(src.recent, function(r) {
    return {
      capGain: clamp(r.capGain, 0, 100),
      whGain: clamp(r.whGain, 0, 100000),
      avgRateW: clamp(r.avgRateW, 0, 100000),
      durationSec: clamp(r.durationSec, 0, 1e9),
      endIso: plain(r.endIso, 40),
      startIso: plain(r.startIso, 40)
    }
  }, 10)
  var last = src.last && typeof src.last === "object" && !Array.isArray(src.last) ? src.last : {}
  return {
    installed: true,
    samples: clamp(src.samples, 0, 100000),
    avgRateW: clamp(src.avgRateW, 0, 100000),
    totalGainWh: clamp(src.totalGainWh, 0, 1e9),
    active: src.active === true,
    activeSec: clamp(src.activeSec, 0, 1e9),
    activeCapGain: clamp(src.activeCapGain, 0, 100),
    activeWhGain: clamp(src.activeWhGain, 0, 100000),
    activeRateW: clamp(src.activeRateW, 0, 100000),
    last: {
      capGain: clamp(last.capGain, 0, 100),
      whGain: clamp(last.whGain, 0, 100000),
      avgRateW: clamp(last.avgRateW, 0, 100000),
      durationSec: clamp(last.durationSec, 0, 1e9)
    },
    recent: recent
  }
}

function parseSnapshot(text) {
  try {
    var data = JSON.parse(String(text || ""))
    if (!data || typeof data !== "object" || Array.isArray(data)) return null
    var b = data.battery && typeof data.battery === "object" ? data.battery : {}
    var p = data.profiles && typeof data.profiles === "object" ? data.profiles : {}
    return {
      battery: {
        present: b.present === true,
        percent: clamp(b.percent, 0, 100),
        status: plain(b.status, MAX_STATUS) || "Unknown",
        watts: clamp(b.watts, 0, 100000),
        minutes: clamp(b.minutes, 0, 100000),
        health: clamp(b.health, 0, 100),
        whFull: clamp(b.whFull, 0, 100000),
        whDesign: clamp(b.whDesign, 0, 100000),
        cycles: clamp(b.cycles, 0, 1000000),
        tempC: plain(b.tempC, 16),
        acOnline: num(b.acOnline) === 1 ? 1 : 0
      },
      profiles: {
        current: plain(p.current, MAX_STATUS),
        mode: plain(p.mode, MAX_STATUS),
        auto: p.auto === true,
        available: boundedList(p.available, function(v) { return { value: plain(v, 16) } }, 8).map(function(v) { return v.value }),
        governor: plain(p.governor, MAX_STATUS),
        boost: num(p.boost, -1),
        helperInstalled: p.helperInstalled === true
      },
      sleep: sleepSummary(data.sleep),
      sleepHook: parseHook(data.sleepHook),
      charge: chargeSummary(data.charge)
    }
  } catch (error) {
    return null
  }
}

function fmtWatts(w) {
  var n = Math.abs(num(w))
  if (n <= 0) return "—"
  return (n >= 10 ? n.toFixed(1) : n.toFixed(2)) + " W"
}

function fmtDuration(mins) {
  var m = clamp(mins, 0, 1e6)
  if (!m) return "—"
  var h = Math.floor(m / 60)
  var r = Math.floor(m % 60)
  if (h > 0) return h + "h " + (r < 10 ? "0" : "") + r + "m"
  return r + "m"
}

function fmtWh(v) {
  var n = Math.abs(num(v))
  return n > 0 ? n.toFixed(1) + " Wh" : "—"
}

function fmtGain(v) {
  return "+" + clamp(v, 0, 100).toFixed(1) + "%"
}

function fmtTemp(v) {
  if (v === undefined || v === null || v === "") return "—"
  return plain(v, 8) + "°C"
}

function fmtAgo(iso, trn, numFn) {
  var t = Date.parse(String(iso || ""))
  if (isNaN(t)) return "—"
  var sec = Math.max(0, Math.round((Date.now() - t) / 1000))
  if (sec < 60) return trn("ago.now", 0)
  var min = Math.floor(sec / 60)
  if (min < 60) return trn("ago.minute", min).arg(numFn(min))
  var hr = Math.floor(min / 60)
  if (hr < 48) return trn("ago.hour", hr).arg(numFn(hr))
  return trn("ago.day", Math.floor(hr / 24)).arg(numFn(Math.floor(hr / 24)))
}

function fmtElapsed(sec) {
  var s = clamp(sec, 0, 1e9)
  if (!s) return "—"
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = Math.floor(s % 60)
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
  if (m > 0) return m + "m " + (r < 10 ? "0" : "") + r + "s"
  return s + "s"
}

function fmtSleepDuration(sec) {
  var s = clamp(sec, 0, 1e9)
  if (!s) return "—"
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
  return m + "m"
}

function statusLabel(b, tr) {
  if (!b || !b.present) return tr("status.noBattery")
  if (b.status === "Charging") return tr("status.charging")
  if (b.status === "Discharging") return tr("status.discharging")
  if (b.status === "Full" || b.status === "Not charging") return tr("status.full")
  return tr("status.unknown")
}

function hookStatusLabel(h, tr) {
  if (!h || h.present !== true) return tr("hook.clean")
  if (h.legacy !== true) return tr("hook.unknown")
  return tr("hook.stale")
}

function profileLabel(mode, tr) {
  if (mode === "auto") return tr("profile.auto")
  if (mode === "econom" || mode === "power-saver") return tr("profile.econom")
  if (mode === "normal" || mode === "balanced") return tr("profile.normal")
  if (mode === "power" || mode === "performance") return tr("profile.power")
  return plain(mode, MAX_STATUS)
}

function activeProfileMode(profiles) {
  if (!profiles) return "normal"
  if (profiles.auto) return "auto"
  var cur = plain(profiles.mode || profiles.current, MAX_STATUS)
  if (cur === "econom" || cur === "power-saver") return "econom"
  if (cur === "normal" || cur === "balanced") return "normal"
  if (cur === "power" || cur === "performance") return "power"
  if (cur === "auto") return "auto"
  return "normal"
}
