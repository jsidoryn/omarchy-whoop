import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var settings: ({})
  property var snapshot: ({
    state: "loading",
    mode: "demo",
    message: "Loading WHOOP",
    recovery: ({ score: null }),
    cycle: ({}),
    sleep: ({}),
    week: []
  })
  property string status: "loading"
  property string message: "Loading WHOOP"
  property bool connected: false
  property bool refreshing: false
  property bool refreshQueued: false
  property string pendingDemoScenario: ""
  property string deferredAction: ""
  property string deferredScenario: ""
  property string lastError: ""
  property string demoScenario: "primed"
  property string _stdout: ""
  property string _stderr: ""
  property double lastFetchStartedAt: 0
  property bool fetchTimedOut: false

  readonly property string pluginId: "io.github.jsidoryn.whoop"
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/whoop").toString().replace(/^file:\/\//, ""))
  readonly property bool demoMode: snapshot && snapshot.mode === "demo"
  readonly property bool hasData: snapshot && snapshot.recovery !== undefined
  readonly property int recoveryScore: hasData && snapshot.recovery.score !== null && snapshot.recovery.score !== undefined
    ? Number(snapshot.recovery.score) : -1
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 600, 300, 3600)
  readonly property bool forceDemo: boolSetting("forceDemo", false)
  readonly property string barLabel: Model.barLabel(snapshot)
  readonly property string tooltip: Model.tooltip(snapshot, refreshing, status, lastError)

  visible: false

  function configure(nextSettings) {
    settings = nextSettings || ({})
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    if (typeof value === "string") return value.toLowerCase() === "true"
    return !!value
  }

  function command() {
    if (forceDemo) return [helper, "demo", demoScenario]
    return [helper, "snapshot", "--fallback-demo", demoScenario]
  }

  function refresh(force) {
    if (fetchProcess.running) {
      if (force === true) refreshQueued = true
      return
    }
    if (force !== true && Date.now() - lastFetchStartedAt < 15000) return
    refreshQueued = false
    refreshing = true
    fetchTimedOut = false
    lastError = ""
    _stdout = ""
    _stderr = ""
    fetchProcess.command = command()
    lastFetchStartedAt = Date.now()
    fetchProcess.running = true
    fetchWatchdog.restart()
  }

  function showDemo(scenario) {
    demoScenario = String(scenario || "primed")
    refreshQueued = false
    if (fetchProcess.running) {
      pendingDemoScenario = demoScenario
      return
    }
    startDemo(demoScenario)
  }

  function startDemo(scenario) {
    refreshing = true
    fetchTimedOut = false
    lastError = ""
    _stdout = ""
    _stderr = ""
    fetchProcess.command = [helper, "demo", String(scenario || "primed")]
    fetchProcess.running = true
    fetchWatchdog.restart()
  }

  function nextDemo() {
    showDemo(Model.nextDemoScenario(snapshot && snapshot.demoScenario ? snapshot.demoScenario : demoScenario))
  }

  function disconnect() {
    if (disconnectProcess.running) return
    disconnectProcess.command = [helper, "disconnect"]
    disconnectProcess.running = true
  }

  function openPanel() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "{}")
  }

  function closePanel() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function togglePanel() {
    if (shell && typeof shell.toggle === "function") shell.toggle(pluginId, "{}")
  }

  function statusJson() {
    var recovery = snapshot && snapshot.recovery ? snapshot.recovery : ({})
    var cycle = snapshot && snapshot.cycle ? snapshot.cycle : ({})
    var sleep = snapshot && snapshot.sleep ? snapshot.sleep : ({})
    return JSON.stringify({
      state: status,
      connected: connected,
      mode: snapshot && snapshot.mode ? snapshot.mode : "demo",
      recovery: recovery.score,
      strain: cycle.strain,
      sleep: sleep.performance,
      refreshing: refreshing,
      error: lastError || ""
    })
  }

  function apply(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (error) {
      status = "error"
      message = "WHOOP returned data the plugin could not read"
      lastError = message
      return
    }

    var nextState = String(parsed.state || "error")
    if (parsed.connected !== undefined) connected = parsed.connected === true
    if (nextState === "error" && hasData) {
      status = "error"
      message = String(parsed.message || "WHOOP refresh failed")
      lastError = message
      return
    }

    snapshot = parsed
    status = nextState
    message = String(parsed.message || "")
    lastError = ""
    if (parsed.demoScenario) demoScenario = String(parsed.demoScenario)
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    id: fetchWatchdog
    interval: 180000
    repeat: false
    onTriggered: {
      root.fetchTimedOut = true
      root.refreshing = false
      root.status = "error"
      root.message = "WHOOP timed out. Unlock your keyring and try again."
      root.lastError = root.message
      fetchProcess.running = false
    }
  }

  Timer {
    id: deferredTimer
    interval: 0
    repeat: false
    onTriggered: {
      var action = root.deferredAction
      var scenario = root.deferredScenario
      root.deferredAction = ""
      root.deferredScenario = ""
      if (action === "demo") root.startDemo(scenario)
      else if (action === "refresh") root.refresh(true)
    }
  }

  // The service is instantiated once by the shell. Keeping IPC here avoids
  // competing handlers when the bar creates one widget per monitor.
  IpcHandler {
    target: root.pluginId

    function open(): string {
      root.openPanel()
      return "ok"
    }

    function close(): string {
      root.closePanel()
      return "ok"
    }

    function show(): string {
      root.openPanel()
      return "ok"
    }

    function hide(): string {
      root.closePanel()
      return "ok"
    }

    function toggle(): string {
      root.togglePanel()
      return "ok"
    }

    function refresh(): string {
      root.refresh(false)
      return "ok"
    }

    function setupFinished(): string {
      root.refresh(true)
      return "ok"
    }

    function demo(): string {
      root.nextDemo()
      root.openPanel()
      return "ok"
    }

    function status(): string {
      return root.statusJson()
    }
  }

  Process {
    id: fetchProcess
    running: false
    command: []

    stdout: StdioCollector {
      id: outputCollector
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }

    stderr: StdioCollector {
      id: errorCollector
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }

    onExited: function(exitCode) {
      fetchWatchdog.stop()
      root.refreshing = false
      var output = String(outputCollector.text || root._stdout || "")
      if (root.fetchTimedOut) root.fetchTimedOut = false
      else if (output.trim() !== "") root.apply(output)
      else {
        var errorText = String(errorCollector.text || root._stderr || "").trim().split("\n")[0]
        root.status = "error"
        root.message = errorText !== "" ? errorText.substring(0, 180) : "The WHOOP helper produced no data"
        root.lastError = root.message
      }
      if (root.pendingDemoScenario !== "") {
        root.deferredScenario = root.pendingDemoScenario
        root.pendingDemoScenario = ""
        root.deferredAction = "demo"
        deferredTimer.restart()
        return
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        root.deferredAction = "refresh"
        deferredTimer.restart()
      }
    }
  }

  Process {
    id: disconnectProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh(true)
      else {
        root.status = "error"
        root.message = "Could not disconnect WHOOP"
        root.lastError = root.message
      }
    }
  }
}
