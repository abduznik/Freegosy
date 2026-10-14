# Patches to gamepads_linux 0.1.2

Upstream: https://github.com/flame-engine/gamepads/tree/main/packages/gamepads_linux
(BSD-style license in `LICENSE`.)

Why this copy exists: when the user's inotify instance limit
(`fs.inotify.max_user_instances`, default 128) is used up, the plugin's
background thread throws `std::runtime_error("Error initializing inotify")`.
Nothing catches it, so the whole app aborts (SIGABRT) at startup, before any
Dart code runs. Whether Freegosy starts then depends on how many other apps
hold inotify instances at that moment.

Changes (all in `linux/`):

- `connection_listener.cc`: `listen` no longer throws. If inotify can't be
  started (or the watch or a read fails), it falls back to polling
  `/dev/input` every 2 seconds for controllers connecting and disconnecting.
  A missing `/dev/input` is tolerated too. Also stops dereferencing an empty
  optional for an unrecognised inotify event.
- `gamepads_linux_plugin.cc`: the two background threads catch every
  exception and log it, so a failure there can never terminate the app.

Drop this copy (and the `dependency_overrides` entry in the root
`pubspec.yaml`) once upstream ships the same fix.

## Ignore motion-sensor devices (#169)

- `device_filter.h` (new) and `connection_listener.cc`: a DualSense exposes
  "... Motion Sensors" as its own `/dev/input/js*` node that streams
  accelerometer axes continuously. Those nodes (by name, or by the kernel's
  INPUT_PROP_ACCELEROMETER property) are no longer reported as gamepads, so
  the app is not flooded with events from them.
