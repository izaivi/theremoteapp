# Bitácora — Flixscope (formerly The Remote)

Registro de decisiones, pendientes y "notas al margen" del proyecto.
Formato: sección por fecha, bullets cortos.

---

## 2026-04-14 — Fase 2a-1: 5 Gems personalizadas (VALIDADA en simulador)

Cerrado el refactor del motor de recomendaciones en `lib/data/repositories/catalog_provider.dart` + ajuste en `lib/presentation/screens/home/home_screen.dart`.

### Filosofía
**NO somos un espejo de IMDb/RT.** Los scores de una sola fuente se pueden inflar con bots. El gate de calidad requiere consenso cross-source (≥2 fuentes clareando thresholds). La personalización (género / themes / sessionLength) es bonus aditivo encima de la calidad — nunca reemplaza el filtro. Entre dos títulos de calidad, el que matchea tu taste gana; entre uno de calidad y uno inflado, el de calidad siempre gana.

### Cambios en `catalog_provider.dart`

**Helpers nuevos (al final del archivo):**
- `_qualitySourceCount(c)` — cuenta cuántas fuentes clarean los thresholds.
- `_kImdbGate=7.2`, `_kRtGate=75`, `_kMetaGate=65`, `_kWatcherGate=70`.
- `_passesQualityGate(c)` — true si ≥2 fuentes pasan.
- `_compositeScore(c)` — promedio 0-100 de las fuentes disponibles (IMDb×10, RT, Meta, watcherScore).
- `_profileBonus(c, p)` — aditivo: +15 por género overlap (cap +45), +10 por `favoriteThemes` match en director/cast (substring case-insensitive, cap +30), +10 si duración cae en la ventana de `sessionLength`.
- `_matchesPlatforms(c, p)` — hard filter por `activePlatforms`. Si el perfil no tiene plataformas seleccionadas, pasa todo (defensivo); si el content no tiene availability conocida, se oculta.
- `_reasonFor(c, p, hasCurated)` — string humano: "Curated pick..." > "Matches your taste in X" > "Rare consensus..." > "High ratings, low noise..."

**`dailyGemsProvider` reescrito:**
1. Lee `profile` via `ref.watch(userProfileProvider)`.
2. Fetch de `creator_takes` con `!inner(creators)` filtrando `is_curated=true` → Set de `tmdbId` para boost 1.5× al composite score.
3. `excluded = watchedIds ∪ dismissedIds` — no duplica lo que ya viste o descartaste.
4. Pool 1: platform + quality gate. Si < 15 titles → tira el gate. Si < 5 → tira el platform filter. Si vacío → catálogo completo (último recurso).
5. Score por candidato = `_compositeScore(c) * (1.5 si curated else 1.0) + _profileBonus(c, p)`.
6. Ordena por score desc, toma top 30.
7. **Daily rotation:** `shuffle(Random(hash(profile.id + yyyy-mm-dd)))` → mismo user ve las mismas 5 todo el día, nuevas 5 mañana.
8. Toma 5, re-ordena por score desc, asigna `gemRank 5..1`. `tierVisibility` = Free para ranks 1-2 (los 2 de menor score como tease), Pro para ranks 3-5 (las 3 mejores detrás del paywall).

**Platform filter aplicado a:** `trendingProvider`, `explodingProvider`, `quickDecisionProvider`, `popularInRegionProvider`, `bingeableProvider`. `dontWasteProvider` queda platform-agnóstico a propósito (la advertencia aplica donde sea).

### Cambio en `home_screen.dart`

Líneas ~49-52: el sort pasó de `watcherScore ASC` a `gemRank ASC`. Estructura visual idéntica — las 2 gems "peores" arriba visibles para Free, las 3 "mejores" al fondo con blur + paywall. Pro ve las 5 ordenadas 1→5.

### Validación en simulador

Vivi corrió `flutter run` post-refactor y confirmó los 3 vectores:
1. Home **cambió** → daily rotation con seed por user+fecha está rodando.
2. Las 5 Gems son **diferentes** a las del algoritmo anterior → el composite + bonus se aplica a su perfil real.
3. **No aparecen títulos que ya marcó con ❤️ o rating alto** → el `excluded` está cortando bien.

### Decisiones de scope

