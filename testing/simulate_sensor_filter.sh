#!/usr/bin/env bash
# Simulation for #169 (native side): fake /sys/class/input with a DualSense's
# pad, motion-sensor node and an Xbox pad, and show which nodes the plugin's
# filter would report as gamepads.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mk() { mkdir -p "$work/$1/device"; echo "$2" > "$work/$1/device/name"; echo "$3" > "$work/$1/device/properties"; }
mk js0 "DualSense Wireless Controller" 0
mk js1 "DualSense Wireless Controller Motion Sensors" 40   # INPUT_PROP_ACCELEROMETER
mk js2 "Xbox 360 Controller" 0
mk js3 "Some Renamed Sensor Node" 40                       # only the property gives it away
cat > "$work/t.cc" <<CC
#include <iostream>
#include "device_filter.h"
int main() {
  int bad = 0;
  const struct { const char* js; bool sensor; } cases[] = {
    {"js0", false}, {"js1", true}, {"js2", false}, {"js3", true}, {"js9", false}};
  for (auto& c : cases) {
    bool got = device_filter::is_sensor_device(c.js, "$work");
    std::cout << c.js << ": " << (got ? "IGNORED (sensor)" : "gamepad") << "\n";
    bad += got != c.sensor;
  }
  std::cout << (bad ? "FAIL" : "ok") << "\n";
  return bad;
}
CC
g++ -std=c++17 -I"$here/thirdparty/gamepads_linux/linux" "$work/t.cc" -o "$work/t"
"$work/t"
