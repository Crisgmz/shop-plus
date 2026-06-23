import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsProfile {
  SettingsProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isActive,
    this.employeeCode,
    this.avatarUrl,
    this.jobTitle,
    this.hireDate,
    this.notes,
  });

  final String id;
  final String? email;
  final String fullName;
  final String? phone;
  final String role;
  final bool isActive;
  final String? employeeCode;
  final String? avatarUrl;
  final String? jobTitle;
  final DateTime? hireDate;
  final String? notes;

  factory SettingsProfile.fromMap(Map<String, dynamic> map) {
    return SettingsProfile(
      id: (map['id'] ?? '').toString(),
      email: map['email']?.toString(),
      fullName: (map['full_name'] ?? '').toString(),
      phone: map['phone']?.toString(),
      role: (map['role'] ?? '').toString(),
      isActive: map['is_active'] == true,
      employeeCode: map['employee_code']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      jobTitle: map['job_title']?.toString(),
      hireDate: map['hire_date'] == null
          ? null
          : DateTime.tryParse(map['hire_date'].toString()),
      notes: map['notes']?.toString(),
    );
  }
}

class SettingsBranch {
  SettingsBranch({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.phone,
    required this.isMain,
    required this.isActive,
    this.legalName,
    this.tradeName,
    this.taxId,
    this.fiscalRegime,
    this.email,
    this.city,
    this.province,
    this.defaultTaxRate = 18.0,
    this.defaultServiceChargeRate = 10.0,
    this.taxIncludedByDefault = false,
    this.invoiceFooter,
    this.website,
    this.whatsapp,
    this.logoUrl,
    this.quoteTerms,
    this.postalCode,
    this.countryCode = 'DO',
    this.currencyCode = 'DOP',
    this.timezoneName = 'America/Santo_Domingo',
  });

  final String id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool isMain;
  final bool isActive;
  final String? legalName;
  final String? tradeName;
  final String? taxId;
  final String? fiscalRegime;
  final String? email;
  final String? city;
  final String? province;
  final double defaultTaxRate;
  final double defaultServiceChargeRate;
  final bool taxIncludedByDefault;
  final String? invoiceFooter;
  final String? website;
  final String? whatsapp;
  final String? logoUrl;
  final String? quoteTerms;
  final String? postalCode;
  final String countryCode;
  final String currencyCode;
  final String timezoneName;

  factory SettingsBranch.fromMap(Map<String, dynamic> map) {
    return SettingsBranch(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      address: map['address']?.toString(),
      phone: map['phone']?.toString(),
      isMain: map['is_main'] == true,
      isActive: map['is_active'] == true,
      legalName: map['legal_name']?.toString(),
      tradeName: map['trade_name']?.toString(),
      taxId: map['tax_id']?.toString(),
      fiscalRegime: map['fiscal_regime']?.toString(),
      email: map['email']?.toString(),
      city: map['city']?.toString(),
      province: map['province']?.toString(),
      defaultTaxRate: _toDouble(map['default_tax_rate'] ?? 18.0),
      defaultServiceChargeRate:
          _toDouble(map['default_service_charge_rate'] ?? 10.0),
      taxIncludedByDefault: map['tax_included_by_default'] == true,
      invoiceFooter: map['invoice_footer']?.toString(),
      website: map['website']?.toString(),
      whatsapp: map['whatsapp']?.toString(),
      logoUrl: map['logo_url']?.toString(),
      quoteTerms: map['quote_terms']?.toString(),
      postalCode: map['postal_code']?.toString(),
      countryCode: (map['country_code'] ?? 'DO').toString(),
      currencyCode: (map['currency_code'] ?? 'DOP').toString(),
      timezoneName:
          (map['timezone_name'] ?? 'America/Santo_Domingo').toString(),
    );
  }
}

class SettingsUserBranch {
  SettingsUserBranch({
    required this.userBranchId,
    required this.branchId,
    required this.isDefault,
    required this.branch,
  });

  final String userBranchId;
  final String branchId;
  final bool isDefault;
  final SettingsBranch branch;

  factory SettingsUserBranch.fromMap(Map<String, dynamic> map) {
    final branchMap = Map<String, dynamic>.from(
      (map['branches'] as Map?) ?? const <String, dynamic>{},
    );

    return SettingsUserBranch(
      userBranchId: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      isDefault: map['is_default'] == true,
      branch: SettingsBranch.fromMap(branchMap),
    );
  }
}

