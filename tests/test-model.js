const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
const model = new Function(`${source}; return { plain, parseSnapshot, statusLabel, batteryIcon, parseHook, parseHookResult, hookStatusLabel };`)()

test("plain neutralizes markup and control characters", () => {
  const dirty = '<img src="https://example.invalid/tracker">\u0001hello'
  const clean = model.plain(dirty, 200)
  assert.equal(clean.includes("<"), false)
  assert.equal(clean.includes(">"), false)
  assert.equal(clean.includes("\u0001"), false)
  assert.ok(clean.includes("example.invalid"))
})

test("plain bounds long untrusted text", () => {
  assert.ok(model.plain("x".repeat(5000), 240).length <= 241)
})

test("parseSnapshot rejects malformed and non-object input", () => {
  assert.equal(model.parseSnapshot("not json"), null)
  assert.equal(model.parseSnapshot("[]"), null)
  assert.equal(model.parseSnapshot("null"), null)
})

test("parseSnapshot clamps numbers and strips markup from dynamic text", () => {
  const raw = JSON.stringify({
    battery: {
      present: true,
      percent: 5000,
      status: '<img src="x">Charging',
      watts: -42,
      tempC: '<b>31</b>',
      cycles: "nonsense"
    },
    profiles: { governor: "<script>alert(1)</script>", boost: 7 },
    sleep: {
      samples: 3,
      last: { capDrop: 900, endIso: "<x>2026-01-01T00:00:00Z" },
      recent: [{ capDrop: 12, endIso: "2026-01-01T00:00:00Z" }]
    }
  })
  const snap = model.parseSnapshot(raw)
  assert.equal(snap.battery.percent, 100)
  assert.equal(snap.battery.status, 'img src="x"Charging')
  assert.equal(snap.battery.watts, 0)
  assert.equal(snap.battery.cycles, 0)
  assert.equal(snap.profiles.governor, "scriptalert(1)/script")
  assert.equal(snap.sleep.samples, 3)
  assert.equal(snap.sleep.last.capDrop, 100)
  assert.equal(snap.sleep.recent.length, 1)
  assert.equal(snap.sleep.recent[0].endIso, "2026-01-01T00:00:00Z")
})

test("statusLabel and batteryIcon only use known states", () => {
  const tr = key => key
  assert.equal(model.statusLabel({ present: false }, tr), "status.noBattery")
  assert.equal(model.statusLabel({ present: true, status: "Charging" }, tr), "status.charging")
  assert.equal(model.statusLabel({ present: true, status: "<b>Full</b>" }, tr), "status.unknown")
  assert.equal(model.batteryIcon(100, "Charging"), "󰂅")
  assert.equal(model.batteryIcon(5, "Discharging"), "󰂃")
})

test("sleepHook is parsed to typed booleans only", () => {
  const snap = model.parseSnapshot(JSON.stringify({
    sleepHook: { present: true, legacy: "yes", readable: true, ownedByRoot: false, extra: "<b>x</b>" }
  }))
  assert.deepEqual(snap.sleepHook, { present: true, legacy: false, readable: true, ownedByRoot: false })
  assert.deepEqual(model.parseHook(null), { present: false, legacy: false, readable: false, ownedByRoot: false })
})

test("parseHookResult whitelists status and sanitizes message", () => {
  assert.equal(model.parseHookResult('{"status":"rm -rf /","message":"x"}'), null)
  assert.equal(model.parseHookResult("not json"), null)
  const result = model.parseHookResult('{"status":"error","message":"<img src=x>bad</img>"}')
  assert.equal(result.status, "error")
  assert.equal(result.message, "img src=xbad/img")
})

test("hookStatusLabel only uses known states", () => {
  const tr = key => key
  assert.equal(model.hookStatusLabel({ present: false }, tr), "hook.clean")
  assert.equal(model.hookStatusLabel({ present: true, legacy: true }, tr), "hook.stale")
  assert.equal(model.hookStatusLabel({ present: true, legacy: false }, tr), "hook.unknown")
})
