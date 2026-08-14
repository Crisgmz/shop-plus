import 'dart:typed_data';

import '../../../../shared/formatters/formatters.dart';
import '../printing_models.dart';
import 'esc_pos_encoder.dart';

/// Convierte un [PrintDocumentData] en un flujo de bytes ESC/POS para
/// impresoras térmicas de 80mm, reflejando el mismo contenido que la vista
/// previa de [PrintReceiptDialog].
///
/// El resultado es apto para enviarse crudo por TCP (puerto 9100) o cualquier
/// transporte que acepte ESC/POS.
class ThermalEscPosRenderer {
  const ThermalEscPosRenderer({this.columns = 48});

  /// Ancho del papel en columnas (80mm ≈ 48, 58mm ≈ 32).
  final int columns;

  /// Renderiza el documento. Si [copies] > 1 repite el ticket en el mismo flujo.
  /// Si [openDrawer] es true, abre la gaveta antes del corte (solo útil en
  /// ventas en efectivo).
  Uint8List render(
    PrintDocumentData doc, {
    int copies = 1,
    bool openDrawer = false,
  }) {
    final e = EscPosEncoder(columns: columns)..reset();

    final total = copies < 1 ? 1 : copies;
    for (var copy = 0; copy < total; copy++) {
      _renderTicket(e, doc);
      if (openDrawer && copy == 0) {
        e.openCashDrawer();
      }
      e.cut();
    }
    return e.bytes();
  }

  void _renderTicket(EscPosEncoder e, PrintDocumentData d) {
    // ── Encabezado centrado ──────────────────────────────────────────────
    e.align(PosAlign.center).bold(true).size(doubleHeight: true);
    e.text(d.branch.name.toUpperCase());
    e.size().bold(false);
    if (_has(d.branch.address)) e.wrapped(d.branch.address!);
    if (_has(d.branch.phone)) e.text(d.branch.phone!);
    if (_has(d.branch.taxId)) e.text('RNC ${d.branch.taxId}');
    if (d.hidePrices) e.bold(true).text('CONDUCE').bold(false);
    e.feed();

    // ── Metadatos ────────────────────────────────────────────────────────
    e.align(PosAlign.left);
    e.text(_formatDate(d.issuedAt));
    e.twoColumns('Serie y Numero:', d.documentNumber);
    if (_has(d.cashRegisterName)) {
      e.twoColumns('Caja:', d.cashRegisterName!);
    }
    if (_has(d.priceTierLabel)) {
      e.twoColumns('Tipo de precio:', d.priceTierLabel!);
    }
    if (_has(d.cashierName)) {
      e.twoColumns('Empleado:', d.cashierName!);
    }
    if (_has(d.ncf)) e.twoColumns('NCF:', d.ncf!);
    if (_has(d.receiptTypeLabel)) {
      e.twoColumns('Comprobante:', d.receiptTypeLabel!);
    }

    // ── Cliente ──────────────────────────────────────────────────────────
    final customer = d.customer;
    if (customer != null) {
      e.feed();
      e.bold(true).text('Factura a:').bold(false);
      e.wrapped('Cliente: ${customer.name}');
      if (_has(customer.document)) e.text('Doc: ${customer.document}');
      if (_has(customer.address)) e.wrapped('Direccion: ${customer.address}');
      if (_has(customer.phone)) e.text('Telefono: ${customer.phone}');
    }

    // ── Tabla de items ───────────────────────────────────────────────────
    e.feed();
    e.divider();
    e.bold(true).text(_itemHeader(d.hidePrices)).bold(false);
    e.divider();
    for (final item in d.items) {
      e.wrapped(item.description);
      e.text(_itemDetail(item, d.hidePrices));
    }
    e.divider();

    // ── Totales (el conduce no lleva montos ni pagos) ────────────────────
    if (!d.hidePrices) {
      final t = d.totals;
      e.twoColumns('Subtotal', money(t.subtotal));
      if (t.discount > 0) e.twoColumns('Descuento', '-${money(t.discount)}');
      if (t.serviceCharge > 0) e.twoColumns('Servicio', money(t.serviceCharge));
      if (t.tax > 0) e.twoColumns('ITBIS', money(t.tax));
      e.bold(true).size(doubleHeight: true);
      e.twoColumns('TOTAL', money(t.total));
      e.size().bold(false);
      if (d.changeAmount != null && d.changeAmount! >= 0) {
        e.twoColumns('Cambio', money(d.changeAmount));
      }
      if (t.balance > 0) {
        e.bold(true).twoColumns('Pendiente', money(t.balance)).bold(false);
      }
      for (final payment in d.payments) {
        e.twoColumns(payment.method, money(payment.amount));
      }
    }

    // ── Notas / pie ──────────────────────────────────────────────────────
    if (_has(d.notes)) {
      e.feed();
      e.wrapped('Notas: ${d.notes}');
    }

    // Conduce: acuse de recibo, igual que en el A4 y el PDF de 80mm.
    if (d.hidePrices) {
      e.feed();
      e.bold(true).text('RECIBIDO POR:').bold(false);
      for (final label in const ['Nombre', 'Cedula o ID', 'Firma', 'Fecha']) {
        e.text('$label: ______________________');
      }
    }
    if (_has(d.footerMessage)) {
      e.feed();
      e.align(PosAlign.center).wrapped(d.footerMessage!).align(PosAlign.left);
    }

    // ── Código de documento (texto, legible/escaneable manualmente) ──────
    if (d.showBarcode) {
      e.feed();
      e.align(PosAlign.center).text(d.documentNumber).align(PosAlign.left);
    }
  }

  String _itemHeader(bool hidePrices) {
    // Columnas: descripción (en su propia línea) y aquí el desglose numérico.
    final label = hidePrices ? 'Cantidad' : 'Cant x Precio';
    final right = label.padLeft(columns - 'Articulo'.length);
    return 'Articulo$right';
  }

  String _itemDetail(PrintDocumentItem item, bool hidePrices) {
    final qty = _qty(item.quantity);
    if (hidePrices) return qty.padLeft(columns);
    final detail = '$qty x ${money(item.unitPrice)}';
    final total = money(item.lineTotal);
    final gap = columns - detail.length - total.length;
    return '$detail${' ' * (gap < 1 ? 1 : gap)}$total';
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _formatDate(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
