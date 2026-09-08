// PRD 07 — 24 categorías de reportes.
//
// Cada categoría conoce: ícono, título, descripción corta, grupo lógico,
// si admite modo gráfico, y si está implementada en este round.
//
// Las no implementadas aún muestran "Próximamente" en la UI — el sidebar
// las lista para que el usuario vea la matriz completa del PRD.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

enum ReportCategory {
  // Operativos
  ventas,
  caja,
  liquidacion,
  cobros,
  pagos,
  ventasSuspendidas,
  // Empleados
  empleados,
  comision,
  // Productos / Inventario
  inventario,
  articulos,
  categorias,
  etiquetas,
  precios,
  mermas,
  // Financieros
  perdidasGanancias,
  credito,
  gastos,
  compras,
  proveedores,
  // Clientes
  clientes,
  descuentos,
  // Fiscales DGII
  estadoDiario,
  reporte606,
  reporte607,
  reporteIt1,
  cierreZFiscal,
  impuestos,
  // Avanzados
  personalizados;

  String get title {
    switch (this) {
      case ReportCategory.ventas:
        return 'Ventas';
      case ReportCategory.caja:
        return 'Caja';
      case ReportCategory.liquidacion:
        return 'Liquidación';
      case ReportCategory.cobros:
        return 'Cobros';
      case ReportCategory.pagos:
        return 'Pagos';
      case ReportCategory.ventasSuspendidas:
        return 'Ventas suspendidas';
      case ReportCategory.empleados:
        return 'Empleados';
      case ReportCategory.comision:
        return 'Comisión';
      case ReportCategory.inventario:
        return 'Inventario';
      case ReportCategory.articulos:
        return 'Artículos';
      case ReportCategory.categorias:
        return 'Categorías';
      case ReportCategory.etiquetas:
        return 'Etiquetas';
      case ReportCategory.precios:
        return 'Precios';
      case ReportCategory.mermas:
        return 'Mermas';
      case ReportCategory.perdidasGanancias:
        return 'Pérdidas y Ganancias';
      case ReportCategory.credito:
        return 'Crédito';
      case ReportCategory.gastos:
        return 'Gastos';
      case ReportCategory.compras:
        return 'Compras';
      case ReportCategory.proveedores:
        return 'Proveedores';
      case ReportCategory.clientes:
        return 'Clientes';
      case ReportCategory.descuentos:
        return 'Descuentos';
      case ReportCategory.estadoDiario:
        return 'Estado de Diario';
      case ReportCategory.reporte606:
        return '606 — Compras DGII';
      case ReportCategory.reporte607:
        return '607 — Ventas DGII';
      case ReportCategory.reporteIt1:
        return 'IT-1 — Resumen ITBIS';
      case ReportCategory.cierreZFiscal:
        return 'Cierre Z Fiscal';
      case ReportCategory.impuestos:
        return 'Impuestos';
      case ReportCategory.personalizados:
        return 'Personalizados';
    }
  }

  String get description {
    switch (this) {
      case ReportCategory.ventas:
        return 'Reporte maestro: ventas por día, mesero, NCF y categoría.';
      case ReportCategory.caja:
        return 'Movimientos por sesión: apertura, cierre, métodos cobrados.';
      case ReportCategory.liquidacion:
        return 'Cierre operativo del turno (no fiscal).';
      case ReportCategory.cobros:
        return 'Pagos recibidos agrupados por método.';
      case ReportCategory.pagos:
        return 'Pagos a proveedores y gastos del período.';
      case ReportCategory.ventasSuspendidas:
        return 'Cuentas abiertas y ventas pendientes.';
      case ReportCategory.empleados:
        return 'Productividad por empleado.';
      case ReportCategory.comision:
        return 'Comisión por mesero según app_settings.';
      case ReportCategory.inventario:
        return 'Stock actual, valor y movimientos.';
      case ReportCategory.articulos:
        return 'Top platos, peor desempeño, mix de ventas.';
      case ReportCategory.categorias:
        return 'Ventas por categoría de menú.';
      case ReportCategory.etiquetas:
        return 'Ventas por etiqueta / tag.';
      case ReportCategory.precios:
        return 'Cambios de precio en el tiempo.';
      case ReportCategory.mermas:
        return 'Desperdicio, derrames, vencidos, devoluciones a cocina.';
      case ReportCategory.perdidasGanancias:
        return 'P&L del período.';
      case ReportCategory.credito:
        return 'Cuentas a crédito y antigüedad de saldos.';
      case ReportCategory.gastos:
        return 'Gastos del negocio.';
      case ReportCategory.compras:
        return 'Compras a proveedores.';
      case ReportCategory.proveedores:
        return 'Top proveedores y deuda actual.';
      case ReportCategory.clientes:
        return 'Top clientes, frecuencia y ticket promedio.';
      case ReportCategory.descuentos:
        return 'Descuentos aplicados (cortesías, promos).';
      case ReportCategory.estadoDiario:
        return 'Todas las ventas del mes, día por día, listo para descargar y enviar al contable.';
      case ReportCategory.reporte606:
        return 'Archivo mensual de compras con NCF de proveedores.';
      case ReportCategory.reporte607:
        return 'Archivo mensual de ventas con NCF emitidos.';
      case ReportCategory.reporteIt1:
        return 'Resumen mensual de ITBIS recibido vs pagado.';
      case ReportCategory.cierreZFiscal:
        return 'Cierre fiscal por sesión, sellado e inmutable.';
      case ReportCategory.impuestos:
        return 'ITBIS, propina legal y otros por período.';
      case ReportCategory.personalizados:
        return 'Query builder visual para reportes propios.';
    }
  }

