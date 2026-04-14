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

## Current Features (v0.3.x)

- **Native Multi-Platform Support**: Full support for **macOS** (ARM64/Intel), **Windows**, and **Linux** (including **Steam Deck/EmuDeck** integration).
- **Enhanced Offline Mode**: Persistent metadata caching for browsing and launching your collection without a connection.
- **RomM Integration**: 
    - Browse and filter your entire library with server-side pagination.
    - **New**: Instant "Downloaded" games filter with background deep collection scanning.
    - Download ROMs directly via HTTP with real-time progress tracking.
    - Personal game properties support (rating, status, completion).
- **Advanced Emulator Management**: 
    - Download, update, and uninstall emulators directly from Settings.
    - Automatic extraction of `.zip`, `.7z`, `.dmg`, `.tar.gz`, `.tar.xz`, and `.AppImage`.
    - Smart binary detection and canonical naming across all platforms.
    - **New**: Dynamic architecture selection for RPCS3 on macOS (ARM64 vs x64).
- **BIOS Management**: Fetch and download BIOS files directly from RomM and automatically place them in the correct directory for each emulator.
- **Save Sync**: Bidirectional local-to-cloud save synchronization with RomM, featuring cross-platform path resolution and automated backups. Optimized for EmuDeck's platform-specific save structure.
- **Refined UI/UX**:
    - **Visual-First Grid**: Interactive game cards with detailed metadata.
    - **Recently Played**: Quick access to your latest games.
    - **Screenshot Gallery**: Interactive, zoomable screenshot viewer.
    - **Multi-Disc Support**: Integrated picker for multi-file games.

## Roadmap: Version 0.4.0 (Upcoming)

- **Android Support**: Bringing the Freegosy experience to mobile devices.
- **Cloud Configuration**: Syncing app settings across multiple devices.
- **API v4.8.2 Readiness**: Full support for progression bars and advanced completion tracking as RomM updates.

## Calling All Testers!
I am currently searching for testers on **macOS** and **Windows** to help polish the experience. 

- **Future Plans**: Steam Deck/Linux support is next, followed by **Android** for a truly unified app.
- **Get Involved**: If you're interested in testing an early release, reach out via GitHub or join the community discussions.

## About RomM

Freegosy is built to complement [RomM](https://github.com/rommapp/romm), a modern ROM manager. It connects to your RomM instance to provide a lightweight, portable way to access and play your games.
