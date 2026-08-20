/// The only route-access state consumed by GoRouter.
enum SessionRouteState {
  /// The first-run route used to create a vault.
  setup,

  /// The route that accepts an existing vault's authentication.
  unlock,

  /// The route available to an unlocked vault session.
  home,
}

/// Maps a [SessionRouteState] to its canonical route path.
extension SessionRouteStatePath on SessionRouteState {
  /// The canonical application path for this state.
  String get path {
    return switch (this) {
      SessionRouteState.setup => '/setup',
      SessionRouteState.unlock => '/unlock',
      SessionRouteState.home => '/home',
    };
  }
}

/// Indicates why bootstrap entered its initial session state.
enum SessionStartReason {
  /// The process started without an existing in-memory session.
  coldStart,
}

/// Enumerates the event that moved an existing vault into a locked state.
enum LockReason {
  /// The app has started and requires the master-password path.
  coldStart,

  /// The app entered background or its idle timeout elapsed.
  backgroundOrTimeout,

  /// The user explicitly locked the vault.
  manualLock,

  /// The operating system invalidated enrolled biometrics.
  biometricInvalidated,

  /// A wipe flow began and must immediately invalidate session data.
  wipeStarted,
}

/// Operation that temporarily suppresses only the foreground idle timeout.
enum LockSuppressionReason {
  /// An unlocked receiver or sender is actively migrating vault data.
  migrationInProgress,

  /// A biometric-assisted master-password recovery is in progress.
  passwordRecoveryInProgress,
}

/// Authentication strength held by an unlocked session.
enum AuthStrength {
  /// No successful authentication is present.
  none,

  /// The session was opened through biometric authentication.
  biometric,

  /// The session has been authenticated with the master password.
  masterPassword,
}

/// Immutable state held by the global session source of truth.
sealed class SessionState {
  /// Creates a session state.
  const SessionState();

  /// The sole route-access state derived from this session state.
  SessionRouteState get routeState;
}

/// State used before any vault has been created on the device.
final class VaultNotCreatedSession extends SessionState {
  /// Creates the initial no-vault state.
  const VaultNotCreatedSession({
    this.startReason = SessionStartReason.coldStart,
  });

  /// The launch reason that produced this bootstrap state.
  final SessionStartReason startReason;

  @override
  SessionRouteState get routeState => SessionRouteState.setup;
}

/// Locked state for an existing vault.
final class LockedSession extends SessionState {
  /// Creates a locked session with its originating [reason].
  const LockedSession({required this.reason});

  /// The event that caused the vault to lock.
  final LockReason reason;

  /// Whether biometric unlock may be offered after this lock reason.
  bool get canUseBiometric =>
      reason == LockReason.coldStart ||
      reason == LockReason.backgroundOrTimeout;

  @override
  SessionRouteState get routeState => SessionRouteState.unlock;
}

/// Unlocked state carrying the session's authentication strength.
final class UnlockedSession extends SessionState {
  /// Creates an unlocked session with the established [authStrength].
  const UnlockedSession({required this.authStrength});

  /// The strongest successful authentication in this unlocked session.
  final AuthStrength authStrength;

  @override
  SessionRouteState get routeState => SessionRouteState.home;
}
