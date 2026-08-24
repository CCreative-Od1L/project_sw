import 'dart:typed_data';

import 'package:project_sw/features/auth/data/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:test/test.dart';

void main() {
  test('confirms biometrics and clears the released key bytes', () async {
    final Uint8List releasedKey = Uint8List.fromList(
      List<int>.generate(32, (int index) => index + 1),
    );
    final BiometricKeyStoreRecoveryConfirmer confirmer =
        BiometricKeyStoreRecoveryConfirmer(
          _RecoveryBiometricKeyStore(releasedKey),
        );

    await confirmer.confirm();

    expect(releasedKey, everyElement(0));
  });
}

final class _RecoveryBiometricKeyStore implements BiometricKeyStore {
  _RecoveryBiometricKeyStore(this.key);

  final Uint8List key;

  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;

  @override
  Future<Uint8List> createAndStoreKey() async => throw UnimplementedError();

  @override
  Future<void> deleteKey() async => throw UnimplementedError();

  @override
  Future<Uint8List> loadKey() async => key;
}
