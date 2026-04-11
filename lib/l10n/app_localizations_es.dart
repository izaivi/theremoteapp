// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Flixscope';

  @override
  String get homeTitle => 'Lo que importa ahora';

  @override
  String get homeTagline =>
      'No te mostramos lo popular. Te mostramos lo que vale tu tiempo.';

  @override
  String get sectionTrendingNow => 'En tendencia';

  @override
  String get sectionTrendingSubtitle => 'Popular y además buena.';

  @override
  String get sectionExploding => 'Explotando';

  @override
  String get sectionExplodingSubtitle => 'Ganando impulso rápido.';

  @override
  String get sectionQuickDecision => 'Decisión rápida';

  @override
  String get sectionQuickDecisionSubtitle => 'Cortas, buenas, listas para hoy.';

  @override
  String get sectionDontWaste => 'No pierdas tu tiempo';

  @override
  String get sectionDontWasteSubtitle =>
      'Mucho ruido, poca recompensa. Mejor sáltalas.';

  @override
  String get sectionFiveGems => 'Tus 5 joyas del día';

  @override
  String fiveGemsLockedTease(int count) {
    return '$count joyas más esperándote hoy';
  }

  @override
  String get fiveGemsLockedCta => 'Ver con Premium';

  @override
  String get paywallTitle => 'Flixscope Premium';

  @override
  String get paywallSubtitle => 'Decide mejor, y antes que el resto.';

  @override
  String get paywallFeatureGems => 'Las 5 joyas completas + Decision Assistant';

  @override
  String get paywallFeatureChat => 'AI Chat ilimitado';

  @override
  String get paywallFeatureFilters => 'Filtros avanzados (drop-off, trust)';

  @override
  String get paywallFeatureExploding => 'Early access a Explotando';

  @override
  String get paywallFeatureQuickTake => 'Escribe Quick Takes (≤230 chars)';

  @override
  String get paywallFeatureNoAds => 'Sin anuncios';

  @override
  String get paywallCta => 'Actualizar';

  @override
  String get paywallLater => 'Ahora no';

  @override
  String get discoverTitle => 'Descubrir';

  @override
  String get discoverSearchHint => 'Busca una película o serie…';

  @override
  String get discoverFilters => 'Filtros';

  @override
  String get discoverClearFilters => 'Limpiar';

  @override
  String get discoverSectionPopularRegion => 'Popular en tu región';

  @override
  String get discoverSectionUnderRadar => 'Bajo el radar';

  @override
  String get discoverSectionUnder90 => 'Menos de 90 minutos';

  @override
  String get discoverSectionBingeable => 'Termínalas este finde';

  @override
  String get discoverEmpty => 'Nada coincide con esos filtros.';

  @override
  String discoverResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Sin resultados',
    );
    return '$_temp0';
  }

  @override
  String get filterGroupGenre => 'Género';

  @override
  String get filterGroupPlatform => 'Plataforma';

  @override
  String get filterGroupType => 'Tipo';

  @override
  String get filterGroupDuration => 'Duración';

  @override
  String get filterGroupMinScore => 'Watcher Score mínimo';

  @override
  String get filterGroupAdvanced => 'Avanzados (Premium)';

  @override
  String get filterTypeMovie => 'Película';

  @override
  String get filterTypeSeries => 'Serie';

  @override
  String get filterDurationShort => 'Corto (<90m)';

  @override
  String get filterDurationMedium => 'Medio (90–150m)';

  @override
  String get filterDurationLong => 'Largo (>150m)';

  @override
  String get filterAdvancedDropoff => 'Bajo drop-off';

  @override
  String get filterAdvancedTrust => 'Alta confianza';

  @override
  String get filterAdvancedConsensus => 'Alto consenso';

  @override
  String get filterAdvancedYearRange => 'Rango de años';

  @override
  String get filterAdvancedOtherRegions => 'Otras regiones';

  @override
  String contentMeta(int year, String platforms) {
    return '$year · $platforms';
  }

  @override
  String contentDurationMin(int minutes) {
    return '$minutes min';
  }

  @override
  String get tabHome => 'Inicio';

  @override
  String get tabDiscover => 'Descubrir';

  @override
  String get tabAi => 'IA';

  @override
  String get tabCreators => 'Creadores';

  @override
  String get tabProfile => 'Perfil';

  @override
  String get tabVault => 'Bóveda';

  @override
  String get vaultTitle => 'Mi Bóveda';

  @override
  String get vaultSubtitle => 'Tu biblioteca personal.';

  @override
  String get vaultTabLoved => 'Favoritas';

  @override
  String get vaultTabRanking => 'Ranking';

  @override
  String get vaultTabWatchlist => 'Para ver';

  @override
  String get vaultTabNotForMe => 'No para mí';

  @override
  String get vaultTabFollowing => 'Siguiendo';

  @override
  String get vaultEmptyLoved =>
      'Aún nada aquí. Califica un título con 5★ para guardarlo.';

  @override
  String get vaultEmptyRanking =>
      'Califica títulos y míralos aquí ordenados por estrellas.';

  @override
  String get vaultEmptyWatchlist =>
      'Tu lista está vacía. Toca 🔖 para guardar títulos para después.';

  @override
  String get vaultEmptyNotForMe =>
      'Nada descartado aún. Toca \'No para mí\' en un título para ocultarlo.';

  @override
  String get vaultEmptyFollowing =>
      'No sigues a nadie aún. Visita Creadores para seguir voces confiables.';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAvatarTitle => 'Avatar';

  @override
  String get settingsAvatarHint =>
      'Elige iniciales, un avatar por defecto, o sube tu foto.';

  @override
  String get profileTitle => 'Perfil';

  @override
  String get settingsLanguageSection => 'Idioma y región';

  @override
  String get settingsUiLanguage => 'Idioma de la app';

  @override
  String get settingsUiLanguageHint => 'Idioma usado en toda la interfaz.';

  @override
  String get settingsContentLanguage => 'Idioma del contenido';

  @override
  String get settingsContentLanguageHint =>
      'Idioma de sinopsis y reseñas cuando estén disponibles.';

  @override
  String get settingsCountry => 'País';

  @override
  String get settingsCountryHint =>
      'Determina qué está disponible en tus plataformas de streaming.';

  @override
  String get prefAuto => 'Automático (sistema)';

  @override
  String get langEnglish => 'Inglés';

  @override
  String get langSpanish => 'Español';

  @override
  String get countryUs => 'Estados Unidos';

  @override
  String get countryMx => 'México';

  @override
  String get countryEs => 'España';

  @override
  String get countryAr => 'Argentina';

  @override
  String get countryCo => 'Colombia';

  @override
  String get countryCl => 'Chile';

  @override
  String get countryUk => 'Reino Unido';

  @override
  String get countryCa => 'Canadá';

  @override
  String get countryBr => 'Brasil';

  @override
  String get countryIe => 'Irlanda';

  @override
  String get countryFr => 'Francia';

  @override
  String get countryDe => 'Alemania';

  @override
  String get countryIt => 'Italia';

  @override
  String get countryNl => 'Países Bajos';

  @override
  String get countryPt => 'Portugal';

  @override
  String get countrySe => 'Suecia';

  @override
  String get countryOther => 'Resto del mundo';

  @override
  String get profileSectionAccount => 'Cuenta';

  @override
  String get profileSectionProfile => 'Perfil';

  @override
  String get profileSectionPreferences => 'Preferencias';

  @override
  String get profileSectionPremium => 'Premium';

  @override
  String get profileSectionSupport => 'Soporte';

  @override
  String get profileSectionLegal => 'Legal';

  @override
  String get profileSectionAbout => 'Acerca de';

  @override
  String get profileNotSignedIn => 'Sin iniciar sesión';

  @override
  String get profileNotSignedInSub =>
      'Inicia sesión para sincronizar tus calificaciones y comentarios entre dispositivos.';

  @override
  String get profileSignIn => 'Iniciar sesión';

  @override
  String get profileAlias => 'Alias';

  @override
  String get profileAliasNotSet => 'Aún sin definir';

  @override
  String get profileAliasChange => 'Cambiar alias';

  @override
  String get profileAliasCooldown => 'Puedes cambiar tu alias cada 90 días.';

  @override
  String get profileTierFree => 'Gratis';

  @override
  String get profileTierPro => 'Premium';

  @override
  String get profileUpgrade => 'Actualizar a Premium';

  @override
  String get profileManageSubscription => 'Administrar suscripción';

  @override
  String get profileHelpCenter => 'Centro de ayuda';

  @override
  String get profileContactUs => 'Contáctanos';

  @override
  String get profileSendFeedback => 'Enviar comentarios';

  @override
  String get profileRateApp => 'Califica Flixscope';

  @override
  String get profileTerms => 'Términos del servicio';

  @override
  String get profilePrivacy => 'Política de privacidad';

  @override
  String get profileLicenses => 'Licencias de código abierto';

  @override
  String get profileVersion => 'Versión';

  @override
  String get profileBuild => 'Build';

  @override
  String get profileComingSoon => 'Próximamente';

  @override
  String get profileSignOut => 'Cerrar sesión';

  @override
  String get creatorsTitle => 'Creadores';

  @override
  String get creatorsTagline =>
      'Voces de confianza. Opiniones reales. Sin algoritmos.';

  @override
  String get creatorsFeaturedSkip => 'NO vale tu tiempo';

  @override
  String get creatorsSectionAll => 'Todos los creadores';

  @override
  String get creatorsSectionLatest => 'Últimas opiniones';

  @override
  String get creatorsCurated => 'Curado';

  @override
  String get creatorsFollow => 'Seguir';

  @override
  String get creatorsFollowing => 'Siguiendo';

  @override
  String creatorsFollowersCount(int count) {
    return '$count seguidores';
  }

  @override
  String get creatorVerdictWorthIt => 'Vale la pena';

  @override
  String get creatorVerdictSkipIt => 'Sáltatelo';

  @override
  String get creatorVerdictQuickTake => 'Opinión rápida';

  @override
  String get creatorActionWatch => 'Ver';

  @override
  String get creatorActionSave => 'Guardar';

  @override
  String get creatorActionHelpful => 'Útil';

  @override
  String get creatorActionNotHelpful => 'No útil';

  @override
  String get creatorDetailTakes => 'Opiniones';

  @override
  String get creatorTakeSaved => 'Guardado en tu lista';

  @override
  String get creatorTakeHelpfulRecorded => 'Gracias por tu señal';

  @override
  String get splashTagline => 'Toma el control';

  @override
  String get splashSubtitle =>
      'No te mostramos lo popular.\nTe mostramos lo que vale tu tiempo.';

  @override
  String get splashCta => 'Comenzar';

  @override
  String get chatTitle => 'Chat IA';

  @override
  String get chatTagline => 'Pregúntame qué ver esta noche.';

  @override
  String get chatInputHint => '¿Qué te provoca ver?';

  @override
  String get chatSend => 'Enviar';

  @override
  String get chatEmptyTitle => 'Tu asistente de decisión';

  @override
  String get chatEmptyBody =>
      'Prueba: \"algo corto para esta noche\", \"una serie prestige\" o \"qué me salto\".';

  @override
  String get chatQuickShort => 'Corto esta noche';

  @override
  String get chatQuickBinge => 'Binge este fin';

  @override
  String get chatQuickSad => 'Algo emocional';

  @override
  String get chatQuickSkip => '¿Qué me salto?';

  @override
  String chatQuotaRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count preguntas restantes hoy',
      one: '1 pregunta restante hoy',
      zero: 'Sin preguntas restantes hoy',
    );
    return '$_temp0';
  }

  @override
  String get chatQuotaPro => 'Ilimitado';

  @override
  String get chatQuotaExhaustedTitle => 'Usaste tus 5 preguntas gratis de hoy';

  @override
  String get chatQuotaExhaustedBody =>
      'Actualiza a Premium para chat IA ilimitado y el Decision Assistant.';

  @override
  String get longQuizTitle => 'Afina tu gusto';

  @override
  String get longQuizIntro =>
      'Unos minutos nos permiten desbloquear joyas clásicas y recomendaciones más precisas para ti.';

  @override
  String get longQuizStepGrid => '¿Cuáles de estos has visto?';

  @override
  String get longQuizStepGridSub =>
      'Un toque si la viste, dos si la amaste. Esto nos ayuda a encontrar tus puntos ciegos.';

  @override
  String get longQuizStepThemes => '¿Qué te encanta?';

  @override
  String get longQuizStepThemesSub =>
      'Directores, temas, estados de ánimo — lo que quieras. Separa con comas.';

  @override
  String get longQuizThemesHint =>
      'ej. Denis Villeneuve, slow burn, neo-noir, paranoia setentera';

  @override
  String get longQuizLegendSeen => 'Vista';

  @override
  String get longQuizLegendLoved => 'Amada';

  @override
  String get longQuizBack => 'Atrás';

  @override
  String get longQuizNext => 'Siguiente';

  @override
  String get longQuizFinish => 'Terminar';

  @override
  String get longQuizSkip => 'Saltar por ahora';

  @override
  String get longQuizDoneTitle => 'Perfil afinado';

  @override
  String get longQuizDoneBody =>
      'Tus 5 Gems están a punto de ponerse mucho más inteligentes.';

  @override
  String get profileStrengthFast => 'Perfil rápido';

  @override
  String get profileStrengthLong => 'Perfil completo';

  @override
  String get profileStrengthCtaComplete => 'Completa tu perfil';

  @override
  String get profileStrengthCtaDone =>
      'Perfil completo — clásicos desbloqueados';

  @override
  String get profileStrengthHint =>
      'Desbloquea joyas clásicas y recomendaciones más precisas.';

  @override
  String get discoverLongQuizBanner => '¿No encuentras lo que buscas?';

  @override
  String get discoverLongQuizBannerSub =>
      'Dedica 2 minutos a afinar tu gusto y lo encontramos por ti.';

  @override
  String get onboardingWelcome => 'Bienvenido a Flixscope';

  @override
  String get onboardingWelcomeSub =>
      '30 segundos y empezamos a encontrar lo que vale tu tiempo.';

  @override
  String get onboardingStep1Title => '¿Desde dónde ves?';

  @override
  String get onboardingStep1Sub =>
      'Esto determina qué está disponible en tus plataformas.';

  @override
  String get onboardingStep2Title => '¿Qué estás pagando?';

  @override
  String get onboardingStep2Sub =>
      'Elige cada plataforma que realmente usas. Nunca te recomendamos algo que no puedas ver.';

  @override
  String get onboardingStep3Title => '¿Qué te gusta?';

  @override
  String get onboardingStep3Sub => 'Elige 3 o más. Puedes cambiarlo después.';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get onboardingBack => 'Atrás';

  @override
  String get onboardingNext => 'Siguiente';

  @override
  String get onboardingFinish => 'Empezar';

  @override
  String get onboardingPlatformsHint => 'Elige al menos 1.';

  @override
  String get onboardingGenresHint => 'Elige al menos 3.';

  @override
  String get genreDrama => 'Drama';

  @override
  String get genreComedy => 'Comedia';

  @override
  String get genreThriller => 'Suspense';

  @override
  String get genreSciFi => 'Ciencia ficción';

  @override
  String get genreRomance => 'Romance';

  @override
  String get genreAction => 'Acción';

  @override
  String get genreHorror => 'Terror';

  @override
  String get genreDocumentary => 'Documental';

  @override
  String get genreAnimation => 'Animación';

  @override
  String get genreCrime => 'Crimen';

  @override
  String get genreHistory => 'Historia';

  @override
  String get genreMystery => 'Misterio';

  @override
  String get contentBack => 'Atrás';

  @override
  String get contentSectionSignals => 'Señales';

  @override
  String get contentSectionSynopsis => 'Sinopsis';

  @override
  String get contentSectionFansSay => 'La comunidad de Flixscope dice';

  @override
  String get contentSectionQuickTakes => 'Comentarios rápidos';

  @override
  String get contentSectionAvailable => 'Disponible en';

  @override
  String get contentWatcherScore => 'Watcher Score';

  @override
  String get contentTrustScore => 'Confianza';

  @override
  String get contentVariance => 'Varianza';

  @override
  String get contentCompletion => 'Terminan';

  @override
  String fansSayCompletion(int pct) {
    return '$pct% la terminó';
  }

  @override
  String fansSayWorth(int pct) {
    return '$pct% dijo que valió la pena';
  }

  @override
  String fansSayRating(String rating) {
    return '$rating / 5 promedio';
  }

  @override
  String fansSaySample(int count) {
    return 'n = $count usuarios verificados';
  }

  @override
  String get fansSayNotEnough =>
      'Todavía no hay suficientes señales verificadas.';

  @override
  String get contentActionRate => 'Calificar';

  @override
  String get contentActionWorth => '¿Valió la pena?';

  @override
  String get contentActionTake => 'Escribe tu comentario';

  @override
  String get contentLoginGate =>
      'Inicia sesión para calificar y compartir tu comentario. Tu señal ayuda a otros a encontrar joyas.';

  @override
  String get contentLoginGateCta => 'Más tarde';

  @override
  String get contentNoTakes =>
      'Aún no hay comentarios. Sé el primer usuario verificado.';

  @override
  String get contentMyRating => 'Tu calificación';

  @override
  String get contentNotForMe => 'No es para mí';
}
