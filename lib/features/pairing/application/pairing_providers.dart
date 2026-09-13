// lib/features/pairing/application/pairing_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/pairing_repository.dart';
import '../domain/paired_device.dart';

final pairingRepositoryProvider = Provider<PairingRepository>(
  (ref) => PairingRepository(ref.watch(functionsProvider)),
);

class PairedDeviceController extends AsyncNotifier<PairedDevice?> {
  @override
  Future<PairedDevice?> build() {
    return ref.read(pairingRepositoryProvider).loadPairedDevice();
  }

  Future<void> setPaired(PairedDevice device) async {
    await ref.read(pairingRepositoryProvider).savePairedDevice(device);
    state = AsyncData(device);
  }

  Future<void> clear() async {
    await ref.read(pairingRepositoryProvider).clearPairedDevice();
    state = const AsyncData(null);
  }
}

final pairedDeviceProvider =
    AsyncNotifierProvider<PairedDeviceController, PairedDevice?>(
  PairedDeviceController.new,
);
