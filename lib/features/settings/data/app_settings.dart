// AppSettings: entity tipada respaldada por un Map<String, dynamic>.
//
// Diseño:
//   - Fila singleton de la tabla `app_settings` (id=1).
//   - Internamente guardamos el row crudo (`_raw`); los getters tipados
//     dan ergonomía y los setters NO existen — todo update viaja por el
//     repository (auto-save por campo).
//   - copyWith acepta un patch (Map) para reflejar cambios optimistas.

import 'package:flutter/foundation.dart';

@immutable
class AppSettings {
  const AppSettings(this._raw);

  final Map<String, dynamic> _raw;

  Map<String, dynamic> get raw => Map.unmodifiable(_raw);

  AppSettings copyWith(Map<String, dynamic> patch) {
    return AppSettings({..._raw, ...patch});
  }

  // ─── Sección 1: Información de la Compañía ───────────────────────────────
  String get companyName => _str('company_name');
  String? get companyLegalName => _strOrNull('company_legal_name');
  String? get companyTaxId => _strOrNull('company_tax_id');
  String? get companyWebsite => _strOrNull('company_website');
  String? get companyLogoUrl => _strOrNull('company_logo_url');
  String? get companyStampUrl => _strOrNull('company_stamp_url');
  String? get companySignatureUrl => _strOrNull('company_signature_url');
  String? get defaultNcfSequenceId => _strOrNull('default_ncf_sequence_id');

  // Emisor + datos para factura/cotización A4 (migración 58).
  String? get companyAddress => _strOrNull('company_address');
  String? get companyPhone => _strOrNull('company_phone');
  String? get companyEmail => _strOrNull('company_email');
  String? get companyBankInfo => _strOrNull('company_bank_info');
  String? get companySignatoryName => _strOrNull('company_signatory_name');
  String? get companySignatoryTitle => _strOrNull('company_signatory_title');
  String? get invoiceObservation => _strOrNull('invoice_observation');

  /// Si false, nunca se muestra el ITBIS en factura/cotización (aunque los
  /// productos tengan tasa). Default true.
  bool get invoiceShowItbis => _bool('invoice_show_itbis', true);

  /// URL del código QR para el pie de factura/cotización. Se descarga en
  /// runtime (como el logo), inmune al caché del bundle/service worker.
  String? get companyQrUrl => _strOrNull('company_qr_url');

  // ─── Sección 2: Inventario ───────────────────────────────────────────────
  bool get invDefaultIsService => _bool('inv_default_is_service', false);
  String get invBarcodeIdSource => _str('inv_barcode_id_source', 'item_id');
  bool get invDisallowBelowCost => _bool('inv_disallow_below_cost', false);
  bool get invImeiMode => _bool('inv_imei_mode', false);
  bool get invDisallowNoStock => _bool('inv_disallow_no_stock', false);
  bool get invHighlightMinStock => _bool('inv_highlight_min_stock', true);
  bool get invDisableMarginCalculator =>
      _bool('inv_disable_margin_calculator', true);

  // ─── Sección 3: Empleado ─────────────────────────────────────────────────
  bool get empPickSellerDuringSale => _bool('emp_pick_seller_during_sale', false);
  bool get empSellerRequired => _bool('emp_seller_required', false);
  String get empDefaultSeller => _str('emp_default_seller', 'logged_in_user');
  double get empCommissionRate => _double('emp_commission_rate');
  String get empCommissionMethod =>
      _str('emp_commission_method', 'sale_price');
  bool get empRequireLoginEachSale =>
      _bool('emp_require_login_each_sale', false);
  bool get empKeepPositionAfterSwitch =>
      _bool('emp_keep_position_after_switch', true);
  bool get empTimeClockEnabled => _bool('emp_time_clock_enabled', false);

  // ─── Sección 4: Impuestos y Moneda ───────────────────────────────────────
  bool get taxDefaultPriceIncludesTax =>
      _bool('tax_default_price_includes_tax', false);
  bool get taxChargeOnReceivings => _bool('tax_charge_on_receivings', false);
  bool get taxIncludeInBarcodes => _bool('tax_include_in_barcodes', true);
  String get currencySymbol => _str('currency_symbol', 'RD\$');
  int get currencyDecimals => _int('currency_decimals', 2);
  String get currencyThousandsSep => _str('currency_thousands_sep', ',');
  String get currencyDecimalPoint => _str('currency_decimal_point', '.');
  List<dynamic> get currencyDenominations =>
      _list('currency_denominations');

