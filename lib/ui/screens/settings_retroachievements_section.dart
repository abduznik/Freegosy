import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/retroachievements/retroachievements_emulator_login.dart';
import '../../core/retroachievements/retroachievements_models.dart';
import '../../providers/retroachievements_provider.dart';
import '../widgets/dialog_back_bridge.dart';
import '../widgets/focus_effect_wrapper.dart';

InputDecoration _buildInputDecoration(BuildContext context, String label, {String? hintText, String? helperText}) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    helperText: helperText,
    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
    helperStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

Widget _buildActionButton(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  bool isPrimary = false,
  bool isDestructive = false,
}) {
  final theme = Theme.of(context);
  return FocusEffectWrapper(
    onTap: onTap,
    borderRadius: 16.0,
    scaleFactor: 1.005,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: isPrimary
            ? LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isPrimary
            ? null
            : (isDestructive
                ? Colors.red.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
        border: Border.all(
          color: isPrimary
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : (isDestructive
                  ? Colors.red.withValues(alpha: 0.2)
                  : theme.colorScheme.outline.withValues(alpha: 0.3)),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: isPrimary
                ? theme.colorScheme.onPrimary
                : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isPrimary
                  ? theme.colorScheme.onPrimary
                  : (isDestructive ? Colors.redAccent : theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSectionCard({
  required BuildContext context,
  required String title,
  required IconData icon,
  required Widget child,
  Widget? trailing,
}) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // ignore: use_null_aware_elements
            if (trailing != null) trailing,
          ],
        ),
        child,
      ],
    ),
  );
}

/// Settings section for connecting a RetroAchievements account.
///
/// Only the username is required. The optional password is exchanged once
/// for an RA login token so Freegosy can sign emulators in at launch (only
/// RetroArch so far); the password itself is never stored. The optional Web
/// API key lets Freegosy show live profile/progress data.
///
/// Freegosy never awards achievements itself: unlocks are detected by
/// rcheevos inside the emulator, which Freegosy has no access to.
class SettingsRetroAchievementsSection extends ConsumerStatefulWidget {
  const SettingsRetroAchievementsSection({super.key});

  @override
  ConsumerState<SettingsRetroAchievementsSection> createState() => _SettingsRetroAchievementsSectionState();
}

class _SettingsRetroAchievementsSectionState extends ConsumerState<SettingsRetroAchievementsSection> {
  late final TextEditingController _usernameController;
  late final TextEditingController _webApiKeyController;
  late final TextEditingController _passwordController;
  bool _isEditing = false;
  bool _isConnecting = false;
  bool _preferencesLoaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _webApiKeyController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _webApiKeyController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credentialsAsync = ref.watch(retroAchievementsCredentialsProvider);
    final profileAsync = ref.watch(retroAchievementsProfileProvider);
    final emulatorLogin = ref.watch(retroAchievementsEmulatorLoginProvider).asData?.value;

