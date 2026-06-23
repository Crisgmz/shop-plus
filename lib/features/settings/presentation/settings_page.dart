import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/services/dgii_lookup_service.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ncf_stock_banner.dart'
    show missingNcfCountProvider;
import '../../../shared/widgets/ui_custom.dart';
import '../data/settings_repository.dart';
import 'settings_providers.dart';

const _receiptTypeLabels = <String, String>{
  'consumer_final': 'Consumidor final',
  'fiscal_credit': 'Crédito fiscal',
  'governmental': 'Gubernamental',
  'special': 'Especial',
  'export': 'Exportación',
};

/// Prefijo NCF según DGII (RD): serie B + tipo de comprobante (2 dígitos). El
/// NCF se forma como prefijo + 8 dígitos de secuencia (ej. B02 + 00000001 =
/// B0200000001, 11 caracteres). Estos son los códigos oficiales por tipo.
const _dgiiNcfPrefixes = <String, String>{
  'consumer_final': 'B02', // Factura de Consumo (consumidor final)
  'fiscal_credit': 'B01', // Factura de Crédito Fiscal
  'governmental': 'B15', // Comprobante Gubernamental
  'special': 'B14', // Comprobante de Regímenes Especiales
  'export': 'B16', // Comprobante para Exportaciones
};

