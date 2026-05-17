# Freegosy

A cross-platform Flutter app for browsing your RomM library, downloading ROMs, and launching games directly in emulators—all from one intuitive interface.

[**Watch the Feature Walkthrough on YouTube**](https://youtu.be/SE5BoFoA700)

![Main Menu](screenshots/screenshot1.png)
*The main menu showcasing the intuitive game card interface.*

![Game Details](screenshots/screenshot2.png)
*Detailed game view with metadata, screenshots, and quick actions.*

## Background & Vision
Freegosy (Free as in "Free for all OS") is the successor to [**Wingosy**](https://github.com/abduznik/Wingosy-Launcher). While Wingosy was focused on Windows, Freegosy is built from the ground up using **Flutter** to provide a unified frontend for all major platforms. 

The original inspiration for these projects was [**Argosy**](https://github.com/rommapp/argosy-launcher), the native Android app for RomM built in Kotlin. Freegosy aims to bring that same native experience to desktop and beyond, ensuring a seamless, ease-of-use interface for accessing your RomM collection on any device.

# Support the Project

Freegosy is a solo passion project — built and maintained in my spare time, with AI tools I pay for out of pocket. If it saves you time or makes your RomM setup better, a small contribution genuinely helps keep it going.

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=github)](https://github.com/sponsors/abduznik)

No pressure at all — the app is and will always be free.

## Current Features (v0.5.0)

- **Native Multi-Platform Support**: Full support for **macOS** (ARM64/Intel), **Windows**, and **Linux** (including **Steam Deck/EmuDeck** and **RetroDECK** integration).
- **Enhanced Offline Mode**: Persistent metadata caching for browsing and launching your collection without a connection.
- **RomM Integration**: 
    - Browse and filter your entire library with server-side pagination.
    - Instant "Downloaded" games filter with background deep collection scanning.
    - Download ROMs directly via HTTP with real-time progress tracking.
    - Personal game properties support (rating, status, completion).
- **Advanced Emulator Management**: 
    - Download, update, and uninstall emulators directly from Settings.
    - Automatic extraction of `.zip`, `.7z`, `.dmg`, `.tar.gz`, `.tar.xz`, and `.AppImage`.
    - Smart binary detection and canonical naming across all platforms.
    - Dynamic architecture selection for RPCS3 on macOS (ARM64 vs x64).
    - **New**: Linux Environment Strategies (Default, EmuDeck, RetroDECK) with automatic path detection.
- **BIOS Management**: Fetch and download BIOS files directly from RomM and automatically place them in the correct directory for each emulator.
- **Save Sync**: 
    - Bidirectional local-to-cloud save synchronization with RomM.
    - Local Backup History (create instant restore points before experimenting).
    - **New**: Serial Background Sync Queue (offline backups silently push to RomM automatically when you reconnect).
    - Optimized for EmuDeck's platform-specific save structure.
- **Refined UI/UX**:
    - **Visual-First Grid**: Interactive game cards with detailed metadata.
    - **Recently Played**: Quick access to your latest games.
    - **Screenshot Gallery**: Interactive, zoomable screenshot viewer.
    - **Multi-Disc Support**: Integrated picker for multi-file games.

## Calling All Testers!
I am currently searching for testers on **macOS**, **Windows**, and **Linux (Steam Deck)** to help polish the experience. 

- **Future Plans**: **Android** support is next for a truly unified app experience.
- **Get Involved**: If you're interested in testing an early release, reach out via GitHub or join the community discussions.

## About RomM

Freegosy is built to complement [RomM](https://github.com/rommapp/romm), a modern ROM manager. It connects to your RomM instance to provide a lightweight, portable way to access and play your games.
