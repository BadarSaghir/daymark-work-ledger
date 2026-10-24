# Contributing to Daymark

Daymark is a solo-built project, but careful contributions are welcome.

## Before opening a pull request

1. Open an issue for anything larger than a bug fix or documentation correction.
2. Keep the app offline-first. New network features must be explicit, local by
   default, and documented in the privacy notes.
3. Preserve existing data. Any schema change needs a numbered migration, a
   pre-migration snapshot, and a test that upgrades an old database.
4. Keep markdown as the user-facing rich-text format.

## Local checks

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

The same commands run in GitHub Actions. A pull request should not reduce test
coverage or introduce analyzer warnings.

## Commit style

Use short, imperative subjects, for example:

```text
Add calendar load heatmap
Fix compact planner overflow
```

## Code style

- Follow the existing feature-first structure under `lib/features`.
- Use the shared colour, type, and surface primitives instead of hard-coded
  styles.
- Prefer small widgets and named private builders over deeply nested build
  methods.
- Document non-obvious product decisions, especially anything about weight,
  time, or data safety.
