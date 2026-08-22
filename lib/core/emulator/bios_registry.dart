/// Per-emulator BIOS requirements sourced from https://docs.libretro.com/library/bios/
library;

/// Each emulator defines which BIOS files it needs, whether they are required
/// or optional, and optional MD5 hashes for verification. This replaces the
/// previous one-size-fits-all approach where all BIOS was treated identically.

enum BiosRequirement { required, optional, notNeeded }

class BiosFileSpec {
  /// Expected filename (case-sensitive on Linux/macOS).
  final String fileName;

  /// Whether this BIOS file is required, optional, or not needed.
  final BiosRequirement requirement;

  /// Human-readable description (e.g. "PS1 US BIOS").
  final String description;

  /// Known MD5 hash for verification. Null if no known hash.
  final String? md5Hash;

  /// Subdirectory within the BIOS folder where this file must reside.
  /// Null means the root BIOS directory. E.g. "dc" for Flycast, "pcsx2/bios" for LRPS2.
  final String? subdirectory;

  /// Region tag for display purposes (e.g. "JP", "US", "EU").
  final String? region;

  const BiosFileSpec({
    required this.fileName,
    required this.requirement,
    required this.description,
    this.md5Hash,
    this.subdirectory,
    this.region,
  });
}

class EmulatorBiosSpec {
  /// All BIOS files this emulator may need.
  final List<BiosFileSpec> files;

  /// If true, the emulator has built-in HLE BIOS and can run without any files.
  final bool hasHleBios;
  
  // Optionally provides a fallback folder if the BIOS file name does not match
  final String? fallbackSubdirectory;

  const EmulatorBiosSpec({required this.files, this.hasHleBios = false, this.fallbackSubdirectory});

  int get requiredCount => files.where((f) => f.requirement == BiosRequirement.required).length;
  int get optionalCount => files.where((f) => f.requirement == BiosRequirement.optional).length;
}