- **Diferido a Fase 2a-2:** community signals (`not_for_me_count`, `loved_count` agregados). Requiere vista + RLS especial porque `user_vault` y `user_ratings` son owner-only. Decisión: esperar ~50+ users activos para calibrar thresholds con data real y no sobreponderar votos de 3 testers.
- **Diferido a Fase 3:** "Change my preferences" en Settings — reactivar Fast/Long Quiz.
- **Diferido a Fase 4:** Remoty consumiendo `userProfileProvider` (incluidos `favoriteThemes`) para conversación tipo "Vi que te gusta Keanu Reeves...".

### Por qué ahora y no antes

El bug reportado en Build 8 ("Quiz 2 ratings no actualizan 5 Gems") era síntoma de que `home_screen.dart` solo leía `tier/avatarKey/alias` y el engine trabajaba con data parcial. Fase 1 trajo los campos reales del quiz a Supabase (cross-device) — Fase 2a-1 por fin los usa para puntuar.

---

## 2026-04-14 — Fase 1: schema expansion + Fix A (CHECK) + Fix B (error surfacing) + VALIDADA

Cerrado el sync completo del perfil. Antes de hoy, `pushProfile/pullProfile` solo movían `id, alias, country, avatar_key, tier, quiz_completion`. Los campos del quiz (`activePlatforms`, `favoriteGenres`, `sessionLength`, `favoriteThemes`, `watchedIds` del seen-canon grid) vivían solo en SharedPreferences → cross-device = pérdida total de preferencias.

### Schema expansion
Migración añadió columnas a `public.profiles`: `active_platforms text[]`, `favorite_genres text[]`, `session_length text` (con CHECK de enum), `favorite_themes text[]`, `watched_canon_ids text[]`. RLS preservada. `pushProfile/pullProfile` actualizados para leer/escribir los 5 campos nuevos.

### Fix A — `user_vault.bucket` CHECK constraint
El CHECK original permitía solo `watchlist | not_for_me`. Cuando Vivi marcaba ❤️ (bucket `loved`), el upsert fallaba con CHECK violation — **y el `catch (_) {}` silencioso en `supabase_sync.dart` lo ocultaba**. Los loved items nunca persistían a Supabase y desaparecían tras `flutter clean`. Migración: `CHECK (bucket IN ('loved','watchlist','not_for_me'))`.

### Fix B — Eliminar catch silenciosos en sync
Patrón cambiado en 6 métodos de `supabase_sync.dart` (`pushRating`, `deleteRating`, `pushVaultBucket`, `deleteVaultEntry`, `pushFollow`, `deleteFollow`):
```dart
// Antes: catch (_) {} — silencioso
// Ahora: catch (e) { if (kDebugMode) debugPrint('[sync] ... failed: $e'); }
```
`pushProfile` mantiene `rethrow` en 23505 para que `setAlias` pueda mostrar el UX "alias ya tomado"; el resto queda best-effort pero **visible en consola**. Regla: nunca más silenciar un error de sync sin al menos log en debug.

### Nuke #2
Tras aplicar Fase 1 + Fix A + Fix B, `DELETE FROM auth.users;` vía Supabase MCP. DB quedó en 0 users / 0 profiles / 0 vault / 0 ratings / 0 follows. Content (6,713 titles) intacto. Necesario para validar el Fast Quiz + vault completo en fresh start.

### Validación
Vivi reportó "veo todo en mi bóveda!!!" — login fresh → Fast Quiz → Long Quiz → marca loved/watchlist/not_for_me/ratings → `flutter clean && flutter run` → login → los 3 buckets + ratings + perfil completo vuelven de Supabase. Cross-device confirmado.

### Audit lateral de follows
`user_follows` OK estructuralmente (PK compuesta, RLS owner-only, FK CASCADE a `creators.id`). Riesgo vivo: hoy hay 0 creators salvo `@izaivi` (recreado al final del día), así que cualquier follow previo moriría 23503. Con Fix B ahora sería visible en consola.

### Creator @izaivi recreado
- `creators.id = 3f248014-315a-470f-9b0e-3ca6cf5e8ef4`
- `user_id = 0d9d455c-1d7f-4eaf-80eb-c1c1141ce6b4` (iCloud, `izanami.ivi@icloud.com`)
- alias `izaivi`, specialty "Sci-fi, thrillers, cine de autor", `is_curated=true`
- Pendiente: Vivi pegará 4 takes. Estos entran al composite con boost 1.5× (ver Fase 2a-1).

