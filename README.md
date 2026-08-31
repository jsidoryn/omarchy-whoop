# WHOOP for Omarchy

A demo-first Omarchy bar plugin for today's WHOOP recovery, strain, sleep, and cycleable seven-day trends for all three scores. It is useful immediately with realistic preview data, then switches to your own data after a guided OAuth setup.

The collector is written in Ruby and uses only Ruby's standard library. Credentials are stored by `secret-tool` in the desktop keyring; they are never written to `shell.json`, this repository, or a cache file.

> [!NOTE]
> This project is an early preview. Its demo experience and OAuth integration are automated-test covered, and the authorization flow is being validated against real WHOOP accounts.

## What it feels like

- The bar shows a compact recovery ring, score, and a `D` while previewing demo data.
- Left-click opens the full panel.
- Middle-click or right-click refreshes.
- In the panel, press `D` to cycle through primed, balanced, strained, and pending states.
- Press `T` to cycle Recovery, Sleep, and Strain trends; press `C` to start setup, `R` to refresh, and `Esc` to close.
- The panel keeps stale data visible if a refresh fails and reports the error inline.

The plugin starts in demo mode automatically. You can review every state and interaction before creating a WHOOP developer app.

## Install

From the public repository:

```bash
omarchy plugin add https://github.com/jsidoryn/omarchy-whoop --enable
```

For local development:

```bash
omarchy plugin add /path/to/omarchy-whoop --enable
```

Stock Omarchy includes Quickshell plugin support, `/usr/bin/ruby`, `secret-tool`, and a desktop keyring. Setup verifies the required keyring command. No gems, build step, daemon, package installation, or elevated privileges are required.

## Connect WHOOP

