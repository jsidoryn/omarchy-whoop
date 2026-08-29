# Contributing

Issues and pull requests are welcome. Please keep changes focused and explain the user-visible outcome.

Before opening a pull request:

```bash
./tests/run
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell \
  Service.qml BarWidget.qml Panel.qml RecoveryRing.qml MetricTile.qml WeekStrip.qml
```

The GitHub check named **Ruby and JavaScript tests** pins Ruby 4.0, the current major version in Omarchy, and runs the Ruby and JavaScript suite. Omarchy plugin validation and QML linting currently run locally because the hosted runner does not include Omarchy. The maintainer runs both local checks before merging QML changes.

Never commit WHOOP Client Secrets, OAuth tokens, keyring contents, real health information, or fixtures copied from a WHOOP account. Use the generated demo scenarios and synthetic test fixtures.

Contributions are made under the repository's MIT license. Submitting a pull request does not grant continuing write access; the maintainer reviews and decides whether to merge each change.