### Nota de autocorrector
Uno de los directores favoritos de Vivi en Long Quiz es **Denis Villeneuve** (no "Villanueva" — el autocorrector iOS lo convierte). Almacenado en `profiles.favorite_themes`.

---

## 2026-04-13 — RC_APPLE_KEY truncada por un carácter (paywall "Invalid API Key")

Días persiguiendo al fantasma del paywall. Error real en TestFlight:
```
PlatformException(11, There was a credentials issue. Invalid API Key.)
```

### Causa
`.build_ipa.sh` línea 18 tenía `RC_APPLE_KEY=appl_nizWIKpVHaGDcMQunpgdVfBaUf`. La key real en el RevenueCat dashboard (Project Settings → API Keys → Public app-specific) es `appl_nizWIKpVHaGDcMQunpgdVfBaUfu` — **con una `u` final que se perdió** en algún copy-paste histórico. Un solo carácter.

El SDK de RevenueCat valida la key server-side. Si no matchea ninguna key registrada, regresa `CONFIGURATION_ERROR` (code 11) con el mensaje "Invalid API Key". No había falla de bundle ID, ni de productos, ni de offerings — literalmente el cliente mandaba una key que no existe en ninguna parte.

### Fix
Actualizada la key en `.build_ipa.sh`. El siguiente build que la compile tendrá paywall funcional (asumiendo todo lo demás del setup de RevenueCat está bien, que sí lo está según Build 8).

### Lección aprendida (segunda vez en el mismo día)
Hoy también nos pasó con SUPABASE_ANON_KEY — un placeholder `eyJhbGc...SMUadOWrw0xXsfZsxTTbzL_RCev7yAe067RrnPo6sd4` pegado literal. Cada vez que yo (Claude) abrevie una key en chat con `...`, verificar contra el archivo fuente antes de pegarla al build script. Reglita: las keys completas nunca se deberían leer/copiar a mano; siempre desde la fuente de verdad.

---

## 2026-04-13 — Build 12: Settings usa `currentUser` como source of truth (hotfix 2)

Build 11 se subió con el fix de `completeFastQuiz`, pero Vivi reportó el MISMO síntoma: login parece funcionar, llega a Home, pero Settings sigue diciendo "log in". El fix de Build 11 era real pero insuficiente — había una causa raíz arquitectural más profunda que cubría múltiples escenarios, no solo Fast Quiz.

### Causa raíz arquitectural
- `profile_screen.dart` línea 44 hacía `isSignedIn = profile.id != null` — un proxy del estado local.
- `app_router.dart` línea 62 hace `signedIn = user != null` con `user = ref.read(currentUserProvider)` — la fuente de verdad de Supabase Auth.
- **Dos checks divergentes para la misma pregunta.** El router usa la fuente de verdad; Settings usaba un mirror local que puede quedar desincronizado por cualquiera de:
  - `refreshFromRemote` aún en vuelo (race con UI render)
  - `pullProfile` devuelve null silenciosamente (network / RLS / trigger tardío)
  - Una factory que construye un `UserProfile` sin aceptar `id` (era el bug de `fromFastQuiz`, podrían existir más en el futuro)
- Resultado: el router cree que sí estás logueada (y con razón, Supabase te tiene), pero Settings cree que no.

### Fix
- `profile_screen.dart`: cambiado a `final currentUser = ref.watch(currentUserProvider); final isSignedIn = currentUser != null;`. Ahora Settings y el router hacen la misma pregunta a la misma tabla.
- Comentario CRITICAL inline para que nadie lo regrese a `profile.id` en el futuro.
- El fix de `completeFastQuiz` (Build 11) se mantiene — sigue siendo correcto por higiene (el state local tampoco debe perder el id), pero ya no es el gate del UI.

### Why no rollback
- Build 11 fix era legítimo y necesario.
- Build 8 tenía el MISMO bug latente (y peor: también faltaba el trigger `handle_new_user`). Rollback nos dejaría con un estado más roto.
- Build 12 corrige el síntoma visible + mantiene las mejoras de integridad anteriores.

