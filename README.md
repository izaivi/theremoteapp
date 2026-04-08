# The Remote — Flutter

iOS-first Flutter app. Stack: Riverpod, GoRouter, Dio, Hive + Drift, freezed.

## Setup

```bash
flutter pub get
flutter run -d ios
```

## Estructura

```
lib/
  core/
    theme/      — colors, theme (Material 3 con feel iOS)
    router/     — GoRouter (5 tabs + rutas secundarias)
    constants/
  data/
    models/     — entidades (Content, Gem, etc.)
    mock/       — mock data para desarrollo sin backend
    repositories/
  domain/
  presentation/
    screens/    — home, discover, chat, creators, profile, content
    widgets/    — main_scaffold, watcher_score_badge, ...
    providers/  — Riverpod
```

## Estado actual (F-1 a F-6 parcial)

- ✅ Bootstrap + estructura de carpetas
- ✅ Theme dark + design tokens
- ✅ Modelos base (sin freezed aún — pendiente F-3)
- ✅ GoRouter con 5 tabs
- ✅ Mock repository
- 🚧 Home screen (versión inicial con score badge + carrusel)
- ⬜ Resto de pantallas (stubs)

Siguiente: migrar modelos a freezed + Home con todas sus secciones
(Exploding, Quick Decision, Don't Waste Your Time, etc.) y conectar
el repository vía Riverpod provider.
