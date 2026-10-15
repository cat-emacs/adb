# android-adb

Small Emacs library for Android device communication. No Android project,
Gradle, or minor mode is required. The core library requires only Emacs 28.1;
its optional Transient UI requires Transient 0.3.0 and an installed adb.

## Installation

```elisp
(use-package android-adb
  :vc (:url "https://github.com/cat-emacs/android-adb"))
```

Dependencies of other Cat Android packages should be installed explicitly via
package-vc as well; their package metadata does not register a VC source.

## Interface

- `android-adb-executable`: explicit executable, then exec-path, then configured
  SDK / ANDROID_HOME / ANDROID_SDK_ROOT platform-tools.
- `android-adb-command`: argument vector for a serial and command arguments.
- `android-adb-start`: asynchronous process, owned by the caller.
- `android-adb-install-apk`: asynchronous `adb install -r` with a completion
  callback receiving exit status and output.
- `android-adb-query`: bounded short query; signals on failure or timeout.
- `android-adb-parse-devices` / `android-adb-devices`: device plists, including
  offline and unauthorized states; an optional flag filters to usable devices.
- `android-adb-device-label` / `android-adb-read-device`: unambiguous labels
  and selection of a usable serial.
- `android-adb-transient.el` provides `M-x android-adb`: a Transient menu for
  device selection/listing, adb server management, reconnect, APK installation,
  and an adb shell command. Loading `android-adb.el` alone does not load
  Transient.

Set `android-adb-default-device-serial` to avoid repeated selection prompts.
The Transient menu uses the same default serial as the programmatic interface.
Set `android-adb-program` for an explicit executable, or
`android-adb-sdk-directory` for SDK fallback. Queries default to a five-second
timeout. Commands use argument vectors, not shell command strings.

## Development

Run `make lint build test`. Tests use fake commands and do not contact devices.
Licensed under GPL-3.0-or-later.