  IconData get icon {
    switch (this) {
      case ReportCategory.ventas:
        return Icons.point_of_sale_outlined;
      case ReportCategory.caja:
        return Icons.account_balance_wallet_outlined;
      case ReportCategory.liquidacion:
        return Icons.access_time_outlined;
      case ReportCategory.cobros:
        return Icons.payments_outlined;
      case ReportCategory.pagos:
        return Icons.outbox_outlined;
      case ReportCategory.ventasSuspendidas:
        return Icons.pause_circle_outline;
      case ReportCategory.empleados:
        return Icons.badge_outlined;
      case ReportCategory.comision:
        return Icons.percent_outlined;
      case ReportCategory.inventario:
        return Icons.inventory_2_outlined;
      case ReportCategory.articulos:
        return Icons.shopping_bag_outlined;
      case ReportCategory.categorias:
        return Icons.category_outlined;
      case ReportCategory.etiquetas:
        return Icons.local_offer_outlined;
      case ReportCategory.precios:
        return Icons.attach_money_outlined;
      case ReportCategory.mermas:
        return Icons.delete_sweep_outlined;
      case ReportCategory.perdidasGanancias:
        return Icons.show_chart_outlined;
      case ReportCategory.credito:
        return Icons.credit_card_outlined;
      case ReportCategory.gastos:
        return Icons.money_off_outlined;
      case ReportCategory.compras:
        return Icons.shopping_cart_outlined;
      case ReportCategory.proveedores:
        return Icons.local_shipping_outlined;
      case ReportCategory.clientes:
        return Icons.people_outline;
      case ReportCategory.descuentos:
        return Icons.discount_outlined;
      case ReportCategory.estadoDiario:
        return Icons.event_note_outlined;
      case ReportCategory.reporte606:
        return Icons.description_outlined;
      case ReportCategory.reporte607:
        return Icons.description_outlined;
      case ReportCategory.reporteIt1:
        return Icons.assignment_outlined;
      case ReportCategory.cierreZFiscal:
        return Icons.lock_outline;
      case ReportCategory.impuestos:
        return Icons.account_balance_outlined;
      case ReportCategory.personalizados:
        return Icons.tune_outlined;
    }
  }

  /// Grupo lógico para organizar el sidebar.
  ReportCategoryGroup get group {
    switch (this) {
      case ReportCategory.ventas:
      case ReportCategory.caja:
      case ReportCategory.liquidacion:
      case ReportCategory.cobros:
      case ReportCategory.pagos:
      case ReportCategory.ventasSuspendidas:
        return ReportCategoryGroup.operativo;
      case ReportCategory.empleados:
      case ReportCategory.comision:
        return ReportCategoryGroup.empleados;
      case ReportCategory.inventario:
      case ReportCategory.articulos:
      case ReportCategory.categorias:
      case ReportCategory.etiquetas:
      case ReportCategory.precios:
      case ReportCategory.mermas:
        return ReportCategoryGroup.productos;
      case ReportCategory.perdidasGanancias:
      case ReportCategory.credito:
      case ReportCategory.gastos:
      case ReportCategory.compras:
      case ReportCategory.proveedores:
        return ReportCategoryGroup.financiero;
      case ReportCategory.clientes:
      case ReportCategory.descuentos:
        return ReportCategoryGroup.clientes;
      case ReportCategory.estadoDiario:
      case ReportCategory.reporte606:
      case ReportCategory.reporte607:
      case ReportCategory.reporteIt1:
      case ReportCategory.cierreZFiscal:
      case ReportCategory.impuestos:
        return ReportCategoryGroup.fiscal;
      case ReportCategory.personalizados:
        return ReportCategoryGroup.avanzados;
    }
  }

  /// Si admite modo gráfico además de resumen. Los fiscales (606/607/IT1)
  /// son sólo resumen + archivo por PRD §4.5.
  bool get supportsGraphicMode {
    switch (this) {
      case ReportCategory.estadoDiario:
      case ReportCategory.reporte606:
      case ReportCategory.reporte607:
      case ReportCategory.reporteIt1:
      case ReportCategory.liquidacion:
        return false;
      default:
        return true;
    }
  }

  /// Si está implementada. "Próximamente" sólo para Etiquetas (no hay modelo
  /// de tags aún) y Personalizados (query builder llega después).
  bool get isImplemented {
    switch (this) {
      case ReportCategory.etiquetas:
      case ReportCategory.personalizados:
        return false;
      default:
        return true;
    }
  }
}

