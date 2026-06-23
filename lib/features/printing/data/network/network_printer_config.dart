import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Configuración local (por terminal) de la impresora térmica de red.
///
/// Se guarda en `shared_preferences` porque la IP de la impresora es
/// específica de la máquina/LAN donde corre el POS, no del negocio en la nube.
class NetworkPrinterConfig {
  const NetworkPrinterConfig({
    this.enabled = false,
    this.host = '',
    this.port = 9100,
    this.paperColumns = 48,
    this.openDrawerOnCashSale = false,
    this.copies = 1,
  });

  /// Si está activa, el diálogo de impresión ofrece imprimir por TCP.
  final bool enabled;

  /// IP o hostname de la impresora (ej. `192.168.1.50`).
  final String host;

  /// Puerto crudo TCP (RAW/JetDirect). Estándar de facto: 9100.
  final int port;

  /// Ancho del papel en columnas: 48 (80mm) o 32 (58mm).
  final int paperColumns;

  /// Abrir la gaveta de efectivo al imprimir (útil en ventas en efectivo).
  final bool openDrawerOnCashSale;

  /// Número de copias por defecto.
  final int copies;

  bool get isConfigured => host.trim().isNotEmpty;

  bool get isReady => enabled && isConfigured;

  NetworkPrinterConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    int? paperColumns,
    bool? openDrawerOnCashSale,
    int? copies,
  }) {
    return NetworkPrinterConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      paperColumns: paperColumns ?? this.paperColumns,
      openDrawerOnCashSale: openDrawerOnCashSale ?? this.openDrawerOnCashSale,
      copies: copies ?? this.copies,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'host': host,
        'port': port,
        'paper_columns': paperColumns,
        'open_drawer_on_cash_sale': openDrawerOnCashSale,
        'copies': copies,
      };

  factory NetworkPrinterConfig.fromJson(Map<String, dynamic> json) {
    return NetworkPrinterConfig(
      enabled: json['enabled'] as bool? ?? false,
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 9100,
      paperColumns: (json['paper_columns'] as num?)?.toInt() ?? 48,
      openDrawerOnCashSale: json['open_drawer_on_cash_sale'] as bool? ?? false,
      copies: (json['copies'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Persistencia local de [NetworkPrinterConfig].
class NetworkPrinterStore {
  const NetworkPrinterStore();

  static const _key = 'shop_plus.network_printer_config.v1';

  Future<NetworkPrinterConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const NetworkPrinterConfig();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return NetworkPrinterConfig.fromJson(json);
    } catch (_) {
      return const NetworkPrinterConfig();
    }
  }

  Future<void> save(NetworkPrinterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
