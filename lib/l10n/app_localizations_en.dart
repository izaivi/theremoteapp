// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Flixscope';

  @override
  String get homeTitle => 'What matters now';

  @override
  String get homeTagline =>
      'We don\'t show you what\'s popular. We show you what\'s worth your time.';

  @override
  String get sectionTrendingNow => 'Trending Now';

  @override
  String get sectionTrendingSubtitle => 'Popular and actually good.';

  @override
  String get sectionExploding => 'Exploding';

  @override
  String get sectionExplodingSubtitle => 'Gaining momentum fast.';

  @override
  String get sectionQuickDecision => 'Quick Decision';

  @override
  String get sectionQuickDecisionSubtitle =>
      'Short, great, ready to watch tonight.';

  @override
  String get sectionDontWaste => 'Don\'t Waste Your Time';

  @override
  String get sectionDontWasteSubtitle =>
      'High hype, low reward. We\'d skip these.';

  @override
  String get sectionFiveGems => '5 Gems for you';

  @override
  String fiveGemsLockedTease(int count) {
    return '$count more gems waiting for you today';
  }

  @override
  String get fiveGemsLockedCta => 'Unlock with Premium';

  @override
  String get paywallTitle => 'PREMIUM User';

  @override
  String get paywallSubtitle => 'Pro experience: decide better and before everyone else.';

  @override
  String get paywallFeatureChat => 'Ask Remoty unlimited (clever Companion)';

  @override
  String get paywallFeatureDecision => 'Daily Decision Assistant (the big one)';

  @override
  String get paywallFeatureFilters => 'Advanced filters (drop-off, signals, trust score)';

  @override
  String get paywallFeatureExploding => 'Early access to trends (Exploding before others)';

  @override
  String get paywallFeatureGems => '5 Gems daily';

  @override
  String get paywallFeatureAlerts => 'Personalized alerts';

  @override
  String get paywallFeatureRegion => 'Explore by region (see what works elsewhere)';

  @override
  String get paywallFeatureStats => 'Advanced statistics';

  @override
  String get paywallFeatureWatchlist => 'Unlimited Watchlist';

  @override
  String get paywallFeatureQuickTake => 'Short comment QuickTake (250 chars)';

  @override
  String get paywallCta => 'Upgrade';

  @override
  String get paywallLater => 'Not now';

  @override
  String get discoverTitle => 'Discover';

  @override
  String get discoverSearchHint => 'Search a movie or show…';

  @override
  String get discoverFilters => 'Filters';

  @override
  String get discoverClearFilters => 'Clear';

  @override
  String get discoverSectionPopularRegion => 'Popular in your region';

  @override
  String get discoverSectionUnderRadar => 'Under the radar';

  @override
  String get discoverSectionUnder90 => 'Under 90 minutes';

  @override
  String get discoverSectionBingeable => 'Finish this weekend';

  @override
  String get discoverEmpty => 'Nothing matches those filters.';

  @override
  String discoverResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String get filterGroupGenre => 'Genre';

  @override
  String get filterGroupPlatform => 'Platform';

  @override
  String get filterGroupType => 'Type';

  @override
  String get filterGroupDuration => 'Duration';

  @override
  String get filterGroupMinScore => 'Min Watcher Score';

  @override
  String get filterGroupAdvanced => 'Advanced (Premium)';

  @override
  String get filterTypeMovie => 'Movie';

  @override
  String get filterTypeSeries => 'Series';

  @override
  String get filterDurationShort => 'Short (<90m)';

  @override
  String get filterDurationMedium => 'Medium (90–150m)';

  @override
  String get filterDurationLong => 'Long (>150m)';

  @override
  String get filterAdvancedDropoff => 'Low drop-off';

  @override
  String get filterAdvancedTrust => 'High trust';

  @override
  String get filterAdvancedConsensus => 'High consensus';

  @override
  String get filterAdvancedYearRange => 'Year range';

  @override
  String get filterAdvancedOtherRegions => 'Other regions';

  @override
  String contentMeta(int year, String platforms) {
    return '$year · $platforms';
  }

  @override
  String contentDurationMin(int minutes) {
    return '$minutes min';
  }

  @override
  String get tabHome => 'Home';

  @override
  String get tabDiscover => 'Discover';

  @override
  String get tabAi => 'Remoty';

  @override
  String get tabCreators => 'Creators';

  @override
  String get tabProfile => 'Profile';

  @override
  String get tabVault => 'Vault';

  @override
  String get vaultTitle => 'My Vault';

  @override
  String get vaultSubtitle => 'Your personal library.';

  @override
  String get vaultTabLoved => 'Loved';

  @override
  String get vaultTabRanking => 'Ranking';

  @override
  String get vaultTabWatchlist => 'Watchlist';

  @override
  String get vaultTabNotForMe => 'Not for me';

  @override
  String get vaultTabFollowing => 'Following';

  @override
  String get vaultEmptyLoved =>
      'Nothing loved yet. Rate a title 5★ to add it here.';

  @override
  String get vaultEmptyRanking =>
      'Rate titles and see them here sorted by stars.';

  @override
  String get vaultEmptyWatchlist =>
      'Your watchlist is empty. Tap 🔖 to save titles for later.';

  @override
  String get vaultEmptyNotForMe =>
      'Nothing dismissed yet. Tap \'Not for me\' on a title to hide it.';

  @override
  String get vaultEmptyFollowing =>
      'You\'re not following anyone yet. Visit Creators to follow trusted voices.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAvatarTitle => 'Avatar';

  @override
  String get settingsAvatarHint =>
      'Pick initials, a default avatar, or upload your own.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get settingsLanguageSection => 'Language & region';

  @override
  String get settingsUiLanguage => 'App language';

  @override
  String get settingsUiLanguageHint =>
      'The language used across the app interface.';

  @override
  String get settingsContentLanguage => 'Content language';

  @override
  String get settingsContentLanguageHint =>
      'Language used for synopses and reviews when available.';

  @override
  String get settingsCountry => 'Country';

  @override
  String get settingsCountryHint =>
      'Used to show what\'s available on your streaming platforms.';

  @override
  String get prefAuto => 'Auto (system)';

  @override
  String get langEnglish => 'English';

  @override
  String get langSpanish => 'Spanish';

  @override
  String get countryUs => 'United States';

  @override
  String get countryMx => 'Mexico';

  @override
  String get countryEs => 'Spain';

  @override
  String get countryAr => 'Argentina';

  @override
  String get countryCo => 'Colombia';

  @override
  String get countryCl => 'Chile';

  @override
  String get countryUk => 'United Kingdom';

  @override
  String get countryCa => 'Canada';

  @override
  String get countryBr => 'Brazil';

  @override
  String get countryIe => 'Ireland';

  @override
  String get countryFr => 'France';

  @override
  String get countryDe => 'Germany';

  @override
  String get countryIt => 'Italy';

  @override
  String get countryNl => 'Netherlands';

  @override
  String get countryPt => 'Portugal';

  @override
  String get countrySe => 'Sweden';

  @override
  String get countryOther => 'Rest of the world';

  @override
  String get profileSectionAccount => 'Account';

  @override
  String get profileSectionProfile => 'Profile';

  @override
  String get profileSectionPreferences => 'Preferences';

  @override
  String get profileSectionPremium => 'Premium';

  @override
  String get profileSectionSupport => 'Support';

  @override
  String get profileSectionLegal => 'Legal';

  @override
  String get profileSectionAbout => 'About';

  @override
  String get profileNotSignedIn => 'Not signed in';

  @override
  String get profileNotSignedInSub =>
      'Sign in to sync your ratings and takes across devices.';

  @override
  String get profileSignIn => 'Sign in';

  @override
  String get profileAlias => 'Alias';

  @override
  String get profileAliasNotSet => 'Not set yet';

  @override
  String get profileAliasChange => 'Change alias';

  @override
  String get profileAliasCooldown => 'You can change your alias every 90 days.';

  @override
  String get profileTierFree => 'Free';

  @override
  String get profileTierPro => 'Premium';

  @override
  String get profileUpgrade => 'Upgrade to Premium';

  @override
  String get profileManageSubscription => 'Manage subscription';

  @override
  String get profileHelpCenter => 'Help Center';

  @override
  String get profileContactUs => 'Contact us';

  @override
  String get profileSendFeedback => 'Send feedback';

  @override
  String get profileRateApp => 'Rate Flixscope';

  @override
  String get profileTerms => 'Terms of Service';

  @override
  String get profilePrivacy => 'Privacy Policy';

  @override
  String get profileLicenses => 'Open source licenses';

  @override
  String get profileVersion => 'Version';

  @override
  String get profileBuild => 'Build';

  @override
  String get profileComingSoon => 'Coming soon';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get creatorsTitle => 'Creators';

  @override
  String get creatorsTagline => 'Trusted voices. Real takes. No algorithms.';

  @override
  String get creatorsFeaturedSkip => 'NOT worth your time';

  @override
  String get creatorsSectionAll => 'All creators';

  @override
  String get creatorsSectionLatest => 'Latest takes';

  @override
  String get creatorsCurated => 'Curated';

  @override
  String get creatorsFollow => 'Follow';

  @override
  String get creatorsFollowing => 'Following';

  @override
  String creatorsFollowersCount(int count) {
    return '$count followers';
  }

  @override
  String get creatorVerdictWorthIt => 'Worth it';

  @override
  String get creatorVerdictSkipIt => 'Skip it';

  @override
  String get creatorVerdictQuickTake => 'Quick take';

  @override
  String get creatorActionWatch => 'Watch';

  @override
  String get creatorActionSave => 'Save';

  @override
  String get creatorActionHelpful => 'Helpful';

  @override
  String get creatorActionNotHelpful => 'Not helpful';

  @override
  String get creatorDetailTakes => 'Takes';

  @override
  String get creatorTakeSaved => 'Saved to your list';

  @override
  String get creatorTakeHelpfulRecorded => 'Thanks for the signal';

  @override
  String get splashTagline => 'Take control';

  @override
  String get splashSubtitle =>
      'We don\'t show you what\'s popular.\nWe show you what\'s worth your time.';

  @override
  String get splashCta => 'Start';

  @override
  String get chatTitle => 'Ask Remoty';

  @override
  String get chatTagline => 'Your streaming companion.';

  @override
  String get chatInputHint => 'What are you in the mood for?';

  @override
  String get chatSend => 'Send';

  @override
  String get chatEmptyTitle => 'Hey! I\'m Remoty';

  @override
  String get chatEmptyBody =>
      'I know the catalog, your vault, and what creators say. Ask me anything about what to watch.';

  @override
  String get chatQuickShort => 'Short tonight';

  @override
  String get chatQuickBinge => 'Binge this weekend';

  @override
  String get chatQuickSad => 'Something emotional';

  @override
  String get chatQuickSkip => 'What should I skip?';

  @override
  String get chatQuickVault => 'My favorites';

  @override
  String get chatQuickRanking => 'My best rated';

  @override
  String get chatQuickCreators => 'Top creator picks';

  @override
  String chatQuotaRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count questions left today',
      one: '1 question left today',
      zero: 'No questions left today',
    );
    return '$_temp0';
  }

  @override
  String get chatQuotaPro => 'Unlimited';

  @override
  String get chatQuotaExhaustedTitle =>
      ‘You’ve used your 5 free questions today’;

  @override
  String get chatQuotaExhaustedBody =>
      'Upgrade to Premium for unlimited Ask Remoty and Decision Assistant.';

  @override
  String get chatGuideTitle => 'How to Ask Remoty';

  @override
  String get chatGuideCategory1Title => 'Mood & Genre';

  @override
  String get chatGuideCategory1Desc =>
      'Tell me how you feel or what genre you want — I\'ll find the best match.';

  @override
  String get chatGuideCategory2Title => 'Favorites & Vault';

  @override
  String get chatGuideCategory2Desc =>
      'Ask about your favorites, watchlist, or what you\'ve dismissed.';

  @override
  String get chatGuideCategory5Title => 'Your Rankings';

  @override
  String get chatGuideCategory5Desc =>
      'Check your best or worst star ratings from your vault.';

  @override
  String get chatGuideCategory3Title => 'Creator Takes';

  @override
  String get chatGuideCategory3Desc =>
      'See what trusted creators are recommending or skipping.';

  @override
  String get chatGuideCategory4Title => 'Platform Search';

  @override
  String get chatGuideCategory4Desc =>
      'Ask what\'s good on Netflix, Max, Disney+, or any platform.';

  @override
  String get chatClearTitle => 'Clear conversation?';

  @override
  String get chatClearBody =>
      'This will remove all messages. This action can\'t be undone.';

  @override
  String get chatClearConfirm => 'Clear';

  @override
  String get chatClearCancel => 'Cancel';

  @override
  String get longQuizTitle => 'Tune your taste';

  @override
  String get longQuizIntro =>
      'A few minutes of input unlocks classic gems and sharper picks for you.';

  @override
  String get longQuizStepGrid => 'Which of these have you seen?';

  @override
  String get longQuizStepGridSub =>
      'Tap once for seen, twice if you loved it. We use this to find your blind spots.';

  @override
  String get longQuizStepThemes => 'What do you love?';

  @override
  String get longQuizStepThemesSub =>
      'Directors, themes, moods — anything. Comma-separated.';

  @override
  String get longQuizThemesHint =>
      'e.g. Denis Villeneuve, slow burn, neo-noir, 70s paranoia';

  @override
  String get longQuizLegendSeen => 'Seen';

  @override
  String get longQuizLegendLoved => 'Loved';

  @override
  String get longQuizBack => 'Back';

  @override
  String get longQuizNext => 'Next';

  @override
  String get longQuizFinish => 'Finish';

  @override
  String get longQuizSkip => 'Skip for now';

  @override
  String get longQuizDoneTitle => 'Profile tuned';

  @override
  String get longQuizDoneBody => 'Your 5 Gems are about to get much smarter.';

  @override
  String get profileStrengthFast => 'Fast profile';

  @override
  String get profileStrengthLong => 'Full profile';

  @override
  String get profileStrengthCtaComplete => 'Complete your profile';

  @override
  String get profileStrengthCtaDone => 'Full profile — classics unlocked';

  @override
  String get profileStrengthHint =>
      'Unlocks classic gems and sharper recommendations.';

  @override
  String get discoverLongQuizBanner => 'Can\'t find what you want?';

  @override
  String get discoverLongQuizBannerSub =>
      'Spend 2 minutes tuning your taste and we\'ll find it for you.';

  @override
  String get onboardingWelcome => 'Welcome to Flixscope';

  @override
  String get onboardingWelcomeSub =>
      '30 seconds and we\'ll start finding what\'s worth your time.';

  @override
  String get onboardingStep1Title => 'Where do you watch from?';

  @override
  String get onboardingStep1Sub =>
      'This determines what\'s available on your streaming platforms.';

  @override
  String get onboardingStep2Title => 'What do you pay for?';

  @override
  String get onboardingStep2Sub =>
      'Pick every platform you actually use. We\'ll never recommend something you can\'t watch.';

  @override
  String get onboardingStep3Title => 'What do you love?';

  @override
  String get onboardingStep3Sub => 'Pick 3 or more. You can change this later.';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingFinish => 'Start watching';

  @override
  String get onboardingPlatformsHint => 'Pick at least 1.';

  @override
  String get onboardingGenresHint => 'Pick at least 3.';

  @override
  String get genreDrama => 'Drama';

  @override
  String get genreComedy => 'Comedy';

  @override
  String get genreThriller => 'Thriller';

  @override
  String get genreSciFi => 'Sci-Fi';

  @override
  String get genreRomance => 'Romance';

  @override
  String get genreAction => 'Action';

  @override
  String get genreHorror => 'Horror';

  @override
  String get genreDocumentary => 'Documentary';

  @override
  String get genreAnimation => 'Animation';

  @override
  String get genreCrime => 'Crime';

  @override
  String get genreHistory => 'History';

  @override
  String get genreMystery => 'Mystery';

  @override
  String get contentBack => 'Back';

  @override
  String get contentSectionSignals => 'Signals';

  @override
  String get contentSectionSynopsis => 'Synopsis';

  @override
  String get contentSectionFansSay => 'Flixscope Fans Say';

  @override
  String get contentSectionQuickTakes => 'Quick takes';

  @override
  String get contentSectionAvailable => 'Available on';

  @override
  String get contentWatcherScore => 'Watcher Score';

  @override
  String get contentTrustScore => 'Trust';

  @override
  String get contentVariance => 'Variance';

  @override
  String get contentCompletion => 'Completion';

  @override
  String fansSayCompletion(int pct) {
    return '$pct% finished it';
  }

  @override
  String fansSayWorth(int pct) {
    return '$pct% said worth their time';
  }

  @override
  String fansSayRating(String rating) {
    return '$rating / 5 average';
  }

  @override
  String fansSaySample(int count) {
    return 'n = $count verified watchers';
  }

  @override
  String get fansSayNotEnough => 'Not enough verified signal yet.';

  @override
  String get contentActionRate => 'Rate';

  @override
  String get contentActionWorth => 'Worth it?';

  @override
  String get contentActionTake => 'Write a take';

  @override
  String get contentLoginGate =>
      'Sign in to rate and share your take. Your signal helps other viewers find joyas.';

  @override
  String get contentLoginGateCta => 'Sign in later';

  @override
  String get contentNoTakes =>
      'No quick takes yet. Be the first verified watcher.';

  @override
  String get contentMyRating => 'Your rating';

  @override
  String get contentNotForMe => 'Not for me';
}
