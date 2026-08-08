/// Stable failure categories exposed by the migration protocol.
enum MigrationErrorCode {
  /// The pairing payload or frame could not be parsed safely.
  malformed,

  /// The pairing payload is outside its validity window.
  expired,

  /// The two endpoints do not share a supported format or algorithm.
  incompatible,

  /// A frame arrived more than once or out of order.
  sequenceMismatch,

  /// A frame failed authenticated decryption.
  authenticationFailed,

  /// A transcript MAC did not match the authenticated transfer.
  transcriptMismatch,

  /// The session was used after it had been finalized or disposed.
  invalidState,
}

/// Non-sensitive protocol error that can be mapped to user-facing feedback.
final class MigrationProtocolException implements Exception {
  /// Creates a protocol error without embedding secrets or payload contents.
  const MigrationProtocolException(this.code, this.message);

  /// Machine-readable failure category.
  final MigrationErrorCode code;

  /// Safe diagnostic message.
  final String message;

  @override
  String toString() => 'MigrationProtocolException(${code.name}): $message';
}
