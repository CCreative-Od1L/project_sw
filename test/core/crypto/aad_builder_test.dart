import 'dart:typed_data';

import 'package:project_sw/core/crypto/aad_builder.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:test/test.dart';

void main() {
  test('DEK wrapping AAD binds the stable EntryRecord identity', () {
    final Uint8List first = AadBuilder.forWrapDek(
      magic: vaultMagic,
      formatVersion: vaultFormatVersion,
      aeadAlgorithmId: 1,
      entryId: Uint8List.fromList(List<int>.filled(16, 1)),
    );
    final Uint8List second = AadBuilder.forWrapDek(
      magic: vaultMagic,
      formatVersion: vaultFormatVersion,
      aeadAlgorithmId: 1,
      entryId: Uint8List.fromList(List<int>.filled(16, 2)),
    );

    expect(first, isNot(second));
    expect(first, isNot(equals(second)));
  });

  test('entry plaintext AAD binds both identity and revision sequence', () {
    final Uint8List id = Uint8List.fromList(List<int>.filled(16, 3));
    final Uint8List first = AadBuilder.forEncryptEntry(
      magic: vaultMagic,
      formatVersion: vaultFormatVersion,
      aeadAlgorithmId: 1,
      entryId: id,
      sequence: 2,
    );
    final Uint8List second = AadBuilder.forEncryptEntry(
      magic: vaultMagic,
      formatVersion: vaultFormatVersion,
      aeadAlgorithmId: 1,
      entryId: id,
      sequence: 3,
    );

    expect(first, isNot(equals(second)));
  });

  test('biometric MVK wrapping AAD has a distinct purpose label', () {
    final Uint8List biometric = AadBuilder.forWrapBiometricMvk(
      magic: vaultMagic,
      formatVersion: vaultFormatVersion,
      aeadAlgorithmId: 1,
    );
    final Uint8List dek = AadBuilder.forWrapDek(
      magic: vaultMagic,
      formatVersion: vaultFormatVersion,
      aeadAlgorithmId: 1,
      entryId: Uint8List(16),
    );

    expect(biometric, isNot(equals(dek)));
    expect(biometric, endsWith(<int>[0x62, 0x69, 0x6f, 0x2d, 0x6d, 0x76, 0x6b]));
  });
}
