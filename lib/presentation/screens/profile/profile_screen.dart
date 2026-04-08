import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/language_prefs.dart';
import '../../../data/repositories/user_profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/paywall_sheet.dart';

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
    final isSignedIn = profile.id != null;

    void comingSoon() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.profileComingSoon),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            l10n.profileTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 20),

          // ---------------- Account ----------------
          _AccountCard(
            isSignedIn: isSignedIn,
            alias: profile.alias,
            onSignIn: comingSoon,
          ),
          const SizedBox(height: 24),

          // ---------------- Profile ----------------
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
              onTap: comingSoon,
            ),
          ]),
          const SizedBox(height: 24),

          // ---------------- Preferences ----------------
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
                _Opt('MX', l10n.countryMx),
                _Opt('ES', l10n.countryEs),
                _Opt('AR', l10n.countryAr),
                _Opt('CO', l10n.countryCo),
                _Opt('CL', l10n.countryCl),
                _Opt('GB', l10n.countryUk),
              ],
              onChanged: langCtrl.setCountry,
            ),
          ]),
          const SizedBox(height: 24),

          // ---------------- Premium ----------------
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

          // ---------------- Support ----------------
          _SectionHeader(l10n.profileSectionSupport),
          _Group(children: [
            _Row(
              icon: Icons.help_outline,
              title: l10n.profileHelpCenter,
              onTap: comingSoon,
            ),
            _Row(
              icon: Icons.mail_outline,
              title: l10n.profileContactUs,
              onTap: comingSoon,
            ),
            _Row(
              icon: Icons.feedback_outlined,
              title: l10n.profileSendFeedback,
              onTap: comingSoon,
            ),
            _Row(
              icon: Icons.star_border,
              title: l10n.profileRateApp,
              onTap: comingSoon,
            ),
          ]),
          const SizedBox(height: 24),

          // ---------------- Legal ----------------
          _SectionHeader(l10n.profileSectionLegal),
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
          ]),
          const SizedBox(height: 24),

          // ---------------- About ----------------
          _SectionHeader(l10n.profileSectionAbout),
          _Group(children: [
            _Row(
              icon: Icons.info_outline,
              title: l10n.profileVersion,
              trailingText: '$_appVersion ($_appBuild)',
            ),
          ]),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'The Remote · $_appVersion',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.primary,
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

  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final textColor = highlight
        ? primary
        : Theme.of(context).textTheme.bodyLarge?.color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: highlight ? primary : Colors.white70),
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
// Account card (hero-ish card at the top)
// ---------------------------------------------------------------------------

class _AccountCard extends StatelessWidget {
  final bool isSignedIn;
  final String? alias;
  final VoidCallback onSignIn;

  const _AccountCard({
    required this.isSignedIn,
    required this.alias,
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withOpacity(0.25),
              border: Border.all(color: primary, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(
              isSignedIn ? Icons.person : Icons.person_outline,
              color: primary,
              size: 28,
            ),
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
                Text(
                  isSignedIn
                      ? l10n.profileAlias
                      : l10n.profileNotSignedInSub,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
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