  // ─── Sección 5.1: Recibo (presentación) ──────────────────────────────────
  String? get receiptIgnoreTitle => _strOrNull('receipt_ignore_title');
  bool get receiptHideSignature => _bool('receipt_hide_signature', true);
  String get receiptTextSize => _str('receipt_text_size', 'small');
  bool get receiptShowItemId => _bool('receipt_show_item_id', false);
  bool get receiptHideBarcode => _bool('receipt_hide_barcode', false);
  bool get receiptHideCreditBalance =>
      _bool('receipt_hide_credit_balance', true);

  // ─── Sección 5.2: Recibo (comportamiento) ────────────────────────────────
  bool get receiptPrintAfterSale => _bool('receipt_print_after_sale', true);
  bool get receiptPrintAfterPurchase =>
      _bool('receipt_print_after_purchase', true);
  bool get receiptAutoDuplicateOnCreditCard =>
      _bool('receipt_auto_duplicate_on_credit_card', true);
  bool get receiptShowAfterSuspend => _bool('receipt_show_after_suspend', true);
  bool get receiptEmailCustomerAuto =>
      _bool('receipt_email_customer_auto', true);
  bool get receiptShowObservationsAuto =>
      _bool('receipt_show_observations_auto', false);
  bool get receiptRedirectAfterPrint =>
      _bool('receipt_redirect_after_print', false);

  // ─── Sección 5.3: Interfaz de venta ──────────────────────────────────────
  String get saleUiColumn => _str('sale_ui_column', 'barcode');
  bool get saleFocusItemField => _bool('sale_focus_item_field', false);
  int get saleRecentPerCustomer => _int('sale_recent_per_customer', 10);
  bool get saleStripCustomerContact =>
      _bool('sale_strip_customer_contact', false);
  bool get saleHideRecentForCustomer =>
      _bool('sale_hide_recent_for_customer', false);
  bool get saleDisableCompleteConfirmation =>
      _bool('sale_disable_complete_confirmation', true);
  bool get saleDisableQuickSale => _bool('sale_disable_quick_sale', false);
  bool get saleChangeDateOnNew => _bool('sale_change_date_on_new', false);
  bool get saleNoGroupIdenticalItems =>
      _bool('sale_no_group_identical_items', false);
  bool get saleEditZeroPriceOnAdd =>
      _bool('sale_edit_zero_price_on_add', true);

  // ─── Sección 5.4: Costo y precios ────────────────────────────────────────
  bool get saleCalcAvgPurchaseCost =>
      _bool('sale_calc_avg_purchase_cost', true);
  String get saleAvgMethod =>
      _str('sale_avg_method', 'current_received_price');
  bool get saleAlwaysUseGlobalAvgCost =>
      _bool('sale_always_use_global_avg_cost', false);
  bool get salePriceTypesRound2Decimals =>
      _bool('sale_price_types_round_2_decimals', true);
  List<dynamic> get salePriceTypes => _list('sale_price_types');

  // ─── Sección 5.5: Tarjetas de regalo ─────────────────────────────────────
  bool get giftcardHideSuspendedReceivings =>
      _bool('giftcard_hide_suspended_receivings', false);
  bool get giftcardDisableDetection =>
      _bool('giftcard_disable_detection', false);
  String get giftcardBenefitWhen =>
      _str('giftcard_benefit_when', 'do_nothing');

  // ─── Sección 5.6: Cuadrícula ─────────────────────────────────────────────
  bool get gridShowDuringSale => _bool('grid_show_during_sale', false);
  bool get gridHideNoStock => _bool('grid_hide_no_stock', false);
  String get gridDefault => _str('grid_default', 'categories');

