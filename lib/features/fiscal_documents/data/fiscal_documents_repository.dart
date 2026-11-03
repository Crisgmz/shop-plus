import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class FiscalDocument {
  FiscalDocument({
    required this.id,
    required this.branchId,
    required this.receiptType,
    required this.ncf,
    required this.fiscalStatus,
    required this.issuedAt,
    required this.subtotal,
    required this.taxableAmount,
    required this.exemptAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.totalAmount,
    required this.discountAmount,
    this.saleId,
    this.clientId,
    this.ncfSequenceId,
    this.sequenceNumber,
    this.expiresOn,
    this.voidedAt,
    this.voidReason,
    this.customerName,
    this.customerDocumentType,
    this.customerDocumentNumber,
    this.customerAddress,
    this.issuerName,
    this.issuerTaxId,
    this.issuerAddress,
    this.ecfStatus,
    this.alanubeDocumentId,
    this.ecfTrackingNumber,
    this.ecfSecurityCode,
    this.ecfSignedAt,
    this.publicUrl,
    this.xmlUrl,
    this.pdfUrl,
    this.submittedAt,
    this.acceptedAt,
    this.lastError,
  });

  final String id;
  final String branchId;
  final String? saleId;
  final String? clientId;
  final String? ncfSequenceId;
  final String receiptType;
  final String ncf;
  final int? sequenceNumber;
  final String fiscalStatus;
  final DateTime issuedAt;
  final DateTime? expiresOn;
  final DateTime? voidedAt;
  final String? voidReason;
  final String? customerName;
  final String? customerDocumentType;
  final String? customerDocumentNumber;
  final String? customerAddress;
  final String? issuerName;
  final String? issuerTaxId;
  final String? issuerAddress;
  final double subtotal;
  final double discountAmount;
  final double taxableAmount;
  final double exemptAmount;
  final double taxAmount;
  final double serviceChargeAmount;
  final double totalAmount;

  // === e-CF (DGII vía Alanube). Solo populado en documentos serie E ===
  /// 'pending' | 'sent' | 'accepted' | 'rejected' | 'uncertain' (Alanube pudo
  /// haberlo recibido; no se reenvía solo, ver migración 101).
  final String? ecfStatus;
  final String? alanubeDocumentId;
  final String? ecfTrackingNumber;
  final String? ecfSecurityCode;
  final DateTime? ecfSignedAt;
  final String? publicUrl; // URL DGII de verificación (contenido del QR)
  final String? xmlUrl;
  final String? pdfUrl;
  final DateTime? submittedAt;
  final DateTime? acceptedAt;
  final String? lastError;

  bool get isVoided => voidedAt != null;
  bool get isApproved => fiscalStatus == 'approved';
  bool get isPending => fiscalStatus == 'pending';

  bool get isElectronic => ncf.startsWith('E');

  /// Código e-CF DGII derivado del NCF: 'E31', 'E32', 'E44', 'E45'…
  String get ncfTypeCode => ncf.length >= 3 ? ncf.substring(0, 3) : ncf;

  /// `true` cuando podemos imprimir un QR válido en la representación del
  /// e-CF. DGII Norma 01-2020 exige el QR en la representación impresa, por
  /// eso renderizamos en cuanto hay `ecf_security_code` (estado `sent`), sin
  /// esperar al webhook que mueve a `accepted`: DGII acepta consultas de docs
  /// "EN PROCESO" mostrando ese estado a quien escanea.
  bool get hasQrData =>
      isElectronic &&
      (ecfStatus == 'accepted' || ecfStatus == 'sent') &&
      (ecfSecurityCode?.isNotEmpty ?? false);

  /// URL DGII de verificación del e-CF (contenido del QR del recibo).
  /// Fallback cuando Alanube aún no populó `public_url` (típico en `sent`).
  /// Norma DGII 01-2020: FechaEmision va DD-MM-YYYY; E31 exige RncComprador.
  String? buildDgiiVerifyUrl({
    required String emitterRnc,
    required bool sandbox,
  }) {
    final code = ecfSecurityCode;
    if (code == null || code.isEmpty) return null;
    if (emitterRnc.trim().isEmpty) return null;

    final base = sandbox
        ? 'https://ecf.dgii.gov.do/testecf/ConsultaTimbreFC'
        : 'https://ecf.dgii.gov.do/ecf/ConsultaTimbreFC';

    final d = issuedAt;
    final fecha = '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.year}';

    final params = <String, String>{
      'RncEmisor': emitterRnc.trim(),
      'ENCF': ncf,
      'FechaEmision': fecha,
      'MontoTotal': totalAmount.toStringAsFixed(2),
      'CodigoSeguridad': code,
    };
    final buyerRnc = customerDocumentNumber?.trim() ?? '';
    if (ncfTypeCode == 'E31' && buyerRnc.isNotEmpty) {
      params['RncComprador'] = buyerRnc;
    }

    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$base?$query';
  }

  /// Mensaje legible del estado e-CF para imprimir cuando aún no hay QR.
  /// Devuelve null si el doc es físico o ya fue aceptado.
  String? get ecfStatusMessage {
    if (!isElectronic) return null;
    switch (ecfStatus) {
      case 'pending':
        return 'Pendiente de emisión a DGII';
      case 'sent':
        return 'En proceso DGII (esperando confirmación)';
      case 'uncertain':
        return 'Envío a DGII sin confirmar';
      case 'rejected':
        final err = lastError ?? '';
        return err.isNotEmpty
            ? 'Rechazado DGII: ${err.substring(0, err.length.clamp(0, 80))}'
            : 'Rechazado por DGII';
      default:
        return null;
    }
  }

  factory FiscalDocument.fromMap(Map<String, dynamic> map) {
    return FiscalDocument(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      saleId: map['sale_id']?.toString(),
      clientId: map['client_id']?.toString(),
      ncfSequenceId: map['ncf_sequence_id']?.toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: (map['ncf'] ?? '').toString(),
      sequenceNumber: map['sequence_number'] == null
          ? null
          : _toInt(map['sequence_number']),
      fiscalStatus: (map['fiscal_status'] ?? 'pending').toString(),
      issuedAt: DateTime.tryParse((map['issued_at'] ?? '').toString()) ??
          DateTime.now(),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
      voidedAt: map['voided_at'] == null
          ? null
          : DateTime.tryParse(map['voided_at'].toString()),
      voidReason: map['void_reason']?.toString(),
      customerName: map['customer_name']?.toString(),
      customerDocumentType: map['customer_document_type']?.toString(),
      customerDocumentNumber: map['customer_document_number']?.toString(),
      customerAddress: map['customer_address']?.toString(),
      issuerName: map['issuer_name']?.toString(),
      issuerTaxId: map['issuer_tax_id']?.toString(),
      issuerAddress: map['issuer_address']?.toString(),
      subtotal: _toDouble(map['subtotal']),
      discountAmount: _toDouble(map['discount_amount']),
      taxableAmount: _toDouble(map['taxable_amount']),
      exemptAmount: _toDouble(map['exempt_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      serviceChargeAmount: _toDouble(map['service_charge_amount']),
      totalAmount: _toDouble(map['total_amount']),
      ecfStatus: map['ecf_status']?.toString(),
      alanubeDocumentId: map['alanube_document_id']?.toString(),
      ecfTrackingNumber: map['ecf_tracking_number']?.toString(),
      ecfSecurityCode: map['ecf_security_code']?.toString(),
      ecfSignedAt: map['ecf_signed_at'] == null
          ? null
          : DateTime.tryParse(map['ecf_signed_at'].toString()),
      publicUrl: map['public_url']?.toString(),
      xmlUrl: map['xml_url']?.toString(),
      pdfUrl: map['pdf_url']?.toString(),
      submittedAt: map['submitted_at'] == null
          ? null
          : DateTime.tryParse(map['submitted_at'].toString()),
      acceptedAt: map['accepted_at'] == null
          ? null
          : DateTime.tryParse(map['accepted_at'].toString()),
      lastError: map['last_error']?.toString(),
    );
  }
}

class FiscalDocumentsRepository {
  FiscalDocumentsRepository(this._client);

  final SupabaseClient _client;

  Future<List<FiscalDocument>> fetchDocuments({
    String? statusFilter,
    String? receiptTypeFilter,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    var query = _client
        .from('fiscal_documents')
        .select(
          'id, branch_id, sale_id, client_id, ncf_sequence_id, receipt_type, ncf, '
          'sequence_number, fiscal_status, issued_at, expires_on, voided_at, void_reason, '
          'customer_name, customer_document_type, customer_document_number, customer_address, '
          'issuer_name, issuer_tax_id, issuer_address, '
          'subtotal, discount_amount, taxable_amount, exempt_amount, tax_amount, '
          'service_charge_amount, total_amount, '
          'ecf_status, alanube_document_id, ecf_tracking_number, ecf_security_code, '
          'ecf_signed_at, public_url, xml_url, pdf_url, submitted_at, accepted_at, last_error',
        )
        .eq('branch_id', branchId);

    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.eq('fiscal_status', statusFilter);
    }
    if (receiptTypeFilter != null && receiptTypeFilter.isNotEmpty) {
      query = query.eq('receipt_type', receiptTypeFilter);
    }
    if (from != null) {
      query = query.gte('issued_at', from.toIso8601String());
    }
    if (to != null) {
      query = query.lte('issued_at', to.toIso8601String());
    }

    final rows = await query.order('issued_at', ascending: false).limit(limit);

    return rows
        .map((item) =>
            FiscalDocument.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<FiscalDocument?> fetchDocument(String id) async {
    final rows = await _client
        .from('fiscal_documents')
        .select()
        .eq('id', id)
        .limit(1);

    if (rows.isEmpty) return null;
    return FiscalDocument.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  Future<FiscalDocument?> fetchDocumentBySaleId(String saleId) async {
    final rows = await _client
        .from('fiscal_documents')
        .select()
        .eq('sale_id', saleId)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return FiscalDocument.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  /// Dispara la Edge Function `emit-document` en modo sync para un documento
  /// electrónico (serie E). Devuelve el documento refrescado con los datos
  /// del QR si la emisión respondió a tiempo; si el timeout expira, el cron
  /// de respaldo drenará la cola y el webhook actualizará el estado después.
  /// Nunca lanza: el e-CF no debe romper el flujo de venta/impresión.
  Future<FiscalDocument?> emitElectronicDocument(
    String fiscalDocumentId, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      await _client.functions
          .invoke(
            'emit-document',
            body: {'fiscal_document_id': fiscalDocumentId},
          )
          .timeout(timeout);
    } catch (_) {
      // La cola/cron reintenta; seguimos para refrescar el estado actual.
    }
    try {
      return await fetchDocument(fiscalDocumentId);
    } catch (_) {
      return null;
    }
  }

  /// Resuelve un envío e-CF incierto (migración 101). Con [foundInAlanube] y
  /// el id que muestra Alanube, el comprobante queda enviado; sin él, vuelve a
  /// la cola con el mismo e-NCF y la misma llave de idempotencia.
  Future<void> resolveUncertainEmission({
    required String fiscalDocumentId,
    required bool foundInAlanube,
    String? alanubeDocumentId,
    String? note,
  }) async {
    await _client.rpc('resolve_uncertain_ecf_emission', params: {
      'p_fiscal_document_id': fiscalDocumentId,
      'p_resolution': foundInAlanube ? 'found_in_alanube' : 'not_in_alanube',
      'p_alanube_document_id': alanubeDocumentId,
      'p_note': note,
    });
  }

  Future<void> voidDocument({
    required String id,
    required String reason,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('fiscal_documents')
        .update({
          'fiscal_status': 'voided',
          'voided_at': DateTime.now().toUtc().toIso8601String(),
          'void_reason': reason.trim(),
        })
        .eq('id', id)
        .eq('branch_id', branchId);
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
