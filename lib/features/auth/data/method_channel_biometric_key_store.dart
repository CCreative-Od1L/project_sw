import 'package:flutter/services.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';

/// Flutter adapter for the Android Keystore/iOS Keychain biometric seam.
final class MethodChannelBiometricKeyStore implements BiometricKeyStore {
  /// Creates an adapter, with an injectable channel for platform tests.
  const MethodChannelBiometricKeyStore({this._channel = _defaultChannel});

  static const MethodChannel _defaultChannel = MethodChannel(
    'project_sw/biometric_key_store',
  );

  final MethodChannel _channel;

  @override
  Future<BiometricAvailability> get availability async {
    try {
      final bool available =
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
      return available
          ? BiometricAvailability.available
          : BiometricAvailability.unavailable;
    } on PlatformException catch (error) {
      throw _normalizePlatformException(error);
    }
  }

  @override
  Future<Uint8List> createAndStoreKey() => _invokeKeyMethod('createKey');

  @override
  Future<Uint8List> loadKey() => _invokeKeyMethod('loadKey');

  @override
  Future<void> deleteKey() async {
    try {
      await _channel.invokeMethod<void>('deleteKey');
    } on PlatformException catch (error) {
      throw _normalizePlatformException(error);
    }
  }

  Future<Uint8List> _invokeKeyMethod(String method) async {
    try {
      final Uint8List? key = await _channel.invokeMethod<Uint8List>(method);
      if (key == null || key.length != 32) {
        throw const BiometricAuthenticationException();
      }
      return Uint8List.fromList(key);
    } on PlatformException catch (error) {
      throw _normalizePlatformException(error);
    }
  }

  BiometricKeyStoreException _normalizePlatformException(
    PlatformException error,
  ) {
    return switch (error.code) {
      'unavailable' => BiometricUnavailableException(cause: error),
      'cancelled' => BiometricCancelledException(cause: error),
      'invalidated' => BiometricInvalidatedException(cause: error),
      _ => BiometricAuthenticationException(cause: error),
    };
  }
}
