import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';

/// Generic viewer that renders a bundled markdown doc from `assets/legal/`.
///
/// Build 16 — Apple UGC compliance. Terms of Use and Community Guidelines
/// are bundled as .md files so they render offline and Apple reviewers can
/// verify the text without hitting the network. Privacy Policy is launched
/// on the web (punkytigerlabs.com) because that version is canonical and
/// changes more often than Terms / Guidelines.
///
/// Used by:
///   - Profile → About → Terms of Service   (asset: terms-of-use.md)
///   - Profile → About → Community Guidelines (asset: community-guidelines.md)
///   - Auth screen (pre sign-in): Terms / Guidelines linked under the form.
///
/// The entry point accepts an asset path and a title for the app bar. Any
/// fully-qualified http/https links inside the markdown are opened in the
/// external browser via url_launcher.
class LegalViewerScreen extends StatefulWidget {
  final String assetPath;
  final String title;

  /// Optional secondary "Open on web" URL. When present, a trailing link
  /// row is shown at the bottom pointing to the canonical hosted copy so
  /// users can verify the in-app text matches the web version.
  final String? webUrl;

  const LegalViewerScreen({
    super.key,
    required this.assetPath,
    required this.title,
    this.webUrl,
  });

  @override
  State<LegalViewerScreen> createState() => _LegalViewerScreenState();
}

class _LegalViewerScreenState extends State<LegalViewerScreen> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = rootBundle.loadString(widget.assetPath);
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              // Very unlikely (bundled asset) — but don't crash; show a
              // friendly fallback with the web link if any so the user can
              // still reach the content.
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.legalLoadError,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (widget.webUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => _launchUrl(widget.webUrl!),
                        icon: const Icon(Icons.public, size: 18),
                        label: Text(l10n.legalOpenOnWeb),
                      ),
                  ],
                ),
              );
            }
            return Markdown(
              data: snap.data!,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              selectable: true,
              onTapLink: (text, href, title) {
                if (href != null) _launchUrl(href);
              },
              styleSheet: _markdownStyle(context),
            );
          },
        ),
      ),
      bottomNavigationBar: widget.webUrl == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () => _launchUrl(widget.webUrl!),
                  icon: const Icon(Icons.public, size: 18),
                  label: Text(l10n.legalOpenOnWeb),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  /// Dark-mode friendly markdown styling. Matches the app's palette
  /// (`AppColors.accent` for links, white/greys for body) so Terms &
  /// Guidelines feel like part of the app and not a floating WebView.
  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      p: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white),
      h1: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
      h2: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
      h3: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
      h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 4),
      listBullet:
          const TextStyle(fontSize: 14, height: 1.5, color: Colors.white),
      a: TextStyle(color: AppColors.accent, decoration: TextDecoration.underline),
      strong: const TextStyle(
          fontWeight: FontWeight.w700, color: Colors.white),
      blockquote: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: Colors.white.withOpacity(0.75),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppColors.accent.withOpacity(0.5), width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      code: TextStyle(
        fontSize: 13,
        color: Colors.white,
        backgroundColor: Colors.white.withOpacity(0.08),
      ),
      codeblockDecoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
    );
  }
}

/// Convenience constructor for the three canonical legal docs. Centralises
/// the asset paths + web URLs so callers don't have to remember them.
class LegalDocs {
  LegalDocs._();

  static const termsAsset = 'assets/legal/terms-of-use.md';
  static const guidelinesAsset = 'assets/legal/community-guidelines.md';

  /// Privacy Policy is hosted on web (not bundled). The URL below is the
  /// canonical version referenced in terms-of-use.md § 1.
  static const privacyWebUrl =
      'https://punkytigerlabs.com/flixscopeapp/privacy-policy';

  /// Optional mirror for the bundled docs — if Punky Tiger Labs publishes
  /// the same text on the web, callers can pass these to show an
  /// "Open on web" button for reference. Build 16 leaves them null because
  /// the web versions don't exist yet; Build 17+ can enable them.
  static const String? termsWebUrl = null;
  static const String? guidelinesWebUrl = null;
}