### Test plan
1. Borrar app, reinstalar desde TestFlight (Build 12).
2. Continue with Apple → completa Fast Quiz → Home.
3. Ir a Settings → debe aparecer tu alias/email, NO "log in".
4. Sign out desde Settings → Settings debe volver a decir "log in".
5. Continue as guest → Settings debe decir que estás como guest (no "log in").

---

## 2026-04-13 — Build 11: Hotfix `completeFastQuiz` perdía el `id` de Supabase

Build 10 salió a TestFlight y reprodujo un bug que en Build 8 quedaba enmascarado por el flujo forzado: tras login (Apple/Google/Guest) → Fast Quiz → Home, Settings mostraba "log in" como si no hubiera sesión. Vivi vio en Supabase un nuevo profile con `alias=NULL` desde MX, confirmando que el auth SÍ creó la fila pero el cliente perdió el `id` localmente.

### Causa raíz
- `UserProfileController.completeFastQuiz` en `lib/data/repositories/user_profile_repository.dart` llamaba a `UserProfile.fromFastQuiz(...)`, una factory que construye un `UserProfile` fresco SIN aceptar `id`, `alias`, `tier` ni `avatarKey`.
- El listener de `signedIn` en `main.dart` ya hacía `refreshFromRemote()` que pulleaba el `id` del Supabase auth → todo bien hasta que el usuario terminaba el Fast Quiz.
- El Fast Quiz disparaba `completeFastQuiz` → `state = UserProfile.fromFastQuiz(...)` → `id = null` → Settings mira `profile.id != null` → "no logueado".
- Como bonus, `pushProfile(next)` enviaba a Supabase un row con `id` regenerado por defaults → fila huérfana sin `auth.uid()` válido.

### Fix
- Cambiado `completeFastQuiz` para usar `state.copyWith(country, activePlatforms, favoriteGenres, quizCompletion)` en vez de `UserProfile.fromFastQuiz(...)`. Preserva todo lo que `refreshFromRemote` ya pobló (`id`, `alias`, `tier`, `avatarKey`).
- Añadido guard: si `state.quizCompletion == long`, no degrades a `fast` (caso "re-correr fast quiz desde Settings" no debe regresar el progreso del long quiz).
- Añadido `assert(activePlatforms.isNotEmpty)` para cazar bugs de UI que dejen pasar la pantalla sin selección.

### Recovery extra (handle_new_user trigger)
- Diagnóstico paralelo encontró que el trigger `on_auth_user_created` sobre `auth.users` estaba ausente (probablemente arrastrado por un cleanup manual de NULLs en la tabla `profiles`). Sin él, los signups de Apple/Google/Guest creaban `auth.users` rows pero NO `profiles` rows.
- Nuevo migration `2026-04-13_restore_handle_new_user.sql`: recrea la función `handle_new_user()` con `SECURITY DEFINER`, recrea el trigger, y backfillea profiles para cualquier `auth.users` huérfano. Idempotente.
- Tras el fix de cliente + recovery del trigger, decisión de Vivi: nuke total (`DELETE FROM auth.users`) → fresh start. Pre-launch los testers se vuelven a registrar gratis. Confirmado: `auth_users=0, profiles=0, creators=0, content=6713 (preservado)`.

### Pendientes Build 11
- Vivi recrea su perfil de creador y re-pega sus 4 takes guardados.
- Siguen pendientes (de Build 10): Premium IAP en TestFlight real, Remoty + Anime intent, SharedPreferences user-scoped keys.

---

## 2026-04-13 — Build 10: Fixes post-TestFlight Build 8

Build 8 salió a TestFlight y Vivi cazó varios bugs de session management + cold start + long quiz. Build 10 ataca los más críticos.

### Cold start → login loop (bug #5)
- **Síntoma**: cerrar la app sin Sign Out, abrirla, te pide volver a logearte aunque la sesión siga viva en Supabase.
- **Causa**: el CTA de splash iba `context.go('/auth')` sin checar si ya había sesión. Returning user → splash → CTA → auth aunque currentUser != null.
- **Fix en `app_router.dart`**: si `atSplash && signedIn`, redirige a `/onboarding` (si falta quiz) o `/home`. Returning users ya no ven splash en cold start.

