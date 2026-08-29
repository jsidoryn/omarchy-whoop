function number(value, fallback) {
  if (value === null || value === undefined || value === "") return fallback
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function recoveryBand(score) {
  var value = number(score, -1)
  if (value < 0) return { id: "pending", label: "Pending", colorRole: "muted" }
  if (value >= 67) return { id: "green", label: "Primed", colorRole: "positive" }
  if (value >= 34) return { id: "yellow", label: "Balanced", colorRole: "warning" }
  return { id: "red", label: "Recover", colorRole: "urgent" }
}

function barLabel(snapshot) {
  var data = snapshot || {}
  var score = data.recovery ? number(data.recovery.score, -1) : -1
  if ((data.state === "ok" || data.state === "demo") && score >= 0) return String(Math.round(score))
  if (data.state === "pending") return "…"
  return "!"
}

var demoScenarios = ["primed", "balanced", "strained", "pending"]

function nextDemoScenario(current) {
  var index = demoScenarios.indexOf(String(current || ""))
  return demoScenarios[(index + 1 + demoScenarios.length) % demoScenarios.length]
}

function metric(value, suffix, digits) {
  var parsed = number(value, NaN)
  if (!isFinite(parsed)) return "—"
  var fixed = digits === undefined ? String(Math.round(parsed)) : parsed.toFixed(digits)
  return fixed + (suffix || "")
}

function freshness(iso, nowMs) {
  var timestamp = typeof iso === "number" ? iso : Date.parse(String(iso || ""))
  if (!isFinite(timestamp)) return "Not refreshed yet"
  var seconds = Math.max(0, Math.floor((number(nowMs, Date.now()) - timestamp) / 1000))
  if (seconds < 60) return "Just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}

function tooltip(snapshot, refreshing, serviceStatus, lastError) {
  if (refreshing) return "Refreshing WHOOP"
  if (serviceStatus === "error") return String(lastError || "WHOOP refresh failed")
  var data = snapshot || {}
  var label = barLabel(data)
  var scored = /^[0-9]+$/.test(label)
  if (data.mode === "demo") {
    return scored ? "WHOOP demo · Recovery " + label : String(data.message || "WHOOP recovery pending")
  }
  if (data.state === "ok") return "Recovery " + label
  return String(data.message || "WHOOP is unavailable")
}

function safeWeek(snapshot) {
  var week = snapshot && Array.isArray(snapshot.week) ? snapshot.week : []
  return week.slice(-7)
}

if (typeof module !== "undefined") {
  module.exports = {
    recoveryBand: recoveryBand,
    barLabel: barLabel,
    nextDemoScenario: nextDemoScenario,
    metric: metric,
    freshness: freshness,
    tooltip: tooltip,
    safeWeek: safeWeek
  }
}
