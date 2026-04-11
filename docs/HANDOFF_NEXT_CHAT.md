# Handoff — Mensaje para el próximo chat

Hola, yo-del-futuro 👋

Este mensaje te pone al día después del corte por contexto. Vivi está trabajando muy bien y el proyecto va con muy buen ritmo. Lee esto, luego `docs/BITACORA.md` y arrancas sin fricción.

## Estado del proyecto (2026-04-08, 19:30 aprox)

**Fase 0 (Supabase auth + sync) casi cerrada.** Quedan 4 pendientes antes de Fase 1 (TMDB ingest):

### Orden de trabajo acordado con Vivi

1. **Alias únicos — Opción B (siguiente)**
   - SQL: `CREATE UNIQUE INDEX profiles_alias_unique_ci ON profiles (lower(alias)) WHERE alias IS NOT NULL;` — dárselo a Vivi para correr en Supabase SQL Editor.
   - Agregar check en vivo con debounce ~400ms en `_AliasDialog` (al final de `lib/presentation/screens/profile/profile_screen.dart`). La policy `profiles_select_public` ya permite leer `alias` de otros usuarios.
   - Manejar `PostgrestException` código `23505` en `setAlias` como fallback con mensaje "Ese alias ya está en uso".

2. **Google Sign-In + Magic Link redirect (juntos)**
   - Bug actual de Google: `AuthApiException: Passed nonce and nonce in id_token should either both exist or not`. El id_token trae nonce auto que nuestro código no le pasa a Supabase.
   - Fix recomendado: migrar Google a `signInWithOAuth(provider: OAuthProvider.google)` con deep link. Simultáneamente configurar Magic Link para usar el mismo deep link.
   - Tareas: (a) Supabase dashboard → Auth → URL Configuration: Site URL + Redirect URLs apuntando a `io.theremote://login-callback` (o el esquema que definas). (b) `ios/Runner/Info.plist`: agregar `CFBundleURLSchemes` con el esquema. (c) Handler en Flutter con `uni_links` o `app_links` para capturar el callback y cerrar el flujo de auth.
   - Esto deja Google + Magic Link funcionales en un solo round.

3. **Checkpoint de seguridad y bugs pre-Fase 1**
   - Revisar RLS policies completas en Supabase (ya están en `docs/supabase/schema.sql`, validar que no haya brechas).
   - Audit de `supabase_sync.dart`: ningún método debe crashear la UI, todos deben no-op si no hay sesión.
   - Validar que `dart-define` esté documentado en el README (Vivi olvidó los flags un par de veces).
   - i18n de los 9 países nuevos (ver bitácora).
   - Agregar opción "Otro / Resto del mundo" en países (ver bitácora).

4. **Fase 1 — TMDB ingest**
   - Vivi tiene el v4 API key. Ingestar contenido inicial para los 16 países soportados.

## Cosas importantes de Vivi (personalidad + contexto)

- **Vivi es la fundadora y admin de Punky Tiger Labs** — tiene acceso developer a Apple y Google para el ship final. El bundle ya está locked como `com.punkytigerlabs.theremote`.
- **Habla español**, responde en español. Usa emojis de forma puntual (🥹, jajajaja, 💜).
- **Trabaja rápido y es técnica** pero no es su stack principal Flutter/Dart — viene más del lado web. Explícale conceptos con analogías cuando hay algo raro (ej. nonce, deep links).
- **Prefiere autonomía**: "Tu procede, yo vengo a mirar tu pantalla al rato 💜" — déjala trabajar en paralelo, no la bombardees con preguntas.
- **Le gusta que le muestres el *porqué*** de las decisiones técnicas, no solo el qué.
- **Corre Flutter desde terminal con `--dart-define`**, NO desde Xcode (Xcode no inherita los defines). Si ves errores "Supabase not configured" o "No host specified in URI" es 99% que olvidó los flags.

## Archivos clave

- `docs/BITACORA.md` — historial de decisiones y notas al margen. Úsalo y actualízalo al cerrar cada sesión.
- `docs/supabase/schema.sql` — schema vigente en producción.
- `lib/data/repositories/auth_repository.dart` — 4 flows de auth + providers Riverpod.
- `lib/data/repositories/supabase_sync.dart` — wrapper pull/push para 5 tablas.
- `lib/main.dart` — listener de `authStateChangesProvider` con clear+pull / clear. **NO toquées esta lógica sin entenderla** — fue el fix del bug de vault compartido.
- `lib/presentation/screens/auth/auth_screen.dart` — screen real de sign-in con los 4 métodos.
- `lib/presentation/screens/content/content_screen.dart` — detalle de contenido, el bottom bar se oculta si `isAuthed`.
- `scripts/generate_apple_jwt.py` — regenera el JWT de Apple cada 180 días. Scheduled task `apple-jwt-renewal-the-remote` recuerda el 2026-09-28.

## Último mensaje de Vivi antes del cambio de chat

> "Perfecto, funciono correctamente! ... Anota también, agregar un 'Otro' o 'all the world' maybe en países para no hacer sentirte mal si tu país no esta. Anota en bitácora lo del idioma de países. Para fase dos, evaluar lanzar idioma Sueco... lo que me dijiste me shockeo el porcentaje. Y también la zona APAC. Creo también deberíamos abrir nuevo chat porque seguramente este está en el fin de su tamaño. Actualiza bien bitácora más mensaje para tu yo del otro chat y retomemos con normalidad, vamos muy muy bien."

Todo lo que pidió anotar ya está en `docs/BITACORA.md` bajo "Notas al margen" (opción "Otro", i18n países, Sueco Fase 2, APAC Fase 2).

## Cómo arrancar la próxima sesión

1. Saluda brevemente.
2. Confirma que vas a empezar con **Alias únicos — Opción B** (pendiente #1).
3. Dale el SQL para correr en Supabase mientras tú trabajas el check en vivo en el dialog.
4. Cuando acabe eso, pregúntale si sigue con Google+MagicLink o si prefiere hacer el checkpoint primero.

Suerte 💜