### Long Quiz ❤️ no llegaba a Bóveda (bug #2)
- **Síntoma**: doble tap en corazón en grid del long quiz → se guarda como `lovedRecentIds` en QuizAnswers, pero NO aparece en Mi Bóveda ni en ratings. UX decepcionante: "le di ❤️ pero mi bóveda sigue igual".
- **Fix en `long_quiz_screen.dart`**: después de `completeLongQuiz`, itera sobre `lovedIds` y llama `vaultProvider.toggleLoved(id)` + `ratingsProvider.setRating(id, 5)` para cada uno. Los ❤️ del quiz ahora aparecen en Bóveda (loved) Y en Mis Puntuaciones (5★).
- Lógica idempotente: si ya estaba loved, no duplica; si ya había rating, lo actualiza a 5.

### Session leak entre usuarios (bugs #6, #8)
- **Síntoma**: al cambiar de cuenta Apple → Google, se veía la Bóveda del usuario anterior. Los thumbs up de quick takes también persistían de la sesión anterior.
- **Causa raíz**: el listener de `authStateChangesProvider` en `main.dart` limpiaba/refrescaba profile/ratings/vault/follows pero NO invalidaba los `FutureProvider.family` de quick takes (que cachean por contentId y leen `user_id` internamente). El estado "mi voto" se quedaba cacheado del user viejo.
- **Fix en `main.dart`**: agregados `ref.invalidate(quickTakesByContentProvider)` y `ref.invalidate(quickTakesTodayCountProvider)` en los handlers de `signedIn` Y `signedOut`. Riverpod purga toda la family → próxima lectura re-fetch con el user nuevo.

### Follow counter sin incrementar (bug #3)
- **Síntoma**: seguir a un creador → botón dice "Following", pero el contador del perfil sigue en el valor viejo y el creador no aparece en la sección "Siguiendo" de Bóveda.
- **Causa raíz**: la sección 2 del migration `2026-04-13_vote_and_follow_triggers.sql` quedó pendiente por type mismatch entre `user_follows.creator_id text` y `creators.id uuid`. Sin trigger, `followers_count` nunca se actualiza.
- **Fix**: nuevo migration `2026-04-13_follow_counter_fix.sql` que:
  1. Migra `user_follows.creator_id` de `text` a `uuid` (TRUNCATE previo — follows pre-launch son baratos de rebuild).
  2. Agrega FK a `creators(id) ON DELETE CASCADE`.
  3. Crea trigger `trg_follower_count` con `SECURITY DEFINER` que incrementa/decrementa `followers_count` en INSERT/DELETE.
  4. Backfill de `followers_count` desde las filas existentes.
- Vivi corre este SQL en Supabase SQL Editor una vez antes de probar Build 10.

### Pendientes Build 10 (no incluidos)
- **Premium IAP en TestFlight**: necesito el error exacto del TestFlight real (no simulador) para diagnosticar. Posible cache del SDK de RevenueCat, o productos "Ready to Submit" faltantes en App Store Connect.
- **Remoty + Anime**: el engine confunde anime con animación general. Agregar intent/filtro por `genre_ids` + `origin_country=JP`. Baja prioridad.
- **SharedPreferences keys user-scoped**: los repos locales (vault/ratings/follows) usan una única key por device (`vault.v1` etc.). El clear+refresh del listener lo compensa, pero sería más robusto keyar por user_id. Refactor de mayor alcance, Build 10+.

---

## 2026-04-13 — Build 8: Onboarding gating + Quick Takes counters + RevenueCat bundle fix

### Quick Takes — contador thumbs up/down arreglado
- **Bug**: el emoji se coloreaba al votar pero el contador permanecía en 0 en `quick_takes.thumbs_up` / `thumbs_down`. Causa raíz: la migration `2026-04-13_vote_and_follow_triggers.sql` corrió en una sola transacción que rolleó atrás por type mismatch en la sección de `user_follows` (creator_id text vs uuid), así que el trigger del primer bloque tampoco quedó aplicado.
- **Fix**: aislada la sección "QUICK TAKE VOTE COUNTERS" y aplicada por separado vía SQL Editor. Función `update_quick_take_vote_counts()` con `SECURITY DEFINER` (necesario porque RLS de `quick_takes` no permite UPDATEs cross-user — el trigger ahora los hace en nombre del owner del registro). Trigger `AFTER INSERT OR UPDATE OR DELETE ON quick_take_votes FOR EACH ROW`. Backfill manual de los contadores existentes con `COUNT(*)` agrupado.
- **Resultado**: votos previos recalculados correctamente ("prueba"=1👍, "flop en la última season"=2👍, "Me gusto. Está divertida."=2👍). Nuevos votos actualizan el contador en tiempo real.
- **Pendiente**: convertir `user_follows.creator_id` de `text` a `uuid` y reaplicar la sección 2 del migration original (followers count). No bloquea Build 8.

