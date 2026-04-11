# Bitácora — Flixscope (formerly The Remote)

Registro de decisiones, pendientes y "notas al margen" del proyecto.
Formato: sección por fecha, bullets cortos.

---

## 2026-04-10 — Builds 3–4 Feedback + Catálogo curado + Vault redesign

### Build 3 Feedback (7 items) — resuelto
- **#2 Fix: Catálogo vacío al primer login.** `catalogProvider` ahora hace `ref.watch(authStateChangesProvider)` para re-fetch automático cuando el usuario inicia sesión.
- **#5 Fix: Vault mostraba conteo pero no listaba títulos.** `_resolveContent()` y `_RankingView` ahora usan `catalogMap` desde Supabase real, con fallback a MockContent para IDs legacy.
- **#3 Fix: Deep links a streaming apps.** Nuevo campo `platformDeepLinks` en `Content` model. Chips de plataformas tapeables vía `url_launcher`.
- **#4 Fix: Botón ❤️ favoritos.** (Corregido en Build 4 — ver abajo).
- **#6 Fix: Creators dummy reemplazados.** Solo queda `@izaivi` como founding creator.
- **#7: Crunchyroll agregado como 7ª plataforma.** Migration aplicada en Supabase. Ingest actualizado.

### Build 4 Feedback (6 items) — resuelto
- **Crunchyroll en quiz.** Agregado a `_platformOptions` en onboarding y a `_allPlatforms` en Discover filter.
- **Post-quiz redirect.** Ahora envía a `/auth` en vez de `/home` para que el usuario se autentique antes de ver catálogo.
- **Ranking tab rediseñado.** Con 4 films a distinto rating, el grid vertical era ilegible. Nuevo diseño: `_StarDivider` (barra de color + estrellas + count + línea horizontal) + `_RankedCard` (card horizontal con poster + metadata + WatcherScore badge).
- **Plataformas vacías.** Mensaje "Not available on any streaming platform in your region right now." cuando no hay disponibilidad.
- **Creator system real.** Migración de MockCreators a Supabase-backed providers (`creatorsProvider`, `creatorByIdProvider`, `latestTakesProvider`, `takesByCreatorProvider`, `featuredSkipProvider`, `currentCreatorProvider`, `submitTake`). Tabla `creators` + `creator_takes` con RLS. Write Take UI completa: bottom sheet con verdict selector (Worth It/Skip It/Quick Take), text field 500 chars, Publish.
- **Creator avatar.** `_SmartAvatar` widget reutilizable que muestra foto de perfil real (via `UserAvatar`) cuando el creator es el usuario actual, fallback a initials. Aplicado en `_CreatorChip`, `_FeaturedSkipCard`, `_TakeCard`, y `_BigAvatar` en creator_detail_screen.
- **Creator identity.** `@izaivi` re-linked a Apple account UUID `7e57e9a8-81cc-468d-bfea-ad0aba68dc68` (izanami.ivi@icloud.com). SQL pendiente de confirmar por Vivi.

### Vault — Tres señales independientes (❤️ 🔖 👎)
- **Bug corregido: ❤️ tenía doble funcionalidad ninja.** El corazón llamaba `toggleWatchlist` en vez de `toggleLoved`. Ahora son 3 botones separados en content_screen:
  - ❤️ → `toggleLoved` (me encanta, favorito personal)
  - 🔖 (bookmark azul) → `toggleWatchlist` (ver después)
  - 👎 → `toggleNotForMe` (descarte)
- **Estrellas independientes de Loved.** 5★ ya NO implica ❤️. Puedes darle 5 estrellas a algo por calidad sin que sea tu favorito. Criterio humano nerd: "el corazón gana".
- **Vault Loved tab actualizado.** Ya no se deriva de 5★ ratings — solo muestra contenido explícitamente marcado con ❤️.
- **Supabase sync actualizado.** `pullVault` y `pushVaultBucket` ahora manejan el bucket `'loved'`. `refreshFromRemote` mergea los 3 buckets.

