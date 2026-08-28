import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
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
  property string state: "loading"
  property string message: "Loading WHOOP"
  property bool refreshing: false
  property bool refreshQueued: false
  property string lastError: ""
  property string demoScenario: "primed"
  property string _stdout: ""
  property string _stderr: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "jsidoryn.whoop"
  readonly property string helper: Qt.resolvedUrl("bin/whoop").toString().replace(/^file:\/\//, "")
  readonly property bool demoMode: snapshot && snapshot.mode === "demo"
  readonly property bool hasData: snapshot && snapshot.recovery !== undefined
  readonly property int recoveryScore: hasData && snapshot.recovery.score !== null && snapshot.recovery.score !== undefined
    ? Number(snapshot.recovery.score) : -1
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 600, 300, 3600)
  readonly property bool forceDemo: boolSetting("forceDemo", false)
  readonly property string barLabel: Model.barLabel(snapshot)
  readonly property string tooltip: Model.tooltip(snapshot, refreshing)

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
    return [helper, "snapshot"]
  }

  function refresh() {
    if (fetchProcess.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    refreshing = true
    lastError = ""
    _stdout = ""
    _stderr = ""
    fetchProcess.command = command()
    fetchProcess.running = true
  }

  function showDemo(scenario) {
    demoScenario = String(scenario || "primed")
    refreshing = true
    _stdout = ""
    _stderr = ""
    if (fetchProcess.running) fetchProcess.running = false
    fetchProcess.command = [helper, "demo", demoScenario]
    fetchProcess.running = true
  }

  function nextDemo() {
    showDemo(Model.nextDemoScenario(snapshot && snapshot.demoScenario ? snapshot.demoScenario : demoScenario))
  }

  function disconnect() {
    if (disconnectProcess.running) return
    disconnectProcess.command = [helper, "disconnect"]
    disconnectProcess.running = true
  }

  function apply(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (error) {
      state = "error"
      message = "WHOOP returned data the plugin could not read"
      lastError = message
      return
    }

    var nextState = String(parsed.state || "error")
    if (nextState === "error" && hasData) {
      state = "error"
      message = String(parsed.message || "WHOOP refresh failed")
      lastError = message
      return
    }

    snapshot = parsed
    state = nextState
    message = String(parsed.message || "")
    if (parsed.demoScenario) demoScenario = String(parsed.demoScenario)
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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
      root.refreshing = false
      var output = String(outputCollector.text || root._stdout || "")
      if (output.trim() !== "") root.apply(output)
      else {
        root.state = "error"
        root.message = "The WHOOP helper produced no data"
        root.lastError = root.message
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: disconnectProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh()
      else {
        root.state = "error"
        root.message = "Could not disconnect WHOOP"
        root.lastError = root.message
      }
    }
  }
}