class SettingsNcfSequence {
  SettingsNcfSequence({
    required this.id,
    required this.receiptType,
    required this.prefix,
    required this.currentNumber,
    required this.maxNumber,
    required this.expiresOn,
    required this.isActive,
    this.series,
    this.documentCode,
    this.sequenceStart,
    this.sequenceEnd,
    this.nextNumber,
    this.warningThreshold = 25,
    this.status = 'active',
    this.notes,
  });

  final String id;
  final String receiptType;
  final String prefix;
  final int currentNumber;
  final int? maxNumber;
  final DateTime? expiresOn;
  final bool isActive;
  final String? series;
  final String? documentCode;
  final int? sequenceStart;
  final int? sequenceEnd;
  final int? nextNumber;
  final int warningThreshold;
  final String status;
  final String? notes;

  int? get available {
    if (maxNumber == null) return null;
    final value = maxNumber! - currentNumber;
    return value < 0 ? 0 : value;
  }

  factory SettingsNcfSequence.fromMap(Map<String, dynamic> map) {
    return SettingsNcfSequence(
      id: (map['id'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      prefix: (map['prefix'] ?? '').toString(),
      currentNumber: _toInt(map['current_number']),
      maxNumber: map['max_number'] == null ? null : _toInt(map['max_number']),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
      isActive: map['is_active'] == true,
      series: map['series']?.toString(),
      documentCode: map['document_code']?.toString(),
      sequenceStart: map['sequence_start'] == null
          ? null
          : _toInt(map['sequence_start']),
      sequenceEnd: map['sequence_end'] == null
          ? null
          : _toInt(map['sequence_end']),
      nextNumber:
          map['next_number'] == null ? null : _toInt(map['next_number']),
      warningThreshold: _toInt(map['warning_threshold'] ?? 25),
      status: (map['status'] ?? 'active').toString(),
      notes: map['notes']?.toString(),
    );
  }
}

class BranchFiscalSettings {
  BranchFiscalSettings({
    required this.branchId,
    this.taxpayerName,
    this.taxpayerRnc,
    this.commercialName,
    this.fiscalAddress,
    this.invoiceCity,
    this.invoiceProvince,
    this.countryCode = 'DO',
    this.email,
    this.phone,
    this.website,
    this.logoUrl,
    this.defaultReceiptType = 'consumer_final',
    this.serviceChargeEnabled = true,
    this.serviceChargeRate = 10.0,
    this.taxEnabled = true,
    this.defaultTaxRate = 18.0,
    this.allowCreditSales = true,
    this.quoteValidDays = 15,
    this.invoiceFooter,
    this.termsAndConditions,
  });

  final String branchId;
  final String? taxpayerName;
  final String? taxpayerRnc;
  final String? commercialName;
  final String? fiscalAddress;
  final String? invoiceCity;
  final String? invoiceProvince;
  final String countryCode;
  final String? email;
  final String? phone;
  final String? website;
  final String? logoUrl;
  final String defaultReceiptType;
  final bool serviceChargeEnabled;
  final double serviceChargeRate;
  final bool taxEnabled;
  final double defaultTaxRate;
  final bool allowCreditSales;
  final int quoteValidDays;
  final String? invoiceFooter;
  final String? termsAndConditions;

  factory BranchFiscalSettings.fromMap(Map<String, dynamic> map) {
    return BranchFiscalSettings(
      branchId: (map['branch_id'] ?? '').toString(),
      taxpayerName: map['taxpayer_name']?.toString(),
      taxpayerRnc: map['taxpayer_rnc']?.toString(),
      commercialName: map['commercial_name']?.toString(),
      fiscalAddress: map['fiscal_address']?.toString(),
      invoiceCity: map['invoice_city']?.toString(),
      invoiceProvince: map['invoice_province']?.toString(),
      countryCode: (map['country_code'] ?? 'DO').toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      website: map['website']?.toString(),
      logoUrl: map['logo_url']?.toString(),
      defaultReceiptType:
          (map['default_receipt_type'] ?? 'consumer_final').toString(),
      serviceChargeEnabled: map['service_charge_enabled'] != false,
      serviceChargeRate: _toDouble(map['service_charge_rate'] ?? 10.0),
      taxEnabled: map['tax_enabled'] != false,
      defaultTaxRate: _toDouble(map['default_tax_rate'] ?? 18.0),
      allowCreditSales: map['allow_credit_sales'] != false,
      quoteValidDays: _toInt(map['quote_valid_days'] ?? 15),
      invoiceFooter: map['invoice_footer']?.toString(),
      termsAndConditions: map['terms_and_conditions']?.toString(),
    );
  }
}

class BusinessProfile {
  BusinessProfile({
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.displayName,
    required this.legalName,
    required this.defaultTaxRate,
    required this.defaultServiceChargeRate,
    required this.defaultReceiptType,
    required this.serviceChargeEnabled,
    required this.taxEnabled,
    this.taxId,
    this.email,
    this.phone,
    this.website,
    this.logoUrl,
    this.address,
    this.city,
    this.province,
    this.countryCode = 'DO',
    this.currencyCode = 'DOP',
    this.invoiceFooter,
  });

  final String branchId;
  final String branchCode;
  final String branchName;
  final String displayName;
  final String legalName;
  final String? taxId;
  final String? email;
  final String? phone;
  final String? website;
  final String? logoUrl;
  final String? address;
  final String? city;
  final String? province;
  final String countryCode;
  final String currencyCode;
  final double defaultTaxRate;
  final double defaultServiceChargeRate;
  final String? invoiceFooter;
  final String defaultReceiptType;
  final bool serviceChargeEnabled;
  final bool taxEnabled;

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      branchId: (map['branch_id'] ?? '').toString(),
      branchCode: (map['branch_code'] ?? '').toString(),
      branchName: (map['branch_name'] ?? '').toString(),
      displayName: (map['display_name'] ?? '').toString(),
      legalName: (map['legal_name'] ?? '').toString(),
      taxId: map['tax_id']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
      website: map['website']?.toString(),
      logoUrl: map['logo_url']?.toString(),
      address: map['address']?.toString(),
      city: map['city']?.toString(),
      province: map['province']?.toString(),
      countryCode: (map['country_code'] ?? 'DO').toString(),
      currencyCode: (map['currency_code'] ?? 'DOP').toString(),
      defaultTaxRate: _toDouble(map['default_tax_rate'] ?? 18.0),
      defaultServiceChargeRate:
          _toDouble(map['default_service_charge_rate'] ?? 10.0),
      invoiceFooter: map['invoice_footer']?.toString(),
      defaultReceiptType:
          (map['default_receipt_type'] ?? 'consumer_final').toString(),
      serviceChargeEnabled: map['service_charge_enabled'] != false,
      taxEnabled: map['tax_enabled'] != false,
    );
  }
}