  // ─── Sección 5.7: Cliente y crédito ──────────────────────────────────────
  bool get customerRequiredForSale =>
      _bool('customer_required_for_sale', false);
  bool get customerRequiredForSuspended =>
      _bool('customer_required_for_suspended', false);
  bool get creditAllowSales => _bool('credit_allow_sales', true);
  bool get creditAllowPurchases => _bool('credit_allow_purchases', true);
  bool get creditDisableAccountOnOverlimit =>
      _bool('credit_disable_account_on_overlimit', false);
  String? get creditAccountMessage => _strOrNull('credit_account_message');
  bool get creditAskCcvOnCard => _bool('credit_ask_ccv_on_card', false);
  String get creditBlockWhen =>
      _str('credit_block_when', 'exceeds_balance_limit');
  int get creditDefaultDays => _int('credit_default_days', 30);
  int get creditWarnDays => _int('credit_warn_days', 7);
  bool get fiscalAllowForExemptProducts =>
      _bool('fiscal_allow_for_exempt_products', true);
  bool get saleDisableNotifications =>
      _bool('sale_disable_notifications', false);
  bool get saleGroupAllTaxesOnReceipt =>
      _bool('sale_group_all_taxes_on_receipt', false);
  bool get saleInvoicePrintControl =>
      _bool('sale_invoice_print_control', false);

  // ─── Sección 5.8: Prefijos ───────────────────────────────────────────────
  String get prefixSale => _str('prefix_sale', 'FA');
  String get prefixCreditNote => _str('prefix_credit_note', 'NC');
  String get prefixDebitNote => _str('prefix_debit_note', 'ND');
  String get prefixDelivery => _str('prefix_delivery', 'CON');
  String get prefixQuote => _str('prefix_quote', 'CO');
  String get prefixCreditPayment => _str('prefix_credit_payment', 'PAC');
  String get prefixInstallmentPayment => _str('prefix_installment_payment', 'PA');
  String get prefixPurchase => _str('prefix_purchase', 'COM');
  String get prefixPurchaseOrder => _str('prefix_purchase_order', 'OC');
  String get prefixReceipt => _str('prefix_receipt', 'REC');

  // ─── Sección 5.9: Métodos de pago ────────────────────────────────────────
  List<dynamic> get paymentMethodsEnabled => _list('payment_methods_enabled');
  String get paymentMethodDefault => _str('payment_method_default', 'cash');
  List<dynamic> get paymentChannels => _list('payment_channels');
  bool get paymentShowChannelsInSale =>
      _bool('payment_show_channels_in_sale', false);

  // ─── Sección 5.10: Formato y políticas ───────────────────────────────────
  String get invoiceDefaultFormat =>
      _str('invoice_default_format', 'pos_invoice');
  String get invoiceB2xFormat => _str('invoice_b2x_format', 'b2c');
  String get returnPolicy => _str('return_policy', '0');
  String? get announcements => _strOrNull('announcements');

  // ─── Sección 6: Cuentas Suspendidas ──────────────────────────────────────
  bool get suspendedHidePayablesInReports =>
      _bool('suspended_hide_payables_in_reports', false);
  bool get suspendedHideAccountPaymentsInTotals =>
      _bool('suspended_hide_account_payments_in_totals', false);
  bool get suspendedChangeDateOnSuspend =>
      _bool('suspended_change_date_on_suspend', true);
  bool get suspendedChangeDateOnComplete =>
      _bool('suspended_change_date_on_complete', true);
  bool get suspendedShowReceiptAfter =>
      _bool('suspended_show_receipt_after', true);

  // ─── Sección 7: Aplicación ───────────────────────────────────────────────
  bool get app2faEnabled => _bool('app_2fa_enabled', false);
  bool get appTestMode => _bool('app_test_mode', false);
  bool get appQuickUserSwitch => _bool('app_quick_user_switch', false);
  bool get appEnableDeliveryNotes => _bool('app_enable_delivery_notes', false);
  String get appLanguage => _str('app_language', 'es');
  String get appDateFormat => _str('app_date_format', 'dd-MM-yyyy');
  String get appTimeFormat => _str('app_time_format', '12h');
  bool get appHidePriceInBarcodes => _bool('app_hide_price_in_barcodes', false);
  bool get appLoyaltyEnabled => _bool('app_loyalty_enabled', false);
  bool get appStatusSounds => _bool('app_status_sounds', true);
  int get appSearchRowsPerPage => _int('app_search_rows_per_page', 20);
  int get appGridItemsPerPage => _int('app_grid_items_per_page', 15);
  String get appSearchSortOrder =>
      _str('app_search_sort_order', 'newest_first');
  bool get appHidePanelStats => _bool('app_hide_panel_stats', false);
  bool get appShowLanguageSwitcher =>
      _bool('app_show_language_switcher', false);
  bool get appShowHeaderClock => _bool('app_show_header_clock', false);
  bool get appFastSearchQueries => _bool('app_fast_search_queries', true);
  String get appSpreadsheetFormat => _str('app_spreadsheet_format', 'xlsx');
  String get appLogoutBehavior =>
      _str('app_logout_behavior', 'redirect_login');