### Ingest — Manual seed + skip-omdb
- **Nuevo flag `--tmdb-ids`** para inyectar títulos específicos por TMDB ID, bypaseando discover. Formato: `movie:78,tv:1399` o solo `78` (default movie).
- **Nuevo flag `--skip-omdb`** para cuando OMDb rate limit está agotado. Los títulos entran con metadata TMDB completa (sinopsis trilingüe, poster, backdrop, géneros, popularidad) — solo faltan scores IMDb/RT/Metacritic.
- **72 títulos curados inyectados** desde MacBook:
  - Blade Runner (1982, 2049)
  - Twilight saga completa (5 films)
  - Villeneuve: Dune 1+2, Arrival, Sicario, Prisoners
  - Nolan: Interstellar, Inception, The Dark Knight, Memento
  - Studio Ghibli: Spirited Away, Mononoke, Totoro, Howl's, Nausicaä, Grave of the Fireflies, Ponyo, Kiki's, The Wind Rises
  - LOTR + Hobbit (6 films)
  - Star Wars saga (9 films)
  - Matrix (4 films)
  - Tarantino: Pulp Fiction, Kill Bill 1+2, Django, Inglourious Basterds, Reservoir Dogs, Once Upon a Time in Hollywood, The Hateful Eight
  - Marvel MCU: Iron Man, Avengers, Endgame, Infinity War, Black Panther, Spider-Man Homecoming, Winter Soldier, Guardians of the Galaxy
  - Anime: Akira, Ghost in the Shell, Your Name, Evangelion 1.0
- **Archivo `ingest/seed_titles.txt`** como catálogo curado de la fundadora.

### N8N + Flutter
- **N8N configurado** en iMac: 2 workflows (Full Monthly 1er lunes + Refresh MierSab). Comando actualizado con `--skip-watchmode --skip-rapidapi`.
- **Flutter upgraded** a 3.41.6 stable.

### Pendiente para Build 5 (mañana)
- **Zona premium** — habilitar y diseñar.
- **Confirmar SQL** de `@izaivi` → Apple account en Supabase.
- **Enriquecer 72 títulos curados** con scores OMDb (correr sin `--skip-omdb` cuando rate limit se resetee).
- **Account linking Apple + Google** (Fase 2).
- **Creator take translation** a body_en/es/sv (Fase 2).

---

## 2026-04-08 — Fase 0 cerrando, primeros bugs post-auth

### Hecho
- **Supabase auth cableado end-to-end**: Apple, Google (con bug), Magic Link (con bug), Guest anónimo.
- **Repos sincronizados con Supabase** (profile, ratings, vault, follows) con patrón hybrid local/remote: SharedPreferences = fuente de verdad local, fire-and-forget push, pull-replace en sign-in.
- **Bug crítico corregido: vault compartido entre usuarios.** Causa: `refreshFromRemote` hacía merge en vez de replace y sign-out no limpiaba nada local. Fix: listener de `authStateChangesProvider` en `main.dart` ahora hace `clear + pull` en signedIn y `clear` en signedOut para los 4 controllers.
- **Bottom bar `Calificar/¿Valió la pena?/Escribe comentario` en content_screen**: estaba usando un mock `profile.id != null` para detectar auth. Ahora usa `currentUserProvider`. Además, si `isAuthed`, la barra se oculta completamente (los controles inline ya hacen ese trabajo).
- **Header de Mi Bóveda** muestra `Tu biblioteca personal, @alias` cuando hay alias.
- **`_AliasDialog`** agregado en profile_screen con validación 3–24 chars `[a-zA-Z0-9_]` (match del CHECK de Postgres).
- **Sign Out button** agregado en Profile (solo visible cuando `isSignedIn`).
- **Países expandidos** de 7 → 16 en onboarding y Ajustes → País. Grupos: Norteamérica (US/CA/MX), LATAM (BR/AR/CO/CL), Europa (ES/GB/IE/FR/DE/IT/NL/PT/SE). Criterio: Digital TV Research 2024 + Statista SVOD por tamaño de mercado y penetración. Los nórdicos representados por Suecia (>80% penetración streaming).

### Decisiones de diseño/producto
- **Los Guests SÍ pueden poner alias y calificar.** Son `auth.users` reales con `is_anonymous=true`. Cuando hacen upgrade vía `linkEmailToCurrentSession` el `user_id` se mantiene, conservan todo (alias, ratings, vault, follows). Lo único que pierden si cambian de dispositivo es la cuenta — mitigar con banner suave "Agrega un email para no perder tu bóveda" (TODO Fase 1).
- **Bundle ID locked**: `com.punkytigerlabs.theremote` (app nativa) + `com.punkytigerlabs.theremote.signin` (Services ID para OAuth web). Cambiar después rompe keychain/certs/provisioning.
- **Apple JWT client_secret** válido 180 días. Scheduled task `apple-jwt-renewal-the-remote` dispara 2026-09-28 con instrucciones completas de regeneración.
- **Google Cloud**: proyecto `the-remote` creado bajo "No organization" (la org de Punky Tiger Labs no existe en Google Cloud y requiere verificación de dominio). Se puede mover después.

