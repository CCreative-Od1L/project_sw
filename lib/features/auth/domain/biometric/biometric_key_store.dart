import 'dart:typed_data';

/// Whether the device can currently perform strong biometric authentication.
enum BiometricAvailability {
  /// A registered biometric and a platform hardware-backed key store exist.
  available,

  /// The device cannot offer the required biometric path.
  unavailable,
}

/// The narrow seam used by the vault to access a platform biometric key.
///
/// Implementations must keep the key protected by Android Keystore or iOS
/// Keychain. The returned bytes are transient key material released only for
/// the current operation; callers must never persist them or log them.
abstract interface class BiometricKeyStore {
  /// Reports whether the platform can create or release the biometric key.
  Future<BiometricAvailability> get availability;

  /// Replaces the platform key and returns its transient key bytes.
  Future<Uint8List> createAndStoreKey();

  /// Authenticates the user and returns the current transient key bytes.
  Future<Uint8List> loadKey();

  /// Removes the platform key and any protected platform-side envelope.
  Future<void> deleteKey();
}

/// Base class for normalized biometric platform failures.
sealed class BiometricKeyStoreException implements Exception {
  /// Creates a normalized platform failure.
  const BiometricKeyStoreException(this.message, {this.cause});

  /// A safe diagnostic message that contains no credentials or key material.
  final String message;

  /// The normalized platform cause, when available.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The device has no enrolled biometric or compatible hardware.
final class BiometricUnavailableException extends BiometricKeyStoreException {
  /// Creates an unavailable-biometric failure.
  const BiometricUnavailableException({Object? cause})
    : super('Biometric unlock is unavailable on this device.', cause: cause);
}

/// The user or operating system cancelled the biometric prompt.
final class BiometricCancelledException extends BiometricKeyStoreException {
  /// Creates a cancelled-biometric failure.
  const BiometricCancelledException({Object? cause})
    : super('Biometric unlock was cancelled.', cause: cause);
}

/// The enrolled biometric set no longer matches the protected platform key.
final class BiometricInvalidatedException extends BiometricKeyStoreException {
  /// Creates an invalidated-biometric failure.
  const BiometricInvalidatedException({Object? cause})
    : super('The enrolled biometric set changed.', cause: cause);
}

/// A biometric prompt was attempted but did not authorize the operation.
final class BiometricAuthenticationException
    extends BiometricKeyStoreException {
  /// Creates a generic biometric-authentication failure.
  const BiometricAuthenticationException({Object? cause})
    : super('Biometric authentication failed.', cause: cause);
}
