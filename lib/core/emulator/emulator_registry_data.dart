const List<Map<String, dynamic>> kEmulatorDefinitions = [
  {
    'id': 'retroarch',
    'name': 'RetroArch',
    'windows_url': 'https://buildbot.libretro.com/stable/1.19.1/windows/x86_64/RetroArch.7z',
    'windows_executable': 'RetroArch.exe',
    'linux_executable': 'retroarch',
    'platform_slugs': [
      'gba', 'gbc', 'gb', 'nes', 'snes', 'n64', 'nds', 'psx', 'psp',
      'segacd', 'saturn', 'dreamcast', 'megadrive', 'genesis', 'gamegear',
      'atari2600', 'atari7800', 'lynx', 'neogeo', 'arcade', 'mame',
      'pcengine', 'wonderswan', 'virtualboy', 'msx', 'dos'
    ],
  },
  {
    'id': 'dolphin',
    'name': 'Dolphin',
    'windows_url': 'https://dl.dolphin-emu.org/builds/dolphin-master-latest-x64.7z',
    'windows_executable': 'Dolphin.exe',
    'linux_executable': 'dolphin-emu',
    'platform_slugs': ['gc', 'gamecube', 'wii', 'ngc'],
  },
  {
    'id': 'eden',
    'name': 'Eden (Switch)',
    'windows_url': 'https://git.eden-emu.dev/eden-emu/eden/-/releases/permalink/latest/downloads/eden-windows-msvc-install.zip',
    'windows_executable': 'eden.exe',
    'linux_executable': 'eden',
    'platform_slugs': ['switch', 'nintendo-switch', 'ns'],
  },
];
