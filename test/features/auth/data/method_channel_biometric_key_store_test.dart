import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/data/method_channel_biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/biometric_key_store');
  late MethodChannelBiometricKeyStore store;

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  setUp(() {
    store = const MethodChannelBiometricKeyStore(channel: channel);
  });

  test('maps platform availability and key lifecycle calls', () async {
    final List<String> calls = <String>[];
    final Uint8List key = Uint8List.fromList(List<int>.filled(32, 7));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call.method);
          return switch (call.method) {
            'isAvailable' => true,
            'createKey' || 'loadKey' => key,
            'deleteKey' => null,
            _ => null,
          };
        });

    expect(await store.availability, BiometricAvailability.available);
    expect(await store.createAndStoreKey(), orderedEquals(key));
    expect(await store.loadKey(), orderedEquals(key));
    await store.deleteKey();
    expect(calls, <String>['isAvailable', 'createKey', 'loadKey', 'deleteKey']);
  });

  test('normalizes cancellation and biometric invalidation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(
            code: switch (call.method) {
              'createKey' => 'cancelled',
              'loadKey' => 'invalidated',
              _ => 'failed',
            },
          );
        });

    expect(
      store.createAndStoreKey(),
      throwsA(isA<BiometricCancelledException>()),
    );
    expect(store.loadKey(), throwsA(isA<BiometricInvalidatedException>()));
    expect(store.deleteKey(), throwsA(isA<BiometricAuthenticationException>()));
  });

  test('rejects a platform response that is not a 256-bit key', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (MethodCall call) async => Uint8List(31),
        );

    expect(store.loadKey(), throwsA(isA<BiometricAuthenticationException>()));
  });
}
