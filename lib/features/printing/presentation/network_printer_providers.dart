// Providers Riverpod para la impresora térmica de red (impresión por TCP).
//
// - networkPrinterStoreProvider: persistencia local (shared_preferences).
// - networkPrintServiceProvider: servicio render + envío TCP.
// - networkPrinterConfigProvider: AsyncNotifier con la config local; expone
//   save() para actualizar y persistir.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/network/network_print_service.dart';
import '../data/network/network_printer_config.dart';

final networkPrinterStoreProvider = Provider<NetworkPrinterStore>((ref) {
  return const NetworkPrinterStore();
});

final networkPrintServiceProvider = Provider<NetworkPrintService>((ref) {
  return NetworkPrintService();
});

class NetworkPrinterConfigController extends AsyncNotifier<NetworkPrinterConfig> {
  NetworkPrinterStore get _store => ref.read(networkPrinterStoreProvider);

  @override
  Future<NetworkPrinterConfig> build() => _store.load();

  /// Persiste y refleja en memoria la nueva configuración.
  Future<void> save(NetworkPrinterConfig config) async {
    state = AsyncValue.data(config);
    await _store.save(config);
  }
}

final networkPrinterConfigProvider =
    AsyncNotifierProvider<NetworkPrinterConfigController, NetworkPrinterConfig>(
  NetworkPrinterConfigController.new,
);
