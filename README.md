# adb

Small Emacs library for Android device communication. No Android project,
Gradle, or minor mode is required. The core library requires only Emacs 28.1;
its optional Transient UI requires Transient 0.3.0 and an installed adb.

## Installation

```elisp
(use-package adb
  :vc (:url "https://github.com/cat-emacs/adb"))
```

Dependencies of other Cat Android packages should be installed explicitly via
package-vc as well; their package metadata does not register a VC source.

## Migration

This package was previously named `android-adb`. Replace its package declaration
with `adb`, rename configured `android-adb-*` symbols to `adb-*`, and restart
Emacs after installing the renamed package. Remove the old package only after
its consumers have been updated; do not load both implementations.

## Interface

- `adb-executable`: explicit executable, then exec-path, then configured
  SDK / ANDROID_HOME / ANDROID_SDK_ROOT platform-tools.
- `adb-command`: argument vector for a serial and command arguments.
- `adb-start`: asynchronous process, owned by the caller.
- `adb-install-apk`: asynchronous `adb install -r` with a completion
  callback receiving exit status and output.
- `adb-launch-package`, `adb-force-stop`,
  `adb-uninstall`, `adb-clear-package-data`: application
  lifecycle operations.
- `adb-push` / `adb-pull`: asynchronous file transfer.
- `adb-connect` / `adb-disconnect` / `adb-pair`:
  network device management.
- `adb-get-state`, `adb-get-serialno`,
  `adb-wait-for-device`, `adb-reboot`, `adb-tcpip`, and
  `adb-usb`: device state and transport control.
- `adb-install-multiple` and `adb-bugreport`: multi-APK
  installation and bug report generation.
- `adb-forward` / `adb-reverse`: port mapping.
- `adb-getprop`, `adb-device-info`, `adb-battery`, and
  `adb-display-size`: common device queries.
- `adb-query`: bounded short query; signals on failure or timeout.
- `adb-parse-devices` / `adb-devices`: device plists, including
  offline and unauthorized states; an optional flag filters to usable devices.
- `adb-device-label` / `adb-read-device`: unambiguous labels
  and selection of a usable serial.
- `adb-transient.el` provides `M-x adb`. Its groups are Device, Network,
  App, Files, and System, and every top-level key is unique. `a` opens the
  activity manager menu and `p` opens the package manager menu. Those menus
  expose the common `am` and `pm` actions together with their usual options:
  intent fields, launch flags, user, package filters, permissions, and
  keep-data or cache-only switches. Package, component, permission, and user
  prompts offer candidates. APK installation remains an adb operation beside
  the shell menus. Loading `adb.el` alone does not load Transient.

Set `adb-default-device-serial` to avoid repeated selection prompts.
The Transient menu uses the same default serial as the programmatic interface.
Set `adb-program` for an explicit executable, or
`adb-sdk-directory` for SDK fallback. Queries default to a five-second
timeout. Commands use argument vectors, not shell command strings.

## Development

Run `make lint build test`. Tests use fake commands and do not contact devices.
Licensed under GPL-3.0-or-later.