class SettingsData {
  SettingsData({
    required this.profile,
    required this.userBranches,
    required this.currentBranchId,
    required this.currentBranch,
    required this.ncfSequences,
    this.fiscalSettings,
  });

  final SettingsProfile? profile;
  final List<SettingsUserBranch> userBranches;
  final String? currentBranchId;
  final SettingsBranch? currentBranch;
  final List<SettingsNcfSequence> ncfSequences;
  final BranchFiscalSettings? fiscalSettings;
}

class ProfileUpdateInput {
  ProfileUpdateInput({
    required this.fullName,
    required this.phone,
    this.employeeCode,
    this.jobTitle,
    this.hireDate,
    this.notes,
    this.avatarUrl,
    this.pinCode,
  });

  final String fullName;
  final String? phone;
  final String? employeeCode;
  final String? jobTitle;
  final DateTime? hireDate;
  final String? notes;
  final String? avatarUrl;
  final String? pinCode;
}

class BranchUpdateInput {
  BranchUpdateInput({
    required this.name,
    required this.address,
    required this.phone,
    required this.isActive,
    this.legalName,
    this.tradeName,
    this.taxId,
    this.fiscalRegime,
    this.email,
    this.city,
    this.province,
    this.defaultTaxRate = 18.0,
    this.defaultServiceChargeRate = 10.0,
    this.taxIncludedByDefault = false,
    this.invoiceFooter,
    this.website,
    this.whatsapp,
    this.logoUrl,
    this.quoteTerms,
    this.postalCode,
    this.countryCode = 'DO',
    this.currencyCode = 'DOP',
    this.timezoneName = 'America/Santo_Domingo',
  });

