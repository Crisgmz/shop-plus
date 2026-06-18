/// Centralized formatters for Shop+.
///
/// Replaces per-page `_money()`, `_date()`, `_pretty()` helpers with a single
/// import. All pages should use these instead of defining local copies.
///
/// Estos formatters son **reactivos** a `app_settings` (PRD 06): el símbolo
/// de moneda, decimales, separadores y formato de fecha se leen de
/// [LiveSettings], que se sincroniza al cambiar la configuración global.
library;

import 'live_settings.dart';

// ── Number helpers ──────────────────────────────────────────────────────────

/// Safely coerce any value to [double].
double toDouble(Object? v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Safely coerce any value to [int].
int toInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

// ── Money ───────────────────────────────────────────────────────────────────

/// Formatea un número como moneda usando los settings globales.
///
/// Ejemplo (defaults RD$, 2 decimales): `money(1500)` → `"RD\$ 1,500.00"`.
String money(Object? amount) {
  final value = toDouble(amount);
  final decimals = LiveSettings.currencyDecimals;
  final thousands = LiveSettings.thousandsSep;
  final decimalPoint = LiveSettings.decimalPoint;
  final symbol = LiveSettings.currencySymbol;

  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final integer = parts[0];
  final decimal = parts.length > 1 ? parts[1] : '';

  final withSep = integer.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => thousands,
  );

  if (decimals == 0 || decimal.isEmpty) {
    return '$symbol $withSep';
  }
  return '$symbol $withSep$decimalPoint$decimal';
}

/// Short money format without decimals for KPIs / compact display.
String moneyShort(Object? amount) {
  final value = toDouble(amount);
  final symbol = LiveSettings.currencySymbol;
  if (value.abs() >= 1000000) {
    return '$symbol ${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value.abs() >= 1000) {
    return '$symbol ${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$symbol ${value.toStringAsFixed(0)}';
}

// ── Dates ───────────────────────────────────────────────────────────────────

/// Formato de fecha según `app_date_format` global.
String formatDate(Object? value) {
  final dt = _parseDate(value);
  if (dt == null) return '—';
  return _applyDateFormat(dt, LiveSettings.dateFormat);
}

/// `dd/MM/yyyy HH:mm` (o el formato configurado) + hora 12h/24h.
String formatDateTime(Object? value) {
  final dt = _parseDate(value);
  if (dt == null) return '—';
  return '${formatDate(dt)} ${_formatTime(dt)}';
}

/// Relative date label: "Hoy", "Ayer", or formato configurado.
String formatDateRelative(Object? value) {
  final dt = _parseDate(value);
  if (dt == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  return formatDate(dt);
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  DateTime? dt;
  if (value is DateTime) {
    dt = value;
  } else if (value is String) {
    dt = DateTime.tryParse(value);
  }
  if (dt == null) return null;
  // Supabase devuelve `timestamptz` en UTC; convertimos a hora local para
  // que `.day`/`.hour`/etc. reflejen la zona del usuario (RD = UTC-4).
  return dt.isUtc ? dt.toLocal() : dt;
}

String _applyDateFormat(DateTime dt, String pattern) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yyyy = dt.year.toString();
  switch (pattern) {
    case 'dd-MM-yyyy':
      return '$dd-$mm-$yyyy';
    case 'MM-dd-yyyy':
      return '$mm-$dd-$yyyy';
    case 'yyyy-MM-dd':
      return '$yyyy-$mm-$dd';
    case 'dd/MM/yyyy':
    default:
      return '$dd/$mm/$yyyy';
  }
}

String _formatTime(DateTime dt) {
  if (LiveSettings.timeFormat == '24h') {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  // 12h
  final isPm = dt.hour >= 12;
  final hour12 = dt.hour == 0
      ? 12
      : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${hour12.toString().padLeft(2, '0')}:$mm ${isPm ? 'PM' : 'AM'}';
}

// ── Percentage ──────────────────────────────────────────────────────────────

/// Format as percentage: `percent(0.152)` → `"15.2%"`
String percent(Object? value) {
  final v = toDouble(value);
  return '${(v * 100).toStringAsFixed(1)}%';
}

// ── Quantity ─────────────────────────────────────────────────────────────────

/// Integer with thousand separators según el separador configurado.
String qty(Object? value) {
  final v = toInt(value);
  final thousands = LiveSettings.thousandsSep;
  return v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}$thousands',
  );
}