/// Registry of BIOS requirements per emulator ID.
///
/// Keys are emulator IDs matching those in `emulator_registry_data.dart`.
/// For emulators that support multiple platforms (e.g. RetroArch), each
/// platform's BIOS files are listed separately within the same emulator entry.
const Map<String, EmulatorBiosSpec> kBiosRegistry = {
  // ── PlayStation 1 (Beetle PSX HW via RetroArch) ──────────────────
  'beetle_psx_hw': EmulatorBiosSpec(
    hasHleBios: true, // OpenBIOS used if no BIOS provided
    files: [
      BiosFileSpec(
        fileName: 'scph5500.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 JP BIOS',
        md5Hash: '8dd7d5296a650fac7319bce665a6a53c',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'scph5501.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 US BIOS',
        md5Hash: '490f666e1afb15b7362b406ed1cea246',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'scph5502.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 EU BIOS',
        md5Hash: '32736f17079d0b2b7024407c39bd3050',
        region: 'EU',
      ),
      // Region-free alternatives
      BiosFileSpec(
        fileName: 'PSXONPSP660.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 region-free BIOS (from PSP)',
        md5Hash: 'c53ca5908936d412331790f4426c6c33',
      ),
      BiosFileSpec(
        fileName: 'ps1_rom.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 region-free BIOS (from PS3)',
        md5Hash: '81bbe60ba7a3d1cea1d48c14cbcc647b',
      ),
      BiosFileSpec(
        fileName: 'openbios.bin',
        requirement: BiosRequirement.optional,
        description: 'OpenBIOS (open-source replacement)',
      ),
    ],
  ),

  // ── DuckStation (standalone PS1) ─────────────────────────────────
  'duckstation': EmulatorBiosSpec(
    hasHleBios: true,
    fallbackSubdirectory: 'bios',
    files: [
      BiosFileSpec(
        fileName: 'scph1001.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 US BIOS v1.0 (earliest, best compatibility)',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'scph7001.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 US BIOS v7',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'scph5500.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 JP BIOS',
        md5Hash: '8dd7d5296a650fac7319bce665a6a53c',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'scph5501.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 US BIOS',
        md5Hash: '490f666e1afb15b7362b406ed1cea246',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'scph5502.bin',
        requirement: BiosRequirement.optional,
        description: 'PS1 EU BIOS',
        md5Hash: '32736f17079d0b2b7024407c39bd3050',
        region: 'EU',
      ),
    ],
  ),

  // ── PlayStation 2 (LRPS2) ───────────────────────────────────────
  'pcsx2': EmulatorBiosSpec(
    files: [
      // Any PS2 BIOS .bin works — no specific filename required.
      // Users must dump from their own console.
      BiosFileSpec(
        fileName: 'SCPH-70000_BIOS_V12_USA_200.BIN',
        requirement: BiosRequirement.required,
        description: 'PS2 US BIOS (example — any valid PS2 BIOS dump works)',
        subdirectory: 'pcsx2/bios',
      ),
      BiosFileSpec(
        fileName: 'SCPH-70004_BIOS_V12_EUR_200.BIN',
        requirement: BiosRequirement.required,
        description: 'PS2 EU BIOS (example)',
        subdirectory: 'pcsx2/bios',
      ),
      BiosFileSpec(
        fileName: 'SCPH-70001_BIOS_V12_JAP_200.BIN',
        requirement: BiosRequirement.required,
        description: 'PS2 JP BIOS (example)',
        subdirectory: 'pcsx2/bios',
      ),
    ],
  ),

  // ── Sega Saturn (Beetle Saturn via RetroArch) ───────────────────
  'beetle_saturn': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'sega_101.bin',
        requirement: BiosRequirement.required,
        description: 'Saturn JP BIOS',
        md5Hash: '85ec9ca47d8f6807718151cbcca8b964',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'mpr-17933.bin',
        requirement: BiosRequirement.required,
        description: 'Saturn US/EU BIOS',
        md5Hash: '3240872c70984b6cbfda1586cab68dbe',
        region: 'US/EU',
      ),
      BiosFileSpec(
        fileName: 'mpr-18811-mx.ic1',
        requirement: BiosRequirement.optional,
        description: "The King of Fighters '95 ROM Cartridge",
        md5Hash: '255113ba943c92a54facd25a10fd780c',
      ),
      BiosFileSpec(
        fileName: 'mpr-19367-mx.ic1',
        requirement: BiosRequirement.optional,
        description: 'Ultraman: Hikari no Kyojin Densetsu ROM Cartridge',
        md5Hash: '1cd19988d1d72a3e7caa0b73234c96b4',
      ),
    ],
  ),

  // ── Sega CD / Mega CD (Genesis Plus GX via RetroArch) ───────────
  'genesis_plus_gx': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'bios_MD.bin',
        requirement: BiosRequirement.optional,
        description: 'MegaDrive/Genesis startup ROM (bootrom)',
        md5Hash: '45e298905a08f9cfb38fd504cd6dbc84',
      ),
      BiosFileSpec(
        fileName: 'bios_CD_E.bin',
        requirement: BiosRequirement.required,
        description: 'MegaCD EU BIOS',
        md5Hash: 'e66fa1dc5820d254611fdcdba0662372',
        region: 'EU',
      ),
      BiosFileSpec(
        fileName: 'bios_CD_U.bin',
        requirement: BiosRequirement.required,
        description: 'SegaCD US BIOS',
        md5Hash: '854b9150240a198070150e4566ae1290',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'bios_CD_J.bin',
        requirement: BiosRequirement.required,
        description: 'MegaCD JP BIOS',
        md5Hash: '278a9397d192149e84e820ac621a8edd',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'bios_E.sms',
        requirement: BiosRequirement.optional,
        description: 'MasterSystem EU BIOS (bootrom)',
        md5Hash: '840481177270d5642a14ca71ee72844c',
        region: 'EU',
      ),
      BiosFileSpec(
        fileName: 'bios_U.sms',
        requirement: BiosRequirement.optional,
        description: 'MasterSystem US BIOS (bootrom)',
        md5Hash: '840481177270d5642a14ca71ee72844c',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'bios_J.sms',
        requirement: BiosRequirement.optional,
        description: 'MasterSystem JP BIOS (bootrom)',
        md5Hash: '24a519c53f67b00640d0048ef7089105',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'bios.gg',
        requirement: BiosRequirement.optional,
        description: 'GameGear BIOS (bootrom)',
        md5Hash: '672e104c3be3a238301aceffc3b23fd6',
      ),
      BiosFileSpec(
        fileName: 'sk.bin',
        requirement: BiosRequirement.optional,
        description: 'Sonic & Knuckles ROM (lock-on)',
        md5Hash: '4ea493ea4e9f6c9ebfccbdb15110367e',
      ),
      BiosFileSpec(
        fileName: 'sk2chip.bin',
        requirement: BiosRequirement.optional,
        description: 'Sonic & Knuckles UPMEM ROM (lock-on)',
        md5Hash: 'b4e76e416b887f4e7413ba76fa735f16',
      ),
      BiosFileSpec(
        fileName: 'areplay.bin',
        requirement: BiosRequirement.optional,
        description: 'Action Replay ROM (lock-on)',
        md5Hash: 'a0028b3043f9d59ceeb03da5b073b30d',
      ),
      BiosFileSpec(
        fileName: 'ggenie.bin',
        requirement: BiosRequirement.optional,
        description: 'Game Genie ROM (lock-on)',
        md5Hash: 'e8af7fe115a75c849f6aab3701e7799b',
      ),
    ],
  ),

  // ── Dreamcast / NAOMI (Flycast) ─────────────────────────────────
  'flycast': EmulatorBiosSpec(
    hasHleBios: true,
    files: [
      BiosFileSpec(
        fileName: 'dc_boot.bin',
        requirement: BiosRequirement.optional,
        description: 'Dreamcast BIOS',
        md5Hash: 'e10c53c2f8b90bab96ead2d368858623',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'naomi.zip',
        requirement: BiosRequirement.optional,
        description: 'NAOMI BIOS (from MAME)',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'awbios.zip',
        requirement: BiosRequirement.optional,
        description: 'Atomiswave BIOS (from MAME)',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'naomi2.zip',
        requirement: BiosRequirement.optional,
        description: 'NAOMI 2 BIOS (from MAME)',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'hod2bios.zip',
        requirement: BiosRequirement.optional,
        description: 'NAOMI The House of the Dead 2 BIOS',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'f355dlx.zip',
        requirement: BiosRequirement.optional,
        description: 'NAOMI Ferrari F355 Challenge (deluxe) BIOS',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'f355bios.zip',
        requirement: BiosRequirement.optional,
        description: 'NAOMI Ferrari F355 Challenge (twin/deluxe) BIOS',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'airlbios.zip',
        requirement: BiosRequirement.optional,
        description: 'NAOMI Airline Pilots (deluxe) BIOS',
        subdirectory: 'dc',
      ),
      BiosFileSpec(
        fileName: 'segasp.zip',
        requirement: BiosRequirement.optional,
        description: 'System SP BIOS (from MAME)',
        subdirectory: 'dc',
      ),
    ],
  ),

  // ── PSP (PPSSPP — HLE, no BIOS needed) ──────────────────────────
  'ppsspp': EmulatorBiosSpec(
    hasHleBios: true,
    files: [], // HLE emulator — no BIOS required
  ),

  // ── Nintendo DS (melonDS) ───────────────────────────────────────
  'melonds': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'bios7.bin',
        requirement: BiosRequirement.optional,
        description: 'NDS ARM7 BIOS',
        md5Hash: 'df692a80a5b1bc90728bc3dfc76cd948',
      ),
      BiosFileSpec(
        fileName: 'bios9.bin',
        requirement: BiosRequirement.optional,
        description: 'NDS ARM9 BIOS',
        md5Hash: 'a392174eb3e572fed6447e956bde4b25',
      ),
      BiosFileSpec(
        fileName: 'firmware.bin',
        requirement: BiosRequirement.optional,
        description: 'NDS Firmware',
      ),
      BiosFileSpec(
        fileName: 'dsi_bios7.bin',
        requirement: BiosRequirement.required,
        description: 'DSi ARM7 BIOS (required for DSi mode)',
      ),
      BiosFileSpec(
        fileName: 'dsi_bios9.bin',
        requirement: BiosRequirement.required,
        description: 'DSi ARM9 BIOS (required for DSi mode)',
      ),
      BiosFileSpec(
        fileName: 'dsi_firmware.bin',
        requirement: BiosRequirement.required,
        description: 'DSi Firmware (required for DSi mode)',
      ),
      BiosFileSpec(
        fileName: 'dsi_nand.bin',
        requirement: BiosRequirement.required,
        description: 'DSi NAND (required for DSi mode)',
      ),
    ],
  ),

  // ── Game Boy Advance (mGBA) ─────────────────────────────────────
  'mgba': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'gba_bios.bin',
        requirement: BiosRequirement.optional,
        description: 'Game Boy Advance BIOS',
        md5Hash: 'a860e8c0b6d573d191e4ec7db1b1e4f6',
      ),
      BiosFileSpec(
        fileName: 'gb_bios.bin',
        requirement: BiosRequirement.optional,
        description: 'Game Boy BIOS',
        md5Hash: '32fbbd84168d3482956eb3c5051637f5',
      ),
      BiosFileSpec(
        fileName: 'gbc_bios.bin',
        requirement: BiosRequirement.optional,
        description: 'Game Boy Color BIOS',
        md5Hash: 'dbfce9db9deaa2567f6a84fde55f9680',
      ),
      BiosFileSpec(
        fileName: 'sgb_bios.bin',
        requirement: BiosRequirement.optional,
        description: 'Super Game Boy BIOS',
        md5Hash: 'd574d4f9c12f305074798f54c091a8b4',
      ),
    ],
  ),

  // ── PC-FX (Beetle PC-FX via RetroArch) ──────────────────────────
  'beetle_pc_fx': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'pcfx.rom',
        requirement: BiosRequirement.required,
        description: 'PC-FX BIOS v1.00',
        md5Hash: '08e36edbea28a017f79f8d4f7ff9b6d7',
      ),
    ],
  ),

  // ── PC Engine / CD (Beetle PCE FAST via RetroArch) ──────────────
  'beetle_pce_fast': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'syscard3.pce',
        requirement: BiosRequirement.required,
        description: 'PC Engine CD BIOS v3.0',
      ),
      BiosFileSpec(
        fileName: 'gexpress.pce',
        requirement: BiosRequirement.optional,
        description: 'Game Express BIOS',
      ),
    ],
  ),

  // ── 3DO (Opera via RetroArch) ───────────────────────────────────
  'opera': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'panafz10.bin',
        requirement: BiosRequirement.required,
        description: '3DO Panasonic FZ-10 BIOS',
        region: 'US',
      ),
      BiosFileSpec(
        fileName: 'panafz1j.bin',
        requirement: BiosRequirement.required,
        description: '3DO Panasonic FZ-1 (Japan) BIOS',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'panafz1j_norsa.bin',
        requirement: BiosRequirement.required,
        description: '3DO Panasonic FZ-1 (Japan, no RSA) BIOS',
        region: 'JP',
      ),
      BiosFileSpec(
        fileName: 'panafz10_norsa.bin',
        requirement: BiosRequirement.required,
        description: '3DO Panasonic FZ-10 (no RSA) BIOS',
      ),
      BiosFileSpec(
        fileName: 'goldstar.bin',
        requirement: BiosRequirement.required,
        description: '3DO Goldstar BIOS',
      ),
      BiosFileSpec(
        fileName: 'sanyotry.bin',
        requirement: BiosRequirement.required,
        description: '3DO Sanyo BIOS',
      ),
      BiosFileSpec(
        fileName: '3do_bios.bin',
        requirement: BiosRequirement.required,
        description: '3DO BIOS (alternate name)',
      ),
    ],
  ),

  // ── GameCube / Wii (Dolphin) ────────────────────────────────────
  'dolphin': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'IPL.bin',
        requirement: BiosRequirement.optional,
        description: 'GameCube BIOS (optional, needed for some games like Star Fox Assault)',
        subdirectory: 'User/GC/USA',
      ),
    ],
  ),

  // ── Nintendo DS (DeSmuME via RetroArch) ─────────────────────────
  'desmume': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'bios7.bin',
        requirement: BiosRequirement.optional,
        description: 'NDS ARM7 BIOS',
        md5Hash: 'df692a80a5b1bc90728bc3dfc76cd948',
      ),
      BiosFileSpec(
        fileName: 'bios9.bin',
        requirement: BiosRequirement.optional,
        description: 'NDS ARM9 BIOS',
        md5Hash: 'a392174eb3e572fed6447e956bde4b25',
      ),
      BiosFileSpec(
        fileName: 'firmware.bin',
        requirement: BiosRequirement.optional,
        description: 'NDS Firmware',
      ),
    ],
  ),

  // ── Lynx (Beetle Lynx via RetroArch) ────────────────────────────
  'beetle_lynx': EmulatorBiosSpec(
    hasHleBios: true,
    files: [
      BiosFileSpec(
        fileName: 'lynxboot.img',
        requirement: BiosRequirement.optional,
        description: 'Lynx Boot ROM (HLE available as fallback)',
      ),
    ],
  ),

  // ── Atari ST (Hatari via RetroArch) ─────────────────────────────
  'hatari': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'tos.img',
        requirement: BiosRequirement.required,
        description: 'Atari ST TOS ROM',
      ),
    ],
  ),

  // ── Amiga (PUAE via RetroArch) ───────────────────────────────────
  'puae_libretro': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'kick34005.A500',
        requirement: BiosRequirement.optional,
        description: 'Amiga 500 Kickstart 1.2',
      ),
      BiosFileSpec(
        fileName: 'kick37175.A500',
        requirement: BiosRequirement.optional,
        description: 'Amiga 500 Kickstart 2.04',
      ),
      BiosFileSpec(
        fileName: 'kick40063.A600',
        requirement: BiosRequirement.optional,
        description: 'Amiga 600 Kickstart 3.1',
      ),
      BiosFileSpec(
        fileName: 'kick40068.A1200',
        requirement: BiosRequirement.optional,
        description: 'Amiga 1200 Kickstart 3.1',
      ),
      BiosFileSpec(
        fileName: 'kick40068.A4000',
        requirement: BiosRequirement.optional,
        description: 'Amiga 4000 Kickstart 3.1',
      ),
    ],
  ),
  'puae2021_libretro': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'kick34005.A500',
        requirement: BiosRequirement.optional,
        description: 'Amiga 500 Kickstart 1.2',
      ),
      BiosFileSpec(
        fileName: 'kick37175.A500',
        requirement: BiosRequirement.optional,
        description: 'Amiga 500 Kickstart 2.04',
      ),
      BiosFileSpec(
        fileName: 'kick40063.A600',
        requirement: BiosRequirement.optional,
        description: 'Amiga 600 Kickstart 3.1',
      ),
      BiosFileSpec(
        fileName: 'kick40068.A1200',
        requirement: BiosRequirement.optional,
        description: 'Amiga 1200 Kickstart 3.1',
      ),
      BiosFileSpec(
        fileName: 'kick40068.A4000',
        requirement: BiosRequirement.optional,
        description: 'Amiga 4000 Kickstart 3.1',
      ),
    ],
  ),

  // ── MSX (blueMSX via RetroArch) ─────────────────────────────────
  'bluemsx': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'MSX.ROM',
        requirement: BiosRequirement.optional,
        description: 'MSX System ROM',
      ),
      BiosFileSpec(
        fileName: 'MSX2.ROM',
        requirement: BiosRequirement.optional,
        description: 'MSX2 System ROM',
      ),
      BiosFileSpec(
        fileName: 'MSX2P.ROM',
        requirement: BiosRequirement.optional,
        description: 'MSX2+ System ROM',
      ),
      BiosFileSpec(
        fileName: 'MSXtR.ROM',
        requirement: BiosRequirement.optional,
        description: 'MSX-Music ROM',
      ),
    ],
  ),

  // ── NES / Famicom Disk System (various cores) ───────────────────
  'fceumm': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'disksys.rom',
        requirement: BiosRequirement.required,
        description: 'Famicom Disk System BIOS (required for FDS games only)',
      ),
    ],
  ),
  'nestopia': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'disksys.rom',
        requirement: BiosRequirement.required,
        description: 'Famicom Disk System BIOS (required for FDS games only)',
      ),
    ],
  ),
  'mesen': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'disksys.rom',
        requirement: BiosRequirement.required,
        description: 'Famicom Disk System BIOS (required for FDS games only)',
      ),
    ],
  ),

  // ── Intellivision (FreeIntv via RetroArch) ──────────────────────
  'freeintv': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'intellivision bios.rom',
        requirement: BiosRequirement.required,
        description: 'Intellivision BIOS',
      ),
    ],
  ),

  // ── ColecoVision (Gearcoleco via RetroArch) ─────────────────────
  'gearcoleco': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'coleco.rom',
        requirement: BiosRequirement.required,
        description: 'ColecoVision BIOS',
      ),
    ],
  ),

  // ── Odyssey2 (O2EM via RetroArch) ──────────────────────────────
  'o2em': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'o2rom.bin',
        requirement: BiosRequirement.required,
        description: 'Odyssey2 BIOS',
      ),
    ],
  ),

  // ── Palm (Mu via RetroArch) ─────────────────────────────────────
  'mu': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'palmos-rom.bin',
        requirement: BiosRequirement.required,
        description: 'Palm OS ROM',
      ),
    ],
  ),

  // ── Sharp X68000 (PX68k via RetroArch) ──────────────────────────
  'px68k': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'iplrom30.dat',
        requirement: BiosRequirement.required,
        description: 'X68000 IPL ROM v3.0',
      ),
      BiosFileSpec(
        fileName: 'iplrom.dat',
        requirement: BiosRequirement.required,
        description: 'X68000 IPL ROM',
      ),
      BiosFileSpec(
        fileName: 'cgrom.dat',
        requirement: BiosRequirement.required,
        description: 'X68000 Character Generator ROM',
      ),
    ],
  ),

  // ── PC-98 (Neko Project II Kai via RetroArch) ──────────────────
  'neko_project_ii_kai': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'np2kai/bios/bios.rom',
        requirement: BiosRequirement.required,
        description: 'PC-98 BIOS ROM',
        subdirectory: 'np2kai/bios',
      ),
      BiosFileSpec(
        fileName: 'np2kai/bios/.sound.rom',
        requirement: BiosRequirement.required,
        description: 'PC-98 Sound BIOS ROM',
        subdirectory: 'np2kai/bios',
      ),
    ],
  ),

  // ── Super Cassette Vision (EmuSCV via RetroArch) ────────────────
  'emuscv': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'ec501.bin',
        requirement: BiosRequirement.required,
        description: 'Super Cassette Vision EC501 BIOS',
      ),
      BiosFileSpec(
        fileName: 'opn.bin',
        requirement: BiosRequirement.required,
        description: 'Super Cassette Vision OPN BIOS',
      ),
    ],
  ),

  // ── Thomson MO/TO (Theodore via RetroArch) ──────────────────────
  'theodore': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'to8.rom',
        requirement: BiosRequirement.required,
        description: 'Thomson TO8 ROM',
      ),
      BiosFileSpec(
        fileName: 'to9.rom',
        requirement: BiosRequirement.required,
        description: 'Thomson TO9 ROM',
      ),
    ],
  ),

  // ── TI-83 (Numero via RetroArch) ────────────────────────────────
  'numero': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'ti83se.rom',
        requirement: BiosRequirement.optional,
        description: 'TI-83 SE ROM',
      ),
    ],
  ),

  // ── ZX Spectrum (Fuse via RetroArch) ────────────────────────────
  'fuse': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: '128.rom',
        requirement: BiosRequirement.optional,
        description: 'ZX Spectrum 128K ROM',
      ),
      BiosFileSpec(
        fileName: '48.rom',
        requirement: BiosRequirement.optional,
        description: 'ZX Spectrum 48K ROM',
      ),
    ],
  ),

  // ── Amstrad CPC (Caprice32 via RetroArch) ───────────────────────
  'caprice32': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'cpc464.rom',
        requirement: BiosRequirement.optional,
        description: 'Amstrad CPC 464 ROM',
      ),
    ],
  ),

  // ── Atari 2600 (Hatarib via RetroArch) ──────────────────────────
  'hatarib': EmulatorBiosSpec(
    hasHleBios: true,
    files: [],
  ),

  // ── Neo Geo (various cores) ─────────────────────────────────────
  // Neo Geo cores use HLE — the AES/MVS BIOS is embedded in ROMs
  'neocd': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'neocd.bin',
        requirement: BiosRequirement.required,
        description: 'Neo Geo CD BIOS',
      ),
    ],
  ),

  // ── PC-88 (QUASI88 via RetroArch) ───────────────────────────────
  'quasi88': EmulatorBiosSpec(
    files: [
      BiosFileSpec(
        fileName: 'n88.rom',
        requirement: BiosRequirement.required,
        description: 'PC-88 N88 ROM',
      ),
      BiosFileSpec(
        fileName: 'n88ext.rom',
        requirement: BiosRequirement.required,
        description: 'PC-88 Extension ROM',
      ),
    ],
  ),

  // ── Commodore 64 (VICE via RetroArch) ───────────────────────────
  'vice': EmulatorBiosSpec(
    hasHleBios: true,
    files: [], // VICE includes its own ROMs
  ),

  // ── WonderSwan (various cores) ──────────────────────────────────
  // No BIOS needed for WonderSwan emulation
};

/// Look up BIOS requirements for a given emulator ID.
///
/// Returns null if the emulator has no entry in the registry (unknown emulator).
/// An empty `files` list with `hasHleBios: true` means no BIOS is needed.
EmulatorBiosSpec? getBiosSpecForEmulator(String emulatorId) {
  return kBiosRegistry[emulatorId];
}

/// Get all known emulator IDs that have BIOS registry entries.
List<String> get registeredEmulatorIds => kBiosRegistry.keys.toList();