  final String name;
  final String? address;
  final String? phone;
  final bool isActive;
  final String? legalName;
  final String? tradeName;
  final String? taxId;
  final String? fiscalRegime;
  final String? email;
  final String? city;
  final String? province;
  final double defaultTaxRate;
  final double defaultServiceChargeRate;
  final bool taxIncludedByDefault;
  final String? invoiceFooter;
  final String? website;
  final String? whatsapp;
  final String? logoUrl;
  final String? quoteTerms;
  final String? postalCode;
  final String countryCode;
  final String currencyCode;
  final String timezoneName;
}

class NcfSequenceInput {
  NcfSequenceInput({
    required this.receiptType,
    required this.prefix,
    required this.currentNumber,
    required this.maxNumber,
    required this.expiresOn,
    required this.isActive,
    this.id,
    this.series,
    this.documentCode,
    this.sequenceStart,
    this.sequenceEnd,
    this.warningThreshold = 25,
    this.status = 'active',
    this.notes,
  });

  final String? id;
  final String receiptType;
  final String prefix;
  final int currentNumber;
  final int? maxNumber;
  final DateTime? expiresOn;
  final bool isActive;
  final String? series;
  final String? documentCode;
  final int? sequenceStart;
  final int? sequenceEnd;
  final int warningThreshold;
  final String status;
  final String? notes;
}

class BranchFiscalSettingsInput {
  BranchFiscalSettingsInput({
    this.taxpayerName,
    this.taxpayerRnc,
    this.commercialName,
    this.fiscalAddress,
    this.invoiceCity,
    this.invoiceProvince,
    this.countryCode = 'DO',
    this.email,
    this.phone,
    this.website,
    this.defaultReceiptType = 'consumer_final',
    this.serviceChargeEnabled = true,
    this.serviceChargeRate = 10.0,
    this.taxEnabled = true,
    this.defaultTaxRate = 18.0,
    this.allowCreditSales = true,
    this.quoteValidDays = 15,
    this.invoiceFooter,
    this.termsAndConditions,
  });

  final String? taxpayerName;
  final String? taxpayerRnc;
  final String? commercialName;
  final String? fiscalAddress;
  final String? invoiceCity;
  final String? invoiceProvince;
  final String countryCode;
  final String? email;
  final String? phone;
  final String? website;
  final String defaultReceiptType;
  final bool serviceChargeEnabled;
  final double serviceChargeRate;
  final bool taxEnabled;
  final double defaultTaxRate;
  final bool allowCreditSales;
  final int quoteValidDays;
  final String? invoiceFooter;
  final String? termsAndConditions;
}

