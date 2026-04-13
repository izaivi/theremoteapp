import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Flixscope'**
  String get appTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'What matters now'**
  String get homeTitle;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'We don\'t show you what\'s popular. We show you what\'s worth your time.'**
  String get homeTagline;

  /// No description provided for @sectionTrendingNow.
  ///
  /// In en, this message translates to:
  /// **'Trending Now'**
  String get sectionTrendingNow;

  /// No description provided for @sectionTrendingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Popular and actually good.'**
  String get sectionTrendingSubtitle;

  /// No description provided for @sectionExploding.
  ///
  /// In en, this message translates to:
  /// **'Exploding'**
  String get sectionExploding;

  /// No description provided for @sectionExplodingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Gaining momentum fast.'**
  String get sectionExplodingSubtitle;

  /// No description provided for @sectionQuickDecision.
  ///
  /// In en, this message translates to:
  /// **'Quick Decision'**
  String get sectionQuickDecision;

  /// No description provided for @sectionQuickDecisionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Short, great, ready to watch tonight.'**
  String get sectionQuickDecisionSubtitle;

  /// No description provided for @sectionDontWaste.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Waste Your Time'**
  String get sectionDontWaste;

  /// No description provided for @sectionDontWasteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'High hype, low reward. We\'d skip these.'**
  String get sectionDontWasteSubtitle;

  /// No description provided for @sectionFiveGems.
  ///
  /// In en, this message translates to:
  /// **'5 Gems for you'**
  String get sectionFiveGems;

  /// No description provided for @fiveGemsLockedTease.
  ///
  /// In en, this message translates to:
  /// **'{count} more gems waiting for you today'**
  String fiveGemsLockedTease(int count);

  /// No description provided for @fiveGemsLockedCta.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Premium'**
  String get fiveGemsLockedCta;

  /// No description provided for @paywallTitle.
  ///
  /// In en, this message translates to:
  /// **'PREMIUM User'**
  String get paywallTitle;

  /// No description provided for @paywallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pro experience: decide better and before everyone else.'**
  String get paywallSubtitle;

  /// No description provided for @paywallFeatureChat.
  ///
  /// In en, this message translates to:
  /// **'Ask Remoty unlimited (clever Companion)'**
  String get paywallFeatureChat;

  /// No description provided for @paywallFeatureFilters.
  ///
  /// In en, this message translates to:
  /// **'Advanced filters (drop-off, signals, trust score)'**
  String get paywallFeatureFilters;

  /// No description provided for @paywallFeatureExploding.
  ///
  /// In en, this message translates to:
  /// **'Early access to trends (Exploding before others)'**
  String get paywallFeatureExploding;

  /// No description provided for @paywallFeatureGems.
  ///
  /// In en, this message translates to:
  /// **'5 Gems daily'**
  String get paywallFeatureGems;

  /// No description provided for @paywallFeatureStats.
  ///
  /// In en, this message translates to:
  /// **'Advanced statistics'**
  String get paywallFeatureStats;

  /// No description provided for @paywallFeatureWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Unlimited Watchlist'**
  String get paywallFeatureWatchlist;

  /// No description provided for @paywallFeatureQuickTake.
  ///
  /// In en, this message translates to:
  /// **'Short comment QuickTake (250 chars)'**
  String get paywallFeatureQuickTake;

  /// No description provided for @paywallCta.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get paywallCta;

  /// No description provided for @paywallLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get paywallLater;

  /// No description provided for @discoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverTitle;

  /// No description provided for @discoverSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search a movie or show…'**
  String get discoverSearchHint;

  /// No description provided for @discoverFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get discoverFilters;

  /// No description provided for @discoverClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get discoverClearFilters;

  /// No description provided for @discoverSectionPopularRegion.
  ///
  /// In en, this message translates to:
  /// **'Popular in your region'**
  String get discoverSectionPopularRegion;

  /// No description provided for @discoverSectionUnderRadar.
  ///
  /// In en, this message translates to:
  /// **'Under the radar'**
  String get discoverSectionUnderRadar;

  /// No description provided for @discoverSectionUnder90.
  ///
  /// In en, this message translates to:
  /// **'Under 90 minutes'**
  String get discoverSectionUnder90;

  /// No description provided for @discoverSectionBingeable.
  ///
  /// In en, this message translates to:
  /// **'Finish this weekend'**
  String get discoverSectionBingeable;

  /// No description provided for @discoverEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches those filters.'**
  String get discoverEmpty;

  /// No description provided for @discoverResultsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No results} =1{1 result} other{{count} results}}'**
  String discoverResultsCount(int count);

  /// No description provided for @filterGroupGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get filterGroupGenre;

  /// No description provided for @filterGroupPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get filterGroupPlatform;

  /// No description provided for @filterGroupType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterGroupType;

  /// No description provided for @filterGroupDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get filterGroupDuration;

  /// No description provided for @filterGroupMinScore.
  ///
  /// In en, this message translates to:
  /// **'Min Watcher Score'**
  String get filterGroupMinScore;

  /// No description provided for @filterGroupAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced (Premium)'**
  String get filterGroupAdvanced;

  /// No description provided for @filterTypeMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get filterTypeMovie;

  /// No description provided for @filterTypeSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get filterTypeSeries;

  /// No description provided for @filterDurationShort.
  ///
  /// In en, this message translates to:
  /// **'Short (<90m)'**
  String get filterDurationShort;

  /// No description provided for @filterDurationMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium (90–150m)'**
  String get filterDurationMedium;

  /// No description provided for @filterDurationLong.
  ///
  /// In en, this message translates to:
  /// **'Long (>150m)'**
  String get filterDurationLong;

  /// No description provided for @filterAdvancedDropoff.
  ///
  /// In en, this message translates to:
  /// **'Low drop-off'**
  String get filterAdvancedDropoff;

  /// No description provided for @filterAdvancedTrust.
  ///
  /// In en, this message translates to:
  /// **'High trust'**
  String get filterAdvancedTrust;

  /// No description provided for @filterAdvancedConsensus.
  ///
  /// In en, this message translates to:
  /// **'High consensus'**
  String get filterAdvancedConsensus;

  /// No description provided for @filterAdvancedYearRange.
  ///
  /// In en, this message translates to:
  /// **'Year range'**
  String get filterAdvancedYearRange;

  /// No description provided for @filterAdvancedOtherRegions.
  ///
  /// In en, this message translates to:
  /// **'Other regions'**
  String get filterAdvancedOtherRegions;

  /// No description provided for @contentMeta.
  ///
  /// In en, this message translates to:
  /// **'{year} · {platforms}'**
  String contentMeta(int year, String platforms);

  /// No description provided for @contentDurationMin.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String contentDurationMin(int minutes);

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get tabDiscover;

  /// No description provided for @tabAi.
  ///
  /// In en, this message translates to:
  /// **'Remoty'**
  String get tabAi;

  /// No description provided for @tabCreators.
  ///
  /// In en, this message translates to:
  /// **'Creators'**
  String get tabCreators;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @tabVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get tabVault;

  /// No description provided for @vaultTitle.
  ///
  /// In en, this message translates to:
  /// **'My Vault'**
  String get vaultTitle;

  /// No description provided for @vaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your personal library.'**
  String get vaultSubtitle;

  /// No description provided for @vaultTabLoved.
  ///
  /// In en, this message translates to:
  /// **'Loved'**
  String get vaultTabLoved;

  /// No description provided for @vaultTabRanking.
  ///
  /// In en, this message translates to:
  /// **'Ranking'**
  String get vaultTabRanking;

  /// No description provided for @vaultTabWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get vaultTabWatchlist;

  /// No description provided for @vaultTabNotForMe.
  ///
  /// In en, this message translates to:
  /// **'Not for me'**
  String get vaultTabNotForMe;

  /// No description provided for @vaultTabFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get vaultTabFollowing;

  /// No description provided for @vaultEmptyLoved.
  ///
  /// In en, this message translates to:
  /// **'Nothing loved yet. Rate a title 5★ to add it here.'**
  String get vaultEmptyLoved;

  /// No description provided for @vaultEmptyRanking.
  ///
  /// In en, this message translates to:
  /// **'Rate titles and see them here sorted by stars.'**
  String get vaultEmptyRanking;

  /// No description provided for @vaultEmptyWatchlist.
  ///
  /// In en, this message translates to:
  /// **'Your watchlist is empty. Tap 🔖 to save titles for later.'**
  String get vaultEmptyWatchlist;

  /// No description provided for @vaultEmptyNotForMe.
  ///
  /// In en, this message translates to:
  /// **'Nothing dismissed yet. Tap \'Not for me\' on a title to hide it.'**
  String get vaultEmptyNotForMe;

  /// No description provided for @vaultEmptyFollowing.
  ///
  /// In en, this message translates to:
  /// **'You\'re not following anyone yet. Visit Creators to follow trusted voices.'**
  String get vaultEmptyFollowing;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAvatarTitle.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get settingsAvatarTitle;

  /// No description provided for @settingsAvatarHint.
  ///
  /// In en, this message translates to:
  /// **'Pick initials, a default avatar, or upload your own.'**
  String get settingsAvatarHint;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language & region'**
  String get settingsLanguageSection;

  /// No description provided for @settingsUiLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsUiLanguage;

  /// No description provided for @settingsUiLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'The language used across the app interface.'**
  String get settingsUiLanguageHint;

  /// No description provided for @settingsContentLanguage.
  ///
  /// In en, this message translates to:
  /// **'Content language'**
  String get settingsContentLanguage;

  /// No description provided for @settingsContentLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Language used for synopses and reviews when available.'**
  String get settingsContentLanguageHint;

  /// No description provided for @settingsCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get settingsCountry;

  /// No description provided for @settingsCountryHint.
  ///
  /// In en, this message translates to:
  /// **'Used to show what\'s available on your streaming platforms.'**
  String get settingsCountryHint;

  /// No description provided for @prefAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (system)'**
  String get prefAuto;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get langSpanish;

  /// No description provided for @countryUs.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get countryUs;

  /// No description provided for @countryMx.
  ///
  /// In en, this message translates to:
  /// **'Mexico'**
  String get countryMx;

  /// No description provided for @countryEs.
  ///
  /// In en, this message translates to:
  /// **'Spain'**
  String get countryEs;

  /// No description provided for @countryAr.
  ///
  /// In en, this message translates to:
  /// **'Argentina'**
  String get countryAr;

  /// No description provided for @countryCo.
  ///
  /// In en, this message translates to:
  /// **'Colombia'**
  String get countryCo;

  /// No description provided for @countryCl.
  ///
  /// In en, this message translates to:
  /// **'Chile'**
  String get countryCl;

  /// No description provided for @countryUk.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get countryUk;

  /// No description provided for @countryCa.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get countryCa;

  /// No description provided for @countryBr.
  ///
  /// In en, this message translates to:
  /// **'Brazil'**
  String get countryBr;

  /// No description provided for @countryIe.
  ///
  /// In en, this message translates to:
  /// **'Ireland'**
  String get countryIe;

  /// No description provided for @countryFr.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get countryFr;

  /// No description provided for @countryDe.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get countryDe;

  /// No description provided for @countryIt.
  ///
  /// In en, this message translates to:
  /// **'Italy'**
  String get countryIt;

  /// No description provided for @countryNl.
  ///
  /// In en, this message translates to:
  /// **'Netherlands'**
  String get countryNl;

  /// No description provided for @countryPt.
  ///
  /// In en, this message translates to:
  /// **'Portugal'**
  String get countryPt;

  /// No description provided for @countrySe.
  ///
  /// In en, this message translates to:
  /// **'Sweden'**
  String get countrySe;

  /// No description provided for @countryOther.
  ///
  /// In en, this message translates to:
  /// **'Rest of the world'**
  String get countryOther;

  /// No description provided for @profileSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileSectionAccount;

  /// No description provided for @profileSectionProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileSectionProfile;

  /// No description provided for @profileSectionPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get profileSectionPreferences;

  /// No description provided for @profileSectionPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get profileSectionPremium;

  /// No description provided for @profileSectionSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get profileSectionSupport;

  /// No description provided for @profileSectionLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get profileSectionLegal;

  /// No description provided for @profileSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileSectionAbout;

  /// No description provided for @profileNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get profileNotSignedIn;

  /// No description provided for @profileNotSignedInSub.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your ratings and takes across devices.'**
  String get profileNotSignedInSub;

  /// No description provided for @profileSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get profileSignIn;

  /// No description provided for @profileAlias.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get profileAlias;

  /// No description provided for @profileAliasNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set yet'**
  String get profileAliasNotSet;

  /// No description provided for @profileAliasChange.
  ///
  /// In en, this message translates to:
  /// **'Change alias'**
  String get profileAliasChange;

  /// No description provided for @profileAliasCooldown.
  ///
  /// In en, this message translates to:
  /// **'You can change your alias every 90 days.'**
  String get profileAliasCooldown;

  /// No description provided for @profileTierFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get profileTierFree;

  /// No description provided for @profileTierPro.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get profileTierPro;

  /// No description provided for @profileUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium'**
  String get profileUpgrade;

  /// No description provided for @profileManageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get profileManageSubscription;

  /// No description provided for @profileHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get profileHelpCenter;

  /// No description provided for @profileContactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get profileContactUs;

  /// No description provided for @profileSendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get profileSendFeedback;

  /// No description provided for @profileRateApp.
  ///
  /// In en, this message translates to:
  /// **'Rate Flixscope'**
  String get profileRateApp;

  /// No description provided for @profileTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get profileTerms;

  /// No description provided for @profilePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get profilePrivacy;

  /// No description provided for @profileLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get profileLicenses;

  /// No description provided for @profileVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get profileVersion;

  /// No description provided for @profileBuild.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get profileBuild;

  /// No description provided for @profileComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get profileComingSoon;

  /// No description provided for @profileSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get profileSignOut;

  /// No description provided for @creatorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Creators'**
  String get creatorsTitle;

  /// No description provided for @creatorsTagline.
  ///
  /// In en, this message translates to:
  /// **'Trusted voices. Real takes. No algorithms.'**
  String get creatorsTagline;

  /// No description provided for @creatorsFeaturedSkip.
  ///
  /// In en, this message translates to:
  /// **'NOT worth your time'**
  String get creatorsFeaturedSkip;

  /// No description provided for @creatorsSectionAll.
  ///
  /// In en, this message translates to:
  /// **'All creators'**
  String get creatorsSectionAll;

  /// No description provided for @creatorsSectionLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest takes'**
  String get creatorsSectionLatest;

  /// No description provided for @creatorsCurated.
  ///
  /// In en, this message translates to:
  /// **'Curated'**
  String get creatorsCurated;

  /// No description provided for @creatorsFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get creatorsFollow;

  /// No description provided for @creatorsFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get creatorsFollowing;

  /// No description provided for @creatorsFollowersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} followers'**
  String creatorsFollowersCount(int count);

  /// No description provided for @creatorVerdictWorthIt.
  ///
  /// In en, this message translates to:
  /// **'Worth it'**
  String get creatorVerdictWorthIt;

  /// No description provided for @creatorVerdictSkipIt.
  ///
  /// In en, this message translates to:
  /// **'Skip it'**
  String get creatorVerdictSkipIt;

  /// No description provided for @creatorVerdictQuickTake.
  ///
  /// In en, this message translates to:
  /// **'Quick take'**
  String get creatorVerdictQuickTake;

  /// No description provided for @creatorActionWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get creatorActionWatch;

  /// No description provided for @creatorActionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get creatorActionSave;

  /// No description provided for @creatorActionHelpful.
  ///
  /// In en, this message translates to:
  /// **'Helpful'**
  String get creatorActionHelpful;

  /// No description provided for @creatorActionNotHelpful.
  ///
  /// In en, this message translates to:
  /// **'Not helpful'**
  String get creatorActionNotHelpful;

  /// No description provided for @creatorDetailTakes.
  ///
  /// In en, this message translates to:
  /// **'Takes'**
  String get creatorDetailTakes;

  /// No description provided for @creatorTakeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your list'**
  String get creatorTakeSaved;

  /// No description provided for @creatorTakeHelpfulRecorded.
  ///
  /// In en, this message translates to:
  /// **'Thanks for the signal'**
  String get creatorTakeHelpfulRecorded;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Take control'**
  String get splashTagline;

  /// No description provided for @splashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We don\'t show you what\'s popular.\nWe show you what\'s worth your time.'**
  String get splashSubtitle;

  /// No description provided for @splashCta.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get splashCta;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask Remoty'**
  String get chatTitle;

  /// No description provided for @chatTagline.
  ///
  /// In en, this message translates to:
  /// **'Your streaming companion.'**
  String get chatTagline;

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'What are you in the mood for?'**
  String get chatInputHint;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Hey! I\'m Remoty'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'I know the catalog, your vault, and what creators say. Ask me anything about what to watch.'**
  String get chatEmptyBody;

  /// No description provided for @chatQuickShort.
  ///
  /// In en, this message translates to:
  /// **'Short tonight'**
  String get chatQuickShort;

  /// No description provided for @chatQuickBinge.
  ///
  /// In en, this message translates to:
  /// **'Binge this weekend'**
  String get chatQuickBinge;

  /// No description provided for @chatQuickSad.
  ///
  /// In en, this message translates to:
  /// **'Something emotional'**
  String get chatQuickSad;

  /// No description provided for @chatQuickSkip.
  ///
  /// In en, this message translates to:
  /// **'What should I skip?'**
  String get chatQuickSkip;

  /// No description provided for @chatQuickVault.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get chatQuickVault;

  /// No description provided for @chatQuickRanking.
  ///
  /// In en, this message translates to:
  /// **'My best rated'**
  String get chatQuickRanking;

  /// No description provided for @chatQuickCreators.
  ///
  /// In en, this message translates to:
  /// **'Top creator picks'**
  String get chatQuickCreators;

  /// No description provided for @chatQuotaRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No questions left today} =1{1 question left today} other{{count} questions left today}}'**
  String chatQuotaRemaining(int count);

  /// No description provided for @chatQuotaPro.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get chatQuotaPro;

  /// No description provided for @chatQuotaExhaustedTitle.
  ///
  /// In en, this message translates to:
  /// **'You’ve used your 5 free questions today'**
  String get chatQuotaExhaustedTitle;

  /// No description provided for @chatQuotaExhaustedBody.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium for unlimited Ask Remoty and Decision Assistant.'**
  String get chatQuotaExhaustedBody;

  /// No description provided for @chatGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to Ask Remoty'**
  String get chatGuideTitle;

  /// No description provided for @chatGuideCategory1Title.
  ///
  /// In en, this message translates to:
  /// **'Mood & Genre'**
  String get chatGuideCategory1Title;

  /// No description provided for @chatGuideCategory1Desc.
  ///
  /// In en, this message translates to:
  /// **'Tell me how you feel or what genre you want — I\'ll find the best match.'**
  String get chatGuideCategory1Desc;

  /// No description provided for @chatGuideCategory2Title.
  ///
  /// In en, this message translates to:
  /// **'Favorites & Vault'**
  String get chatGuideCategory2Title;

  /// No description provided for @chatGuideCategory2Desc.
  ///
  /// In en, this message translates to:
  /// **'Ask about your favorites, watchlist, or what you\'ve dismissed.'**
  String get chatGuideCategory2Desc;

  /// No description provided for @chatGuideCategory5Title.
  ///
  /// In en, this message translates to:
  /// **'Your Rankings'**
  String get chatGuideCategory5Title;

  /// No description provided for @chatGuideCategory5Desc.
  ///
  /// In en, this message translates to:
  /// **'Check your best or worst star ratings from your vault.'**
  String get chatGuideCategory5Desc;

  /// No description provided for @chatGuideCategory3Title.
  ///
  /// In en, this message translates to:
  /// **'Creator Takes'**
  String get chatGuideCategory3Title;

  /// No description provided for @chatGuideCategory3Desc.
  ///
  /// In en, this message translates to:
  /// **'See what trusted creators are recommending or skipping.'**
  String get chatGuideCategory3Desc;

  /// No description provided for @chatGuideCategory4Title.
  ///
  /// In en, this message translates to:
  /// **'Platform Search'**
  String get chatGuideCategory4Title;

  /// No description provided for @chatGuideCategory4Desc.
  ///
  /// In en, this message translates to:
  /// **'Ask what\'s good on Netflix, Max, Disney+, or any platform.'**
  String get chatGuideCategory4Desc;

  /// No description provided for @chatClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation?'**
  String get chatClearTitle;

  /// No description provided for @chatClearBody.
  ///
  /// In en, this message translates to:
  /// **'This will remove all messages. This action can\'t be undone.'**
  String get chatClearBody;

  /// No description provided for @chatClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get chatClearConfirm;

  /// No description provided for @chatClearCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get chatClearCancel;

  /// No description provided for @longQuizTitle.
  ///
  /// In en, this message translates to:
  /// **'Tune your taste'**
  String get longQuizTitle;

  /// No description provided for @longQuizIntro.
  ///
  /// In en, this message translates to:
  /// **'A few minutes of input unlocks classic gems and sharper picks for you.'**
  String get longQuizIntro;

  /// No description provided for @longQuizStepGrid.
  ///
  /// In en, this message translates to:
  /// **'Which of these have you seen?'**
  String get longQuizStepGrid;

  /// No description provided for @longQuizStepGridSub.
  ///
  /// In en, this message translates to:
  /// **'Tap once for seen, twice if you loved it. We use this to find your blind spots.'**
  String get longQuizStepGridSub;

  /// No description provided for @longQuizStepThemes.
  ///
  /// In en, this message translates to:
  /// **'What do you love?'**
  String get longQuizStepThemes;

  /// No description provided for @longQuizStepThemesSub.
  ///
  /// In en, this message translates to:
  /// **'Directors, themes, moods — anything. Comma-separated.'**
  String get longQuizStepThemesSub;

  /// No description provided for @longQuizThemesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Denis Villeneuve, slow burn, neo-noir, 70s paranoia'**
  String get longQuizThemesHint;

  /// No description provided for @longQuizLegendSeen.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get longQuizLegendSeen;

  /// No description provided for @longQuizLegendLoved.
  ///
  /// In en, this message translates to:
  /// **'Loved'**
  String get longQuizLegendLoved;

  /// No description provided for @longQuizBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get longQuizBack;

  /// No description provided for @longQuizNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get longQuizNext;

  /// No description provided for @longQuizFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get longQuizFinish;

  /// No description provided for @longQuizSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get longQuizSkip;

  /// No description provided for @longQuizDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile tuned'**
  String get longQuizDoneTitle;

  /// No description provided for @longQuizDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Your 5 Gems are about to get much smarter.'**
  String get longQuizDoneBody;

  /// No description provided for @profileStrengthFast.
  ///
  /// In en, this message translates to:
  /// **'Fast profile'**
  String get profileStrengthFast;

  /// No description provided for @profileStrengthLong.
  ///
  /// In en, this message translates to:
  /// **'Full profile'**
  String get profileStrengthLong;

  /// No description provided for @profileStrengthCtaComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get profileStrengthCtaComplete;

  /// No description provided for @profileStrengthCtaDone.
  ///
  /// In en, this message translates to:
  /// **'Full profile — classics unlocked'**
  String get profileStrengthCtaDone;

  /// No description provided for @profileStrengthHint.
  ///
  /// In en, this message translates to:
  /// **'Unlocks classic gems and sharper recommendations.'**
  String get profileStrengthHint;

  /// No description provided for @discoverLongQuizBanner.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find what you want?'**
  String get discoverLongQuizBanner;

  /// No description provided for @discoverLongQuizBannerSub.
  ///
  /// In en, this message translates to:
  /// **'Spend 2 minutes tuning your taste and we\'ll find it for you.'**
  String get discoverLongQuizBannerSub;

  /// No description provided for @onboardingWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Flixscope'**
  String get onboardingWelcome;

  /// No description provided for @onboardingWelcomeSub.
  ///
  /// In en, this message translates to:
  /// **'30 seconds and we\'ll start finding what\'s worth your time.'**
  String get onboardingWelcomeSub;

  /// No description provided for @onboardingStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Where do you watch from?'**
  String get onboardingStep1Title;

  /// No description provided for @onboardingStep1Sub.
  ///
  /// In en, this message translates to:
  /// **'This determines what\'s available on your streaming platforms.'**
  String get onboardingStep1Sub;

  /// No description provided for @onboardingStep2Title.
  ///
  /// In en, this message translates to:
  /// **'What do you pay for?'**
  String get onboardingStep2Title;

  /// No description provided for @onboardingStep2Sub.
  ///
  /// In en, this message translates to:
  /// **'Pick every platform you actually use. We\'ll never recommend something you can\'t watch.'**
  String get onboardingStep2Sub;

  /// No description provided for @onboardingStep3Title.
  ///
  /// In en, this message translates to:
  /// **'What do you love?'**
  String get onboardingStep3Title;

  /// No description provided for @onboardingStep3Sub.
  ///
  /// In en, this message translates to:
  /// **'Pick 3 or more. You can change this later.'**
  String get onboardingStep3Sub;

  /// No description provided for @onboardingStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepOf(int current, int total);

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Start watching'**
  String get onboardingFinish;

  /// No description provided for @onboardingPlatformsHint.
  ///
  /// In en, this message translates to:
  /// **'Pick at least 1.'**
  String get onboardingPlatformsHint;

  /// No description provided for @onboardingGenresHint.
  ///
  /// In en, this message translates to:
  /// **'Pick at least 3.'**
  String get onboardingGenresHint;

  /// No description provided for @genreDrama.
  ///
  /// In en, this message translates to:
  /// **'Drama'**
  String get genreDrama;

  /// No description provided for @genreComedy.
  ///
  /// In en, this message translates to:
  /// **'Comedy'**
  String get genreComedy;

  /// No description provided for @genreThriller.
  ///
  /// In en, this message translates to:
  /// **'Thriller'**
  String get genreThriller;

  /// No description provided for @genreSciFi.
  ///
  /// In en, this message translates to:
  /// **'Sci-Fi'**
  String get genreSciFi;

  /// No description provided for @genreRomance.
  ///
  /// In en, this message translates to:
  /// **'Romance'**
  String get genreRomance;

  /// No description provided for @genreAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get genreAction;

  /// No description provided for @genreHorror.
  ///
  /// In en, this message translates to:
  /// **'Horror'**
  String get genreHorror;

  /// No description provided for @genreDocumentary.
  ///
  /// In en, this message translates to:
  /// **'Documentary'**
  String get genreDocumentary;

  /// No description provided for @genreAnimation.
  ///
  /// In en, this message translates to:
  /// **'Animation'**
  String get genreAnimation;

  /// No description provided for @genreCrime.
  ///
  /// In en, this message translates to:
  /// **'Crime'**
  String get genreCrime;

  /// No description provided for @genreHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get genreHistory;

  /// No description provided for @genreMystery.
  ///
  /// In en, this message translates to:
  /// **'Mystery'**
  String get genreMystery;

  /// No description provided for @contentBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get contentBack;

  /// No description provided for @contentSectionSignals.
  ///
  /// In en, this message translates to:
  /// **'Signals'**
  String get contentSectionSignals;

  /// No description provided for @contentSectionSynopsis.
  ///
  /// In en, this message translates to:
  /// **'Synopsis'**
  String get contentSectionSynopsis;

  /// No description provided for @contentSectionFansSay.
  ///
  /// In en, this message translates to:
  /// **'Flixscope Fans Say'**
  String get contentSectionFansSay;

  /// No description provided for @contentSectionQuickTakes.
  ///
  /// In en, this message translates to:
  /// **'Quick takes'**
  String get contentSectionQuickTakes;

  /// No description provided for @contentSectionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available on'**
  String get contentSectionAvailable;

  /// No description provided for @contentWatcherScore.
  ///
  /// In en, this message translates to:
  /// **'Watcher Score'**
  String get contentWatcherScore;

  /// No description provided for @contentTrustScore.
  ///
  /// In en, this message translates to:
  /// **'Trust'**
  String get contentTrustScore;

  /// No description provided for @contentVariance.
  ///
  /// In en, this message translates to:
  /// **'Variance'**
  String get contentVariance;

  /// No description provided for @contentCompletion.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get contentCompletion;

  /// No description provided for @fansSayCompletion.
  ///
  /// In en, this message translates to:
  /// **'{pct}% finished it'**
  String fansSayCompletion(int pct);

  /// No description provided for @fansSayWorth.
  ///
  /// In en, this message translates to:
  /// **'{pct}% said worth their time'**
  String fansSayWorth(int pct);

  /// No description provided for @fansSayRating.
  ///
  /// In en, this message translates to:
  /// **'{rating} / 5 average'**
  String fansSayRating(String rating);

  /// No description provided for @fansSaySample.
  ///
  /// In en, this message translates to:
  /// **'n = {count} verified watchers'**
  String fansSaySample(int count);

  /// No description provided for @fansSayNotEnough.
  ///
  /// In en, this message translates to:
  /// **'Not enough verified signal yet.'**
  String get fansSayNotEnough;

  /// No description provided for @contentActionRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get contentActionRate;

  /// No description provided for @contentActionWorth.
  ///
  /// In en, this message translates to:
  /// **'Worth it?'**
  String get contentActionWorth;

  /// No description provided for @contentActionTake.
  ///
  /// In en, this message translates to:
  /// **'Write a take'**
  String get contentActionTake;

  /// No description provided for @contentLoginGate.
  ///
  /// In en, this message translates to:
  /// **'Sign in to rate and share your take. Your signal helps other viewers find joyas.'**
  String get contentLoginGate;

  /// No description provided for @contentLoginGateCta.
  ///
  /// In en, this message translates to:
  /// **'Sign in later'**
  String get contentLoginGateCta;

  /// No description provided for @contentNoTakes.
  ///
  /// In en, this message translates to:
  /// **'No quick takes yet. Be the first verified watcher.'**
  String get contentNoTakes;

  /// No description provided for @contentMyRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get contentMyRating;

  /// No description provided for @contentNotForMe.
  ///
  /// In en, this message translates to:
  /// **'Not for me'**
  String get contentNotForMe;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
