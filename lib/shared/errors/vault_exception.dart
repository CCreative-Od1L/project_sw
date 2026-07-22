/// Base exception for project-owned vault failures.
sealed class VaultException implements Exception {
  /// Creates a vault exception with a safe diagnostic [message].
  const VaultException(this.message, {this.cause});

  /// A message that must not contain secrets.
  final String message;

  /// The normalized underlying cause, when available.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Raised when an operation requires an unlocked vault.
final class VaultLockedException extends VaultException {
  /// Creates a locked-vault exception.
  const VaultLockedException() : super('The vault is locked.');
}

/// Raised when a supplied master password cannot unlock a vault.
final class InvalidMasterPasswordException extends VaultException {
  /// Creates an invalid-master-password exception.
  const InvalidMasterPasswordException()
    : super('The master password is invalid.');
}

/// Raised when vault data fails integrity or format validation.
final class VaultCorruptedException extends VaultException {
  /// Creates a vault-corruption exception.
  const VaultCorruptedException({Object? cause})
    : super('The vault data is corrupted.', cause: cause);
}

/// Raised when a vault file operation fails.
final class VaultIoException extends VaultException {
  /// Creates a vault I/O exception.
  const VaultIoException({Object? cause})
    : super('The vault could not be read or written.', cause: cause);
}

/// Raised when the cryptography runtime cannot initialize.
final class CryptoInitializationException extends VaultException {
  /// Creates a crypto-initialization exception.
  const CryptoInitializationException({Object? cause})
    : super('Cryptography could not be initialized.', cause: cause);
}

/// Raised when a cryptographically secure random source is unavailable.
final class EntropyUnavailableException extends VaultException {
  /// Creates an entropy-unavailable exception.
  const EntropyUnavailableException({Object? cause})
    : super('Secure randomness is unavailable.', cause: cause);
}

/// Raised when a caller violates a public input contract.
final class InvalidArgumentException extends VaultException {
  /// Creates an invalid-argument exception.
  const InvalidArgumentException(super.message);
}
