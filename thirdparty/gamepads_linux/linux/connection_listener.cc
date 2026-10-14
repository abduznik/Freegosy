#include <unistd.h>
#include <functional>
#include <iostream>
#include <optional>
#include <string>

#include <dirent.h>
#include <sys/inotify.h>
#include <chrono>
#include <map>
#include <set>
#include <thread>
#include <vector>

#include "connection_listener.h"
#include "device_filter.h"
#include "utils.h"

using namespace connection_listener;

const std::string _input_dir = "/dev/input/";

std::map<ConnectionEventType, const char*> connectionEventTypeNames = {
    {ConnectionEventType::CONNECTED, "CONNECTED"},
    {ConnectionEventType::DISCONNECTED, "DISCONNECTED"},
};

std::optional<ConnectionEventType> _parseEventType(inotify_event* event) {
  uint mask = event->mask;
  if ((mask & IN_CREATE) || (mask & IN_ATTRIB)) {
    return ConnectionEventType::CONNECTED;
  } else if (mask & IN_DELETE) {
    return ConnectionEventType::DISCONNECTED;
  } else {
    return std::nullopt;
  }
}

// The joystick devices in /dev/input right now. Empty (not an error) when the
// directory can't be read.
std::vector<std::string> _list_devices() {
  std::vector<std::string> devices;
  DIR* dir = opendir(_input_dir.c_str());
  if (!dir) {
    std::cerr << "Failed to open directory: " << _input_dir << std::endl;
    return devices;
  }

  struct dirent* entry;
  while ((entry = readdir(dir)) != nullptr) {
    if (entry->d_type != DT_CHR) {
      continue;
    }
    if (!starts_with(entry->d_name, "js")) {
      continue;
    }
    if (device_filter::is_sensor_device(entry->d_name)) {
      std::cout << "Ignoring motion sensor device " << entry->d_name
                << std::endl;
      continue;
    }
    devices.push_back(_input_dir + entry->d_name);
  }
  closedir(dir);
  return devices;
}

void _list_existing(
    const std::function<void(const ConnectionEvent&)>& event_consumer) {
  for (std::string& device : _list_devices()) {
    ConnectionEvent connectionEvent = {ConnectionEventType::CONNECTED, device};
    event_consumer(connectionEvent);
  }
}

// Used when inotify isn't available (its per-user instance limit can be used
// up by other apps): look for controllers connecting and disconnecting every
// couple of seconds instead.
void _poll_for_connections(
    const bool* keep_reading,
    const std::function<void(const ConnectionEvent&)>& event_consumer) {
  std::cout << "Polling for gamepads (inotify unavailable)..." << std::endl;
  std::set<std::string> known;
  for (const std::string& device : _list_devices()) {
    known.insert(device);
  }
  while (*keep_reading) {
    // Sleep in short steps so a stop request is noticed quickly.
    for (int i = 0; i < 20 && *keep_reading; i++) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (!*keep_reading) {
      break;
    }
    std::vector<std::string> devices = _list_devices();
    std::set<std::string> current(devices.begin(), devices.end());
    for (const std::string& device : current) {
      if (known.count(device) == 0) {
        event_consumer({ConnectionEventType::CONNECTED, device});
      }
    }
    for (const std::string& device : known) {
      if (current.count(device) == 0) {
        event_consumer({ConnectionEventType::DISCONNECTED, device});
      }
    }
    known = current;
  }
  std::cout << "Stopped listening for gamepads." << std::endl;
}

void _wait_for_connections(
    int inotify,
    const std::function<void(const ConnectionEvent&)>& event_consumer) {
  char buffer[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
  ssize_t len = read(inotify, buffer, sizeof(buffer));
  if (len < 0) {
    std::cerr << "Error reading inotify events" << std::endl;
    throw std::runtime_error("Error reading inotify events");
  }

  char* ptr = buffer;
  while (ptr < buffer + len) {
    auto* event = reinterpret_cast<struct inotify_event*>(ptr);
    std::string name = event->name;
    if (!starts_with(name, "js")) {
      break;
    }

    std::string device = _input_dir + name;
    std::optional<ConnectionEventType> type = _parseEventType(event);
    if (!type) {
      ptr += sizeof(struct inotify_event) + event->len;
      continue;
    }

    if (*type == ConnectionEventType::CONNECTED &&
        device_filter::is_sensor_device(name)) {
      std::cout << "Ignoring motion sensor device " << name << std::endl;
      ptr += sizeof(struct inotify_event) + event->len;
      continue;
    }

    std::cout << "Connection found: " << connectionEventTypeNames[*type]
              << " - " << name << std::endl;
    ConnectionEvent connection_event = {*type, device};
    event_consumer(connection_event);

    ptr += sizeof(struct inotify_event) + event->len;
  }
}

namespace connection_listener {
// Never throws: a failure here would otherwise terminate the whole app from
// this background thread. Without inotify it polls instead.
void listen(const bool* keep_reading,
            const std::function<void(const ConnectionEvent&)>& event_consumer) {
  std::cout << "Reading initial gamepads..." << std::endl;
  _list_existing(event_consumer);

  int inotify = inotify_init();
  if (inotify == -1) {
    std::cerr << "Error initializing inotify" << std::endl;
    _poll_for_connections(keep_reading, event_consumer);
    return;
  }
  int watcher = inotify_add_watch(inotify, _input_dir.c_str(),
                                  IN_CREATE | IN_DELETE | IN_ATTRIB);
  if (watcher == -1) {
    close(inotify);
    std::cerr << "Error adding watch for " << _input_dir << std::endl;
    _poll_for_connections(keep_reading, event_consumer);
    return;
  }

  std::cout << "Listening for gamepads..." << std::endl;
  bool failed = false;
  while (*keep_reading) {
    try {
      _wait_for_connections(inotify, event_consumer);
    } catch (const std::exception& e) {
      std::cerr << "Gamepad connection listener failed: " << e.what()
                << std::endl;
      failed = true;
      break;
    }
  }

  // Remove the inotify watch and close the file descriptor
  inotify_rm_watch(inotify, watcher);
  close(inotify);
  if (failed) {
    _poll_for_connections(keep_reading, event_consumer);
    return;
  }
  std::cout << "Stopped listening for gamepads." << std::endl;
}
}  // namespace connection_listener