class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  Future<SettingsData> fetchSettings() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesion para cargar configuracion.');
    }

    final results = await Future.wait<dynamic>([
      _fetchProfile(user.id),
      _fetchUserBranches(user.id),
      _currentBranchId(),
    ]);

    final profile = results[0] as SettingsProfile?;
    final userBranches = results[1] as List<SettingsUserBranch>;
    final currentBranchId = results[2] as String?;

    SettingsBranch? currentBranch;
    List<SettingsNcfSequence> ncfSequences = const [];
    BranchFiscalSettings? fiscalSettings;

    if (currentBranchId != null) {
      final branchResults = await Future.wait<dynamic>([
        _fetchBranch(currentBranchId),
        _fetchNcfSequences(currentBranchId),
        fetchBranchFiscalSettings(currentBranchId),
      ]);
      currentBranch = branchResults[0] as SettingsBranch?;
      ncfSequences = branchResults[1] as List<SettingsNcfSequence>;
      fiscalSettings = branchResults[2] as BranchFiscalSettings?;
    }

    return SettingsData(
      profile: profile,
      userBranches: userBranches,
      currentBranchId: currentBranchId,
      currentBranch: currentBranch,
      ncfSequences: ncfSequences,
      fiscalSettings: fiscalSettings,
    );
  }

  Future<void> updateProfile(ProfileUpdateInput input) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('No hay sesion activa.');

    await _client
        .from('profiles')
        .update({
          'full_name': input.fullName.trim(),
          'phone': _nullIfEmpty(input.phone),
          'employee_code': _nullIfEmpty(input.employeeCode),
          'job_title': _nullIfEmpty(input.jobTitle),
          'hire_date': input.hireDate?.toIso8601String().split('T').first,
          'notes': _nullIfEmpty(input.notes),
          'avatar_url': _nullIfEmpty(input.avatarUrl),
          'pin_code': _nullIfEmpty(input.pinCode),
        })
        .eq('id', user.id);
  }

  Future<void> updateCurrentBranch(BranchUpdateInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) throw Exception('No hay sucursal actual asignada.');

    await _client
        .from('branches')
        .update({
          'name': input.name.trim(),
          'address': _nullIfEmpty(input.address),
          'phone': _nullIfEmpty(input.phone),
          'is_active': input.isActive,
          'legal_name': _nullIfEmpty(input.legalName),
          'trade_name': _nullIfEmpty(input.tradeName),
          'tax_id': _nullIfEmpty(input.taxId),
          'fiscal_regime': _nullIfEmpty(input.fiscalRegime),
          'email': _nullIfEmpty(input.email),
          'city': _nullIfEmpty(input.city),
          'province': _nullIfEmpty(input.province),
          'default_tax_rate': input.defaultTaxRate,
          'default_service_charge_rate': input.defaultServiceChargeRate,
          'tax_included_by_default': input.taxIncludedByDefault,
          'invoice_footer': _nullIfEmpty(input.invoiceFooter),
          'website': _nullIfEmpty(input.website),
          'whatsapp': _nullIfEmpty(input.whatsapp),
          'logo_url': _nullIfEmpty(input.logoUrl),
          'quote_terms': _nullIfEmpty(input.quoteTerms),
          'postal_code': _nullIfEmpty(input.postalCode),
          'country_code':
              input.countryCode.isNotEmpty ? input.countryCode : 'DO',
          'currency_code':
              input.currencyCode.isNotEmpty ? input.currencyCode : 'DOP',
          'timezone_name': input.timezoneName.isNotEmpty
              ? input.timezoneName
              : 'America/Santo_Domingo',
        })
        .eq('id', branchId);
  }

  Future<void> saveNcfSequence(NcfSequenceInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) throw Exception('No hay sucursal actual asignada.');

    final payload = <String, dynamic>{
      'receipt_type': input.receiptType,
      'prefix': input.prefix.trim(),
      'current_number': input.currentNumber,
      'max_number': input.maxNumber,
      'expires_on': input.expiresOn?.toIso8601String().split('T').first,
      'is_active': input.isActive,
      'series': _nullIfEmpty(input.series),
      'document_code': _nullIfEmpty(input.documentCode),
      'sequence_start': input.sequenceStart,
      'sequence_end': input.sequenceEnd,
      'warning_threshold': input.warningThreshold,
      'status': input.status,
      'notes': _nullIfEmpty(input.notes),
    };

    if (input.id == null) {
      payload['branch_id'] = branchId;
      await _client.from('ncf_sequences').insert(payload);
      return;
    }

    await _client
        .from('ncf_sequences')
        .update(payload)
        .eq('id', input.id!)
        .eq('branch_id', branchId);
  }

  Future<void> setNcfSequenceActive({
    required String sequenceId,
    required bool isActive,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) throw Exception('No hay sucursal actual asignada.');

    await _client
        .from('ncf_sequences')
        .update({'is_active': isActive})
        .eq('id', sequenceId)
        .eq('branch_id', branchId);
  }

  /// Asigna el siguiente NCF disponible a las ventas emitidas (completed/credit)
  /// que quedaron sin comprobante en la sucursal actual. Llama al RPC
  /// `bulk_assign_missing_ncfs`. Devuelve cuántas se asignaron y cuántas
  /// quedaron sin asignar (p. ej. secuencia agotada).
  Future<({int assigned, int failed})> assignMissingNcfs() async {
    final branchId = await _currentBranchId();
    if (branchId == null) throw Exception('No hay sucursal actual asignada.');

    final result = await _client.rpc(
      'bulk_assign_missing_ncfs',
      params: {'p_branch_id': branchId},
    );

    final rows = (result as List?) ?? const [];
    var assigned = 0;
    var failed = 0;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final ncf = (map['ncf'] ?? '').toString().trim();
      if (ncf.isNotEmpty) {
        assigned++;
      } else {
        failed++;
      }
    }
    return (assigned: assigned, failed: failed);
  }

  Future<BranchFiscalSettings?> fetchBranchFiscalSettings([
    String? branchId,
  ]) async {
    final id = branchId ?? await _currentBranchId();
    if (id == null) return null;

    final rows = await _client
        .from('branch_fiscal_settings')
        .select()
        .eq('branch_id', id)
        .limit(1);

    if (rows.isEmpty) return null;
    return BranchFiscalSettings.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<void> saveBranchFiscalSettings(
    BranchFiscalSettingsInput input,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) throw Exception('No hay sucursal actual asignada.');

    await _client.from('branch_fiscal_settings').upsert(
      {
        'branch_id': branchId,
        'taxpayer_name': _nullIfEmpty(input.taxpayerName),
        'taxpayer_rnc': _nullIfEmpty(input.taxpayerRnc),
        'commercial_name': _nullIfEmpty(input.commercialName),
        'fiscal_address': _nullIfEmpty(input.fiscalAddress),
        'invoice_city': _nullIfEmpty(input.invoiceCity),
        'invoice_province': _nullIfEmpty(input.invoiceProvince),
        'country_code':
            input.countryCode.isNotEmpty ? input.countryCode : 'DO',
        'email': _nullIfEmpty(input.email),
        'phone': _nullIfEmpty(input.phone),
        'website': _nullIfEmpty(input.website),
        'default_receipt_type': input.defaultReceiptType,
        'service_charge_enabled': input.serviceChargeEnabled,
        'service_charge_rate': input.serviceChargeRate,
        'tax_enabled': input.taxEnabled,
        'default_tax_rate': input.defaultTaxRate,
        'allow_credit_sales': input.allowCreditSales,
        'quote_valid_days': input.quoteValidDays,
        'invoice_footer': _nullIfEmpty(input.invoiceFooter),
        'terms_and_conditions': _nullIfEmpty(input.termsAndConditions),
      },
      onConflict: 'branch_id',
    );
  }

  Future<SettingsProfile?> _fetchProfile(String userId) async {
    final rows = await _client
        .from('profiles')
        .select(
          'id, email, full_name, phone, role, is_active, '
          'employee_code, avatar_url, job_title, hire_date, notes',
        )
        .eq('id', userId)
        .limit(1);

    if (rows.isEmpty) return null;
    return SettingsProfile.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<SettingsUserBranch>> _fetchUserBranches(String userId) async {
    final rows = await _client
        .from('users_branches')
        .select(
          'id, branch_id, is_default, '
          'branches(id, code, name, address, phone, is_main, is_active, '
          'legal_name, trade_name, tax_id, fiscal_regime, email, city, province, '
          'default_tax_rate, default_service_charge_rate, tax_included_by_default, '
          'invoice_footer, website, whatsapp, logo_url, quote_terms, '
          'postal_code, country_code, currency_code, timezone_name)',
        )
        .eq('user_id', userId)
        .eq('is_active', true)
        .order('is_default', ascending: false);

    return rows
        .map(
          (item) => SettingsUserBranch.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<SettingsBranch?> _fetchBranch(String branchId) async {
    final rows = await _client
        .from('branches')
        .select(
          'id, code, name, address, phone, is_main, is_active, '
          'legal_name, trade_name, tax_id, fiscal_regime, email, city, province, '
          'default_tax_rate, default_service_charge_rate, tax_included_by_default, '
          'invoice_footer, website, whatsapp, logo_url, quote_terms, '
          'postal_code, country_code, currency_code, timezone_name',
        )
        .eq('id', branchId)
        .limit(1);

    if (rows.isEmpty) return null;
    return SettingsBranch.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<SettingsNcfSequence>> _fetchNcfSequences(
    String branchId,
  ) async {
    final rows = await _client
        .from('ncf_sequences')
        .select(
          'id, receipt_type, prefix, current_number, max_number, expires_on, '
          'is_active, series, document_code, sequence_start, sequence_end, '
          'next_number, warning_threshold, status, notes',
        )
        .eq('branch_id', branchId)
        .order('receipt_type')
        .order('prefix');

    return rows
        .map(
          (item) => SettingsNcfSequence.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<BusinessProfile?> fetchBusinessProfile() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final rows = await _client
        .from('branch_business_profile_view')
        .select(
          'branch_id, branch_code, branch_name, display_name, legal_name, '
          'tax_id, email, phone, website, logo_url, '
          'address, city, province, country_code, currency_code, '
          'default_tax_rate, default_service_charge_rate, invoice_footer, '
          'default_receipt_type, service_charge_enabled, tax_enabled',
        )
        .eq('branch_id', branchId)
        .limit(1);

    if (rows.isEmpty) return null;
    return BusinessProfile.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
