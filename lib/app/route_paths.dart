/// Canonical feature paths for the v0.5 application shell.
const String vaultRoutePath = '/home';

/// Generator remains reachable while the vault is locked.
const String generatorRoutePath = '/generator';

/// Settings is protected by the unlocked session route policy.
const String settingsRoutePath = '/settings';

/// Route for the unlocked local-network vault migration flow.
const String migrationRoutePath = '/migration';
