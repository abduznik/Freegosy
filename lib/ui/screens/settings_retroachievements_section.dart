import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/retroachievements/retroachievements_models.dart';
import '../../providers/retroachievements_provider.dart';
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
/// This is intentionally read-only/profile-focused: Freegosy launches
/// emulators as external processes and has no access to their live memory,
/// so it cannot itself track or award achievement unlocks the way rcheevos
/// (built into RetroArch, Dolphin, PCSX2, etc.) does from inside the
/// emulator. Connecting an account here only lets Freegosy display that
/// account's profile and points.
class SettingsRetroAchievementsSection extends ConsumerStatefulWidget {
  const SettingsRetroAchievementsSection({super.key});

  @override
  ConsumerState<SettingsRetroAchievementsSection> createState() => _SettingsRetroAchievementsSectionState();
}

class _SettingsRetroAchievementsSectionState extends ConsumerState<SettingsRetroAchievementsSection> {
  late final TextEditingController _usernameController;
  late final TextEditingController _webApiKeyController;
  bool _isEditing = false;
  bool _isConnecting = false;
  bool _preferencesLoaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _webApiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _webApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credentialsAsync = ref.watch(retroAchievementsCredentialsProvider);
    final profileAsync = ref.watch(retroAchievementsProfileProvider);

    return credentialsAsync.when(
      data: (credentials) {
        if (!_preferencesLoaded) {
          _usernameController.text = credentials?.username ?? '';
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
                'Connect your RetroAchievements account to see your profile and points in Freegosy. '
                'Achievements are still tracked and unlocked by the emulator itself (e.g. RetroArch, Dolphin, PCSX2) — '
                'Freegosy does not award achievements, only displays your account here.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (credentials != null && !_isEditing) ...[
                _buildProfileDisplay(context, profileAsync),
              ] else ...[
                TextField(
                  controller: _usernameController,
                  readOnly: !_isEditing,
                  decoration: _buildInputDecoration(context, 'Username'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _webApiKeyController,
                  readOnly: !_isEditing,
                  obscureText: true,
                  decoration: _buildInputDecoration(
                    context,
                    'Web API Key',
                    helperText: 'Find this under Settings > Keys on retroachievements.org',
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

  Widget _buildProfileDisplay(BuildContext context, AsyncValue<RetroAchievementsProfile?> profileAsync) {
    final theme = Theme.of(context);
    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return Text('Not connected.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant));
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

  Future<void> _connect(BuildContext context) async {
    final username = _usernameController.text.trim();
    final webApiKey = _webApiKeyController.text.trim();

    if (username.isEmpty || webApiKey.isEmpty) {
      setState(() => _errorMessage = 'Username and Web API Key are required.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final connect = ref.read(retroAchievementsConnectProvider);
      await connect(RetroAchievementsCredentials(username: username, webApiKey: webApiKey));
      if (!mounted) return;
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
    setState(() {
      _isEditing = true;
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disconnected from RetroAchievements.')));
  }
}