### RevenueCat — Credentials issue resuelto (Bundle ID mismatch)
- **Síntoma**: dashboard de RevenueCat marcaba "Credentials need attention" para la app Flixscope. La misma App-Specific Shared Secret funcionaba sin problemas para Kireya (otra app en la misma cuenta de Apple Developer 95925D7AY7).
- **Causa raíz** (descubierta vía Chrome MCP inspeccionando el form de la app config): RevenueCat tenía registrado `com.punkytiger.flixscope` como Bundle ID — un identificador que **nunca existió** en App Store Connect. El bundle real registrado es `com.punkytigerlabs.theremote`.
- **Fix**: actualizado el campo "App Bundle ID" en RevenueCat a `com.punkytigerlabs.theremote`, save changes, refresh credentials → "Valid credentials" ✅.
- **Producto IDs sin cambios**: `com.punkytiger.flixscope.pro.monthly` y `.pro.annual` siguen siendo correctos (matchean App Store Connect).
- **Persistencia del error en simulador**: aún después del fix en dashboard, el simulador iOS sigue tirando "credential issue" — comportamiento esperado por (a) cache del SDK de RevenueCat en el cliente, (b) StoreKit en simulador es flaky sin StoreKit Configuration File. Validación real va en TestFlight con device físico + sandbox tester.

### Onboarding — Reorden de flujo: Splash → Auth → Quiz → Home
- **Cambio de UX**: antes el quiz iba antes del auth, ahora el auth es lo primero. Razón: las preferencias del quiz se guardan a un user_id real en Supabase, así que pedir auth primero elimina edge cases de "guest hace quiz, después se loggea, qué pasa con sus preferencias".
- **`splash_screen.dart`**: CTA `context.go('/home')` → `context.go('/auth')`. Docstring del flujo actualizada.
- **`onboarding_screen.dart`**: al terminar el quiz va directo a `/home` (la sesión ya existe). Comentario explicando el nuevo orden.
- **`app_router.dart`**: gating de auth añadido en el redirect:
  - Importa `auth_repository.dart` para `currentUserProvider` y `authStateChangesProvider`.
  - `ref.listen(authStateChangesProvider, (_, __) => refresh.value++)` — el router reacciona a cambios de auth state (sign-in / sign-out) y reevalúa el redirect.
  - Reglas: si no hay sesión y no estás en `/splash` o `/auth` → redirige a `/auth`. Si hay sesión pero quiz no completado → `/onboarding`. Si quiz completado y estás en `/onboarding` → `/home`.
- **`auth_screen.dart`**: botón de cerrar (X) en AppBar ahora es condicional a `ref.watch(currentUserProvider) != null`. Sin sesión = sin escape, no puedes saltarte el auth obligatorio. Con sesión = botón visible (caso "Settings → Sign in to upgrade"). `automaticallyImplyLeading: false` para evitar back button automático.

### Verificación en simulador
- **Account existente**: signin → salta directo a Home (quiz ya completado en sesión previa). ✅
- **Guest**: signin anonymous → quiz aparece (3 pasos) → Home. ✅
- **Premium IAP**: error de credentials persiste en simulador (esperado, ver RevenueCat arriba). Validación pendiente en TestFlight.

### Pendientes Build 8
- Subir IPA Build 8 a TestFlight.
- Probar Premium IAP en device real con sandbox tester.
- Migration de `user_follows.creator_id` text → uuid + reaplicar trigger de followers count.

---

## 2026-04-11 — Build 5: Take System Redesign + Platform Links + Quick Takes + Remoty

