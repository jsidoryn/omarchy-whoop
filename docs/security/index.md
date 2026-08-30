---
layout: default
title: Installation, architecture, and security
---

# Installation, architecture, and security

WHOOP for Omarchy is a local-first shell plugin. Its QML interface runs inside the long-lived Omarchy shell; short-lived Ruby processes handle credentials, WHOOP API requests, token rotation, and data normalization. Your machine communicates directly with WHOOP over HTTPS. The project operates no API relay, account service, analytics service, or health-data store.

## Installation footprint

The standard installation command is:

```bash
omarchy plugin add https://github.com/jsidoryn/omarchy-whoop --enable
```

Omarchy clones the repository into the user plugin directory, validates its manifest, enables its service and bar widget, and records its bar placement and settings in the Omarchy shell configuration.

| Item | Location | Lifetime | Contents |
| --- | --- | --- | --- |
| Plugin source | `~/.config/omarchy/plugins/io.github.jsidoryn.whoop/` | Until plugin removal | QML, Ruby, JavaScript, documentation, and tests. No user credentials. |
| Shell configuration | `~/.config/omarchy/shell.json` | While configured | Plugin ID, placement, refresh interval, and demo-mode setting. |
| Credential bundle | Desktop keyring via `secret-tool` | Until disconnect or manual deletion | Client ID, Client Secret, access token, refresh token, expiry, redirect URI, and scopes. |
| Callback desktop entry | `~/.local/share/applications/io.github.jsidoryn.omarchy-whoop-oauth.desktop` | Only during interactive authorization under normal operation | The installed helper path and custom URI association. No credentials or WHOOP data. |
| OAuth runtime socket | `$XDG_RUNTIME_DIR/omarchy-whoop/oauth-callback.sock` | Only while setup waits | The browser callback in transit; it is not persisted. |
| Runtime lock files | `$XDG_RUNTIME_DIR/omarchy-whoop/` | Desktop session | Empty coordination files with owner-only permissions. |
| Displayed health snapshot | Quickshell process memory | Until refresh or shell exit | The normalized values currently shown by the bar and panel. |

The plugin does not install Ruby gems, Node packages, a browser extension, daemon, systemd unit, cron job, database, binary executable, or privileged helper. It does not call `sudo` or `pkexec`. Stock Omarchy already includes Ruby, `libsecret`, `secret-tool`, and a compatible desktop keyring; setup checks for the command instead of installing packages.

## Runtime architecture

### Authorization

1. The setup helper registers a temporary Linux `x-scheme-handler` desktop entry for `io.github.jsidoryn.omarchy-whoop://oauth/callback`.
2. Ruby opens WHOOP authorization in the default browser and waits on an owner-only Unix socket.
3. WHOOP returns a short-lived authorization code and the original OAuth state through the custom URI.
4. Linux launches the plugin's callback helper, which validates the URI and relays it to the waiting setup process.
5. Setup verifies the state, exchanges the code directly with WHOOP, and removes the temporary desktop handler.
6. The returned credential bundle is stored as one desktop-keyring item.

The callback URL is briefly present as a process argument to the short-lived desktop helper. It is then transferred through the runtime socket and is never written to disk. Like other process arguments, it may be observable by local process-inspection tools available to the same user while that helper runs.

### Data refresh

`Service.qml` owns one timer and one shared snapshot for all bar surfaces. Every ten minutes by default, it starts `bin/whoop snapshot` and captures one JSON response.

The Ruby helper:

1. Looks up the exact keyring item.
2. Refreshes the access token only when it is close to expiry.
3. Requests current and recent cycle, recovery, and sleep records from WHOOP.
4. Reduces the response to the display contract.
5. Writes that JSON to standard output and exits.

The ten-minute interval controls data freshness; it is not a token-refresh requirement. Manual refresh is available from the panel and bar. Token renewal uses WHOOP's returned `expires_in` value and the saved refresh token. Refresh tokens rotate, so the plugin serializes renewal and replaces the complete keyring value atomically.

At the default interval, one continuously running plugin makes approximately 720 data requests per day. This is below WHOOP's published default limit of 10,000 requests per day. Users can configure a polling interval from five minutes to one hour.

## Security decisions

### Per-user WHOOP applications

Each installer creates and controls a separate WHOOP developer application. The repository contains no shared Client ID or Client Secret. This avoids distributing one credential across every installation and limits a developer credential compromise to the application that owns it.

