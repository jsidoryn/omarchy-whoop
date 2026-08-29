const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("recovery zones expose readable labels and theme roles", () => {
  assert.deepEqual(Model.recoveryBand(82), { id: "green", label: "Primed", colorRole: "positive" })
  assert.deepEqual(Model.recoveryBand(55), { id: "yellow", label: "Balanced", colorRole: "warning" })
  assert.deepEqual(Model.recoveryBand(28), { id: "red", label: "Recover", colorRole: "urgent" })
  assert.equal(Model.recoveryBand(null).id, "pending")
})

test("bar labels handle live, demo, pending and unavailable states", () => {
  assert.equal(Model.barLabel({ state: "ok", recovery: { score: 82 } }), "82")
  assert.equal(Model.barLabel({ state: "demo", recovery: { score: 67 } }), "67")
  assert.equal(Model.barLabel({ state: "pending", recovery: { score: null } }), "…")
  assert.equal(Model.barLabel({ state: "error" }), "!")
})

test("demo scenarios cycle deterministically", () => {
  assert.equal(Model.nextDemoScenario("primed"), "balanced")
  assert.equal(Model.nextDemoScenario("balanced"), "strained")
  assert.equal(Model.nextDemoScenario("strained"), "pending")
  assert.equal(Model.nextDemoScenario("pending"), "primed")
})

test("freshness formatting stays compact", () => {
  assert.equal(Model.freshness(Date.now() - 90_000, Date.now()), "1m ago")
})

test("tooltip reports a refresh error instead of healthy stale data", () => {
  const stale = { state: "ok", mode: "live", recovery: { score: 82 } }
  assert.equal(Model.tooltip(stale, false, "error", "Could not reach WHOOP"), "Could not reach WHOOP")
  assert.equal(Model.tooltip(stale, true, "error", "Could not reach WHOOP"), "Refreshing WHOOP")
})

test("tooltip reports the recovery score without an interpreted label", () => {
  const live = { state: "ok", mode: "live", recovery: { score: 82 } }
  const demo = { state: "demo", mode: "demo", recovery: { score: 67 } }

  assert.equal(Model.tooltip(live, false, "ok", ""), "Recovery 82")
  assert.equal(Model.tooltip(demo, false, "demo", ""), "WHOOP demo · Recovery 67")
})

test("tooltip explains unscored snapshots instead of exposing bar sentinels", () => {
  const pending = {
    state: "pending",
    mode: "demo",
    message: "WHOOP is calculating recovery",
    recovery: { score: null }
  }
  const loading = {
    state: "loading",
    mode: "demo",
    message: "Loading WHOOP",
    recovery: { score: null }
  }

  assert.equal(Model.tooltip(pending, false, "pending", ""), "WHOOP is calculating recovery")
  assert.equal(Model.tooltip(loading, false, "loading", ""), "Loading WHOOP")
})
