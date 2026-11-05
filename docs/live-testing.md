# Live testing against a fake RomM

`integration_test/library_flow_test.dart` runs the real app (a real window) against
`tool/fake_romm/fake_romm.py`, a small stand-in for RomM, and checks the files it
leaves on disk. It covers Select Files / Files / Delete / Download All, a 60-file
picker, a DOS game, and pause / resume. It takes about a minute.

```bash
python3 tool/fake_romm/fake_romm.py 18080 &     # the fake server
# Use throwaway data folders so the app does not touch your real settings:
export XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d)
flutter test integration_test/library_flow_test.dart -d linux
```

Notes:

- A desktop session that is unlocked is needed: a locked screen draws no frames, so
  the test just waits.
- The test downloads into a temporary ROM folder (`LIVE_ROMS` picks another one) and
  deletes what it downloads.
- `LIVE_OUT=<folder>` saves screenshots of key moments (needs `spectacle`);
  `FAKE_ROMM_URL` points at a server on another address.
- The Linux build needs `clang++`. If it is missing, `flutter build linux` fails even
  though `g++` is installed; a `clang`/`clang++` wrapper script on `PATH` that execs
  `gcc`/`g++` is enough.
- This is what a CI job for #208 could grow from: the fake server speaks the parts of
  RomM's API the app uses, and serves downloads the way RomM does (`file_ids`, zip for
  several files, the bare file for one, `Range`).
