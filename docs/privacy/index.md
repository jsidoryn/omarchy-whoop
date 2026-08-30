---
layout: default
title: Privacy Policy
---

# WHOOP for Omarchy Privacy Policy

**Effective date:** 30 August 2026

WHOOP for Omarchy is a local-first desktop plugin maintained by Jason Sidoryn. This policy explains how the plugin processes information when you connect it to your WHOOP account.

## Information the plugin processes

With your authorization, the plugin requests the minimum WHOOP scopes it needs to display:

- physiological cycle timing and strain;
- recovery score, status, heart rate variability, and resting heart rate;
- sleep score and related sleep measurements; and
- recent cycle, recovery, and sleep records used to display seven-day trends.

The plugin also processes the Client ID and Client Secret for the WHOOP developer application you create, together with the OAuth access token, refresh token, expiry, redirect URI, and granted scopes returned by WHOOP.

The plugin does not request WHOOP profile, email, body measurement, workout, or write access.

## How information is used

WHOOP information is used only to retrieve and display your statistics in the Omarchy desktop interface. It is not used for advertising, profiling, analytics, or automated decision-making, and it is not sold or rented.

## Processing and storage

- Requests travel directly from your computer to WHOOP over HTTPS. The maintainer does not operate an intermediary server.
- WHOOP statistics are held in the running plugin's memory and replaced when data is refreshed. They are not written to a plugin database or permanent cache and are discarded when the Omarchy shell exits.
- OAuth credentials are stored as one item in your desktop keyring through `secret-tool`. They are not written to the plugin directory, Omarchy configuration, logs, or a health-data cache.
- During setup, the browser returns a short-lived authorization code to a temporary, per-user desktop URL handler. The desktop launcher briefly supplies the callback URL to the helper as a process argument; the helper then relays it to the waiting setup process through an owner-only runtime socket. The callback is not written to disk. Like other process arguments, it can be visible to local process-inspection tools while that short-lived helper is running. The handler's desktop entry contains only the installed helper path and is removed after authorization succeeds or ordinarily fails.
- A local owner-only runtime lock file coordinates token refreshes. It contains no WHOOP credentials or health information.
- Demo information is generated locally and is never sent to WHOOP.

## Sharing and third parties

The plugin does not send WHOOP information to the maintainer, analytics providers, advertisers, or other third parties. WHOOP processes your account and API requests under the [WHOOP Privacy Policy](https://www.whoop.com/privacy/).

This policy website is hosted by GitHub Pages. GitHub may process ordinary website access information under the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). No additional analytics or tracking scripts are installed on this site.

## Retention and deletion

Credentials remain in your desktop keyring until you disconnect the plugin or remove the keyring item. Choosing **Disconnect** asks WHOOP to revoke access and removes the local credential bundle even if revocation cannot be completed because the network is unavailable.

Removing the plugin by itself does not remove credentials. To revoke access and delete them first, run:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop disconnect
```

The temporary callback-handler desktop entry should not remain after setup. A power loss or forced process termination can prevent normal cleanup. Inspect and remove a residual entry before uninstalling the plugin if necessary:

```bash
~/.config/omarchy/plugins/io.github.jsidoryn.whoop/bin/whoop callback-handler remove
```

You can also revoke the application from your WHOOP account. In-memory WHOOP statistics are discarded when the Omarchy shell exits.

If the saved keyring item is corrupt and the helper cannot read it, remove that one item directly:

```bash
secret-tool clear service omarchy-whoop account credentials
```

Because the maintainer receives and stores no copy of your WHOOP information, the maintainer cannot retrieve or delete that information on your behalf. You control it locally through the plugin, your desktop keyring, and WHOOP.

## Security

The plugin uses HTTPS for WHOOP requests and the desktop keyring for credentials. Omarchy plugins run with the permissions of your user account, so you should install only code you trust and keep your desktop session protected.

Never post Client Secrets, OAuth tokens, or health information in a public issue. Report security concerns using [GitHub private vulnerability reporting](https://github.com/jsidoryn/omarchy-whoop/security/advisories/new).

## Changes to this policy

Material changes will be published on this page and the effective date will be updated. The version in effect when you use the plugin describes its current processing.

## Contact

For privacy questions or requests, contact [jason@katalyst.com.au](mailto:jason@katalyst.com.au). For general support, you may also [open a GitHub issue](https://github.com/jsidoryn/omarchy-whoop/issues), but do not include credentials or health information.

WHOOP for Omarchy is an independent open-source project and is not affiliated with, endorsed by, or sponsored by WHOOP.