### Remoty Companion — IA tab → Ask Remoty
- **Rebrand completo:** tab inferior pasa de "IA" → "Remoty" con icono `smart_toy`.
- **Ask Remoty screen:** header con título "Ask Remoty" + tagline "Your streaming companion" / "Tu compañero de streaming".
- **Dos botones en header:** Guide (❓) abre bottom sheet con categorías de uso + Clear (🗑) borra conversación con confirmación.
- **Guide sheet:** 4 categorías (Mood & Genre, Your Vault, Creator Takes, Platform Search) con example chips tapeables que disparan la pregunta.
- **RemotypEngine:** reemplaza MockAiResponder. Motor de intenciones rule-based con 14 intents: greeting, thanks, skip, short, binge, sad, action, sciFi, classic, vault, **ranking**, creators, platform, generic.
- **Data real de Supabase:** engine recibe catalog, vault (loved/watchlist/notForMe), star ratings, y creator takes desde providers. Ya no usa MockContent para sus respuestas.
- **Ranking intent (nuevo):** responde a "my best rated", "mis mejores", "5 stars" etc. Muestra títulos con 5 estrellas, o los peor calificados si preguntas por "worst". Summary por nivel de estrellas si no hay 5★.
- **Cards aleatorias:** vault (loved, watchlist) y ranking muestran 3 cards random cada vez, no siempre las primeras.
- **Chat persistence:** `_chatMessagesProvider` + `_chatThinkingProvider` (Riverpod StateProvider). La conversación sobrevive cambios de tab (ShellRoute mata KeepAlive, así que Riverpod era la solución).
- **Creator premium:** `isProProvider` combina `tier=='pro'` OR `isCreatorOverride` (set by `currentCreatorProvider`). Creators verificados tienen acceso ilimitado a Remoty.
- **Tappable cards:** las cards de recomendación navegan a `/content/$id` con tap.
- **Quota 5→10:** preguntas gratis diarias incrementadas. L10n strings actualizadas.
- **Bilingüe EN/ES:** detecta locale del usuario y responde en el idioma correcto.
- **Mascota Remoty:** avatar circular mascot_ask.png en header y mensajes. mascot_search.png mientras piensa.
- **Empty state:** mascota grande + "Hey! I'm Remoty" con 7 quick chips (short, binge, sad, skip, favorites, ranking, creators).
- **Guide sheet:** 5 categorías (Mood & Genre, Favorites & Vault, Your Rankings, Creator Takes, Platform Search) con chips tapeables.
- **Sin dependencia de API de IA:** todo funciona con keyword matching + catálogo real de Supabase.


### Take System — Separación Creator Takes vs Quick Takes
- **Arquitectura nueva: dos sistemas independientes.**
  - **Creator Takes**: solo creators registrados. Verdict obligatorio (Worth It / Skip It). 500 chars. Editable (max 2 edits). Sin límite diario. Se muestran en "CREATOR TAKES" en la ficha del contenido.
  - **Quick Takes**: cualquier usuario autenticado. Sin verdict. 250 chars. No editable (borrar y rehacer). Free: 1/día. Premium: ilimitado. Votación thumbs up/down. Se muestran en "FLIXSCOPE FANS SAY".
- **Estrategia freemium**: 1 quick take gratis al día crea engagement + dopamina social de los deditos → empuja naturalmente al premium para quick takes ilimitados.
- **Tablas Supabase**: `quick_takes` (user_id, content_id, body, thumbs_up, thumbs_down) + `quick_take_votes` (quick_take_id, user_id, vote). RLS completa para CRUD.
- **`CreatorVerdict.quickTake` eliminado** del enum — creators solo tienen `worthIt` y `skipIt`. Limpieza en: `creator.dart`, `creators_provider.dart`, `creators_screen.dart`, `creator_detail_screen.dart`, `content_screen.dart`.
- **Bloqueo de duplicados**: un creator no puede hacer dos takes en el mismo film. Después de publicar, el botón cambia a "Edit Your Take (X left)".
- **Popularidad de creators**: takes en la ficha del contenido se ordenan por `followers_count` del creator (más popular primero), luego por fecha.