### Pendientes urgentes (orden acordado)
1. **Alias únicos (Opción B)**: índice único case-insensitive + check en vivo con debounce en `_AliasDialog` + manejo de error 23505 (unique_violation).
2. **Google Sign-In bug**: `AuthApiException: Passed nonce and nonce in id_token should either both exist or not`. El id_token de Google incluye nonce automático que Supabase rechaza. Fix recomendado: migrar a `signInWithOAuth(provider: google)` con deep link — mata dos pájaros (también resuelve #3).
3. **Magic Link redirect**: hoy va a `localhost:3000`. Necesita Site URL + Redirect URLs en Supabase dashboard + deep link iOS (Info.plist URL scheme + handler Flutter).
4. **Checkpoint de seguridad/bugs** antes de Fase 1.

## 2026-04-09 — Pendiente #1 (Alias únicos) cerrado + bug crítico de reset

### Hecho
- **Índice único `profiles_alias_unique_ci`** creado en Supabase (case-insensitive, partial WHERE alias IS NOT NULL).
- **`isAliasAvailable(alias)`** agregado en `supabase_sync.dart`: usa `ilike` contra `profiles`, excluye la fila del propio user, optimista en errores de red.
- **`pushProfile`** ahora rethrowea `PostgrestException` code `23505` (antes se lo tragaba).
- **`setAlias`** en `UserProfileController` hace rollback del estado local + throw `AliasTakenException` en caso de unique_violation. Call-site en `profile_screen.dart` atrapa y muestra SnackBar.
- **`_AliasDialog` rewrite**: `ConsumerStatefulWidget` con debounce 400ms, secuenciador para descartar respuestas viejas, estados visuales (idle/checking/available/taken/formatError), suffix icon dinámico, Save deshabilitado si no está en estado válido.
- **Policy `profiles_select_public_alias`** creada (`USING (true)` a authenticated) para que el check en vivo pueda leer filas de otros users. TODO: restringir a vista con solo `id/alias/avatar_key` en checkpoint pre-Fase 1 (anotado arriba).
- **Verificado end-to-end** en sesión guest real: al tipear un alias ya usado por otra cuenta, sale ❌ rojo "Ese alias ya está en uso." y Save queda deshabilitado.

### Bug crítico encontrado y corregido: `reset()` en signedIn causaba pérdida de alias + Home en negro
- **Síntomas**: (1) Al iniciar sesión con Apple, el Home renderizaba negro hasta navegar a otro tab y volver. (2) El alias local sobrevivía en SharedPreferences entre sesiones pero no llegaba a Supabase de forma consistente.
- **Causa raíz**: en `main.dart` el listener de `authStateChangesProvider` hacía `userProfileProvider.reset()` en `signedIn` ANTES del `refreshFromRemote()`. El reset:
  1. Seteaba el profile a `UserProfile.anonymous` (quizCompletion=none).
  2. El router, que watchea `userProfileProvider`, disparaba el redirect → `/onboarding` porque `!done`.
  3. Luego `refreshFromRemote` cargaba el profile real → redirect de vuelta a `/home`.
  4. El rebote `/auth → /home → /onboarding → /home` en ~1s causaba el render negro.
  5. Peor: `reset()` llamaba `_repo.clear()`, borrando SharedPreferences. Si el pull remoto no tenía alias (porque push previo había fallado o timing de auth), el alias se perdía.
- **Fix**:
  - `main.dart`: quitar el `reset()` del profile en `signedIn`. Los resets de `vault/ratings/follows` se quedan porque esos SÍ son per-account. `refreshFromRemote` del profile se encarga solo.
  - `refreshFromRemote` en `user_profile_repository.dart`: detecta si `remote.alias == null && state.alias != null` y hace un **backfill push** automático. Atrapa cualquier error (incluido 23505) para no tumbar el sign-in.
- **Estado**: ✅ verificado 2026-04-09. Vivi hizo sign-in con Apple y el Home renderizó normal sin pantalla negra ni rebote.

### Security Advisor — lints revisados (2026-04-08)
Corrimos los 7 WARN del linter de Supabase. Resoluciones:
- **[RESUELTO] `function_search_path_mutable`** sobre `public.tg_touch_updated_at`: fijamos `search_path = public, pg_temp` con `ALTER FUNCTION`. Elimina el vector teórico de search_path hijacking.
- **[SKIP justificado] `auth_leaked_password_protection`**: requiere email provider configurado. Nuestro flow de email es Magic Link (sin password), por lo que el check de HaveIBeenPwned no aplicaría. Re-evaluar SOLO si alguna vez habilitamos email+password tradicional.
- **[PENDIENTE — Checkpoint pre-Fase 1] Restringir `profiles_select_public_alias`**: creada con `USING (true)` para desbloquear el check de alias en vivo. Expone todas las columnas de `profiles` a cualquier authenticated. Mitigación: crear una vista `public_profiles` con solo `id, alias, avatar_key` y apuntar el check contra la vista, o cambiar la policy a column-level security.
- **[PENDIENTE — Checkpoint pre-Fase 1] `auth_allow_anonymous_sign_ins` × 5 tablas** (profiles, user_follows, user_loved_quiz, user_ratings, user_vault): las policies actuales no tienen cláusula `TO` explícita, así que aplican también al rol `anon` (usuarios sin JWT). Funcionalmente no es brecha porque todas usan `auth.uid() = user_id` y un anon no tiene uid, pero el linter warn hasta que agreguemos `TO authenticated` explícito. Fix: drop+create de las 13 policies con `TO authenticated`. Los Guests siguen funcionando porque son `auth.users` con `is_anonymous=true` bajo el rol `authenticated`. Hacerlo de un tirón en el checkpoint para no dejar la DB con policies inconsistentes.

### Notas al margen (para retomar después)
- **[i18n países]** Los 9 países nuevos (CA, BR, IE, FR, DE, IT, NL, PT, SE) están **hardcoded en español** en `onboarding_screen.dart` y `profile_screen.dart`. Pendiente: agregar keys `countryCa`, `countryBr`, etc. en `app_en.arb` / `app_es.arb` y regenerar l10n. Cuando el idioma de la app esté en inglés los verá como "Canadá" en lugar de "Canada". Prioridad: baja — hacerlo en el checkpoint pre-Fase 1.
- **[opción "Otro"]** Agregar opción `Other / Resto del mundo` al final de la lista de países para que usuarios en mercados no listados no se sientan excluidos. Implementación: valor especial `'XX'` o `null`, label *"Otro país"*, y que el `effectiveCountryProvider` caiga al catálogo US por default. Prioridad: media — hacerlo junto con el i18n de países.
- **[Fase 2 — Sueco (SV)]** Suecia tiene >80% de penetración de streaming, mayor que US. Evaluar lanzar soporte de idioma sueco como primera expansión europea no-inglesa. Justifica la inversión en l10n por el tamaño del mercado relativo.
- **[Fase 2 — APAC]** Zona Asia-Pacífico pendiente para Fase 2: Japón, Corea del Sur, India, Australia, Nueva Zelanda. Requiere contenido local en TMDB ingest + idiomas + posibles proveedores de streaming que no están en el catálogo actual (iQIYI, WeTV, Hotstar, Stan, etc.).
- **[Chrome MCP]** En este entorno `execute_javascript` de Control_Chrome consistentemente falla con "Chrome is not running" aunque `list_tabs` funcione. Probable causa: Brave vs Chrome o permiso de extensión. Workaround: copy-paste manual cuando haya que inyectar SQL/scripts.

---

## 2026-04-09 — Pendiente #2 (Google OAuth + Magic Link redirect) cerrado parcial

### Hecho
- **Migración de Google Sign-In nativo → Supabase OAuth browser flow.** Quitamos `google_sign_in` del `auth_repository.dart`. Nueva constante `kAuthRedirectUrl = 'io.theremote://login-callback/'`. `signInWithGoogle()` ahora llama `_auth.signInWithOAuth(OAuthProvider.google, redirectTo: kAuthRedirectUrl)`. Esto mata el bug del nonce (Google id_token trae nonce automático que Supabase rechazaba en el flow nativo) y unifica el mecanismo de callback con Magic Link.
- **Magic Link**: `signInWithMagicLink` actualizado con `emailRedirectTo: kAuthRedirectUrl`.
- **Info.plist**: agregado segundo `CFBundleURLTypes` dict con scheme `io.theremote` junto al legacy de Google (ambos documentados con comentarios inline).
- **`auth_screen.dart`**: `_doGoogle()` ya no navega a `/home` directo (el OAuth es async vía deep link). Agregamos `ref.listen(authStateChangesProvider, ...)` dentro del build que detecta `AuthChangeEvent.signedIn` y navega. Fallback de 2s para limpiar `_busy` si el user cancela.
- **Router catch-all para deep link**: `app_router.dart` redirect function ahora detecta `loc.contains('login-callback')` (y `fullLoc` de `state.uri.toString()`) y redirige a `/home`. Sin esto, go_router tiraba `GoException: no routes for location: io.theremote://login-callback/?code=...` con la pantalla "Something went off the rails".
- **Google OAuth verificado end-to-end**: sign-in exitoso, landing en Home normal, sesión persistente. En el segundo intento la ventana del browser aparece en blanco porque `ASWebAuthenticationSession` cachea cookies de Google y completa el auth silenciosamente — **no es bug**, es comportamiento esperado del webview cuando la sesión ya está autenticada.

### Pendiente de verificación
- **Magic Link**: el link del email no abrió nada en simulador iOS. Hipótesis: (a) el preview del cliente de email "quema" el token PKCE al pre-fetchear el URL, (b) custom URL schemes + Mail.app en simulador son notoriamente flaky. Código está cableado (redirect URL correcto, router atrapa el callback). **Verificar en TestFlight en device real** antes de marcar como cerrado.

---

## 2026-04-09 — Pendiente #3 (Checkpoint seguridad pre-Fase 1) cerrado ✅

### DB — RLS endurecida y vista pública
- **Migration `2026-04-09_rls_to_authenticated_and_public_profiles.sql`** aplicada. Drop + create de las 13 policies en las 5 tablas (profiles, user_ratings, user_vault, user_follows, user_loved_quiz) con `TO authenticated` explícito. Cierra los 5 WARN de `auth_allow_anonymous_sign_ins` del Security Advisor. Los guests siguen funcionando porque son `auth.users` con `is_anonymous=true` bajo el rol `authenticated`.
- **Policy permisiva `profiles_select_public_alias` eliminada.** Reemplazada por la vista `public.public_profiles` (`security_invoker=false`, `grant select to authenticated`) que expone SOLO `id, alias, avatar_key` donde `alias is not null`. Las columnas sensibles (country, language, tier, created_at) quedan owner-only por las policies de la tabla base.
- **`isAliasAvailable` en `supabase_sync.dart`** ahora consulta `public_profiles` en vez de `profiles`. El índice único `profiles_alias_unique_ci` sigue siendo la última línea de defensa.
- **`schema.sql` local** sincronizado con el estado nuevo para que sea reproducible desde cero.

### App — i18n de países + opción "Resto del mundo"
- **10 keys nuevas** en `app_en.arb` / `app_es.arb`: `countryCa/Br/Ie/Fr/De/It/Nl/Pt/Se/Other`. Los generated files (`app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart`) actualizados manualmente — regenerar con `flutter gen-l10n` desde los .arb da el mismo resultado.
- **`onboarding_screen.dart`**: `_countryCodes` ahora tiene 17 entradas (16 países + `'XX'` al final). `_label()` usa `l10n.*` para los 9 nuevos y `l10n.countryOther` para `XX`. Se eliminaron los strings hardcoded en español.
- **`profile_screen.dart`**: settings dropdown de país migrado a `l10n.country*` para todas las opciones nuevas + `_Opt('XX', l10n.countryOther)` al final.
- **`effectiveCountryProvider`** en `language_prefs.dart` trata `'XX'` como "auto": cae a `platformDispatcher.locale.countryCode` → `'US'` como último recurso. Elegir "Resto del mundo" ya no fuerza al user a identificarse con un mercado al que no pertenece.

### Security Advisor post-checkpoint
- ✅ 5× `auth_allow_anonymous_sign_ins` → resueltos por `TO authenticated`.
- ✅ `function_search_path_mutable` sobre `tg_touch_updated_at` → ya estaba resuelto en ronda previa.
- ⏭️ `auth_leaked_password_protection` → skip justificado (no usamos email+password tradicional, solo Magic Link).

### Estado Fase 0 post-checkpoint
- **Pendientes 1–3 cerrados.** Pendiente #2 queda con Magic Link ⏳ pendiente verificación en TestFlight en device real (el código está cableado, pero el link del email no abre nada en simulador iOS — problema conocido de custom URL schemes + Mail.app simulado, o preview del cliente de email "quemando" el token PKCE).
- **Listo para Fase 1** (TMDB ingest) o para subir un build a TestFlight y cerrar Magic Link antes.

---

## 2026-04-09 — Fase 1 (Content Ingest) primera carga completa ✅

### DB — Tablas de catálogo + migración de user tables
- **Migration `2026-04-09_fase1_content_ingest.sql`** aplicada. Crea 3 tablas nuevas:
  - `platforms` (6 rows seed: Netflix, Max, Disney+, Prime Video, Apple TV+, MUBI) con `tmdb_provider_id` y `color_hex`.
  - `content` (PK `tmdb_id bigint`) con sinopsis trilingüe (en/es/sv), scores externos (IMDb/RT/Metacritic), señales TMDB, columnas Watcher Score (nullable, Fase 2), `data_sources text[]`.
  - `content_availability` (PK compuesta `content_id, country_code, platform_id, monetization_type`) con deep_link, precios, source.
- **User tables migradas**: `user_ratings`, `user_vault`, `user_loved_quiz` — TRUNCATE + ALTER `content_id` de `text` a `bigint` con FK a `content(tmdb_id) ON DELETE CASCADE`. `user_follows` NO se toca (usa `creator_id`, no `content_id`).
- **RLS**: `enable row level security` + `SELECT` only policies `TO authenticated` en las 3 tablas nuevas. Writes exclusivamente vía `service_role` desde el script de ingest.
- **Índices**: `content(tmdb_popularity desc)`, `content(watcher_score desc)`, `content(media_type)`, `content_availability(country_code, platform_id)`, `content_availability(last_checked_at)`.

### Ingest — Pipeline server-side
- **Carpeta `ingest/`** creada con: `ingest.py`, `.env`, `.env.example`, `.gitignore`, `requirements.txt`, `README.md`.
- **Pipeline**: TMDB (backbone: catálogo + metadata + watch providers) → OMDb (IMDb/RT/Metacritic scores) → Watchmode (deep links + precios, US/MX/SE) → RapidAPI streaming-availability (fallback para ES).
- **4 países Fase 1**: US, MX, ES, SE (Suecia deliberadamente en lugar de España para Watchmode free tier — TMDB providers cubre ES).
- **Sinopsis trilingüe**: en, es, sv (sueco para mercado sueco, 88% coverage en TMDB).
- **Flags**: `--limit N`, `--platforms slug,slug`, `--skip-watchmode` (para refreshes sin quemar free tier).

### Full run — resultados
- **587 títulos** en `content` (movies + series, 6 plataformas × 4 países).
- **~2,400+ availability rows** en `content_availability`.
- **Scores coverage**: IMDb 95% (560/587), RT 52% (303/587), Metacritic 50% (295/587).
- **Sinopsis coverage**: EN 100%, ES 98.6% (579/587), SV 88% (517/587).
- **Plataformas**: Netflix 416, Disney+ 415, Max 406, Prime Video 404, Apple TV+ 346, MUBI 230.
- **Sources**: TMDB + Watchmode contribuyendo ambos.
- **Duración**: 30 min (full run con `INGEST_PAGES_PER_PROVIDER=2`).
- **Cero errores, cero warnings** en el run.

### Plan de cron (N8N en iMac secundaria, `shashin@iMac`)
- **Flujo 1 "Full Monthly"**: 1er lunes de cada mes, 8:00 → `python ingest.py` (con Watchmode).
- **Flujo 2 "Refresh Bi-weekly"**: miércoles y sábados, 8:00 → `python ingest.py --skip-watchmode`.
- Consumo mensual estimado: ~600 Watchmode (free tier 1,000) + ~3,000 OMDb (free tier 30,000/mes).

### Decisiones de producto
- **Suecia (SE) confirmada** como mercado Fase 1 en lugar de España (ES). Razón: >80% penetración streaming, comunidad TMDB activa (88% sinopsis en sueco). ES sigue cubierta por TMDB providers, solo sin deep links de Watchmode.
- **Watchmode free tier 3 países**: US, MX, SE. Upgrade a paid al lanzar Plan Pro.
- **RapidAPI** como fallback para ES (streaming-availability). Si se lanza más allá de 4 países, consolidar con plan RapidAPI $29/mo que cubre múltiples endpoints.
- **Settings → About**: pendiente agregar atribuciones ("Powered by TMDB", logo Punky Tiger Labs) + "Plan Pro disponible al salir de Beta".

### Pendientes inmediatos
- Sincronizar `ingest.py` actualizado (con `--skip-watchmode`) a la iMac.
- Configurar los 2 workflows de N8N.
- Conectar Flutter repositories a las tablas reales de `content`/`content_availability` (reemplazar mocks).
- Settings → About con atribuciones + logo `punkytigerlabs.png` (ya en `Graphics/`).

---
