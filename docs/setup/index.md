---
layout: default
title: Setup and troubleshooting
---

# Setup and troubleshooting

WHOOP for Omarchy starts with local demo data. Connecting your account requires a WHOOP developer application that you own; the plugin does not provide or share a central client application.

<div class="setup-grid">
<section markdown="1">

## Requirements

- A current Omarchy installation with Quickshell plugin support.
- An active WHOOP account and access to the [WHOOP Developer Dashboard](https://developer-dashboard.whoop.com/).
- The plugin installed and enabled:

  ```bash
  omarchy plugin add https://github.com/jsidoryn/omarchy-whoop --enable
  ```

Stock Omarchy includes Ruby, `secret-tool`, and a desktop keyring. The setup command verifies the required keyring command before requesting credentials. It does not install packages or request elevated privileges.

</section>
<section markdown="1">

## 1. Create the WHOOP application

Create an application in the WHOOP Developer Dashboard and configure it with the following values.

### Redirect URL

```text
io.github.jsidoryn.omarchy-whoop://oauth/callback
```

The value must match exactly, including the scheme and path.

### Scopes

```text
read:cycles
read:recovery
read:sleep
```

Select those three scopes in the WHOOP Developer Dashboard. They provide the cycle, recovery, sleep, HRV, resting heart rate, and history data displayed by the plugin. Do not enable the profile, workout, body-measurement, or write scopes.

The dashboard does not offer an `offline` checkbox. The plugin adds `offline` to the authorization request automatically so WHOOP can issue a refresh token and keep the connection working without repeated browser authorization.

### Privacy policy

The dashboard requires a privacy-policy URL. Use:

```text
https://jsidoryn.github.io/omarchy-whoop/privacy/
```

Save the application, then keep its Client ID and Client Secret available for the next step. Treat the Client Secret as a credential; do not post it in an issue or include it in a shell command.

</section>
</div>

## 2. Run setup

Open the WHOOP panel and select **Connect WHOOP**, or run:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop setup
```

The setup terminal will:

1. Register a temporary, per-user handler for the redirect URL.
2. Ask for the Client ID and Client Secret. The secret is entered without terminal echo.
3. Open WHOOP authorization in the default browser.
4. Wait for the browser to return the authorization result.

Review the requested scopes on WHOOP's consent screen and select **Grant**. Your browser (Chromium on stock Omarchy) should then ask whether to open **WHOOP for Omarchy**. Accept that prompt.

The browser may remain on WHOOP's grant page after the handoff. This is expected. Use the setup terminal—not the final browser page—as the source of completion status.

After the callback arrives, setup removes the temporary desktop handler, exchanges the short-lived authorization code for tokens, stores one credential bundle in the desktop keyring, and fetches the first snapshot. No callback URL needs to be copied.

## 3. Verify the connection

Inspect non-secret connection metadata:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop status
```

A connected result resembles:

```json
{"connected":true,"storage":"secret-tool","expiresAt":1788053846,"scopes":["offline","read:cycles","read:recovery","read:sleep"]}
```

The exact expiry changes over time. This command does not print the Client Secret, access token, or refresh token.

The panel should switch from demo data to live data after setup. Press `R`, middle-click the bar widget, or right-click it to request another refresh.

## Reconnect or change credentials

Run setup again. It creates a new temporary callback handler and replaces the keyring credential bundle only after WHOOP returns a valid token set. Normal token renewal does not require the browser callback handler.

Re-running setup does not revoke the previous grant at WHOOP; the old refresh token simply stops being used. To revoke it (for example, after rotating a leaked Client Secret), disconnect first:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop disconnect
```

Disconnect attempts to revoke access at WHOOP and removes the local keyring item even if the network is unavailable.

## Remove and reinstall the plugin

For a normal reinstall, remove the installed plugin and add it again from the public repository:

```bash
omarchy plugin remove io.github.jsidoryn.whoop
omarchy plugin add https://github.com/jsidoryn/omarchy-whoop --enable
```

The remove command unloads the plugin from Omarchy and deletes its installed Git checkout at `~/.config/omarchy/plugins/io.github.jsidoryn.whoop/`. It intentionally keeps the WHOOP credential bundle in your desktop keyring, so the newly installed copy should reconnect without another authorization flow.

For a completely clean reinstall, disconnect before removing the plugin:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop disconnect
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop status
```

`disconnect` attempts to revoke access at WHOOP and always removes the local credential bundle. If either command fails, stop and resolve the error before removing the plugin. Continue only after `status` reports `"connected":false`.

If you ran `disconnect` while offline or could not confirm that WHOOP accepted the revocation, also remove the authorization from WHOOP before continuing. The helper cannot guarantee remote revocation in those cases.

After confirming the plugin is disconnected, remove and add it again:

```bash
omarchy plugin remove io.github.jsidoryn.whoop
omarchy plugin add https://github.com/jsidoryn/omarchy-whoop --enable
```

After a clean reinstall, reuse your existing WHOOP application and repeat steps 2–3 above to authorize the plugin again. Run `disconnect` before `plugin remove`, because the helper used to revoke access is inside the installed plugin directory.

## Troubleshooting

### The panel still shows demo data

Check connection state:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop status
```

If `connected` is `true`, make sure forced demo mode is disabled, then refresh:

```bash
omarchy bar set io.github.jsidoryn.whoop forceDemo false --json
omarchy-shell io.github.jsidoryn.whoop refresh
```

If `connected` is `false`, run setup again.

### The browser did not open

Setup prints the complete WHOOP authorization URL when `xdg-open` fails. Open that URL in the same desktop session while the setup terminal is still waiting. Do not close or restart setup before completing consent; the callback is accepted only by that active setup attempt.

### The browser asks whether to open WHOOP for Omarchy

Accept the prompt. It is the browser's confirmation before passing the custom callback URI to the temporary desktop handler.

If you deny it, restart setup and authorize again. Do not copy the WHOOP consent-page URL; it is not the callback URL.

### The browser remains on the grant page

This is normal for a custom application URI. The browser has handed the callback to the plugin but keeps the last rendered web page open. Confirm completion in the setup terminal, then close the browser tab.

### `No WHOOP setup is waiting for this callback`

The callback arrived after setup exited or timed out. Start setup again and complete the new browser flow. Authorization codes and OAuth state values belong to one setup attempt and should not be reused.

### The callback URL does not match

Verify the WHOOP application uses exactly:

```text
io.github.jsidoryn.omarchy-whoop://oauth/callback
```

Then start a new setup attempt. A WHOOP login, consent, or dashboard URL cannot be submitted as the callback.

### Another application owns the callback scheme

Setup refuses to replace an existing handler. Inspect it with:

```bash
xdg-mime query default x-scheme-handler/io.github.jsidoryn.omarchy-whoop
```

If the result is not `io.github.jsidoryn.omarchy-whoop-oauth.desktop`, identify and resolve that application before retrying. Do not replace an unknown handler blindly.

### A callback handler remains after setup

Normal completion and ordinary setup failures remove it automatically. A power loss or forced process termination can prevent cleanup. Inspect and remove only this plugin's handler with:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler status
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler remove
```

The removal command verifies that the desktop entry belongs to this plugin and preserves unrelated MIME associations.

### `secret-tool` is missing or the keyring is unavailable

Stock Omarchy installs `secret-tool` through `libsecret` and configures a desktop keyring. Verify the command exists:

```bash
command -v secret-tool
```

If it exists but setup reports a locked or unavailable keyring, unlock the desktop keyring or log out and back into the Omarchy session before retrying. Do not work around the error by writing credentials to a plaintext file.

### The first WHOOP fetch fails after connection

Setup stores valid credentials before requesting the first snapshot. Check `whoop status`, then retry with `R` or:

```bash
omarchy-shell io.github.jsidoryn.whoop refresh
```

Temporary WHOOP or network failures do not require repeating authorization.

### Refresh returns an authorization error

The plugin refreshes expired access tokens automatically and retries once after a `401`. If authorization continues to fail, the refresh token may have been revoked, rotated elsewhere, or invalidated. Disconnect and run setup again.

### Inspect shell errors

Review recent Quickshell messages:

```bash
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

Do not include Client Secrets, callback URLs, access tokens, refresh tokens, or personal health information in public support reports. Use [private vulnerability reporting](https://github.com/jsidoryn/omarchy-whoop/security/advisories/new) for security-sensitive findings.

## Related documentation

- [Installation, architecture, and security](../security/)
- [Privacy Policy](../privacy/)
- [Project README](https://github.com/jsidoryn/omarchy-whoop)
