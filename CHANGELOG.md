# Changelog

All notable user-visible changes to PROJECT_SW are documented here.

## [1.0.0] - Unreleased

### Added

- Biometric unlock with master-password fallback and biometric-set invalidation handling.
- Master-password step-up protection for high-sensitivity settings and recovery actions.
- Local network migration core with pairing payloads, ephemeral session encryption, transcript integrity, conflict handling, and atomic import.
- Master-password recovery with biometric confirmation, cooldown, and deadlock-wipe protection.
- Material-style settings, recovery, and lock-state experiences.

### Security and privacy

- Background, timeout, manual, biometric-invalidation, and wipe locks clear application-held sensitive state.
- Asynchronous authentication results are bound to the session that started them; stale results cannot restore a newer session.
- Clipboard cleanup remains best-effort on Android. Vendor clipboard implementations and third-party input methods may retain copies outside the app's control.

### Known limitations

- QR display, camera scanning, and migration pages remain in unmerged PR #64. The candidate still needs migration master-password step-up and integration with the current session activity lease/guard APIs and production wiring.
- A failed wipe keeps the current process locked, but wipe progress/failure state is not persisted across process restarts. Restart-safe handling of an incomplete wipe remains an implementation gap.
- LAN migration integration, restart-safe wipe handling, final Android real-device acceptance, production signing configuration, and a complete tag-to-Release rehearsal remain release-gate work. The Android signing/build/publish pipeline is implemented, with a temporary-signing AAB build recorded. An iOS software release is outside the V1.0 scope because signing certificates and distribution qualification are unavailable.