See the complete [setup and troubleshooting guide](https://jsidoryn.github.io/omarchy-whoop/setup/).

First, create an app in the [WHOOP Developer Dashboard](https://developer-dashboard.whoop.com/). Configure it with:

- Redirect URL: `io.github.jsidoryn.omarchy-whoop://oauth/callback`
- Scopes: `offline`, `read:cycles`, `read:recovery`, `read:sleep`

Then open the WHOOP panel and choose **Connect WHOOP**, or run:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop setup
```

The setup wizard temporarily registers **WHOOP for Omarchy** as the per-user handler for that callback URL, asks for the app's Client ID and Client Secret, and opens WHOOP authorization in your browser. After you grant access, allow the browser to open WHOOP for Omarchy. The callback is delivered directly to the waiting Ruby process and setup continues automatically; there is no URL to copy.

Registration follows the Linux `x-scheme-handler` desktop convention and does not require `sudo`. The plugin refuses to replace an existing handler for the same scheme. Its desktop entry contains only the installed helper path—never credentials or WHOOP data—and is removed after setup succeeds or ordinarily fails. The desktop launcher briefly passes the callback URL to that helper as a process argument; it then crosses an owner-only socket under `$XDG_RUNTIME_DIR` without being saved.

On success, the wizard stores one credential bundle in the keyring and immediately fetches the first live snapshot. Access tokens are refreshed automatically. WHOOP rotates refresh tokens, so the plugin serializes refreshes and atomically replaces the complete keyring value.

### Keyring security boundary

`secret-tool` is the command-line client for Secret Service-compatible desktop keyrings. This keeps tokens out of plaintext files and lets the desktop session manage lock and unlock behavior. The plugin uses one exact lookup:

```bash
secret-tool lookup service omarchy-whoop account credentials
```

This is a storage boundary, not a per-plugin sandbox. Once your login keyring is unlocked, another process running as your user can generally ask the same service for this item, and may also be able to request other keyring items if it knows or searches their attributes. Omarchy plugins themselves are unsandboxed code. Only install plugins you trust, keep the screen locked when away, and treat your user session as the trust boundary.

To inspect connection metadata without printing tokens:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop status
```

To revoke WHOOP access and remove the local keyring item:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop disconnect
```

The callback handler is temporary. Inspect or remove a residual handler after an interrupted setup:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler status
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler remove
```

## Configure

Refresh every ten minutes by default. WHOOP data does not need rapid polling; the supported range is five minutes to one hour.

```bash
omarchy bar set io.github.jsidoryn.whoop refreshIntervalSec 900 --json
```

Force preview data without disconnecting live credentials:

```bash
omarchy bar set io.github.jsidoryn.whoop forceDemo true --json
```

Return to live data:

```bash
omarchy bar set io.github.jsidoryn.whoop forceDemo false --json
```

Useful IPC commands:

```bash
omarchy-shell io.github.jsidoryn.whoop status
omarchy-shell io.github.jsidoryn.whoop demo
omarchy-shell io.github.jsidoryn.whoop refresh
omarchy-shell shell toggle io.github.jsidoryn.whoop '{}'
```

## Privacy and API behavior

Read the full [Privacy Policy](https://jsidoryn.github.io/omarchy-whoop/privacy/).
For the complete local footprint, trust boundaries, and installer responsibilities, read [Installation, architecture, and security](https://jsidoryn.github.io/omarchy-whoop/security/).

- Requests go directly from your machine to `api.prod.whoop.com` over HTTPS.
- Only cycle, recovery, and sleep read scopes are requested, plus `offline` for refresh tokens.
- No profile, email, body measurement, workout, or write scope is requested.
- No analytics, telemetry, webhooks, or third-party server is involved.
- Disconnect attempts WHOOP's revocation endpoint, then removes local credentials even if the network is unavailable.
- Demo data is generated locally and is never sent to WHOOP.

## Develop and test

All data normalization lives in small Ruby classes and all display formatting lives in `Model.js`, so most behavior can be tested without Quickshell or a compositor.

```bash
tests/run
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell \
  Service.qml BarWidget.qml Panel.qml RecoveryRing.qml MetricTile.qml WeekStrip.qml
```

The stock `/usr/bin/ruby` is intentionally used in production and tests. The Ruby test harness is bundled because Omarchy's stock Ruby does not need to include Minitest.

To reload an installed development copy:

```bash
omarchy plugin update io.github.jsidoryn.whoop --yes
omarchy-shell shell rescanPlugins
```

## Remove

Disconnect first if you want to revoke access and clear the credential bundle, then remove the plugin:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop disconnect
omarchy plugin remove io.github.jsidoryn.whoop
```

Removing the plugin alone does not intentionally erase credentials, which makes accidental uninstall/reinstall recoverable. The temporary callback registration normally removes itself. After a power loss or forced termination during setup, run `callback-handler status` and `callback-handler remove` before removing the plugin if a residual registration remains.

To reinstall while keeping the existing WHOOP connection, skip `disconnect` and run:

```bash
omarchy plugin remove io.github.jsidoryn.whoop
omarchy plugin add https://github.com/jsidoryn/omarchy-whoop --enable
```

See the [setup guide's removal and reinstall instructions](https://jsidoryn.github.io/omarchy-whoop/setup/#remove-and-reinstall-the-plugin) for the difference between a normal reinstall and a completely clean reinstall.

## Architecture

- `Service.qml` owns one polling process and shared state across bar surfaces.
- `BarWidget.qml` renders the compact bar entry and hosts the popup.
- `Panel.qml` is the keyboard-friendly detail and setup experience.
- `bin/whoop` is the stable QML-to-Ruby interface and emits one JSON snapshot.
- `lib/omarchy_whoop/` handles OAuth, the local callback handoff, keyring access, API calls, token rotation, normalization, and demos.

The helper's JSON is a private plugin contract. The UI never reads credentials and the Ruby helper never draws UI.

## Current limitation

The OAuth flow and WHOOP payload handling are covered by automated tests and checked against the current WHOOP v2 documentation. The repository deliberately contains no developer credentials or real health fixtures.

For support, [open an issue](https://github.com/jsidoryn/omarchy-whoop/issues). Please use [private vulnerability reporting](https://github.com/jsidoryn/omarchy-whoop/security/advisories/new) for security-sensitive reports and never include WHOOP credentials or health data in a public issue.

## License

MIT