### Least-privilege scopes

The plugin requests only:

```text
offline
read:cycles
read:recovery
read:sleep
```

It does not request profile, email, body-measurement, workout, or write scopes. `offline` is required to obtain a refresh token and does not grant an additional health-data category.

### Desktop keyring instead of plaintext files

Credentials are stored through `secret-tool` using one exact attribute pair:

```bash
secret-tool lookup service omarchy-whoop account credentials
```

The complete JSON bundle is supplied to `secret-tool store` through standard input, not as a command-line argument. Tokens are not stored in `shell.json`, the plugin directory, environment files, logs, or a health-data cache.

This is a storage boundary, not a per-plugin sandbox. Once the desktop keyring is unlocked, another process running as the same user may be able to request this item or other keyring items. Omarchy plugins also execute with the permissions of the logged-in user.

### Temporary callback registration

The custom URI handler exists only while setup is waiting for authorization and is removed on success and ordinary failure. It contains only the helper path. Registration is per-user, requires no elevation, and refuses to replace another application's handler for the same scheme.

Setup uses an eight-character random OAuth state, validates the returned scheme, host, path, and state, rejects control characters and oversized callbacks, and accepts callbacks only while that setup process owns the runtime socket.

### Owner-only runtime coordination

The OAuth runtime directory is mode `0700`; its socket and lock are mode `0600`. Setup rejects a runtime directory not owned by the current user and prevents concurrent authorization attempts. Token refresh uses a separate owner-only lock so two shell requests cannot rotate the same refresh token concurrently.

### No persistent health-data cache

WHOOP responses are normalized by a short-lived Ruby process and retained only in Quickshell memory for display. The plugin writes no health-history database. Seven-day trends are retrieved from WHOOP's collection endpoints on each refresh rather than accumulated locally.

### Direct, bounded network access

Runtime requests go only to WHOOP's production OAuth and developer API endpoints over HTTPS. The plugin uses Ruby's standard HTTP and TLS libraries with connection and read timeouts. There are no webhooks, third-party relays, analytics requests, or remote code downloads.

### Predictable failure behavior

The panel keeps the last successful in-memory snapshot visible when a refresh fails and reports the error inline. A `401` expires the saved access token and causes one refresh-and-retry cycle. Disconnect attempts WHOOP revocation but always removes the local keyring item, allowing local deletion while offline.

## Installer responsibilities

Installing an Omarchy plugin authorizes code to run as your desktop user. Before enabling this plugin, you are responsible for:

- reviewing the repository, release history, and manifest from the source you intend to install;
- creating and maintaining your own WHOOP developer application;
- keeping its Client Secret and the plugin's OAuth credentials out of issues, screenshots, shell history, dotfiles, and shared logs;
- enabling only the documented scopes and using the exact redirect URL;
- protecting the desktop session and keyring, including locking the screen when unattended;
- applying trusted Omarchy and plugin updates;
- reviewing WHOOP's developer terms and this project's [Privacy Policy](../privacy/); and
- disconnecting the integration before removal when you want authorization and local credentials deleted.

Do not install a fork or commit you do not trust merely because its manifest validates. Omarchy's validation checks plugin structure; it is not a runtime sandbox or a security review.

## Removal and recovery

To revoke access and remove the keyring item, then remove the plugin:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop disconnect
omarchy plugin remove io.github.jsidoryn.whoop
```

Removing the plugin alone intentionally leaves the credential bundle in the keyring, allowing recovery from accidental removal. Run `disconnect` first when performing a deliberate clean uninstall.

The callback desktop entry should not remain after setup. A power loss or forced process termination can prevent normal cleanup. Before removing the plugin, inspect and remove a residual handler if necessary:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler status
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler remove
```

The removal operation verifies that the desktop entry belongs to this plugin and removes only its MIME associations.

## Reporting security issues

Never include a Client Secret, callback URL, access token, refresh token, or health data in a public issue. Use [GitHub private vulnerability reporting](https://github.com/jsidoryn/omarchy-whoop/security/advisories/new) for security-sensitive reports.

## Related documentation

- [Setup and troubleshooting](../setup/)
- [Privacy Policy](../privacy/)
- [Source repository](https://github.com/jsidoryn/omarchy-whoop)
