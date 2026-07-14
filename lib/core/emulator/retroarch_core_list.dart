enum CoreCategory { recommended, nintendo, sega, sony, arcade, computer, handheld, other }

class RetroArchCore {
  final String id;
  final String displayName;
  final List<String> platforms;
  final CoreCategory category;
  final bool isRecommended;
  final String? description;

  const RetroArchCore({
    required this.id,
    required this.displayName,
    required this.platforms,
    required this.category,
    this.isRecommended = false,
    this.description,
  });
}

const List<RetroArchCore> kRetroArchCores = [
  // ── Nintendo ──────────────────────────────────────────────
  RetroArchCore(
    id: 'mgba_libretro',
    displayName: 'mGBA',
    platforms: ['gba', 'game-boy-advance'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Best GBA core',
  ),
  RetroArchCore(
    id: 'gambatte_libretro',
    displayName: 'Gambatte',
    platforms: ['gbc', 'gb', 'game-boy-color', 'game-boy'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Best Game Boy / Game Boy Color core',
  ),
  RetroArchCore(
    id: 'sameboy_libretro',
    displayName: 'SameBoy',
    platforms: ['gbc', 'gb', 'game-boy-color', 'game-boy'],
    category: CoreCategory.nintendo,
    description: 'High-accuracy Game Boy / Game Boy Color',
  ),
  RetroArchCore(
    id: 'gearboy_libretro',
    displayName: 'Gearboy',
    platforms: ['gbc', 'gb', 'game-boy-color', 'game-boy'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'tgbdual_libretro',
    displayName: 'TGB Dual',
    platforms: ['gbc', 'gb', 'game-boy-color', 'game-boy'],
    category: CoreCategory.nintendo,
    description: 'Game Boy with link cable emulation',
  ),
  RetroArchCore(
    id: 'mesen_libretro',
    displayName: 'Mesen',
    platforms: ['nes'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Highly accurate NES core',
  ),
  RetroArchCore(
    id: 'fceumm_libretro',
    displayName: 'FCEUmm',
    platforms: ['nes'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Popular NES core with good compatibility',
  ),
  RetroArchCore(
    id: 'nestopia_libretro',
    displayName: 'Nestopia UE',
    platforms: ['nes'],
    category: CoreCategory.nintendo,
    description: 'Accurate NES / Famicom emulator',
  ),
  RetroArchCore(
    id: 'quicknes_libretro',
    displayName: 'QuickNES',
    platforms: ['nes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'fixnes_libretro',
    displayName: 'FixNES',
    platforms: ['nes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'snes9x_libretro',
    displayName: 'Snes9x',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Best overall SNES core',
  ),
  RetroArchCore(
    id: 'bsnes_libretro',
    displayName: 'bsnes',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
    description: 'High-accuracy SNES (high CPU usage)',
  ),
  RetroArchCore(
    id: 'bsnes2014_accuracy_libretro',
    displayName: 'bsnes2014 Accuracy',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes2014_balanced_libretro',
    displayName: 'bsnes2014 Balanced',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes2014_performance_libretro',
    displayName: 'bsnes2014 Performance',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes_hd_beta_libretro',
    displayName: 'bsnes HD Beta',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
    description: 'bsnes with HD texture packs',
  ),
  RetroArchCore(
    id: 'bsnes_mercury_accuracy_libretro',
    displayName: 'bsnes Mercury Accuracy',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes_mercury_balanced_libretro',
    displayName: 'bsnes Mercury Balanced',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes_mercury_performance_libretro',
    displayName: 'bsnes Mercury Performance',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes-jg_libretro',
    displayName: 'bsnes-jg',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'bsnes_cplusplus98_libretro',
    displayName: 'bsnes C++98',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'mednafen_snes_libretro',
    displayName: 'Mednafen SNES',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'mednafen_supafaust_libretro',
    displayName: 'Mednafen Supafaust',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'snes9x2002_libretro',
    displayName: 'Snes9x 2002',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
    description: 'Older Snes9x for low-end devices',
  ),
  RetroArchCore(
    id: 'snes9x2005_libretro',
    displayName: 'Snes9x 2005',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'snes9x2005_plus_libretro',
    displayName: 'Snes9x 2005 Plus',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'snes9x2010_libretro',
    displayName: 'Snes9x 2010',
    platforms: ['snes'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'mupen64plus_next_libretro',
    displayName: 'mupen64Plus-Next',
    platforms: ['n64', 'nintendo-64'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Best N64 core',
  ),
  RetroArchCore(
    id: 'parallel_n64_libretro',
    displayName: 'Parallel N64',
    platforms: ['n64', 'nintendo-64'],
    category: CoreCategory.nintendo,
    description: 'N64 with parallel-RDP renderer',
  ),
  RetroArchCore(
    id: 'melonds_libretro',
    displayName: 'melonDS',
    platforms: ['nds', 'nintendo-ds', 'ds'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Best NDS core',
  ),
  RetroArchCore(
    id: 'melondsds_libretro',
    displayName: 'melonDS DS',
    platforms: ['nds', 'nintendo-ds', 'ds'],
    category: CoreCategory.nintendo,
    description: 'Newer melonDS fork',
  ),
  RetroArchCore(
    id: 'desmume2015_libretro',
    displayName: 'DeSmuME 2015',
    platforms: ['nds', 'nintendo-ds', 'ds'],
    category: CoreCategory.nintendo,
    description: 'Older DeSmuME (better compatibility)',
  ),
  RetroArchCore(
    id: 'desmume_libretro',
    displayName: 'DeSmuME',
    platforms: ['nds', 'nintendo-ds', 'ds'],
    category: CoreCategory.nintendo,
    description: 'DeSmuME (macOS ARM not supported)',
  ),
  RetroArchCore(
    id: 'meteor_libretro',
    displayName: 'Meteor',
    platforms: ['gba', 'game-boy-advance'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'azahar_libretro',
    displayName: 'Azahar',
    platforms: ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'],
    category: CoreCategory.nintendo,
    isRecommended: true,
    description: 'Best 3DS core (formerly Citra)',
  ),
  RetroArchCore(
    id: 'citra_libretro',
    displayName: 'Citra',
    platforms: ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'],
    category: CoreCategory.nintendo,
    description: 'Original Citra core (legacy)',
  ),
  RetroArchCore(
    id: 'citra2018_libretro',
    displayName: 'Citra 2018',
    platforms: ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'panda3ds_libretro',
    displayName: 'Panda3DS',
    platforms: ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'],
    category: CoreCategory.nintendo,
    description: 'New HLE 3DS core',
  ),
  RetroArchCore(
    id: 'mednafen_vb_libretro',
    displayName: 'Mednafen VB',
    platforms: ['virtualboy'],
    category: CoreCategory.nintendo,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'vecx_libretro',
    displayName: 'VecX',
    platforms: ['vectrex'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'lowresnx_libretro',
    displayName: 'LowRes NX',
    platforms: ['lowresnx'],
    category: CoreCategory.other,
    description: 'Fantasy console',
  ),
  RetroArchCore(
    id: 'tic80_libretro',
    displayName: 'TIC-80',
    platforms: ['tic80'],
    category: CoreCategory.other,
    description: 'Fantasy computer',
  ),
  RetroArchCore(
    id: 'wasm4_libretro',
    displayName: 'WASM-4',
    platforms: ['wasm4'],
    category: CoreCategory.other,
    description: 'Fantasy console',
  ),
  RetroArchCore(
    id: 'retro8_libretro',
    displayName: 'Retro8',
    platforms: ['pico8'],
    category: CoreCategory.other,
    description: 'PICO-8 fantasy console',
  ),

  // ── Sega ──────────────────────────────────────────────────
  RetroArchCore(
    id: 'genesis_plus_gx_libretro',
    displayName: 'Genesis Plus GX',
    platforms: ['megadrive', 'genesis', 'md', 'segacd', 'gamegear', 'sms', 'mastersystem'],
    category: CoreCategory.sega,
    isRecommended: true,
    description: 'Best all-in-one Sega core',
  ),
  RetroArchCore(
    id: 'genesis_plus_gx_wide_libretro',
    displayName: 'Genesis Plus GX Wide',
    platforms: ['megadrive', 'genesis', 'md', 'segacd', 'gamegear', 'sms', 'mastersystem'],
    category: CoreCategory.sega,
    description: 'Widescreen hack of Genesis Plus GX',
  ),
  RetroArchCore(
    id: 'picodrive_libretro',
    displayName: 'PicoDrive',
    platforms: ['megadrive', 'genesis', 'md', 'sms', 'mastersystem'],
    category: CoreCategory.sega,
  ),
  RetroArchCore(
    id: 'gearsystem_libretro',
    displayName: 'Gearsystem',
    platforms: ['gamegear', 'sms', 'mastersystem', 'megadrive', 'genesis', 'md'],
    category: CoreCategory.sega,
  ),
  RetroArchCore(
    id: 'smsplus_libretro',
    displayName: 'SMS Plus',
    platforms: ['sms', 'mastersystem', 'gamegear'],
    category: CoreCategory.sega,
  ),
  RetroArchCore(
    id: 'blastem_libretro',
    displayName: 'BlastEm',
    platforms: ['megadrive', 'genesis', 'md'],
    category: CoreCategory.sega,
    description: 'Accurate Genesis / Mega Drive',
  ),
  RetroArchCore(
    id: 'flycast_libretro',
    displayName: 'Flycast',
    platforms: ['dc', 'dreamcast', 'naomi', 'naomi2', 'atomiswave'],
    category: CoreCategory.sega,
    isRecommended: true,
    description: 'Best Dreamcast / Naomi core',
  ),
  RetroArchCore(
    id: 'kronos_libretro',
    displayName: 'Kronos',
    platforms: ['saturn'],
    category: CoreCategory.sega,
    description: 'Yabause fork (Saturn)',
  ),
  RetroArchCore(
    id: 'yabasanshiro_libretro',
    displayName: 'Yaba Sanshiro',
    platforms: ['saturn'],
    category: CoreCategory.sega,
    description: 'Saturn (GPU-accelerated)',
  ),
  RetroArchCore(
    id: 'yabause_libretro',
    displayName: 'Yabause',
    platforms: ['saturn'],
    category: CoreCategory.sega,
  ),
  RetroArchCore(
    id: 'mednafen_saturn_libretro',
    displayName: 'Mednafen Saturn',
    platforms: ['saturn'],
    category: CoreCategory.sega,
    isRecommended: true,
    description: 'Accurate Saturn emulation',
  ),
  RetroArchCore(
    id: 'geolith_libretro',
    displayName: 'Geolith',
    platforms: ['sg1000'],
    category: CoreCategory.sega,
  ),

  // ── Sony ──────────────────────────────────────────────────
  RetroArchCore(
    id: 'mednafen_psx_hw_libretro',
    displayName: 'Beetle PSX HW',
    platforms: ['psx', 'ps1', 'playstation'],
    category: CoreCategory.sony,
    isRecommended: true,
    description: 'Best PS1 core (hardware-accelerated)',
  ),
  RetroArchCore(
    id: 'pcsx_rearmed_libretro',
    displayName: 'PCSX ReARMed',
    platforms: ['psx', 'ps1', 'playstation'],
    category: CoreCategory.sony,
    description: 'Lightweight PS1 core',
  ),
  RetroArchCore(
    id: 'mednafen_psx_libretro',
    displayName: 'Mednafen PSX',
    platforms: ['psx', 'ps1', 'playstation'],
    category: CoreCategory.sony,
    description: 'High-accuracy PS1 (software renderer)',
  ),
  RetroArchCore(
    id: 'swanstation_libretro',
    displayName: 'SwanStation',
    platforms: ['psx', 'ps1', 'playstation'],
    category: CoreCategory.sony,
    description: 'DuckStation-based PS1 core',
  ),
  RetroArchCore(
    id: 'ppsspp_libretro',
    displayName: 'PPSSPP',
    platforms: ['psp', 'playstation-portable'],
    category: CoreCategory.sony,
    isRecommended: true,
    description: 'Best PSP core',
  ),
  RetroArchCore(
    id: 'pcsx2_libretro',
    displayName: 'PCSX2',
    platforms: ['ps2', 'playstation-2', 'playstation2'],
    category: CoreCategory.sony,
    isRecommended: true,
    description: 'PS2 emulator core',
  ),
  RetroArchCore(
    id: 'mednafen_pce_fast_libretro',
    displayName: 'Mednafen PCE Fast',
    platforms: ['pcengine', 'pcenginecd', 'tg16', 'turbografx16', 'turbografx-16'],
    category: CoreCategory.sony,
  ),
  RetroArchCore(
    id: 'mednafen_pce_libretro',
    displayName: 'Mednafen PCE',
    platforms: ['pcengine', 'pcenginecd', 'tg16', 'turbografx16', 'turbografx-16'],
    category: CoreCategory.sony,
    isRecommended: true,
    description: 'Accurate PC Engine / TurboGrafx-16',
  ),
  RetroArchCore(
    id: 'mednafen_supergrafx_libretro',
    displayName: 'Mednafen SuperGrafx',
    platforms: ['supergrafx'],
    category: CoreCategory.sony,
  ),
  RetroArchCore(
    id: 'mednafen_pcfx_libretro',
    displayName: 'Mednafen PC-FX',
    platforms: ['pcfx'],
    category: CoreCategory.sony,
  ),
  RetroArchCore(
    id: 'neocd_libretro',
    displayName: 'NeoCD',
    platforms: ['neogeocd', 'neocd'],
    category: CoreCategory.sony,
  ),

  // ── Atari ─────────────────────────────────────────────────
  RetroArchCore(
    id: 'stella_libretro',
    displayName: 'Stella',
    platforms: ['atari2600'],
    category: CoreCategory.handheld,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'stella2014_libretro',
    displayName: 'Stella 2014',
    platforms: ['atari2600'],
    category: CoreCategory.handheld,
  ),
  RetroArchCore(
    id: 'stella2023_libretro',
    displayName: 'Stella 2023',
    platforms: ['atari2600'],
    category: CoreCategory.handheld,
    description: 'Modern Stella port',
  ),
  RetroArchCore(
    id: 'prosystem_libretro',
    displayName: 'ProSystem',
    platforms: ['atari7800'],
    category: CoreCategory.handheld,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'atari800_libretro',
    displayName: 'Atari800',
    platforms: ['atari5200', 'atari800', 'atari8bit'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'a5200_libretro',
    displayName: 'A5200',
    platforms: ['atari5200'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'handy_libretro',
    displayName: 'Handy',
    platforms: ['lynx'],
    category: CoreCategory.handheld,
  ),
  RetroArchCore(
    id: 'mednafen_lynx_libretro',
    displayName: 'Mednafen Lynx',
    platforms: ['lynx'],
    category: CoreCategory.handheld,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'gearlynx_libretro',
    displayName: 'GearLynx',
    platforms: ['lynx'],
    category: CoreCategory.handheld,
  ),

  // ── Bandai / Handheld ─────────────────────────────────────
  RetroArchCore(
    id: 'mednafen_wswan_libretro',
    displayName: 'Mednafen WonderSwan',
    platforms: ['wonderswan', 'wonderswancolor'],
    category: CoreCategory.handheld,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'mednafen_ngp_libretro',
    displayName: 'Mednafen Neo Geo Pocket',
    platforms: ['ngp', 'ngpc', 'neo-geo-pocket'],
    category: CoreCategory.handheld,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'pokemini_libretro',
    displayName: 'PokeMini',
    platforms: ['pokemini'],
    category: CoreCategory.handheld,
  ),
  RetroArchCore(
    id: 'gw_libretro',
    displayName: 'GW (Game & Watch)',
    platforms: ['gameandwatch'],
    category: CoreCategory.handheld,
  ),

  // ── Arcade / SNK ──────────────────────────────────────────
  RetroArchCore(
    id: 'fbneo_libretro',
    displayName: 'FinalBurn Neo',
    platforms: ['neogeo', 'arcade', 'fbneo'],
    category: CoreCategory.arcade,
    isRecommended: true,
    description: 'Best arcade core',
  ),
  RetroArchCore(
    id: 'fbalpha2012_libretro',
    displayName: 'FB Alpha 2012',
    platforms: ['neogeo', 'arcade'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'fbalpha2012_cps1_libretro',
    displayName: 'FB Alpha 2012 CPS1',
    platforms: ['cps1', 'arcade'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'fbalpha2012_cps2_libretro',
    displayName: 'FB Alpha 2012 CPS2',
    platforms: ['cps2', 'arcade'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'fbalpha2012_cps3_libretro',
    displayName: 'FB Alpha 2012 CPS3',
    platforms: ['cps3', 'arcade'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'fbalpha2012_neogeo_libretro',
    displayName: 'FB Alpha 2012 Neo Geo',
    platforms: ['neogeo'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'fbalpha_libretro',
    displayName: 'FB Alpha',
    platforms: ['neogeo', 'arcade'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'mame2000_libretro',
    displayName: 'MAME 2000',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
    description: 'MAME 0.37b5',
  ),
  RetroArchCore(
    id: 'mame2003_libretro',
    displayName: 'MAME 2003',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
    description: 'MAME 0.78',
  ),
  RetroArchCore(
    id: 'mame2003_plus_libretro',
    displayName: 'MAME 2003-Plus',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
    description: 'MAME 0.78 with more games',
  ),
  RetroArchCore(
    id: 'mame2003_midway_libretro',
    displayName: 'MAME 2003 Midway',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
  ),
  RetroArchCore(
    id: 'mame2010_libretro',
    displayName: 'MAME 2010',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
    description: 'MAME 0.139',
  ),
  RetroArchCore(
    id: 'mame_libretro',
    displayName: 'MAME (Current)',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
    isRecommended: true,
    description: 'Latest MAME',
  ),
  RetroArchCore(
    id: 'hbmame_libretro',
    displayName: 'HBMAME',
    platforms: ['arcade', 'mame'],
    category: CoreCategory.arcade,
    description: 'Homebrew MAME',
  ),
  RetroArchCore(
    id: 'same_cdi_libretro',
    displayName: 'Same CDI',
    platforms: ['cdi'],
    category: CoreCategory.arcade,
  ),

  // ── Computer ──────────────────────────────────────────────
  RetroArchCore(
    id: 'dosbox_pure_libretro',
    displayName: 'DOSBox Pure',
    platforms: ['dos'],
    category: CoreCategory.computer,
    isRecommended: true,
    description: 'Best DOS core, plug-and-play',
  ),
  RetroArchCore(
    id: 'dosbox_core_libretro',
    displayName: 'DOSBox Core',
    platforms: ['dos'],
    category: CoreCategory.computer,
    description: 'DOSBox with libretro API',
  ),
  RetroArchCore(
    id: 'dosbox_svn_libretro',
    displayName: 'DOSBox SVN',
    platforms: ['dos'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'bluemsx_libretro',
    displayName: 'blueMSX',
    platforms: ['msx', 'msx2'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'fmsx_libretro',
    displayName: 'fMSX',
    platforms: ['msx', 'msx2'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'fuse_libretro',
    displayName: 'Fuse',
    platforms: ['zxspectrum', 'zx-spectrum', 'sinclair'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'cap32_libretro',
    displayName: 'Caprice32',
    platforms: ['amstradcpc', 'amstrad-cpc'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'hatari_libretro',
    displayName: 'Hatari',
    platforms: ['atarist', 'atari-st', 'st'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'vice_x64_libretro',
    displayName: 'VICE (C64)',
    platforms: ['c64', 'commodore64', 'commodore-64'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'vice_x64sc_libretro',
    displayName: 'VICE (C64 SC)',
    platforms: ['c64', 'commodore64'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_xscpu64_libretro',
    displayName: 'VICE (SCPU64)',
    platforms: ['c64', 'commodore64'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_x128_libretro',
    displayName: 'VICE (C128)',
    platforms: ['c128', 'commodore128'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_xvic_libretro',
    displayName: 'VICE (VIC-20)',
    platforms: ['vic20', 'vic-20'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_xpet_libretro',
    displayName: 'VICE (PET)',
    platforms: ['pet'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_xplus4_libretro',
    displayName: 'VICE (Plus/4)',
    platforms: ['plus4'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_xcbm2_libretro',
    displayName: 'VICE (CBM-II)',
    platforms: ['cbm2'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'vice_xcbm5x0_libretro',
    displayName: 'VICE (CBM 5x0)',
    platforms: ['cbm5x0'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'puae_libretro',
    displayName: 'PUAE (Amiga)',
    platforms: ['amiga'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'puae2021_libretro',
    displayName: 'PUAE 2021 (Amiga)',
    platforms: ['amiga'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'px68k_libretro',
    displayName: 'PX-68K',
    platforms: ['sharp68000', 'x68000'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'np2kai_libretro',
    displayName: 'Neko Project II',
    platforms: ['pc98', 'pc-98'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'quasi88_libretro',
    displayName: 'QUASI88',
    platforms: ['pc88', 'pc-88'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'x1_libretro',
    displayName: 'X Mil',
    platforms: ['x1'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'applewin_libretro',
    displayName: 'AppleWin',
    platforms: ['apple2', 'apple-ii'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'frodo_libretro',
    displayName: 'Frodo',
    platforms: ['c64', 'commodore64'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'ep128emu_core_libretro',
    displayName: 'EP128 Emu',
    platforms: ['enterprise'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'o2em_libretro',
    displayName: 'O2EM',
    platforms: ['odyssey2', 'magnavox Odyssey 2'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'bbkemu_libretro',
    displayName: 'BBK Emu',
    platforms: ['bbk'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'm2000_libretro',
    displayName: 'M2000',
    platforms: ['trs80'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'mojozork_libretro',
    displayName: 'MojoZork',
    platforms: ['zork'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'oricium_libretro',
    displayName: 'Oricium',
    platforms: ['oric'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'theodore_libretro',
    displayName: 'Théodore',
    platforms: ['mo5'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'multicore_libretro',
    displayName: 'MultiCore',
    platforms: ['multi'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'freechaf_libretro',
    displayName: 'FreeChaF',
    platforms: ['fairchild-channelf', 'channelf'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'freeintv_libretro',
    displayName: 'FreeIntV',
    platforms: ['intellivision'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'jaguar_libretro',
    displayName: 'ProSystem Jaguar',
    platforms: ['jaguar'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'virtualjaguar_libretro',
    displayName: 'Virtual Jaguar',
    platforms: ['jaguar'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'opera_libretro',
    displayName: 'Opera',
    platforms: ['3do'],
    category: CoreCategory.computer,
    isRecommended: true,
  ),
  RetroArchCore(
    id: 'crocods_libretro',
    displayName: 'CrocoDS',
    platforms: ['amstrad-cpc', 'amstradcpc'],
    category: CoreCategory.computer,
  ),

  // ── Game Engines / Ports ──────────────────────────────────
  RetroArchCore(
    id: 'prboom_libretro',
    displayName: 'PrBoom (Doom)',
    platforms: ['doom'],
    category: CoreCategory.other,
    description: 'Doom engine',
  ),
  RetroArchCore(
    id: 'ecwolf_libretro',
    displayName: 'ECWolf',
    platforms: ['wolf3d'],
    category: CoreCategory.other,
    description: 'Wolfenstein 3D engine',
  ),
  RetroArchCore(
    id: 'nxengine_libretro',
    displayName: 'NxEngine',
    platforms: ['cavestory'],
    category: CoreCategory.other,
    description: 'Cave Story engine',
  ),
  RetroArchCore(
    id: 'tyrquake_libretro',
    displayName: 'TyrQuake',
    platforms: ['quake'],
    category: CoreCategory.other,
    description: 'Quake engine',
  ),
  RetroArchCore(
    id: 'openlara_libretro',
    displayName: 'OpenLara',
    platforms: ['tombraider'],
    category: CoreCategory.other,
    description: 'Tomb Raider engine',
  ),
  RetroArchCore(
    id: 'vitaquake2_libretro',
    displayName: 'VitaQuake II',
    platforms: ['quake2'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vitaquake2-rogue_libretro',
    displayName: 'VitaQuake II (Rogue)',
    platforms: ['quake2'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vitaquake2-xatrix_libretro',
    displayName: 'VitaQuake II (Xatrix)',
    platforms: ['quake2'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vitaquake2-zaero_libretro',
    displayName: 'VitaQuake II (Zaero)',
    platforms: ['quake2'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vitaquake3_libretro',
    displayName: 'VitaQuake 3',
    platforms: ['quake3'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'reminiscence_libretro',
    displayName: 'Reminiscence',
    platforms: ['flashback'],
    category: CoreCategory.other,
    description: 'Flashback engine',
  ),
  RetroArchCore(
    id: 'doukutsu_rs_libretro',
    displayName: 'Doukutsu RS',
    platforms: ['cavestory'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'craft_libretro',
    displayName: 'Craft',
    platforms: ['minecraft'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'chailove_libretro',
    displayName: 'ChaiLove',
    platforms: ['chailove'],
    category: CoreCategory.other,
    description: 'ChaiLove fantasy console',
  ),
  RetroArchCore(
    id: 'mrboom_libretro',
    displayName: 'Mr.Boom',
    platforms: ['mrboom'],
    category: CoreCategory.other,
    description: 'Bomberman clone',
  ),
  RetroArchCore(
    id: 'boom3_libretro',
    displayName: 'Boom 3',
    platforms: ['boom3'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'anarch_libretro',
    displayName: 'Anarch',
    platforms: ['anarch'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'gong_libretro',
    displayName: 'Gong',
    platforms: ['gong'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'jumpnbump_libretro',
    displayName: "Jump 'n Bump",
    platforms: ['jumpnbump'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'xrick_libretro',
    displayName: 'xRick',
    platforms: ['xrick'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'dice_libretro',
    displayName: 'Dice',
    platforms: ['dice'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'dinothawr_libretro',
    displayName: 'Dinothawr',
    platforms: ['dinothawr'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'dirksimple_libretro',
    displayName: 'Dirk Simple',
    platforms: ['dirksimple'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: '2048_libretro',
    displayName: '2048',
    platforms: ['2048'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'b2_libretro',
    displayName: 'B2',
    platforms: ['b2'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'boom3_xp_libretro',
    displayName: 'Boom 3 XP',
    platforms: ['boom3'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'cdi2015_libretro',
    displayName: 'CDi 2015',
    platforms: ['cdi'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'doublecherrygb_libretro',
    displayName: 'Gam4980',
    platforms: ['gam4980'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'holani_libretro',
    displayName: 'Holani',
    platforms: ['holani'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'irogb_libretro',
    displayName: 'IROGB',
    platforms: ['gb'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'jollycv_libretro',
    displayName: 'Jolly CV',
    platforms: ['cv'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'lutro_libretro',
    displayName: 'Lutro',
    platforms: ['lutro'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'mcsoftserve_libretro',
    displayName: 'McSoftServe',
    platforms: ['mcsoftserve'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'mu_libretro',
    displayName: 'Mu',
    platforms: ['mu'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'native32emu_libretro',
    displayName: 'Native32 Emu',
    platforms: ['native32emu'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'nekop2_libretro',
    displayName: 'Neko P2',
    platforms: ['nekop2'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'noods_libretro',
    displayName: 'NooDS',
    platforms: ['nds'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'numero_libretro',
    displayName: 'Numero',
    platforms: ['numero'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'nuance_libretro',
    displayName: 'Nuance',
    platforms: ['nuance'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'oberon_libretro',
    displayName: 'Oberon',
    platforms: ['oberon'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'pd777_libretro',
    displayName: 'PD-777',
    platforms: ['pd777'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'play_libretro',
    displayName: 'Play! (PS2)',
    platforms: ['ps2'],
    category: CoreCategory.sony,
    description: 'Alternative PS2 core',
  ),
  RetroArchCore(
    id: 'pocketcdg_libretro',
    displayName: 'PocketCDG',
    platforms: ['pocketcdg'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'romcleaner_libretro',
    displayName: 'ROM Cleaner',
    platforms: ['romcleaner'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'sameduck_libretro',
    displayName: 'SameDuck',
    platforms: ['gb'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'skyemu_libretro',
    displayName: 'SkyEmu',
    platforms: ['gb', 'gbc', 'gba'],
    category: CoreCategory.nintendo,
    description: 'GB/GBC/GBA emulator',
  ),
  RetroArchCore(
    id: 'squirreljme_libretro',
    displayName: 'SquirrelJME',
    platforms: ['j2me'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'superbroswar_libretro',
    displayName: 'Super Bros War',
    platforms: ['superbroswar'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'tamalibretro_libretro',
    displayName: 'Tamalibretro',
    platforms: ['tamalibretro'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'thepowdertoy_libretro',
    displayName: 'The Powder Toy',
    platforms: ['thepowdertoy'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'tia_libretro',
    displayName: 'TIA',
    platforms: ['tia'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'uzem_libretro',
    displayName: 'Uzem',
    platforms: ['uzem'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'uw8_libretro',
    displayName: 'UW8',
    platforms: ['uw8'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vaporspec_libretro',
    displayName: 'Vapor Spec',
    platforms: ['vaporspec'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vbam_libretro',
    displayName: 'VBA-M',
    platforms: ['gba', 'gbc', 'gb'],
    category: CoreCategory.nintendo,
    description: 'Visual Boy Advance-M',
  ),
  RetroArchCore(
    id: 'vba_next_libretro',
    displayName: 'VBA Next',
    platforms: ['gba'],
    category: CoreCategory.nintendo,
  ),
  RetroArchCore(
    id: 'vemulator_libretro',
    displayName: 'VE Emulator',
    platforms: ['vemulator'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'vircon32_libretro',
    displayName: 'Vircon32',
    platforms: ['vircon32'],
    category: CoreCategory.other,
  ),
  RetroArchCore(
    id: 'virtualxt_libretro',
    displayName: 'VirtualXT',
    platforms: ['dos'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: '81_libretro',
    displayName: '81',
    platforms: ['zx81'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'bk_libretro',
    displayName: 'BK',
    platforms: ['bk'],
    category: CoreCategory.computer,
  ),
  RetroArchCore(
    id: 'galaksija_libretro',
    displayName: 'Galaksija',
    platforms: ['galaksija'],
    category: CoreCategory.computer,
  ),
];

/// Returns the default (recommended) core ID for a given platform slug.
String? getDefaultCoreForSlug(String slug) {
  for (final core in kRetroArchCores) {
    if (core.isRecommended && core.platforms.contains(slug)) {
      return core.id;
    }
  }
  return null;
}

/// Returns all cores that support a given platform slug.
List<RetroArchCore> getCoresForSlug(String slug) {
  return kRetroArchCores.where((c) => c.platforms.contains(slug)).toList();
}

/// Returns all recommended cores grouped by category.
Map<CoreCategory, List<RetroArchCore>> getRecommendedCoresByCategory() {
  final map = <CoreCategory, List<RetroArchCore>>{};
  for (final core in kRetroArchCores) {
    if (core.isRecommended) {
      map.putIfAbsent(core.category, () => []).add(core);
    }
  }
  return map;
}

/// Returns the display name for a core category.
String categoryDisplayName(CoreCategory category) {
  switch (category) {
    case CoreCategory.recommended:
      return 'Recommended';
    case CoreCategory.nintendo:
      return 'Nintendo';
    case CoreCategory.sega:
      return 'Sega';
    case CoreCategory.sony:
      return 'Sony';
    case CoreCategory.arcade:
      return 'Arcade';
    case CoreCategory.computer:
      return 'Computer';
    case CoreCategory.handheld:
      return 'Handheld';
    case CoreCategory.other:
      return 'Other / Engines';
  }
}

/// Extracts the core base name from a full core filename.
/// e.g. 'mgba_libretro.dll' -> 'mgba_libretro'
String coreBaseName(String coreId) {
  if (coreId.endsWith('.dll') || coreId.endsWith('.so') || coreId.endsWith('.dylib')) {
    final lastDot = coreId.lastIndexOf('.');
    return coreId.substring(0, lastDot);
  }
  return coreId;
}
