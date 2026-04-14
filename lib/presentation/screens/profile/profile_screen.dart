import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:go_router/go_router.dart';

import '../../../core/prefs/language_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/supabase_sync.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/user_avatar.dart';

/// Profile / Settings screen.
///
/// iOS-style grouped list with sections:
///   Account, Profile, Preferences, Premium, Support, Legal, About.
///
/// Legal/Support links are dummies (SnackBar "Coming soon") until the
/// real web pages exist. Alias change is stubbed behind a 90-day cooldown
/// message — full persistence will land with Supabase Auth.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  // Hardcoded until we wire `package_info_plus`.
  static const String _appVersion = '1.0.0';
  static const String _appBuild = '1';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final prefs = ref.watch(languagePrefsProvider);
    final langCtrl = ref.read(languagePrefsProvider.notifier);
    final profile = ref.watch(userProfileProvider);
    final isPro = profile.tier == 'pro';
    // Source of truth for sign-in is Supabase Auth (currentUser), NOT the
    // local profile mirror. `profile.id` is populated by `refreshFromRemote`
    // which can lag, fail silently, or be wiped by a stray factory call.
    // Watching `currentUserProvider` keeps this in lockstep with the router's
    // own `signedIn` check and with reality.
    final currentUser = ref.watch(currentUserProvider);
    final isSignedIn = currentUser != null;

    void comingSoon() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.profileComingSoon),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    Future<void> pickAndSaveAvatar() async {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 92,
        );
        if (picked == null) return;
        // Copy to the app's documents dir so it survives across relaunches
        // (the picker returns a path in a temp cache that iOS may purge).
        final docsDir = await getApplicationDocumentsDirectory();
        final avatarsDir = Directory('${docsDir.path}/avatars');
        if (!await avatarsDir.exists()) {
          await avatarsDir.create(recursive: true);
        }
        final ext = picked.path.contains('.')
            ? picked.path.substring(picked.path.lastIndexOf('.'))
            : '.jpg';
        final destPath =
            '${avatarsDir.path}/user_${DateTime.now().millisecondsSinceEpoch}$ext';
        await File(picked.path).copy(destPath);
        ref
            .read(userProfileProvider.notifier)
            .setAvatar('file:$destPath');
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.profileComingSoon),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [

          // ═══════════════ Account ═══════════════
          _AccountCard(
            isSignedIn: isSignedIn,
            alias: profile.alias,
            email: currentUser?.email,
            avatarKey: profile.avatarKey,
            onSignIn: () => context.push('/auth'),
          ),
          const SizedBox(height: 14),

          // ═══════════════ Avatar picker ═══════════════
          _AvatarPickerCard(
            currentKey: profile.avatarKey,
            seed: profile.alias ?? l10n.settingsTitle,
            onSelect: (key) =>
                ref.read(userProfileProvider.notifier).setAvatar(key),
            onUpload: () {
              pickAndSaveAvatar();
            },
          ),
          const SizedBox(height: 14),

          // ═══════════════ Profile strength ═══════════════
          _ProfileStrengthCard(
            completed: profile.quizCompletion == QuizCompletion.long,
          ),
          const SizedBox(height: 24),

          // ═══════════════ Profile ═══════════════
          _SectionHeader(l10n.profileSectionProfile),
          _Group(children: [
            _Row(
              icon: Icons.alternate_email,
              title: l10n.profileAlias,
              trailingText: profile.alias ?? l10n.profileAliasNotSet,
            ),
            _Row(
              icon: Icons.edit_outlined,
              title: l10n.profileAliasChange,
              subtitle: l10n.profileAliasCooldown,
              onTap: () async {
                final newAlias = await showDialog<String>(
                  context: context,
                  builder: (_) => _AliasDialog(current: profile.alias),
                );
                if (newAlias != null && newAlias.isNotEmpty) {
                  try {
                    await ref
                        .read(userProfileProvider.notifier)
                        .setAlias(newAlias);
                  } on AliasTakenException {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ese alias ya está en uso.'),
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ]),
          const SizedBox(height: 24),

          // ═══════════════ Preferences ═══════════════
          _SectionHeader(l10n.profileSectionPreferences),
          _Group(children: [
            _DropdownRow<String?>(
              icon: Icons.language,
              label: l10n.settingsUiLanguage,
              value: prefs.uiLanguage,
              items: [
                _Opt(null, l10n.prefAuto),
                _Opt('en', l10n.langEnglish),
                _Opt('es', l10n.langSpanish),
              ],
              onChanged: langCtrl.setUiLanguage,
            ),
            _DropdownRow<String?>(
              icon: Icons.subtitles_outlined,
              label: l10n.settingsContentLanguage,
              value: prefs.contentLanguage,
              items: [
                _Opt(null, l10n.prefAuto),
                _Opt('en', l10n.langEnglish),
                _Opt('es', l10n.langSpanish),
              ],
              onChanged: langCtrl.setContentLanguage,
            ),
            _DropdownRow<String?>(
              icon: Icons.public,
              label: l10n.settingsCountry,
              value: prefs.country,
              items: [
                _Opt(null, l10n.prefAuto),
                _Opt('US', l10n.countryUs),
                _Opt('CA', l10n.countryCa),
                _Opt('MX', l10n.countryMx),
                _Opt('BR', l10n.countryBr),
                _Opt('AR', l10n.countryAr),
                _Opt('CO', l10n.countryCo),
                _Opt('CL', l10n.countryCl),
                _Opt('ES', l10n.countryEs),
                _Opt('GB', l10n.countryUk),
                _Opt('IE', l10n.countryIe),
                _Opt('FR', l10n.countryFr),
                _Opt('DE', l10n.countryDe),
                _Opt('IT', l10n.countryIt),
                _Opt('NL', l10n.countryNl),
                _Opt('PT', l10n.countryPt),
                _Opt('SE', l10n.countrySe),
                _Opt('XX', l10n.countryOther),
              ],
              onChanged: langCtrl.setCountry,
            ),
          ]),
          const SizedBox(height: 24),

          // ═══════════════ Premium ═══════════════
          _SectionHeader(l10n.profileSectionPremium),
          _Group(children: [
            _Row(
              icon: isPro ? Icons.workspace_premium : Icons.lock_outline,
              title: isPro ? l10n.profileTierPro : l10n.profileTierFree,
              trailing: isPro
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('PRO',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    )
                  : null,
            ),
            if (!isPro)
              _Row(
                icon: Icons.auto_awesome,
                title: l10n.profileUpgrade,
                highlight: true,
                onTap: () => showPaywall(context),
              )
            else
              _Row(
                icon: Icons.settings_outlined,
                title: l10n.profileManageSubscription,
                onTap: comingSoon,
              ),
          ]),
          const SizedBox(height: 24),

          // ═══════════════ Contact Us ═══════════════
          _SectionHeader('Contact us'),
          _ContactCard(
            icon: Icons.mail_outlined,
            title: 'General Inquiries',
            subtitle: 'contact@punkytigerlabs.com',
            onTap: () => launchUrl(
              Uri.parse('mailto:contact@punkytigerlabs.com'),
            ),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.business_center_outlined,
            title: 'Business & Partnerships',
            subtitle: 'partnerships@punkytigerlabs.com',
            onTap: () => launchUrl(
              Uri.parse('mailto:partnerships@punkytigerlabs.com'),
            ),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.lightbulb_outline,
            title: 'Suggestions & Feedback',
            subtitle: 'feedback@punkytigerlabs.com',
            onTap: () => launchUrl(
              Uri.parse('mailto:feedback@punkytigerlabs.com'),
            ),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.star_border,
            title: l10n.profileRateApp,
            subtitle: 'Love Flixscope? Leave us a review!',
            onTap: comingSoon,
          ),
          const SizedBox(height: 24),

          // ═══════════════ Visit Us ═══════════════
          _SectionHeader('Visit us'),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://punkytigerlabs.com'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.public, size: 18),
              label: const Text('punkytigerlabs.com'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withOpacity(0.15)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ═══════════════ Punky Tiger Labs branding ═══════════════
          _PtlBrandingCard(),
          const SizedBox(height: 24),

          // ═══════════════ About ═══════════════
          _SectionHeader(l10n.profileSectionAbout),
          _Group(children: [
            _Row(
              icon: Icons.description_outlined,
              title: l10n.profileTerms,
              onTap: comingSoon,
            ),
            _Row(
              icon: Icons.privacy_tip_outlined,
              title: l10n.profilePrivacy,
              onTap: comingSoon,
            ),
            _Row(
              icon: Icons.code,
              title: l10n.profileLicenses,
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: _appVersion,
              ),
            ),
            _Row(
              icon: Icons.info_outline,
              title: l10n.profileVersion,
              trailingText: 'v$_appVersion — Build 2026.04.12',
            ),
          ]),
          const SizedBox(height: 24),

          // ═══════════════ Danger Zone ═══════════════
          _SectionHeader('Danger zone', isDestructive: true),
          _Group(children: [
            if (isSignedIn)
              _Row(
                icon: Icons.logout,
                title: l10n.profileSignOut,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(l10n.profileSignOut),
                      content: const Text(
                          'Your local data stays on this device. Sign in again to sync.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(l10n.profileSignOut),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await ref.read(authRepositoryProvider).signOut();
                    await ref.read(userProfileProvider.notifier).reset();
                    if (context.mounted) context.go('/home');
                  }
                },
              ),
            _Row(
              icon: Icons.delete_forever,
              title: 'Delete Account',
              destructive: true,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Account?'),
                    content: const Text(
                        'This will permanently delete your account and all associated data. This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  comingSoon(); // TODO: wire real account deletion
                }
              },
            ),
          ]),

          const SizedBox(height: 32),

          // ═══════════════ Copyright footer ═══════════════
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Text(
                  '\u00a9 2026 Punky Tiger Labs, Inc. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'All concepts, designs, gamification systems, translation engines, '
                  'and intellectual property contained in this application are '
                  'proprietary to Punky Tiger Labs, Inc.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Protected under United States Copyright Law, Title 17, U.S. Code.\n'
                  'Unauthorized reproduction or distribution is strictly prohibited.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDestructive;
  const _SectionHeader(this.title, {this.isDestructive = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: isDestructive
                ? Colors.red.shade400
                : const Color(0xFFCFB053), // gold accent like F1 Fan
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Grouped rounded card + dividers
// ---------------------------------------------------------------------------

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i != children.length - 1) {
        separated.add(Divider(
          height: 1,
          thickness: 0.5,
          indent: 52,
          color: Colors.white.withOpacity(0.08),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFCFB053).withOpacity(0.15),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: separated),
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlight;
  final bool destructive;

  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.highlight = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final textColor = destructive
        ? Colors.red.shade400
        : highlight
            ? primary
            : Theme.of(context).textTheme.bodyLarge?.color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: destructive ? Colors.red.shade400 : highlight ? primary : Colors.white70),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          highlight ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && trailingText != null)
              Text(
                trailingText!,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dropdown row (for preferences)
// ---------------------------------------------------------------------------

class _Opt<T> {
  final T value;
  final String label;
  const _Opt(this.value, this.label);
}

class _DropdownRow<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<_Opt<T>> items;
  final ValueChanged<T> onChanged;

  const _DropdownRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            isDense: true,
            icon: Icon(Icons.keyboard_arrow_down,
                color: Theme.of(context).textTheme.bodySmall?.color),
            items: [
              for (final item in items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: Text(item.label,
                      style: const TextStyle(fontSize: 14)),
                ),
            ],
            onChanged: (v) {
              if (v != null || null is T) onChanged(v as T);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact card — styled with outline border like F1 Fan reference
// ---------------------------------------------------------------------------

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: const Color(0xFFCFB053).withOpacity(0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.white70),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward,
                size: 18,
                color: const Color(0xFFCFB053).withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Punky Tiger Labs branding card
// ---------------------------------------------------------------------------

class _PtlBrandingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          // PTL logo
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/punkytigerlabs.png',
              width: 80,
              height: 80,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'PUNKY TIGER LABS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
              color: Color(0xFFCFB053),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 40,
            height: 2,
            decoration: BoxDecoration(
              color: const Color(0xFFCFB053),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Applied Artificial Intelligence\nResearch & Development Laboratory',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Headquarters: Burbank, California, United States',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account card (hero-ish card at the top)
// ---------------------------------------------------------------------------

class _AccountCard extends StatelessWidget {
  final bool isSignedIn;
  final String? alias;
  final String? email;
  final String? avatarKey;
  final VoidCallback onSignIn;

  const _AccountCard({
    required this.isSignedIn,
    required this.alias,
    required this.email,
    required this.avatarKey,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withOpacity(0.22),
            Theme.of(context).colorScheme.surface,
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          UserAvatar(
            avatarKey: avatarKey,
            seed: alias ?? 'Flixscope',
            size: 56,
            withBorder: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSignedIn
                      ? (alias ?? l10n.profileAliasNotSet)
                      : l10n.profileNotSignedIn,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                // When signed in, show the email of the active auth account
                // so the user always knows which provider/identity they're
                // logged in as. Apple users with "Hide My Email" will see
                // their relay address (xxxx@privaterelay.appleid.com) — that
                // IS the account email Supabase stores, so it's accurate.
                // Guests (anonymous) have no email → fall back to the label.
                Text(
                  isSignedIn
                      ? (email ?? l10n.profileAlias)
                      : l10n.profileNotSignedInSub,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!isSignedIn)
            ElevatedButton(
              onPressed: onSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              child: Text(l10n.profileSignIn),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile strength card (Fast vs Long quiz)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Avatar picker — initials fallback + 5 bundled defaults + upload (stubbed).
// The 5 bundled avatars live in `assets/avatars/avatar_1.png` .. `avatar_5.png`.
// If the PNGs are missing, [UserAvatar] degrades to initials gracefully, so
// this picker is safe to ship before the art assets land.
// ---------------------------------------------------------------------------

class _AvatarPickerCard extends StatelessWidget {
  final String? currentKey;
  final String seed;
  final ValueChanged<String?> onSelect;
  final VoidCallback onUpload;

  const _AvatarPickerCard({
    required this.currentKey,
    required this.seed,
    required this.onSelect,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Options: null (initials), default:1..5, and an "upload" action tile.
    final options = <String?>[null, 'default:1', 'default:2', 'default:3',
      'default:4', 'default:5'];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsAvatarTitle,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsAvatarHint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opt in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _AvatarChoice(
                      avatarKey: opt,
                      seed: seed,
                      selected: currentKey == opt,
                      onTap: () => onSelect(opt),
                    ),
                  ),
                // Upload action tile (stub — will wire image_picker later)
                _UploadTile(onTap: onUpload),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  final String? avatarKey;
  final String seed;
  final bool selected;
  final VoidCallback onTap;
  const _AvatarChoice({
    required this.avatarKey,
    required this.seed,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: UserAvatar(
          avatarKey: avatarKey,
          seed: seed,
          size: 56,
        ),
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final VoidCallback onTap;
  const _UploadTile({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        margin: const EdgeInsets.all(3),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.04),
          border: Border.all(
            color: AppColors.accent.withOpacity(0.5),
            width: 1.4,
          ),
        ),
        child: const Icon(Icons.add_a_photo_outlined,
            size: 22, color: AppColors.accent),
      ),
    );
  }
}

class _ProfileStrengthCard extends StatelessWidget {
  final bool completed;
  const _ProfileStrengthCard({required this.completed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: completed ? null : () => context.push('/long-quiz'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: completed
                ? AppColors.accent.withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
          gradient: completed
              ? LinearGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.18),
                    Theme.of(context).colorScheme.surface,
                  ],
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: completed
                    ? AppColors.accent.withOpacity(0.2)
                    : Colors.white.withOpacity(0.06),
                border: Border.all(
                  color: completed
                      ? AppColors.accent
                      : Colors.white.withOpacity(0.15),
                ),
              ),
              child: Icon(
                completed ? Icons.auto_awesome : Icons.tune,
                color: completed ? AppColors.accent : Colors.white70,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completed
                        ? l10n.profileStrengthLong
                        : l10n.profileStrengthFast,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    completed
                        ? l10n.profileStrengthCtaDone
                        : l10n.profileStrengthHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            if (!completed)
              const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}


enum _AliasStatus { idle, checking, available, taken, formatError }

class _AliasDialog extends ConsumerStatefulWidget {
  final String? current;
  const _AliasDialog({this.current});

  @override
  ConsumerState<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends ConsumerState<_AliasDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current ?? '');
  _AliasStatus _status = _AliasStatus.idle;
  String? _error;
  Timer? _debounce;
  int _reqSeq = 0;

  static final _re = RegExp(r'^[a-zA-Z0-9_]+$');

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    final v = _ctrl.text.trim();

    // Empty or same as current → idle.
    if (v.isEmpty || v == (widget.current ?? '')) {
      setState(() {
        _status = _AliasStatus.idle;
        _error = null;
      });
      return;
    }
    // Format errors surface immediately, no network call.
    if (v.length < 3 || v.length > 24) {
      setState(() {
        _status = _AliasStatus.formatError;
        _error = 'Must be 3–24 characters.';
      });
      return;
    }
    if (!_re.hasMatch(v)) {
      setState(() {
        _status = _AliasStatus.formatError;
        _error = 'Letters, numbers, and _ only.';
      });
      return;
    }

    setState(() {
      _status = _AliasStatus.checking;
      _error = null;
    });

    final seq = ++_reqSeq;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final sync = ref.read(supabaseSyncProvider);
      final available = await sync.isAliasAvailable(v);
      // Ignore stale responses if the user kept typing.
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _status =
            available ? _AliasStatus.available : _AliasStatus.taken;
        _error = available ? null : 'Ese alias ya está en uso.';
      });
    });
  }

  void _save() {
    final v = _ctrl.text.trim();
    if (v.length < 3 || v.length > 24) {
      setState(() {
        _status = _AliasStatus.formatError;
        _error = 'Must be 3–24 characters.';
      });
      return;
    }
    if (!_re.hasMatch(v)) {
      setState(() {
        _status = _AliasStatus.formatError;
        _error = 'Letters, numbers, and _ only.';
      });
      return;
    }
    // Block save while still checking or known-taken; allow unchanged value
    // (idle) and confirmed available.
    if (_status == _AliasStatus.checking ||
        _status == _AliasStatus.taken ||
        _status == _AliasStatus.formatError) {
      return;
    }
    Navigator.pop(context, v);
  }

  Widget? _suffixIcon() {
    switch (_status) {
      case _AliasStatus.checking:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _AliasStatus.available:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _AliasStatus.taken:
      case _AliasStatus.formatError:
        return const Icon(Icons.error, color: Colors.redAccent);
      case _AliasStatus.idle:
        return null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _status == _AliasStatus.idle ||
        _status == _AliasStatus.available;
    return AlertDialog(
      title: const Text('Choose an alias'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 24,
        decoration: InputDecoration(
          hintText: 'e.g. vivi_93',
          errorText: _error,
          suffixIcon: _suffixIcon(),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