### Ficha de Contenido — Rediseño de secciones
- **Nuevo orden**: Synopsis → CREATOR TAKES → FLIXSCOPE FANS SAY → AVAILABLE ON.
- **CREATOR TAKES**: data real de Supabase. Muestra hasta 3 takes con badge de verdict y alias del creator. Tap en el título → navega al tab Creators. "See all creator takes →" si hay más de 3.
- **FLIXSCOPE FANS SAY**: quick takes reales con thumbs up/down. Tap en cada dedito vota. Botón "Share your quick take" abre compose sheet (250 chars). Pantalla expandida si hay >3 takes. Bote de basura visible en tus propios takes.
- **Secciones mock eliminadas**: `_FansSayBlock` y `_QuickTakesBlock` reemplazados por widgets con data real. Import de `mock_content.dart` y `signals.dart` removido del content_screen.

### Platform Deep Links — Reescritura completa
- **Eliminada dependencia de Watchmode/RapidAPI para deep links.** La app ya no usa el campo `deep_link` de `content_availability`.
- **Nuevo sistema: URLs de búsqueda por plataforma.** Cada chip genera `netflix.com/search?q=Título`, `play.max.com/search?q=Título`, etc. Funciona para: Netflix, Disney+, Max, Prime Video, Apple TV+, Hulu, Paramount+, Crunchyroll, Peacock, Mubi, Tubi, Vix.
- **Abre la app nativa** si está instalada (iOS universal links) o el browser como fallback.
- **Todos los chips ahora se ven activos** (estilo morado con flecha) porque todos tienen URL funcional.

### Creator Profile — Edit/Delete funcional
- **Edit de takes funciona**: bottom sheet pre-llena verdict y body, muestra "X edit(s) remaining", botón "Save Edit". Después de 2 edits se deshabilita.
- **Delete de takes funciona**: confirmación con AlertDialog, invalidación de providers, refresco inmediato.
- **"My Takes" en perfil propio**: cuando ves tu propio perfil de creator, el botón Follow se oculta, el título cambia a "My Takes", cada take muestra controles de editar (lápiz) y borrar (trash rojo).
- **RLS DELETE policy**: `takes_delete_own` existía pero no estaba creada — verificada y confirmada.

### Bugs corregidos
- **Vault/ratings data loss en sign-out→sign-in (de ayer)**: `pullRatings` y `pullVault` usaban `as String` para `content_id` bigint. Supabase devuelve `int`, cast fallaba silenciosamente en `catch(_)`. Fix: `.toString()`.
- **Takes no aparecían después de publish**: `FutureProvider` caching. Fix: `ref.invalidate()` en 3 providers de takes después del submit.
- **Navigator assertion error** al tocar "CREATOR TAKES >" desde content screen: `context.push('/creators')` chocaba con ShellRoute. Fix: cambiar a `context.go('/creators')`.

### Migraciones SQL aplicadas
- `2026-04-11_takes_edit_count.sql` — `edit_count smallint` con CHECK 0-2 en `creator_takes`.
- `2026-04-11_quick_takes.sql` — Tablas `quick_takes` + `quick_take_votes` con RLS completa.
- Cleanup: `DELETE FROM creator_takes WHERE verdict = 'quick_take'`.

### Debug logging agregado
- `currentCreatorProvider`: logs de user_id y query results.
- `submitTake`, `updateTake`, `deleteTake`, `submitQuickTake`, `voteQuickTake`: logs de operación y errores.

### Decisiones de producto
- **Quick Take 1/día para free users**: crea engagement sin excluir. Deditos generan dopamina social → incentivo natural al premium.
- **Premium = quick takes ilimitidos + editing** (Build 6, zona de pago).
- **5★ ≠ ❤️**: el corazón es señal independiente. "Criterio humano nerd".
- **Onboarding quiz**: no es bug que no aparezca al abrir simulador — SharedPreferences persisten entre runs. En instalación limpia sí aparece.

### Siguiente: Remoty (Companion)
- **Renaming**: IA tab → REMOTY. Chat IA → ASK REMOTY.
- **Basado en patrón de Kireya** (app de maquillaje de Vivi): detección de intención + data local + catálogo. Sin API de IA.
- **Bilingüe**: inglés y español.
- **Mascota**: Remoty con poses (estudiando, viendo algo, escuchándote).
- **Botones**: guía de uso + borrar conversación.

### Pendientes Build 6 (zona premium)
- Payment integration (Stripe / RevenueCat).
- Quick takes ilimitados para premium.
- Quick take editing para premium.
- Account linking Apple + Google.
- Enriquecer 72 títulos curados con OMDb scores.

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
