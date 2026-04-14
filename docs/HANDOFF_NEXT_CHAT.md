# Handoff — Mensaje para el próximo chat

Hola, yo-del-futuro 👋

Este chat se compiló 3 veces, así que Vivi pidió cerrar y arrancar fresco. Todo el estado está en `docs/BITACORA.md` (entradas 2026-04-14 Fase 1 y Fase 2a-1) y en auto-memory (`project_flixscope.md`). Este handoff resume solo lo necesario para retomar sin fricción.

---

## Estado al cerrar sesión (2026-04-14)

**Fase 1 (Supabase sync completo del perfil):** ✅ VALIDADA.
**Fase 2a-1 (5 Gems personalizadas):** ✅ VALIDADA en simulador.
**Build 15 oficial:** código listo, **pendiente archive desde Xcode**. Acumula los fixes de Build 14 + Fase 1 + Fase 2a-1.

### Qué cambió hoy en el código (no compilado aún)

- `lib/data/repositories/supabase_sync.dart` — Fix B: catch silenciosos reemplazados por `debugPrint` en `kDebugMode`.
- `lib/data/repositories/catalog_provider.dart` — refactor grande: helpers de scoring, `dailyGemsProvider` personalizado, platform filter en Trending/Exploding/QuickDecision/PopularInRegion/Bingeable.
- `lib/presentation/screens/home/home_screen.dart` — sort de 5 Gems por `gemRank` ASC en vez de `watcherScore`.

Además en Supabase (ya aplicado vía MCP):
- Migración `user_vault.bucket CHECK` ahora incluye `loved`.
- Migración schema expansion en `public.profiles` (activePlatforms / favoriteGenres / sessionLength / favoriteThemes / watchedCanonIds).
- Nuke #2 de `auth.users` ejecutado (DB limpia, content 6,713 intacto).
- Creator `@izaivi` recreado (`3f248014-315a-470f-9b0e-3ca6cf5e8ef4`).

### Validación de Vivi al final

> "perfecto, mi home cambio, no veo sugeridos los mismos títulos ni lo que yo tengo con corazón o alto ranking, las 5 gemas cambiaron. bien"

Los 3 vectores del refactor funcionan: daily rotation con seed, composite+bonus aplicado al perfil real, exclusión de watched/dismissed.

---

## Cómo arrancar la próxima sesión

1. **Saluda breve** (Vivi es sprint y directa, no te extiendas en preámbulos).
2. **Confirma orden de pendientes:**
   - (a) ¿Ya pegaste los 4 takes como `@izaivi`? — deberían aparecer con reason "Curated pick..." y subir en ranking por el boost 1.5×.
   - (b) ¿Compilamos Build 15 oficial en Xcode? Antes del archive: `flutter analyze` esperando 0 errores, y verificar que Google Provider en Supabase Dashboard tenga el iOS Client ID (`64121881188-t7oljdru0mpff5doo7evi0i9gdk6fu9p.apps.googleusercontent.com`) en Authorized Client IDs.
3. **Luego decidan juntas:** Fase 2a-2 (community signals) necesita más users para calibrar — NO empujar aún. Alternativas naturales:
   - **Fase 3** — Settings → "Change my preferences" (retake de Fast/Long Quiz).
   - **Fase 4** — Remoty leyendo `userProfileProvider` (incluidos `favoriteThemes`) para personalizar la conversación (ej. "vi que te gusta Keanu Reeves").
   - **Pendientes sueltos de la lista viva** (ver sección abajo).

---

## Cosas importantes de Vivi (para calibrar tono)

- **Fundadora de Punky Tiger Labs**, Flixscope es iOS-first. Bundle locked `com.punkytigerlabs.theremote`.
- **Bilingüe ES/EN**, responde en español con puntadas en inglés. Emojis puntuales (🥹, 💜, 🤓).
- **Técnica y sprint**, pero no es Flutter su stack principal. Agradece analogías cuando hay conceptos nuevos (nonce, RLS, composite scoring).
- **Prefiere planeación antes de tocar DB o arquitectura**, pero una vez alineadas **ejecuta rápido**. Si te dice "procede" significa "déjame de preguntas, hazlo".
- **Lee bitácora y handoff** al volver — no tienes que recapitular todo.
- **Corre Flutter desde terminal con `--dart-define`**, NO desde Xcode (Xcode no inherita los defines).
- **Calibra Terms/Community Guidelines al estándar de Ultimate F1 Fan** (app hermana ya publicada), no plantillas SaaS genéricas.

---

## Pendientes vivos (por prioridad)

1. **Archive Build 15 oficial en Xcode** — acumula Build 14 fixes + Fase 1 + Fase 2a-1.
2. **Takes de `@izaivi`** — Vivi los pega en DB; validar que aparezcan como "Curated pick..." en Home.
3. **Remoty + anime intent** — confunde anime con animación general. Filtro por `genre_ids + origin_country=JP`. Prioridad baja.
4. **SharedPreferences user-scoped keys** — refactor estructural, Build 10+. No urgente pero bug latente.
5. **Enriquecer 72 títulos curados con OMDb** — entraron con `--skip-omdb`.
6. **Android: agregar testers al canal interno.**
7. **Apple JWT** client_secret vence 2026-09-28 — scheduled task `apple-jwt-renewal-the-remote`.
8. **Tech-debt Build 15+:** migrar `withOpacity` a `.withValues()` (~180 sites) y limpiar `!` innecesarios.
9. **Pulido visual del email de Magic Link** — hoy es HTML plano funcional, falta logo + branding.

---

## Archivos clave

- `docs/BITACORA.md` — historial completo. Entradas más recientes: 2026-04-14 Fase 1 y Fase 2a-1.
- `docs/supabase/schema.sql` — schema vigente en producción.
- `lib/data/repositories/catalog_provider.dart` — motor de 5 Gems + rows de Home. Helpers de scoring al final del archivo.
- `lib/data/repositories/supabase_sync.dart` — wrapper pull/push, ahora con logs de sync en debug.
- `lib/data/repositories/user_profile_repository.dart` — controller del perfil, `refreshFromRemote` toma `remote.quizCompletion` como canónico.
- `lib/presentation/screens/home/home_screen.dart` — Home, sort por `gemRank` ASC.
- `lib/main.dart` — listener de `authStateChangesProvider`. **NO toquées sin entenderla** — tiene el fix del user switch y del quiz leak.
- `scripts/generate_apple_jwt.py` — renueva JWT de Apple cada 180 días.

---

## Filosofía del engine (para que no la pierdas)

**No somos IMDb/RT.** El gate de ≥2 fuentes es anti-bot: un 8.5 inflado en IMDb solo no pasa el gate si RT y Meta no lo respaldan. La personalización es bonus aditivo, nunca reemplaza el filtro de calidad. Entre dos títulos de calidad, el que matchea el taste del user gana. Entre uno de calidad y uno inflado, siempre el de calidad.

Cualquier cambio futuro al ranking debe mantener esta jerarquía.

---

Vamos muy bien. Suerte 💜