    return credentialsAsync.when(
      data: (credentials) {
        if (!_preferencesLoaded) {
          _usernameController.text = credentials?.username ?? '';
          // Pre-filled (obscured) so re-saving without retyping keeps the key.
          _webApiKeyController.text = credentials?.webApiKey ?? '';
          _isEditing = credentials == null;
          _preferencesLoaded = true;
        }

        return _buildSectionCard(
          context: context,
          title: 'RetroAchievements',
          icon: Icons.emoji_events,
          trailing: credentials != null
              ? FocusEffectWrapper(
                  borderRadius: 24,
                  scaleFactor: 1.1,
                  useSafeScale: false,
                  onTap: () => setState(() => _isEditing = !_isEditing),
                  child: IconButton(
                    icon: Icon(
                      _isEditing ? Icons.lock_open : Icons.lock,
                      color: _isEditing ? theme.colorScheme.primary : Colors.grey,
                    ),
                    tooltip: _isEditing ? 'Lock connection details' : 'Unlock connection details to edit',
                    onPressed: () => setState(() => _isEditing = !_isEditing),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect your RetroAchievements account once here: Freegosy signs your emulators in when it '
                'launches them (RetroArch for now) and shows your progress on each game. '
                'Achievements are still detected and unlocked by the emulator itself.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (credentials != null && !_isEditing) ...[
                _buildProfileDisplay(context, profileAsync, credentials),
                const SizedBox(height: 16),
                _buildStatus(context, credentials, emulatorLogin),
              ] else ...[
                TextField(
                  controller: _usernameController,
                  readOnly: !_isEditing,
                  decoration: _buildInputDecoration(context, 'Username'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  readOnly: !_isEditing,
                  obscureText: true,
                  decoration: _buildInputDecoration(
                    context,
                    'Password (optional)',
                    helperText: emulatorLogin != null
                        ? 'Emulators are signed in. Leave empty to keep that, or re-enter to refresh.'
                        : 'Signs RetroArch in to RetroAchievements. Used once, never stored.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _webApiKeyController,
                  readOnly: !_isEditing,
                  obscureText: true,
                  decoration: _buildInputDecoration(
                    context,
                    'Web API Key (optional)',
                    helperText: 'Shows live progress in Freegosy. Find it under Settings > Keys on retroachievements.org',
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        context,
                        icon: _isConnecting ? Icons.hourglass_empty : Icons.link,
                        label: _isConnecting ? 'Connecting...' : 'Connect',
                        isPrimary: true,
                        onTap: _isConnecting ? null : () => _connect(context),
                      ),
                    ),
                    if (credentials != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          context,
                          icon: Icons.link_off,
                          label: 'Disconnect',
                          isDestructive: true,
                          onTap: _isConnecting ? null : () => _disconnect(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => _buildSectionCard(
        context: context,
        title: 'RetroAchievements',
        icon: Icons.emoji_events,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, s) => _buildSectionCard(
        context: context,
        title: 'RetroAchievements',
        icon: Icons.emoji_events,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Failed to load: $e', style: TextStyle(color: theme.colorScheme.error)),
        ),
      ),
    );
  }

  Widget _buildProfileDisplay(
    BuildContext context,
    AsyncValue<RetroAchievementsProfile?> profileAsync,
    RetroAchievementsCredentials credentials,
  ) {
    final theme = Theme.of(context);
    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          // Connected without a Web API key: no profile data to show.
          return Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Text(credentials.username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          );
        }
        return Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              backgroundImage: profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
              child: profile.avatarUrl == null ? Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.username,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rank #${profile.rank} — ${profile.totalPoints} points (${profile.totalTruePoints} hardcore)',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Text(
        'Could not load profile: $e',
        style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
      ),
    );
  }

  Widget _buildStatus(
    BuildContext context,
    RetroAchievementsCredentials credentials,
    RetroAchievementsEmulatorLogin? emulatorLogin,
  ) {
    final theme = Theme.of(context);
    Widget line(bool ok, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.info_outline,
                  size: 16, color: ok ? Colors.green : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant))),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(emulatorLogin != null,
            emulatorLogin != null ? 'RetroArch is signed in at launch.' : 'Emulators are not signed in — add your password to set them up.'),
        line(credentials.hasWebApiKey,
            credentials.hasWebApiKey ? 'Live progress from RetroAchievements.' : 'Progress comes from RomM only (if your server has RetroAchievements enabled).'),
        if (emulatorLogin != null)
          // Own Material so the tile's ink isn't hidden by the card's background.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hardcore mode', style: TextStyle(fontSize: 14)),
              subtitle: const Text('No save states, rewind or cheats; unlocks count as hardcore.', style: TextStyle(fontSize: 12)),
              value: emulatorLogin.hardcore,
              onChanged: (v) => ref.read(retroAchievementsSetHardcoreProvider)(v),
            ),
          ),
      ],
    );
  }

  Future<bool> _confirmNoPassword(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogBackBridge(
        child: AlertDialog(
          title: const Text('Emulators won\'t be set up'),
          content: const Text(
            'Without your password, Freegosy can\'t sign your emulators in to RetroAchievements, '
            'so you\'d have to log in inside each emulator yourself.\n\nSave without a password anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Go back')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save anyway')),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _connect(BuildContext context) async {
    final username = _usernameController.text.trim();
    final webApiKey = _webApiKeyController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Username is required.');
      return;
    }
    if (password.isEmpty && webApiKey.isEmpty) {
      setState(() => _errorMessage = 'Enter your password, your Web API key, or both.');
      return;
    }

    // An existing emulator login is kept when the username is unchanged, so
    // only warn when saving would leave emulators signed out.
    final existing = ref.read(retroAchievementsEmulatorLoginProvider).asData?.value;
    final keepsLogin = existing != null && existing.username.toLowerCase() == username.toLowerCase();
    if (password.isEmpty && !keepsLogin && !await _confirmNoPassword(context)) return;
    if (!context.mounted) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final connect = ref.read(retroAchievementsConnectProvider);
      await connect(RetroAchievementsCredentials(username: username, webApiKey: webApiKey), password: password);
      if (!mounted) return;
      _passwordController.clear();
      setState(() {
        _isConnecting = false;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected to RetroAchievements!')));
    } on RetroAchievementsAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Could not connect: $e';
      });
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final disconnect = ref.read(retroAchievementsDisconnectProvider);
    await disconnect();
    if (!mounted) return;
    _usernameController.clear();
    _webApiKeyController.clear();
    _passwordController.clear();
    setState(() {
      _isEditing = true;
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disconnected from RetroAchievements.')));
  }
}
