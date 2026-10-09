import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/update/update_installer.dart';
import '../core/update/update_models.dart';
import '../core/update/update_service.dart';
import 'platform_info_provider.dart';
import 'shared_prefs_provider.dart';

/// Absent from prefs until the user answers the first-launch prompt.
const _appliedShaKey = 'update_applied_sha';
const _appliedVersionKey = 'update_applied_version';
const updateCheckPrefKey = 'update_check_on_launch';
final updateCheckOnLaunchProvider = createPersistentProvider<bool>(updateCheckPrefKey, true);
final updateAutoDownloadProvider = createPersistentProvider<bool>('update_auto_download', true);
final updateChannelProvider = createPersistentProvider<String>('update_channel', 'stable');

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(
    platform: ref.watch(platformInfoProvider),
    supportDir: getApplicationSupportDirectory,
  );
});

final updateInstallerProvider = Provider<UpdateInstaller>((ref) => UpdateInstaller());

enum UpdateStatus { idle, checking, upToDate, available, downloading, ready, applying, error }

@immutable
class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final double progress;
  final String? error;
  final DateTime? lastChecked;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.progress = 0,
    this.error,
    this.lastChecked,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    double? progress,
    String? error,
    DateTime? lastChecked,
  }) =>
      UpdateState(
        status: status ?? this.status,
        info: info ?? this.info,
        progress: progress ?? this.progress,
        error: error,
        lastChecked: lastChecked ?? this.lastChecked,
      );
}

class UpdateController extends StateNotifier<UpdateState> {
  final Ref _ref;
  io.File? _downloaded;

  /// Injectable so tests don't terminate the test process.
  final void Function(int code) _exit;

  UpdateController(this._ref, {void Function(int code)? exitFn})
      : _exit = exitFn ?? io.exit,
        super(const UpdateState());

  bool get _busy => state.status == UpdateStatus.checking ||
      state.status == UpdateStatus.downloading ||
      state.status == UpdateStatus.applying;

  /// Set once the launch prompt/check ran, so a rebuilt widget tree can't repeat it.
  bool launchHandled = false;

  /// Called once at startup; honours the "check on launch" setting.
  Future<void> checkOnLaunch() async {
    if (!_ref.read(updateCheckOnLaunchProvider)) return;
    await check(manual: false);
  }

  /// Looks for a newer release. A launch check stays quiet on failure; a
  /// manual one shows the error. Downloads automatically when allowed.
  Future<void> check({required bool manual}) async {
    if (_busy) return;
    final service = _ref.read(updateServiceProvider);
    final channel = UpdateChannel.parse(_ref.read(updateChannelProvider));
    state = state.copyWith(status: UpdateStatus.checking, progress: 0);
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      // The recorded digest only describes this build if it was applied for this version.
      final recorded = prefs.getString(_appliedVersionKey) == AppConstants.version ? prefs.getString(_appliedShaKey) : null;
      final info = await service.checkForUpdate(AppConstants.version, channel, recordedSha: recorded);
      if (!mounted) return;
      if (info == null) {
        state = UpdateState(status: UpdateStatus.upToDate, lastChecked: DateTime.now());
        return;
      }
      state = UpdateState(status: UpdateStatus.available, info: info, lastChecked: DateTime.now());
      if (_ref.read(updateAutoDownloadProvider) && service.installKind != InstallKind.manual && info.hasAsset) {
        await download();
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
      if (!mounted) return;
      state = manual
          ? UpdateState(status: UpdateStatus.error, error: _friendly(e), lastChecked: DateTime.now())
          : UpdateState(lastChecked: DateTime.now());
    }
  }

  Future<void> download() async {
    final info = state.info;
    if (info == null || _busy) return;
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      _downloaded = await _ref.read(updateServiceProvider).download(info, onProgress: (p) {
        if (mounted) state = state.copyWith(progress: p);
      });
      if (mounted) state = state.copyWith(status: UpdateStatus.ready, progress: 1);
    } catch (e) {
      debugPrint('Update download failed: $e');
      if (mounted) state = state.copyWith(status: UpdateStatus.error, error: _friendly(e));
    }
  }

  /// Installs the downloaded update, relaunches, and exits this process.
  Future<void> restartToUpdate() async {
    final file = _downloaded;
    if (file == null || state.status != UpdateStatus.ready) return;
    state = state.copyWith(status: UpdateStatus.applying);
    try {
      final sha = state.info?.sha256;
      await _ref.read(updateInstallerProvider)
          .installAndRestart(_ref.read(updateServiceProvider).installKind, file);
      // Only now is the new build really going to run; recording earlier would
      // make a failed install look applied and hide the update from later checks.
      if (sha != null) {
        final prefs = _ref.read(sharedPreferencesProvider);
        await prefs.setString(_appliedShaKey, sha);
        await prefs.setString(_appliedVersionKey, state.info!.version);
      }
      _exit(0);
    } catch (e) {
      debugPrint('Applying update failed: $e');
      if (mounted) state = state.copyWith(status: UpdateStatus.error, error: _friendly(e));
    }
  }

  static String _friendly(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}

final updateControllerProvider = StateNotifierProvider<UpdateController, UpdateState>((ref) => UpdateController(ref));