enum ReportCategoryGroup {
  operativo('Operación'),
  empleados('Empleados'),
  productos('Productos e inventario'),
  financiero('Financiero'),
  clientes('Clientes'),
  fiscal('Fiscal DGII'),
  avanzados('Avanzados');

  const ReportCategoryGroup(this.label);
  final String label;
}

enum ReportMode { graphic, summary }

/// Sub-reportes dentro de "Ventas" (PRD §F-Ventas). El usuario ve esta lista
/// al entrar a la categoría; click → abre el sub-reporte específico.
enum VentasSubReport {
  graficos,
  resumen,
  detallados,
  beneficioEntregas,
  detallado607,
  resumenTime,
  graficoTime,
  conduce,
  eliminadas,
  delivery;

  String get title {
    switch (this) {
      case VentasSubReport.graficos:
        return 'Reportes Gráficos';
      case VentasSubReport.resumen:
        return 'Reportes de Resumen';
      case VentasSubReport.detallados:
        return 'Reportes Detallados';
      case VentasSubReport.beneficioEntregas:
        return 'Reporte de beneficio por entregas';
      case VentasSubReport.detallado607:
        return 'Reportes Detallados 607';
      case VentasSubReport.resumenTime:
        return 'Resumen de ventas por Time Reports';
      case VentasSubReport.graficoTime:
        return 'Resumen gráfico Ventas por Time Reports';
      case VentasSubReport.conduce:
        return 'Reportes Detallados Conduce';
      case VentasSubReport.eliminadas:
        return 'Reportes Detallados Ventas Eliminadas';
      case VentasSubReport.delivery:
        return 'Reportes Detallados de Delivery';
    }
  }

  IconData get icon {
    switch (this) {
      case VentasSubReport.graficos:
      case VentasSubReport.graficoTime:
        return Icons.bar_chart_rounded;
      case VentasSubReport.resumen:
      case VentasSubReport.resumenTime:
        return Icons.receipt_long_outlined;
      default:
        return Icons.calendar_today_outlined;
    }
  }

  bool get isImplemented {
    switch (this) {
      case VentasSubReport.beneficioEntregas:
      case VentasSubReport.conduce:
      case VentasSubReport.delivery:
        return false;
      default:
        return true;
    }
  }
}

/// Presets de rango de fecha (PRD §9.3).
enum ReportDateRangePreset {
  today('Hoy'),
  yesterday('Ayer'),
  thisWeek('Esta semana'),
  thisMonth('Este mes'),
  lastMonth('Mes anterior'),
  customRange('Personalizado');

  const ReportDateRangePreset(this.label);
  final String label;
}

class ReportDateRange {
  const ReportDateRange({
    required this.preset,
    required this.from,
    required this.to,
  });

  factory ReportDateRange.fromPreset(ReportDateRangePreset preset, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case ReportDateRangePreset.today:
        return ReportDateRange(preset: preset, from: today, to: today);
      case ReportDateRangePreset.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return ReportDateRange(preset: preset, from: y, to: y);
      case ReportDateRangePreset.thisWeek:
        final from = today.subtract(Duration(days: today.weekday - 1));
        return ReportDateRange(preset: preset, from: from, to: today);
      case ReportDateRangePreset.thisMonth:
        return ReportDateRange(
          preset: preset,
          from: DateTime(now.year, now.month, 1),
          to: today,
        );
      case ReportDateRangePreset.lastMonth:
        final firstOfThis = DateTime(now.year, now.month, 1);
        final lastOfPrev = firstOfThis.subtract(const Duration(days: 1));
        return ReportDateRange(
          preset: preset,
          from: DateTime(lastOfPrev.year, lastOfPrev.month, 1),
          to: lastOfPrev,
        );
      case ReportDateRangePreset.customRange:
        return ReportDateRange(
          preset: preset,
          from: customFrom ?? today,
          to: customTo ?? today,
        );
    }
  }

  final ReportDateRangePreset preset;
  final DateTime from;
  final DateTime to;

  /// Formato `yyyy-MM-dd` para `.eq` / `gte` en queries.
  String get fromIso => _iso(from);
  String get toIso => _iso(to);

  static String _iso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

/// Colores por grupo para badges del sidebar.
extension ReportCategoryGroupColor on ReportCategoryGroup {
  Color get accent {
    switch (this) {
      case ReportCategoryGroup.operativo:
        return AppTokens.primary;
      case ReportCategoryGroup.empleados:
        return AppTokens.info;
      case ReportCategoryGroup.productos:
        return AppTokens.success;
      case ReportCategoryGroup.financiero:
        return AppTokens.warning;
      case ReportCategoryGroup.clientes:
        return AppTokens.info;
      case ReportCategoryGroup.fiscal:
        return AppTokens.destructive;
      case ReportCategoryGroup.avanzados:
        return AppTokens.mutedForeground;
    }
  }
}