/// Tipos cuyas secuencias NCF NO vencen, según DGII (Guía de Comprobantes
/// Fiscales, sección 6): Facturas de Consumo (B02), Notas de Crédito (B04) y
/// Registro Único de Ingresos (B12). El resto vence el 31 de diciembre del año
/// siguiente al que fue autorizado. De estos, el POS solo emite B02.
const _dgiiNonExpiringTypes = <String>{'consumer_final'};

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsDataProvider);

    return ModulePage(
      title: 'Configuración',
      description: 'Perfil, sucursal actual, fiscal y secuencias NCF.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/configuracion'),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Configuración global'),
        ),
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: settingsAsync.when(
        data: (data) {
          final activeNcf = data.ncfSequences.where((item) => item.isActive);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsKpis(
                branchCount: data.userBranches.length,
                ncfCount: activeNcf.length,
                role: _roleLabel(data.profile?.role),
              ),
              const SizedBox(height: AppTokens.s24),
              _profileCard(data.profile),
              const SizedBox(height: AppTokens.s24),
              _branchCard(data),
              const SizedBox(height: AppTokens.s24),
              _fiscalSettingsCard(data),
              const SizedBox(height: AppTokens.s24),
              _businessProfileCard(),
              const SizedBox(height: AppTokens.s24),
              _ncfCard(data),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorCard(
          message: 'No se pudo cargar configuración: $error',
          onRetry: _refresh,
        ),
      ),
    );
  }

  // ─── Profile card ────────────────────────────────────────────────────────────

  Widget _profileCard(SettingsProfile? profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Perfil de usuario',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: profile == null
                      ? null
                      : () => _onEditProfile(profile),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (profile == null)
              const Text('No se encontró perfil para este usuario.')
            else
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _detail('Nombre', profile.fullName),
                  _detail('Email', profile.email ?? '-'),
                  _detail('Teléfono', profile.phone ?? '-'),
                  _detail('Rol', _roleLabel(profile.role)),
                  if (profile.jobTitle != null)
                    _detail('Cargo', profile.jobTitle!),
                  if (profile.employeeCode != null)
                    _detail('Código empleado', profile.employeeCode!),
                  if (profile.hireDate != null)
                    _detail('Fecha contratación', _date(profile.hireDate!)),
                  _detail('Estado', profile.isActive ? 'Activo' : 'Inactivo'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ─── Branch card ─────────────────────────────────────────────────────────────

  Widget _branchCard(SettingsData data) {
    final branch = data.currentBranch;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sucursal actual',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: branch == null
                      ? null
                      : () => _onEditBranch(branch),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Editar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (branch == null)
              const Text('No hay una sucursal actual asignada.')
            else
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _detail('Código', branch.code),
                  _detail('Nombre', branch.name),
                  if (branch.legalName != null)
                    _detail('Razón social', branch.legalName!),
                  if (branch.tradeName != null)
                    _detail('Nombre comercial', branch.tradeName!),
                  if (branch.taxId != null)
                    _detail('RNC/Tax ID', branch.taxId!),
                  if (branch.fiscalRegime != null)
                    _detail('Régimen fiscal', branch.fiscalRegime!),
                  if (branch.city != null || branch.province != null)
                    _detail(
                      'Ubicación',
                      [
                        branch.city,
                        branch.province,
                      ].whereType<String>().join(', '),
                    ),
                  _detail('Dirección', branch.address ?? '-'),
                  if (branch.postalCode != null)
                    _detail('Código postal', branch.postalCode!),
                  _detail('País', branch.countryCode),
                  _detail('Moneda', branch.currencyCode),
                  _detail('Teléfono', branch.phone ?? '-'),
                  if (branch.whatsapp != null)
                    _detail('WhatsApp', branch.whatsapp!),
                  if (branch.email != null) _detail('Email', branch.email!),
                  if (branch.website != null) _detail('Web', branch.website!),
                  _detail(
                    'ITBIS',
                    '${branch.defaultTaxRate.toStringAsFixed(0)}%'
                        '${branch.taxIncludedByDefault ? ' (incluido)' : ''}',
                  ),
                  _detail(
                    'Serv. cargo',
                    '${branch.defaultServiceChargeRate.toStringAsFixed(0)}%',
                  ),
                  _detail('Principal', branch.isMain ? 'Sí' : 'No'),
                  _detail('Estado', branch.isActive ? 'Activa' : 'Inactiva'),
                ],
              ),
            const SizedBox(height: 12),
            Text(
              'Sucursales asignadas',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (data.userBranches.isEmpty)
              const Text('No hay sucursales asignadas a este usuario.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: data.userBranches
                    .map((membership) {
                      final isCurrent =
                          membership.branchId == data.currentBranchId;
                      return Chip(
                        avatar: Icon(
                          isCurrent
                              ? Icons.check_circle_outline
                              : Icons.storefront_outlined,
                          size: 18,
                        ),
                        label: Text(
                          '${membership.branch.code} - ${membership.branch.name}'
                          '${membership.isDefault ? ' (Default)' : ''}',
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Fiscal settings card ────────────────────────────────────────────────────

  Widget _fiscalSettingsCard(SettingsData data) {
    final fiscal = data.fiscalSettings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Configuración fiscal del negocio',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: data.currentBranch == null
                      ? null
                      : () => _onEditFiscalSettings(fiscal),
                  icon: Icon(fiscal == null ? Icons.add : Icons.edit_outlined),
                  label: Text(fiscal == null ? 'Configurar' : 'Editar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (data.currentBranch == null)
              const Text('No hay sucursal actual asignada.')
            else if (fiscal == null)
              const Text(
                'No se ha configurado el perfil fiscal del negocio.',
                style: TextStyle(color: AppTokens.mutedForeground),
              )
            else
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  if (fiscal.taxpayerName != null)
                    _detail('Contribuyente', fiscal.taxpayerName!),
                  if (fiscal.taxpayerRnc != null)
                    _detail('RNC', fiscal.taxpayerRnc!),
                  if (fiscal.commercialName != null)
                    _detail('Nombre comercial', fiscal.commercialName!),
                  if (fiscal.fiscalAddress != null)
                    _detail('Dirección fiscal', fiscal.fiscalAddress!),
                  _detail(
                    'Comprobante por defecto',
                    _receiptTypeLabel(fiscal.defaultReceiptType),
                  ),
                  _detail(
                    'Cargo por servicio',
                    fiscal.serviceChargeEnabled
                        ? '${fiscal.serviceChargeRate.toStringAsFixed(0)}%'
                        : 'Desactivado',
                  ),
                  _detail(
                    'ITBIS',
                    fiscal.taxEnabled
                        ? '${fiscal.defaultTaxRate.toStringAsFixed(0)}%'
                        : 'Desactivado',
                  ),
                  _detail(
                    'Ventas a crédito',
                    fiscal.allowCreditSales ? 'Permitido' : 'No permitido',
                  ),
                  _detail(
                    'Validez cotización',
                    '${fiscal.quoteValidDays} días',
                  ),
                  if (fiscal.email != null)
                    _detail('Email fiscal', fiscal.email!),
                  if (fiscal.phone != null)
                    _detail('Teléfono fiscal', fiscal.phone!),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ─── Business profile card ───────────────────────────────────────────────────

  Widget _businessProfileCard() {
    final profileAsync = ref.watch(businessProfileProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perfil de facturación efectivo',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Valores consolidados que aparecerán en las facturas',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 10),
            profileAsync.when(
              data: (profile) {
                if (profile == null) {
                  return const Text(
                    'No hay perfil disponible para esta sucursal.',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  );
                }
                final location = [
                  profile.city,
                  profile.province,
                ].whereType<String>().join(', ');
                return Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _detail('Nombre fiscal', profile.displayName),
                    if (profile.legalName.isNotEmpty)
                      _detail('Razón social', profile.legalName),
                    if (profile.taxId != null) _detail('RNC', profile.taxId!),
                    if (profile.email != null) _detail('Email', profile.email!),
                    if (profile.phone != null)
                      _detail('Teléfono', profile.phone!),
                    if (profile.website != null)
                      _detail('Web', profile.website!),
                    if (profile.address != null)
                      _detail('Dirección', profile.address!),
                    if (location.isNotEmpty)
                      _detail('Ciudad / Provincia', location),
                    _detail('País', profile.countryCode),
                    _detail('Moneda', profile.currencyCode),
                    _detail(
                      'Comprobante por defecto',
                      _receiptTypeLabel(profile.defaultReceiptType),
                    ),
                    _detail(
                      'ITBIS',
                      profile.taxEnabled
                          ? '${profile.defaultTaxRate.toStringAsFixed(0)}%'
                          : 'Desactivado',
                    ),
                    _detail(
                      'Cargo por servicio',
                      profile.serviceChargeEnabled
                          ? '${profile.defaultServiceChargeRate.toStringAsFixed(0)}%'
                          : 'Desactivado',
                    ),
                    if (profile.invoiceFooter != null)
                      _detail('Pie de factura', profile.invoiceFooter!),
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 32,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text(
                'Error cargando perfil: $e',
                style: const TextStyle(color: AppTokens.destructive),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── NCF card ────────────────────────────────────────────────────────────────

  Widget _ncfCard(SettingsData data) {
    // El aviso de "ventas sin NCF" va FUERA del DataTableShell. Ese shell
    // envuelve su hijo en un scroll horizontal de ancho NO acotado (maxWidth
    // infinito), y un Row con Expanded ahí dentro revienta el layout
    // (RenderFlex unbounded width), lo que rompía la tarjeta y dejaba muerto el
    // botón "Nueva secuencia". Aquí el ancho está acotado por la página.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _missingNcfBanner(),
        DataTableShell(
          title: 'Secuencias NCF',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s20,
                  AppTokens.s12,
                  AppTokens.s20,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: data.currentBranch == null ? null : _onCreateNcf,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nueva secuencia'),
                  ),
                ),
              ),
              if (data.currentBranch == null)
                const Padding(
                  padding: EdgeInsets.all(AppTokens.s20),
                  child: Text(
                    'Asigna una sucursal actual para gestionar NCF.',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  ),
                )
              else if (data.ncfSequences.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppTokens.s20),
                  child: Text(
                    'No hay secuencias NCF registradas.',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Tipo')),
                      DataColumn(label: Text('Prefijo')),
                      DataColumn(label: Text('Serie')),
                      DataColumn(label: Text('Actual'), numeric: true),
                      DataColumn(label: Text('Máximo'), numeric: true),
                      DataColumn(label: Text('Disponible'), numeric: true),
                      DataColumn(label: Text('Alerta'), numeric: true),
                      DataColumn(label: Text('Vence')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: data.ncfSequences
                        .map(
                          (item) => DataRow(
                            cells: [
                              DataCell(
                                Text(_receiptTypeLabel(item.receiptType)),
                              ),
                              DataCell(
                                Text(
                                  item.prefix,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              DataCell(Text(item.series ?? '-')),
                              DataCell(Text(item.currentNumber.toString())),
                              DataCell(Text(item.maxNumber?.toString() ?? '-')),
                              DataCell(
                                Text(item.available?.toString() ?? 'Ilimitado'),
                              ),
                              DataCell(Text(item.warningThreshold.toString())),
                              DataCell(
                                Text(
                                  item.expiresOn == null
                                      ? '-'
                                      : _date(item.expiresOn!),
                                ),
                              ),
                              DataCell(
                                StatusBadge(
                                  label: item.isActive ? 'Activa' : 'Inactiva',
                                  status: item.isActive ? 'active' : 'inactive',
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar',
                                      onPressed: () => _onEditNcf(item),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: AppTokens.iconSizeS,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    IconButton(
                                      tooltip: item.isActive
                                          ? 'Desactivar'
                                          : 'Activar',
                                      onPressed: () => _onToggleNcf(item),
                                      icon: Icon(
                                        item.isActive
                                            ? Icons.block_outlined
                                            : Icons.check_circle_outline,
                                        size: AppTokens.iconSizeS,
                                        color: item.isActive
                                            ? AppTokens.destructive
                                            : AppTokens.success,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Aviso de ventas emitidas SIN NCF + botón de backfill. Va fuera del
  /// DataTableShell para tener ancho acotado (Expanded válido).
  Widget _missingNcfBanner() {
    return Consumer(
      builder: (context, ref, _) {
        final missing = ref.watch(missingNcfCountProvider).valueOrNull ?? 0;
        if (missing == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s12),
          child: Container(
            padding: const EdgeInsets.all(AppTokens.s12),
            decoration: BoxDecoration(
              color: AppTokens.destructive.withValues(alpha: 0.10),
              border: Border.all(
                color: AppTokens.destructive.withValues(alpha: 0.40),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: AppTokens.destructive,
                  size: 20,
                ),
                const SizedBox(width: AppTokens.s12),
                Expanded(
                  child: Text(
                    '$missing venta(s) emitida(s) sin NCF. '
                    'Faltó una secuencia o se agotó.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: AppTokens.s12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.destructive,
                  ),
                  onPressed: _onAssignMissingNcfs,
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Asignar faltantes'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Shared detail widget ────────────────────────────────────────────────────

  Widget _detail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppTokens.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(value),
      ],
    );
  }

  // ─── Actions ────────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    ref.invalidate(settingsDataProvider);
    ref.invalidate(businessProfileProvider);
  }

  Future<void> _onEditProfile(SettingsProfile profile) async {
    final result = await showDialog<_ProfileDialogResult>(
      context: context,
      builder: (_) => _ProfileDialog(profile: profile),
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateProfile(
            ProfileUpdateInput(
              fullName: result.fullName,
              phone: result.phone,
              employeeCode: result.employeeCode,
              jobTitle: result.jobTitle,
              hireDate: result.hireDate,
              notes: result.notes,
              avatarUrl: result.avatarUrl,
              pinCode: result.pinCode,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
      ref.invalidate(settingsDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar perfil: $error')),
      );
    }
  }

  Future<void> _onEditBranch(SettingsBranch branch) async {
    final result = await showDialog<_BranchDialogResult>(
      context: context,
      builder: (_) => _BranchDialog(branch: branch),
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateCurrentBranch(
            BranchUpdateInput(
              name: result.name,
              address: result.address,
              phone: result.phone,
              isActive: result.isActive,
              legalName: result.legalName,
              tradeName: result.tradeName,
              taxId: result.taxId,
              fiscalRegime: result.fiscalRegime,
              email: result.email,
              city: result.city,
              province: result.province,
              defaultTaxRate: result.defaultTaxRate,
              defaultServiceChargeRate: result.defaultServiceChargeRate,
              taxIncludedByDefault: result.taxIncludedByDefault,
              invoiceFooter: result.invoiceFooter,
              website: result.website,
              whatsapp: result.whatsapp,
              quoteTerms: result.quoteTerms,
              postalCode: result.postalCode,
              countryCode: result.countryCode,
              currencyCode: result.currencyCode,
              timezoneName: result.timezoneName,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sucursal actualizada')));
      ref.invalidate(settingsDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar sucursal: $error')),
      );
    }
  }

  Future<void> _onEditFiscalSettings(BranchFiscalSettings? current) async {
    final result = await showDialog<_FiscalDialogResult>(
      context: context,
      builder: (_) => _FiscalSettingsDialog(current: current),
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveBranchFiscalSettings(
            BranchFiscalSettingsInput(
              taxpayerName: result.taxpayerName,
              taxpayerRnc: result.taxpayerRnc,
              commercialName: result.commercialName,
              fiscalAddress: result.fiscalAddress,
              invoiceCity: result.invoiceCity,
              invoiceProvince: result.invoiceProvince,
              countryCode: result.countryCode,
              email: result.email,
              phone: result.phone,
              website: result.website,
              defaultReceiptType: result.defaultReceiptType,

              serviceChargeEnabled: result.serviceChargeEnabled,
              serviceChargeRate: result.serviceChargeRate,
              taxEnabled: result.taxEnabled,
              defaultTaxRate: result.defaultTaxRate,
              allowCreditSales: result.allowCreditSales,
              quoteValidDays: result.quoteValidDays,
              invoiceFooter: result.invoiceFooter,
              termsAndConditions: result.termsAndConditions,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración fiscal guardada')),
      );
      ref.invalidate(settingsDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar configuración fiscal: $error'),
        ),
      );
    }
  }

  Future<void> _onCreateNcf() async {
    final result = await showDialog<_NcfDialogResult>(
      context: context,
      builder: (_) => const _NcfDialog(),
    );
    if (result == null || !mounted) return;
    await _saveNcf(result);
  }

  Future<void> _onEditNcf(SettingsNcfSequence sequence) async {
    final result = await showDialog<_NcfDialogResult>(
      context: context,
      builder: (_) => _NcfDialog(sequence: sequence),
    );
    if (result == null || !mounted) return;
    await _saveNcf(result);
  }

  Future<void> _saveNcf(_NcfDialogResult input) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveNcfSequence(
            NcfSequenceInput(
              id: input.id,
              receiptType: input.receiptType,
              prefix: input.prefix,
              currentNumber: input.currentNumber,
              maxNumber: input.maxNumber,
              expiresOn: input.expiresOn,
              isActive: input.isActive,
              series: input.series,
              documentCode: input.documentCode,
              sequenceStart: input.sequenceStart,
              sequenceEnd: input.sequenceEnd,
              warningThreshold: input.warningThreshold,
              status: input.status,
              notes: input.notes,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secuencia NCF guardada')));
      ref.invalidate(settingsDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar secuencia: $error')),
      );
    }
  }

  Future<void> _onToggleNcf(SettingsNcfSequence sequence) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setNcfSequenceActive(
            sequenceId: sequence.id,
            isActive: !sequence.isActive,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sequence.isActive ? 'Secuencia desactivada' : 'Secuencia activada',
          ),
        ),
      );
      ref.invalidate(settingsDataProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar secuencia: $error')),
      );
    }
  }

  /// Asigna NCF a las ventas emitidas que quedaron sin comprobante (backfill).
  /// Acción manual y explícita: solo toca ventas SIN NCF (nunca sobrescribe una
  /// que ya tenga comprobante). Pide confirmación para no dispararse por error.
  Future<void> _onAssignMissingNcfs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Asignar NCF a ventas sin comprobante'),
        content: const Text(
          'Se asignará el siguiente NCF disponible solo a las ventas que '
          'quedaron SIN comprobante. Las ventas que ya tienen NCF no se tocan. '
          'Ojo: recibirán números nuevos (posteriores a los más recientes). '
          '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ref
          .read(settingsRepositoryProvider)
          .assignMissingNcfs();
      if (!mounted) return;
      ref.invalidate(missingNcfCountProvider);
      ref.invalidate(settingsDataProvider);
      final msg = res.failed > 0
          ? 'NCF asignados: ${res.assigned}. Sin asignar: ${res.failed} '
                '(revisa la secuencia, puede estar agotada o vencida).'
          : res.assigned > 0
          ? '${res.assigned} NCF asignado(s) a ventas pendientes.'
          : 'No había ventas sin NCF.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron asignar los NCF: $error')),
      );
    }
  }
}

// ─── KPIs ────────────────────────────────────────────────────────────────────

class _SettingsKpis extends StatelessWidget {
  const _SettingsKpis({
    required this.branchCount,
    required this.ncfCount,
    required this.role,
  });

  final int branchCount;
  final int ncfCount;
  final String role;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Sucursales asignadas',
        value: branchCount.toString(),
        icon: Icons.business_outlined,
      ),
      KPICard(
        label: 'Secuencias NCF activas',
        value: ncfCount.toString(),
        icon: Icons.receipt_long_outlined,
      ),
      KPICard(label: 'Rol', value: role, icon: Icons.badge_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 800
            ? 3
            : w >= 400
            ? 2
            : 1;
        final cardWidth = (w - (cols - 1) * AppTokens.s12) / cols;
        return Wrap(
          spacing: AppTokens.s12,
          runSpacing: AppTokens.s12,
          children: cards
              .map((c) => SizedBox(width: cardWidth, child: c))
              .toList(),
        );
      },
    );
  }
}

// ─── Profile dialog ──────────────────────────────────────────────────────────

class _ProfileDialogResult {
  _ProfileDialogResult({
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

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profile});

  final SettingsProfile profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _employeeCodeController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _hireDateController;
  late final TextEditingController _notesController;
  late final TextEditingController _avatarUrlController;
  late final TextEditingController _pinCodeController;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _fullNameController = TextEditingController(text: p.fullName);
    _phoneController = TextEditingController(text: p.phone ?? '');
    _employeeCodeController = TextEditingController(text: p.employeeCode ?? '');
    _jobTitleController = TextEditingController(text: p.jobTitle ?? '');
    _hireDateController = TextEditingController(
      text: p.hireDate == null ? '' : _date(p.hireDate!),
    );
    _notesController = TextEditingController(text: p.notes ?? '');
    _avatarUrlController = TextEditingController(text: p.avatarUrl ?? '');
    _pinCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _employeeCodeController.dispose();
    _jobTitleController.dispose();
    _hireDateController.dispose();
    _notesController.dispose();
    _avatarUrlController.dispose();
    _pinCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return AlertDialog(
      title: const Text('Editar perfil'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Este campo es requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                _row(isMobile, [
                  TextFormField(
                    controller: _jobTitleController,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                  ),
                  TextFormField(
                    controller: _employeeCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Código empleado',
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hireDateController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Fecha contratación',
                    suffixIcon: IconButton(
                      onPressed: _pickHireDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _avatarUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de avatar (imagen)',
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pinCodeController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN (dejar vacío para no cambiar)',
                    hintText: '4–6 dígitos',
                  ),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return null;
                    if (!RegExp(r'^\d{4,6}$').hasMatch(v)) {
                      return 'El PIN debe tener 4 a 6 dígitos numéricos';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _ProfileDialogResult(
                fullName: _fullNameController.text.trim(),
                phone: _phoneController.text.trim(),
                employeeCode: _employeeCodeController.text.trim(),
                jobTitle: _jobTitleController.text.trim(),
                hireDate: _parseDate(_hireDateController.text),
                notes: _notesController.text.trim(),
                avatarUrl: _avatarUrlController.text.trim(),
                pinCode: _pinCodeController.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _pickHireDate() async {
    final now = DateTime.now();
    final parsed = _parseDate(_hireDateController.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
    );
    if (picked == null) return;
    _hireDateController.text = _date(picked);
  }

  Widget _row(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 12)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
              .toList()
            ..removeLast(),
    );
  }
}

// ─── Branch dialog ───────────────────────────────────────────────────────────

class _BranchDialogResult {
  _BranchDialogResult({
    required this.name,
    required this.address,
    required this.phone,
    required this.isActive,
    required this.defaultTaxRate,
    required this.defaultServiceChargeRate,
    required this.taxIncludedByDefault,
    required this.countryCode,
    required this.currencyCode,
    required this.timezoneName,
    this.legalName,
    this.tradeName,
    this.taxId,
    this.fiscalRegime,
    this.email,
    this.city,
    this.province,
    this.invoiceFooter,
    this.website,
    this.whatsapp,
    this.quoteTerms,
    this.postalCode,
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
  final String? quoteTerms;
  final String? postalCode;
  final String countryCode;
  final String currencyCode;
  final String timezoneName;
}

class _BranchDialog extends StatefulWidget {
  const _BranchDialog({required this.branch});

  final SettingsBranch branch;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _legalNameController;
  late final TextEditingController _tradeNameController;
  late final TextEditingController _taxIdController;
  late final TextEditingController _fiscalRegimeController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _countryCodeController;
  late final TextEditingController _currencyCodeController;
  late final TextEditingController _timezoneController;
  late final TextEditingController _websiteController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _defaultTaxRateController;
  late final TextEditingController _defaultServiceChargeRateController;
  late final TextEditingController _invoiceFooterController;
  late final TextEditingController _quoteTermsController;
  late bool _isActive;
  late bool _taxIncludedByDefault;

  @override
  void initState() {
    super.initState();
    final b = widget.branch;
    _nameController = TextEditingController(text: b.name);
    _legalNameController = TextEditingController(text: b.legalName ?? '');
    _tradeNameController = TextEditingController(text: b.tradeName ?? '');
    _taxIdController = TextEditingController(text: b.taxId ?? '');
    _fiscalRegimeController = TextEditingController(text: b.fiscalRegime ?? '');
    _emailController = TextEditingController(text: b.email ?? '');
    _addressController = TextEditingController(text: b.address ?? '');
    _phoneController = TextEditingController(text: b.phone ?? '');
    _cityController = TextEditingController(text: b.city ?? '');
    _provinceController = TextEditingController(text: b.province ?? '');
    _postalCodeController = TextEditingController(text: b.postalCode ?? '');
    _countryCodeController = TextEditingController(text: b.countryCode);
    _currencyCodeController = TextEditingController(text: b.currencyCode);
    _timezoneController = TextEditingController(text: b.timezoneName);
    _websiteController = TextEditingController(text: b.website ?? '');
    _whatsappController = TextEditingController(text: b.whatsapp ?? '');
    _defaultTaxRateController = TextEditingController(
      text: b.defaultTaxRate.toStringAsFixed(2),
    );
    _defaultServiceChargeRateController = TextEditingController(
      text: b.defaultServiceChargeRate.toStringAsFixed(2),
    );
    _invoiceFooterController = TextEditingController(
      text: b.invoiceFooter ?? '',
    );
    _quoteTermsController = TextEditingController(text: b.quoteTerms ?? '');
    _isActive = b.isActive;
    _taxIncludedByDefault = b.taxIncludedByDefault;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _taxIdController.dispose();
    _fiscalRegimeController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    _countryCodeController.dispose();
    _currencyCodeController.dispose();
    _timezoneController.dispose();
    _websiteController.dispose();
    _whatsappController.dispose();
    _defaultTaxRateController.dispose();
    _defaultServiceChargeRateController.dispose();
    _invoiceFooterController.dispose();
    _quoteTermsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return AlertDialog(
      title: const Text('Editar sucursal'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Identificación ──────────────────────────────────────
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la sucursal',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Este campo es requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _legalNameController,
                  decoration: const InputDecoration(labelText: 'Razón social'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tradeNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre comercial',
                  ),
                ),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _taxIdController,
                    decoration: const InputDecoration(
                      labelText: 'RNC / Tax ID',
                    ),
                  ),
                  TextFormField(
                    controller: _fiscalRegimeController,
                    decoration: const InputDecoration(
                      labelText: 'Régimen fiscal',
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                // ── Contacto y ubicación ─────────────────────────────────
                _row(isMobile, [
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                  ),
                  TextFormField(
                    controller: _whatsappController,
                    decoration: const InputDecoration(labelText: 'WhatsApp'),
                  ),
                ]),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextFormField(
                    controller: _websiteController,
                    decoration: const InputDecoration(labelText: 'Sitio web'),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                  ),
                  TextFormField(
                    controller: _provinceController,
                    decoration: const InputDecoration(labelText: 'Provincia'),
                  ),
                ]),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _postalCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Código postal',
                    ),
                  ),
                  TextFormField(
                    controller: _countryCodeController,
                    decoration: const InputDecoration(labelText: 'País'),
                  ),
                ]),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _currencyCodeController,
                    decoration: const InputDecoration(labelText: 'Moneda'),
                  ),
                  TextFormField(
                    controller: _timezoneController,
                    decoration: const InputDecoration(
                      labelText: 'Zona horaria',
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                // ── Impuestos y configuración ────────────────────────────
                _row(isMobile, [
                  TextFormField(
                    controller: _defaultTaxRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'ITBIS por defecto (%)',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _defaultServiceChargeRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cargo servicio (%)',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _taxIncludedByDefault,
                  onChanged: (v) => setState(() => _taxIncludedByDefault = v),
                  title: const Text('ITBIS incluido en precio por defecto'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _invoiceFooterController,
                  decoration: const InputDecoration(
                    labelText: 'Nota de pie de factura',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quoteTermsController,
                  decoration: const InputDecoration(
                    labelText: 'Términos y condiciones (cotizaciones)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                const Divider(),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Sucursal activa'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _BranchDialogResult(
                name: _nameController.text.trim(),
                legalName: _legalNameController.text.trim(),
                tradeName: _tradeNameController.text.trim(),
                taxId: _taxIdController.text.trim(),
                fiscalRegime: _fiscalRegimeController.text.trim(),
                email: _emailController.text.trim(),
                address: _addressController.text.trim(),
                phone: _phoneController.text.trim(),
                city: _cityController.text.trim(),
                province: _provinceController.text.trim(),
                postalCode: _postalCodeController.text.trim(),
                countryCode: _countryCodeController.text.trim().isEmpty
                    ? 'DO'
                    : _countryCodeController.text.trim(),
                currencyCode: _currencyCodeController.text.trim().isEmpty
                    ? 'DOP'
                    : _currencyCodeController.text.trim(),
                timezoneName: _timezoneController.text.trim().isEmpty
                    ? 'America/Santo_Domingo'
                    : _timezoneController.text.trim(),
                website: _websiteController.text.trim(),
                whatsapp: _whatsappController.text.trim(),
                defaultTaxRate: double.parse(
                  _defaultTaxRateController.text.trim(),
                ),
                defaultServiceChargeRate: double.parse(
                  _defaultServiceChargeRateController.text.trim(),
                ),
                taxIncludedByDefault: _taxIncludedByDefault,
                invoiceFooter: _invoiceFooterController.text.trim(),
                quoteTerms: _quoteTermsController.text.trim(),
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _row(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 12)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
              .toList()
            ..removeLast(),
    );
  }
}

// ─── Fiscal settings dialog ──────────────────────────────────────────────────

class _FiscalDialogResult {
  _FiscalDialogResult({
    required this.defaultReceiptType,
    required this.serviceChargeEnabled,
    required this.serviceChargeRate,
    required this.taxEnabled,
    required this.defaultTaxRate,
    required this.allowCreditSales,
    required this.quoteValidDays,
    required this.countryCode,
    this.taxpayerName,
    this.taxpayerRnc,
    this.commercialName,
    this.fiscalAddress,
    this.invoiceCity,
    this.invoiceProvince,
    this.email,
    this.phone,
    this.website,
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

class _FiscalSettingsDialog extends StatefulWidget {
  const _FiscalSettingsDialog({this.current});

  final BranchFiscalSettings? current;

  @override
  State<_FiscalSettingsDialog> createState() => _FiscalSettingsDialogState();
}

class _FiscalSettingsDialogState extends State<_FiscalSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _taxpayerNameController;
  late final TextEditingController _taxpayerRncController;
  late final TextEditingController _commercialNameController;
  late final TextEditingController _fiscalAddressController;
  late final TextEditingController _invoiceCityController;
  late final TextEditingController _invoiceProvinceController;
  late final TextEditingController _countryCodeController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _websiteController;
  late final TextEditingController _serviceChargeRateController;
  late final TextEditingController _defaultTaxRateController;
  late final TextEditingController _quoteValidDaysController;
  late final TextEditingController _invoiceFooterController;
  late final TextEditingController _termsController;
  late String _defaultReceiptType;
  late bool _serviceChargeEnabled;
  late bool _taxEnabled;
  late bool _allowCreditSales;

  final _dgii = DgiiLookupService();
  bool _rncLookupLoading = false;

  /// Consulta el RNC del negocio contra DGII y auto-completa nombre del
  /// contribuyente (razón social) y nombre comercial.
  Future<void> _lookupRnc() async {
    final raw = _taxpayerRncController.text.trim();
    if (raw.isEmpty) {
      AppSnackBar.info(context, 'Escribe el RNC primero.');
      return;
    }
    setState(() => _rncLookupLoading = true);
    try {
      final info = await _dgii.lookupByRnc(raw);
      if (!mounted) return;
      if (info == null) {
        AppSnackBar.error(context, 'RNC no encontrado en DGII.');
        return;
      }
      setState(() {
        final name = info.nombreRazonSocial ?? info.displayName;
        if (name != null &&
            name.isNotEmpty &&
            _taxpayerNameController.text.trim().isEmpty) {
          _taxpayerNameController.text = name;
        }
        final comercial = info.nombreComercial;
        if (comercial != null &&
            comercial.isNotEmpty &&
            _commercialNameController.text.trim().isEmpty) {
          _commercialNameController.text = comercial;
        }
      });
      if (info.isActivo) {
        AppSnackBar.success(context, 'Encontrado: ${info.displayName ?? raw}');
      } else {
        AppSnackBar.info(
          context,
          'Encontrado (${info.estado ?? "estado desconocido"}): '
          '${info.displayName ?? raw}',
        );
      }
    } on InvalidRncException catch (e) {
      if (mounted) AppSnackBar.error(context, e.reason);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo consultar el RNC', e);
    } finally {
      if (mounted) setState(() => _rncLookupLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _taxpayerNameController = TextEditingController(
      text: c?.taxpayerName ?? '',
    );
    _taxpayerRncController = TextEditingController(text: c?.taxpayerRnc ?? '');
    _commercialNameController = TextEditingController(
      text: c?.commercialName ?? '',
    );
    _fiscalAddressController = TextEditingController(
      text: c?.fiscalAddress ?? '',
    );
    _invoiceCityController = TextEditingController(text: c?.invoiceCity ?? '');
    _invoiceProvinceController = TextEditingController(
      text: c?.invoiceProvince ?? '',
    );
    _countryCodeController = TextEditingController(
      text: c?.countryCode ?? 'DO',
    );
    _emailController = TextEditingController(text: c?.email ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _websiteController = TextEditingController(text: c?.website ?? '');
    _serviceChargeRateController = TextEditingController(
      text: (c?.serviceChargeRate ?? 10.0).toStringAsFixed(2),
    );
    _defaultTaxRateController = TextEditingController(
      text: (c?.defaultTaxRate ?? 18.0).toStringAsFixed(2),
    );
    _quoteValidDaysController = TextEditingController(
      text: (c?.quoteValidDays ?? 15).toString(),
    );
    _invoiceFooterController = TextEditingController(
      text: c?.invoiceFooter ?? '',
    );
    _termsController = TextEditingController(text: c?.termsAndConditions ?? '');
    _defaultReceiptType = c?.defaultReceiptType ?? 'consumer_final';
    _serviceChargeEnabled = c?.serviceChargeEnabled ?? true;
    _taxEnabled = c?.taxEnabled ?? true;
    _allowCreditSales = c?.allowCreditSales ?? true;
  }

  @override
  void dispose() {
    _taxpayerNameController.dispose();
    _taxpayerRncController.dispose();
    _commercialNameController.dispose();
    _fiscalAddressController.dispose();
    _invoiceCityController.dispose();
    _invoiceProvinceController.dispose();
    _countryCodeController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _serviceChargeRateController.dispose();
    _defaultTaxRateController.dispose();
    _quoteValidDaysController.dispose();
    _invoiceFooterController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return AlertDialog(
      title: Text(
        widget.current == null
            ? 'Configurar perfil fiscal'
            : 'Editar perfil fiscal',
      ),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Contribuyente ────────────────────────────────────────
                TextFormField(
                  controller: _taxpayerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del contribuyente',
                  ),
                ),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _taxpayerRncController,
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (_) => _lookupRnc(),
                    decoration: InputDecoration(
                      labelText: 'RNC',
                      suffixIcon: _rncLookupLoading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Buscar en DGII',
                              icon: const Icon(Icons.search),
                              onPressed: _lookupRnc,
                            ),
                    ),
                  ),
                  TextFormField(
                    controller: _commercialNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre comercial',
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fiscalAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección fiscal',
                  ),
                ),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _invoiceCityController,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                  ),
                  TextFormField(
                    controller: _invoiceProvinceController,
                    decoration: const InputDecoration(labelText: 'Provincia'),
                  ),
                ]),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                  ),
                ]),
                const SizedBox(height: 12),
                _row(isMobile, [
                  TextFormField(
                    controller: _websiteController,
                    decoration: const InputDecoration(labelText: 'Sitio web'),
                  ),
                  TextFormField(
                    controller: _countryCodeController,
                    decoration: const InputDecoration(labelText: 'País'),
                  ),
                ]),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                // ── Configuración fiscal ─────────────────────────────────
                DropdownButtonFormField<String>(
                  initialValue: _defaultReceiptType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de comprobante por defecto',
                  ),
                  items: _receiptTypeLabels.entries
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _defaultReceiptType = v);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _taxEnabled,
                  onChanged: (v) => setState(() => _taxEnabled = v),
                  title: const Text('ITBIS habilitado'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_taxEnabled) ...[
                  TextFormField(
                    controller: _defaultTaxRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tasa ITBIS (%)',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 0) return 'Valor inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                SwitchListTile.adaptive(
                  value: _serviceChargeEnabled,
                  onChanged: (v) => setState(() => _serviceChargeEnabled = v),
                  title: const Text('Cargo por servicio habilitado'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_serviceChargeEnabled) ...[
                  TextFormField(
                    controller: _serviceChargeRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cargo por servicio (%)',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 0) return 'Valor inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                SwitchListTile.adaptive(
                  value: _allowCreditSales,
                  onChanged: (v) => setState(() => _allowCreditSales = v),
                  title: const Text('Permitir ventas a crédito'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _quoteValidDaysController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Días de validez cotización',
                  ),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null || parsed < 1) return 'Valor inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                // ── Documento ────────────────────────────────────────────
                TextFormField(
                  controller: _invoiceFooterController,
                  decoration: const InputDecoration(
                    labelText: 'Nota de pie de factura',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _termsController,
                  decoration: const InputDecoration(
                    labelText: 'Términos y condiciones',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _FiscalDialogResult(
                taxpayerName: _taxpayerNameController.text.trim(),
                taxpayerRnc: _taxpayerRncController.text.trim(),
                commercialName: _commercialNameController.text.trim(),
                fiscalAddress: _fiscalAddressController.text.trim(),
                invoiceCity: _invoiceCityController.text.trim(),
                invoiceProvince: _invoiceProvinceController.text.trim(),
                countryCode: _countryCodeController.text.trim().isEmpty
                    ? 'DO'
                    : _countryCodeController.text.trim(),
                email: _emailController.text.trim(),
                phone: _phoneController.text.trim(),
                website: _websiteController.text.trim(),
                defaultReceiptType: _defaultReceiptType,
                serviceChargeEnabled: _serviceChargeEnabled,
                serviceChargeRate: _serviceChargeEnabled
                    ? double.parse(_serviceChargeRateController.text.trim())
                    : 0,
                taxEnabled: _taxEnabled,
                defaultTaxRate: _taxEnabled
                    ? double.parse(_defaultTaxRateController.text.trim())
                    : 0,
                allowCreditSales: _allowCreditSales,
                quoteValidDays: int.parse(
                  _quoteValidDaysController.text.trim(),
                ),
                invoiceFooter: _invoiceFooterController.text.trim(),
                termsAndConditions: _termsController.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _row(bool isMobile, List<Widget> children) {
    if (isMobile) {
      return Column(
        children:
            children.expand((w) => [w, const SizedBox(height: 12)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
              .toList()
            ..removeLast(),
    );
  }
}

// ─── NCF dialog ──────────────────────────────────────────────────────────────

class _NcfDialogResult {
  _NcfDialogResult({
    required this.id,
    required this.receiptType,
    required this.prefix,
    required this.currentNumber,
    required this.maxNumber,
    required this.expiresOn,
    required this.isActive,
    required this.warningThreshold,
    required this.status,
    this.series,
    this.documentCode,
    this.sequenceStart,
    this.sequenceEnd,
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

class _NcfDialog extends StatefulWidget {
  const _NcfDialog({this.sequence});

  final SettingsNcfSequence? sequence;

  @override
  State<_NcfDialog> createState() => _NcfDialogState();
}

class _NcfDialogState extends State<_NcfDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _receiptType;
  late String _status;
  late final TextEditingController _prefixController;
  late final TextEditingController _seriesController;
  late final TextEditingController _documentCodeController;
  late final TextEditingController _currentController;
  late final TextEditingController _maxController;
  late final TextEditingController _seqStartController;
  late final TextEditingController _seqEndController;
  late final TextEditingController _warningController;
  late final TextEditingController _expiresController;
  late final TextEditingController _notesController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final s = widget.sequence;
    _receiptType = s?.receiptType ?? _receiptTypeLabels.keys.first;
    _status = s?.status ?? 'active';
    _prefixController = TextEditingController(
      text: s?.prefix ?? _dgiiNcfPrefixes[_receiptType] ?? '',
    );
    _seriesController = TextEditingController(text: s?.series ?? '');
    _documentCodeController = TextEditingController(
      text: s?.documentCode ?? '',
    );
    _currentController = TextEditingController(
      text: s?.currentNumber.toString() ?? '0',
    );
    _maxController = TextEditingController(
      text: s?.maxNumber?.toString() ?? '',
    );
    _seqStartController = TextEditingController(
      text: s?.sequenceStart?.toString() ?? '',
    );
    _seqEndController = TextEditingController(
      text: s?.sequenceEnd?.toString() ?? '',
    );
    _warningController = TextEditingController(
      text: (s?.warningThreshold ?? 25).toString(),
    );
    _expiresController = TextEditingController(
      text: s?.expiresOn == null ? '' : _date(s!.expiresOn!),
    );
    _notesController = TextEditingController(text: s?.notes ?? '');
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _seriesController.dispose();
    _documentCodeController.dispose();
    _currentController.dispose();
    _maxController.dispose();
    _seqStartController.dispose();
    _seqEndController.dispose();
    _warningController.dispose();
    _expiresController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return AlertDialog(
      title: Text(
        widget.sequence == null
            ? 'Nueva secuencia NCF'
            : 'Editar secuencia NCF',
      ),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _receiptType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de comprobante',
                  ),
                  items: _receiptTypeLabels.entries
                      .map((entry) {
                        final code = _dgiiNcfPrefixes[entry.key];
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            code == null
                                ? entry.value
                                : '${entry.value} ($code)',
                          ),
                        );
                      })
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      final prevPrefix = _dgiiNcfPrefixes[_receiptType];
                      _receiptType = value;
                      // Auto-completar el prefijo DGII al cambiar de tipo, sin
                      // pisar uno que el usuario haya escrito a mano.
                      final cur = _prefixController.text.trim();
                      if (cur.isEmpty || cur == prevPrefix) {
                        _prefixController.text = _dgiiNcfPrefixes[value] ?? cur;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _prefixController,
                        decoration: const InputDecoration(labelText: 'Prefijo'),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Este campo es requerido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _seriesController,
                        decoration: const InputDecoration(labelText: 'Serie'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _documentCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Código doc.',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _warningController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Alerta (disponibles)',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _seqStartController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Inicio rango',
                        ),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          if (trimmed.isEmpty) return null;
                          final parsed = int.tryParse(trimmed);
                          if (parsed == null || parsed < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _seqEndController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Fin rango',
                        ),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          if (trimmed.isEmpty) return null;
                          final parsed = int.tryParse(trimmed);
                          if (parsed == null || parsed < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currentController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Número actual',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Número máximo (opcional)',
                        ),
                        validator: (value) {
                          final trimmed = (value ?? '').trim();
                          if (trimmed.isEmpty) return null;
                          final parsed = int.tryParse(trimmed);
                          if (parsed == null || parsed < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _expiresController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Fecha vencimiento (opcional)',
                    helperText: _dgiiNonExpiringTypes.contains(_receiptType)
                        ? 'DGII: este comprobante no vence. Puedes dejarlo vacío.'
                        : 'DGII: vence el 31 dic del año siguiente a la '
                              'autorización.',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Activa')),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Inactiva'),
                    ),
                    DropdownMenuItem(
                      value: 'exhausted',
                      child: Text('Agotada'),
                    ),
                    DropdownMenuItem(value: 'expired', child: Text('Vencida')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _status = v);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Secuencia activa'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final parsed = _parseDate(_expiresController.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    _expiresController.text = _date(picked);
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;

    final current = int.parse(_currentController.text.trim());
    final maxText = _maxController.text.trim();
    final max = maxText.isEmpty ? null : int.parse(maxText);
    final expires = _parseDate(_expiresController.text);

    if (max != null && max < current) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El número máximo no puede ser menor al actual.'),
        ),
      );
      return;
    }

    final seqStartText = _seqStartController.text.trim();
    final seqEndText = _seqEndController.text.trim();

    Navigator.of(context).pop(
      _NcfDialogResult(
        id: widget.sequence?.id,
        receiptType: _receiptType,
        prefix: _prefixController.text.trim(),
        series: _seriesController.text.trim(),
        documentCode: _documentCodeController.text.trim(),
        currentNumber: current,
        maxNumber: max,
        sequenceStart: seqStartText.isEmpty ? null : int.parse(seqStartText),
        sequenceEnd: seqEndText.isEmpty ? null : int.parse(seqEndText),
        warningThreshold: int.parse(_warningController.text.trim()),
        expiresOn: expires,
        isActive: _isActive,
        status: _status,
        notes: _notesController.text.trim(),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _roleLabel(String? role) {
  switch (role) {
    case 'admin':
      return 'Administrador';
    case 'supervisor':
      return 'Supervisor';
    case 'cashier':
      return 'Cajero';
    case 'accountant':
      return 'Contador';
    default:
      return role == null || role.isEmpty ? '-' : role;
  }
}

String _receiptTypeLabel(String type) => _receiptTypeLabels[type] ?? type;

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}