  DateTime? get updatedAt => _date('updated_at');
  String? get updatedBy => _strOrNull('updated_by');

  // ─── Helpers de coerción ─────────────────────────────────────────────────
  String _str(String key, [String fallback = '']) {
    final value = _raw[key];
    if (value == null) return fallback;
    return value.toString();
  }

  String? _strOrNull(String key) {
    final value = _raw[key];
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  bool _bool(String key, bool fallback) {
    final value = _raw[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    return value.toString() == 'true';
  }

  int _int(String key, [int fallback = 0]) {
    final value = _raw[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  double _double(String key, [double fallback = 0]) {
    final value = _raw[key];
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  List<dynamic> _list(String key) {
    final value = _raw[key];
    if (value is List) return value;
    return const [];
  }

  DateTime? _date(String key) {
    final value = _raw[key];
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

/// Entrada de auditoría (`app_settings_audit`).
@immutable
class AppSettingsAuditEntry {
  const AppSettingsAuditEntry({
    required this.id,
    required this.fieldName,
    required this.changedAt,
    this.oldValue,
    this.newValue,
    this.changedBy,
  });

  factory AppSettingsAuditEntry.fromMap(Map<String, dynamic> map) {
    return AppSettingsAuditEntry(
      id: (map['id'] ?? 0) is int
          ? map['id'] as int
          : int.tryParse(map['id'].toString()) ?? 0,
      fieldName: (map['field_name'] ?? '').toString(),
      oldValue: map['old_value'],
      newValue: map['new_value'],
      changedAt: DateTime.tryParse(map['changed_at']?.toString() ?? '') ??
          DateTime.now(),
      changedBy: map['changed_by']?.toString(),
    );
  }

  final int id;
  final String fieldName;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime changedAt;
  final String? changedBy;
}

/// Identificadores de las 7 secciones del PRD 06 (orden de UI).
enum AppSettingsSection {
  companyInfo,
  inventory,
  employee,
  taxCurrency,
  salesReceipt,
  suspendedSales,
  application;

  String get title {
    switch (this) {
      case AppSettingsSection.companyInfo:
        return 'Información de la compañía';
      case AppSettingsSection.inventory:
        return 'Inventario';
      case AppSettingsSection.employee:
        return 'Ajustes del empleado';
      case AppSettingsSection.taxCurrency:
        return 'Impuestos y moneda';
      case AppSettingsSection.salesReceipt:
        return 'Ventas y recibo';
      case AppSettingsSection.suspendedSales:
        return 'Cuentas abiertas';
      case AppSettingsSection.application:
        return 'Configuración de la aplicación';
    }
  }

  String get description {
    switch (this) {
      case AppSettingsSection.companyInfo:
        return 'Datos legales, logo, sello y comprobante por defecto.';
      case AppSettingsSection.inventory:
        return 'Comportamiento de productos y validaciones de stock.';
      case AppSettingsSection.employee:
        return 'Vendedor por defecto, comisiones, control horario.';
      case AppSettingsSection.taxCurrency:
        return 'ITBIS, símbolo de moneda y denominaciones para arqueo.';
      case AppSettingsSection.salesReceipt:
        return 'Recibo, prefijos, métodos de pago y políticas de venta.';
      case AppSettingsSection.suspendedSales:
        return 'Cuentas en curso y su comportamiento al suspender.';
      case AppSettingsSection.application:
        return 'Idioma, formatos, paginación y opciones generales.';
    }
  }
}
