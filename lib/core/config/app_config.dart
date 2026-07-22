/// Immutable process configuration for the initial application skeleton.
final class AppConfig {
  /// Creates application configuration with conservative security defaults.
  const AppConfig({
    this.vaultExistsAtLaunch = false,
    this.idleTimeout = const Duration(minutes: 5),
  });

  /// Whether bootstrap has established that a vault exists on this device.
  final bool vaultExistsAtLaunch;

  /// The future session idle timeout, owned by the session source of truth.
  final Duration idleTimeout;
}
