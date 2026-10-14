#pragma once

#include <algorithm>
#include <cctype>
#include <fstream>
#include <string>

// Some controllers expose their motion sensors (and touchpad) as extra
// /dev/input/js* nodes: a DualSense shows up as "DualSense Wireless
// Controller" plus "DualSense Wireless Controller Motion Sensors". The sensor
// node streams accelerometer/gyro axes continuously, which is not controller
// input and floods the app (#169). SDL skips these the same way, by the
// INPUT_PROP_ACCELEROMETER property.
namespace device_filter {

inline std::string lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return value;
}

inline bool name_is_sensor(const std::string& name) {
  const std::string lower = lowercase(name);
  return lower.find("motion sensors") != std::string::npos ||
         lower.find("accelerometer") != std::string::npos ||
         lower.find("gyroscope") != std::string::npos ||
         lower.find("touchpad") != std::string::npos;
}

// INPUT_PROP_ACCELEROMETER is bit 6 of the device's `properties` bitmask.
// The file is a hex string; with several words (64-bit masks) the lowest is last.
inline bool properties_mark_accelerometer(const std::string& properties) {
  const auto start = properties.find_last_of(' ');
  const std::string last =
      start == std::string::npos ? properties : properties.substr(start + 1);
  try {
    return (std::stoul(last, nullptr, 16) & (1ul << 6)) != 0;
  } catch (const std::exception&) {
    return false;
  }
}

inline std::string read_first_line(const std::string& path) {
  std::ifstream file(path);
  std::string line;
  if (file.is_open()) {
    std::getline(file, line);
  }
  return line;
}

// `js_name` is e.g. "js1"; `sysfs_class_input` is normally /sys/class/input.
inline bool is_sensor_device(const std::string& js_name,
                             const std::string& sysfs_class_input =
                                 "/sys/class/input") {
  const std::string base = sysfs_class_input + "/" + js_name + "/device/";
  return name_is_sensor(read_first_line(base + "name")) ||
         properties_mark_accelerometer(read_first_line(base + "properties"));
}

}  // namespace device_filter
