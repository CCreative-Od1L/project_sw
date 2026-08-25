# Changelog

All notable user-visible changes to PROJECT_SW are documented here.

## [1.0.0] - Unreleased

### Added

- Biometric unlock with master-password fallback and biometric-set invalidation handling.
- Master-password step-up protection for high-sensitivity settings and recovery actions.
- Local network vault migration with QR pairing, ephemeral session encryption, transcript integrity, conflict handling, and atomic import.
- Master-password recovery with biometric confirmation, cooldown, and deadlock-wipe protection.
- Material-style settings, recovery, migration, and lock-state experiences.

### Security and privacy

- Background, timeout, manual, biometric-invalidation, and wipe locks clear application-held sensitive state.
- Asynchronous authentication results are bound to the session that started them; stale results cannot restore a newer session.
- Clipboard cleanup remains best-effort on Android. Vendor clipboard implementations and third-party input methods may retain copies outside the app's control.

### Known limitations

- Android release signing and real-device acceptance remain release-gate work. An iOS software release is outside the V1.0 scope because signing certificates and distribution qualification are unavailable.
