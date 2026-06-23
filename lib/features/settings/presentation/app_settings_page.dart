// Pantalla principal del PRD 06: Configuración Global del Negocio.
//
// Layout:
//   - Sidebar (280px en desktop, drawer en mobile) con las 7 secciones.
//   - Contenido scrolleable con tarjetas por sección.
//   - Auto-save por campo con feedback discreto ("Guardado ✓").
//   - Banner de solo lectura si el usuario no es admin.
//
// No reemplaza la pantalla actual `SettingsPage` (perfil/sucursal/NCF).
// Vive en /configuracion/global y se accede vía botón en SettingsPage.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../cash_register/data/cash_register_repository.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
import '../../inventory/data/file_io_helper.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../users/data/users_repository.dart';
import '../../users/presentation/users_providers.dart';
import '../data/app_settings.dart';
import 'app_settings_providers.dart';
import 'settings_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  final _sectionKeys = <AppSettingsSection, GlobalKey>{
    for (final s in AppSettingsSection.values) s: GlobalKey(),
  };
  AppSettingsSection _activeSection = AppSettingsSection.companyInfo;
  String _saveStatus = '';
  bool _hasError = false;

  void _scrollTo(AppSettingsSection section) {
    setState(() => _activeSection = section);
    final key = _sectionKeys[section];
    final ctx = key?.currentContext;
    if (ctx != null) {
      // ModulePage usa CustomScrollView; Scrollable.ensureVisible busca el
      // scrollable ancestral por nosotros — no necesitamos un controller propio.
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.02,
      );
    }
  }

  Future<void> _save(String column, dynamic value) async {
    setState(() {
      _saveStatus = 'Guardando…';
      _hasError = false;
    });
    try {
      await ref
          .read(appSettingsProvider.notifier)
          .updateField(column, value);
      if (!mounted) return;
      setState(() => _saveStatus = 'Guardado ✓');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _saveStatus == 'Guardado ✓') {
          setState(() => _saveStatus = '');
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saveStatus = 'Error al guardar';
        _hasError = true;
      });
      AppSnackBar.error(context, 'No se pudo guardar', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final profileAsync = ref.watch(settingsDataProvider);
    final isAdmin = profileAsync.valueOrNull?.profile?.role == 'admin';

    return ModulePage(
      title: 'Configuración global',
      description:
          'Ajustes operativos del negocio. Los cambios se guardan al instante.',
      actions: [
        if (_saveStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: AppTokens.s12),
            child: _SaveBadge(label: _saveStatus, isError: _hasError),
          ),
        OutlinedButton.icon(
          onPressed: () => context.push('/configuracion/cuenta'),
          icon: const Icon(Icons.person_outline, size: 18),
          label: const Text('Mi cuenta / NCF'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(appSettingsProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorCard(
          message: 'No se pudo cargar la configuración: $error',
          onRetry: () => ref.read(appSettingsProvider.notifier).refresh(),
        ),
        data: (settings) => _Body(
          settings: settings,
          isReadOnly: !isAdmin,
          activeSection: _activeSection,
          sectionKeys: _sectionKeys,
          onSectionTap: _scrollTo,
          onSave: _save,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.settings,
    required this.isReadOnly,
    required this.activeSection,
    required this.sectionKeys,
    required this.onSectionTap,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final AppSettingsSection activeSection;
  final Map<AppSettingsSection, GlobalKey> sectionKeys;
  final ValueChanged<AppSettingsSection> onSectionTap;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 980;

    // ModulePage ya provee el scroll vertical (CustomScrollView), así que el
    // contenido sólo necesita ser un Column. Si fuera un ListView, Flutter se
    // queja de "Vertical viewport was given unbounded height".
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isReadOnly) const _ReadOnlyBanner(),
        _CompanyInfoSection(
          key: sectionKeys[AppSettingsSection.companyInfo],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s24),
        _InventorySection(
          key: sectionKeys[AppSettingsSection.inventory],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s24),
        _EmployeeSection(
          key: sectionKeys[AppSettingsSection.employee],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s24),
        _TaxCurrencySection(
          key: sectionKeys[AppSettingsSection.taxCurrency],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s24),
        _SalesReceiptSection(
          key: sectionKeys[AppSettingsSection.salesReceipt],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s24),
        _SuspendedSalesSection(
          key: sectionKeys[AppSettingsSection.suspendedSales],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s24),
        _ApplicationSection(
          key: sectionKeys[AppSettingsSection.application],
          settings: settings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s48),
      ],
    );

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionDropdown(
            active: activeSection,
            onChanged: onSectionTap,
          ),
          const SizedBox(height: AppTokens.s12),
          content,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Sidebar(
          active: activeSection,
          onTap: onSectionTap,
        ),
        const SizedBox(width: AppTokens.s24),
        Expanded(child: content),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sidebar / Section navigator
// ─────────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.active, required this.onTap});

  final AppSettingsSection active;
  final ValueChanged<AppSettingsSection> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in AppSettingsSection.values)
                _SidebarItem(
                  section: section,
                  isActive: section == active,
                  onTap: () => onTap(section),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.isActive,
    required this.onTap,
  });

  final AppSettingsSection section;
  final bool isActive;
  final VoidCallback onTap;

  static const _iconBySection = <AppSettingsSection, IconData>{
    AppSettingsSection.companyInfo: Icons.business_outlined,
    AppSettingsSection.inventory: Icons.inventory_2_outlined,
    AppSettingsSection.employee: Icons.badge_outlined,
    AppSettingsSection.taxCurrency: Icons.attach_money_outlined,
    AppSettingsSection.salesReceipt: Icons.receipt_long_outlined,
    AppSettingsSection.suspendedSales: Icons.pause_circle_outline,
    AppSettingsSection.application: Icons.tune,
  };

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTokens.primary : AppTokens.foreground;
    return Material(
      color: isActive ? AppTokens.primary.withValues(alpha: 0.08) : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s12,
            vertical: AppTokens.s10,
          ),
          child: Row(
            children: [
              Icon(_iconBySection[section], size: 20, color: color),
              const SizedBox(width: AppTokens.s12),
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    color: color,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionDropdown extends StatelessWidget {
  const _SectionDropdown({required this.active, required this.onChanged});

  final AppSettingsSection active;
  final ValueChanged<AppSettingsSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AppSettingsSection>(
      initialValue: active,
      decoration: const InputDecoration(
        labelText: 'Sección',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final s in AppSettingsSection.values)
          DropdownMenuItem(value: s, child: Text(s.title)),
      ],
      onChanged: (s) {
        if (s != null) onChanged(s);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Banners / badges
// ─────────────────────────────────────────────────────────────────────────

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s16),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppTokens.warning),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: Text(
              'Solo lectura: tu rol no puede modificar la configuración global. '
              'Pide a un administrador que haga los cambios.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveBadge extends StatelessWidget {
  const _SaveBadge({required this.label, required this.isError});

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTokens.destructive : AppTokens.success;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s10,
        vertical: AppTokens.s6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 16,
          ),
          const SizedBox(width: AppTokens.s6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section card + reusable rows
// ─────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.children,
  });

  final AppSettingsSection section;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              section.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTokens.mutedForeground,
                  ),
            ),
            const SizedBox(height: AppTokens.s16),
            const Divider(height: 1, color: AppTokens.border),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s16, bottom: AppTokens.s4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTokens.mutedForeground,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _BoolRow extends StatelessWidget {
  const _BoolRow({
    required this.label,
    required this.value,
    required this.column,
    required this.isReadOnly,
    required this.onSave,
    this.helper,
  });

  final String label;
  final String? helper;
  final bool value;
  final String column;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                if (helper != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      helper!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTokens.mutedForeground,
                          ),
                    ),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: isReadOnly ? null : (v) => onSave(column, v),
          ),
        ],
      ),
    );
  }
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.label,
    required this.value,
    required this.column,
    required this.isReadOnly,
    required this.onSave,
    this.hint,
    this.maxLength,
    this.uppercase = false,
    this.helper,
    this.maxLines = 1,
  });

  final String label;
  final String? value;
  final String? hint;
  final String? helper;
  final int? maxLength;
  final bool uppercase;
  final int maxLines;
  final String column;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
    _focus = FocusNode();
    _focus.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _TextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = widget.value ?? '';
    }
  }

  void _handleFocus() {
    if (!_focus.hasFocus) {
      final newValue = _ctrl.text.trim();
      final original = widget.value ?? '';
      if (newValue != original) {
        widget.onSave(widget.column, newValue.isEmpty ? null : newValue);
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
          if (widget.helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.helper!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.mutedForeground,
                    ),
              ),
            ),
          const SizedBox(height: AppTokens.s6),
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            enabled: !widget.isReadOnly,
            maxLength: widget.maxLength,
            maxLines: widget.maxLines,
            keyboardType: widget.maxLines > 1
                ? TextInputType.multiline
                : null,
            inputFormatters: widget.uppercase
                ? [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    TextInputFormatter.withFunction(
                      (oldV, newV) => newV.copyWith(
                        text: newV.text.toUpperCase(),
                      ),
                    ),
                  ]
                : null,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _NumRow extends StatefulWidget {
  const _NumRow({
    required this.label,
    required this.value,
    required this.column,
    required this.isReadOnly,
    required this.onSave,
    this.min,
    this.max,
  });

  final String label;
  final num value;
  final num? min;
  final num? max;
  final String column;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  State<_NumRow> createState() => _NumRowState();
}

class _NumRowState extends State<_NumRow> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
    _focus = FocusNode();
    _focus.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _NumRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = widget.value.toString();
    }
  }

  void _handleFocus() {
    if (!_focus.hasFocus) {
      final parsed = num.tryParse(_ctrl.text.trim());
      if (parsed == null || parsed == widget.value) {
        _ctrl.text = widget.value.toString();
        return;
      }
      var clamped = parsed;
      if (widget.min != null && clamped < widget.min!) clamped = widget.min!;
      if (widget.max != null && clamped > widget.max!) clamped = widget.max!;
      _ctrl.text = clamped.toString();
      widget.onSave(widget.column, clamped);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Row(
        children: [
          Expanded(
            child:
                Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: AppTokens.s12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.isReadOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.end,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnumRow<T> extends StatelessWidget {
  const _EnumRow({
    required this.label,
    required this.value,
    required this.options,
    required this.column,
    required this.isReadOnly,
    required this.onSave,
    this.helper,
  });

  final String label;
  final String? helper;
  final T value;
  final Map<T, String> options;
  final String column;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                if (helper != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      helper!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTokens.mutedForeground,
                          ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<T>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in options.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: isReadOnly
                  ? null
                  : (v) {
                      if (v != null) onSave(column, v);
                    },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 1: Información de la Compañía
// ─────────────────────────────────────────────────────────────────────────

class _CompanyInfoSection extends StatelessWidget {
  const _CompanyInfoSection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.companyInfo,
      children: [
        _TextRow(
          label: 'Nombre de la compañía',
          value: settings.companyName,
          column: 'company_name',
          hint: 'Mi Negocio S.R.L.',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Razón social',
          value: settings.companyLegalName,
          column: 'company_legal_name',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'RNC',
          value: settings.companyTaxId,
          column: 'company_tax_id',
          maxLength: 11,
          helper: 'Formato RD: 9 u 11 dígitos.',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Sitio web',
          value: settings.companyWebsite,
          column: 'company_website',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        // ── Datos para factura / cotización (formato A4) ──
        _TextRow(
          label: 'Dirección (factura/cotización)',
          value: settings.companyAddress,
          column: 'company_address',
          hint: 'Calle / sector\nCiudad, provincia',
          helper: 'Aparece en el encabezado. Una línea por renglón.',
          maxLines: 3,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Teléfono(s)',
          value: settings.companyPhone,
          column: 'company_phone',
          hint: '829-000-0000 / 809-000-0000',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Correo (factura/cotización)',
          value: settings.companyEmail,
          column: 'company_email',
          hint: 'ventas@minegocio.com',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Datos bancarios para pago',
          value: settings.companyBankInfo,
          column: 'company_bank_info',
          hint: 'BANCO POPULAR : 000000000 CUENTA CORRIENTE\n'
              'NOMBRE TITULAR   CEDULA: 000-0000000-0',
          helper: 'Bloque de pago al pie. Una línea por renglón.',
          maxLines: 3,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Firmante (nombre)',
          value: settings.companySignatoryName,
          column: 'company_signatory_name',
          hint: 'Nombre que va sobre la línea de firma',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Firmante (cargo)',
          value: settings.companySignatoryTitle,
          column: 'company_signatory_title',
          hint: 'Ej. Gerente de Finanzas',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Observación (factura/cotización)',
          value: settings.invoiceObservation,
          column: 'invoice_observation',
          helper: 'Texto opcional impreso en el bloque de observación.',
          maxLines: 2,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar ITBIS en factura/cotización',
          value: settings.invoiceShowItbis,
          column: 'invoice_show_itbis',
          helper: 'Si se apaga, nunca se desglosa el ITBIS aunque los '
              'productos tengan tasa. Igual se oculta si ningún ítem lo lleva.',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _CompanyLogoPicker(
          value: settings.companyLogoUrl,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _CompanyLogoPicker(
          value: settings.companyQrUrl,
          column: 'company_qr_url',
          label: 'Código QR (factura/cotización)',
          noun: 'QR',
          uploadKind: 'qr',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'URL del sello',
          value: settings.companyStampUrl,
          column: 'company_stamp_url',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'URL de la firma',
          value: settings.companySignatureUrl,
          column: 'company_signature_url',
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
      ],
    );
  }
}

class _CompanyLogoPicker extends ConsumerStatefulWidget {
  const _CompanyLogoPicker({
    required this.value,
    required this.isReadOnly,
    required this.onSave,
    this.column = 'company_logo_url',
    this.label = 'Logo de la empresa',
    this.noun = 'logo',
    this.uploadKind = 'logo',
  });

  final String? value;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  /// Columna de app_settings donde se guarda el URL.
  final String column;

  /// Etiqueta arriba del control.
  final String label;

  /// Sustantivo para los botones (ej. "Cambiar logo", "No se pudo subir el QR").
  final String noun;

  /// Prefijo del archivo en Storage: `_company/[kind]-[timestamp].[ext]`.
  final String uploadKind;

  @override
  ConsumerState<_CompanyLogoPicker> createState() =>
      _CompanyLogoPickerState();
}

class _CompanyLogoPickerState extends ConsumerState<_CompanyLogoPicker> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    if (_uploading || widget.isReadOnly) return;
    final picked = await FileIoHelper.pickImage();
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final repo = ref.read(appSettingsRepositoryProvider);
      final url = await repo.uploadCompanyLogo(
        bytes: picked.bytes,
        extension: picked.extension,
        kind: widget.uploadKind,
      );
      if (!mounted) return;
      widget.onSave(widget.column, url);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo subir el ${widget.noun}', error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _clear() {
    if (widget.isReadOnly || _uploading) return;
    widget.onSave(widget.column, null);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.value?.trim() ?? '';
    final hasImage = url.isNotEmpty;
    final disabled = widget.isReadOnly || _uploading;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTokens.s6),
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTokens.muted,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTokens.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        cacheHeight: 144,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppTokens.mutedForeground,
                        ),
                      )
                    : const Icon(
                        Icons.image_outlined,
                        color: AppTokens.mutedForeground,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: disabled ? null : _pickAndUpload,
                      icon: _uploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: Text(
                        _uploading
                            ? 'Subiendo…'
                            : (hasImage
                                ? 'Cambiar ${widget.noun}'
                                : 'Seleccionar ${widget.noun}'),
                      ),
                    ),
                    if (hasImage)
                      TextButton.icon(
                        onPressed: disabled ? null : _clear,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Quitar'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 2: Inventario
// ─────────────────────────────────────────────────────────────────────────

class _InventorySection extends StatelessWidget {
  const _InventorySection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.inventory,
      children: [
        _BoolRow(
          label: 'Marcar "es servicio" por defecto en artículos nuevos',
          column: 'inv_default_is_service',
          value: settings.invDefaultIsService,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Id a mostrar en el código de barras',
          column: 'inv_barcode_id_source',
          value: settings.invBarcodeIdSource,
          options: const {
            'item_id': 'ID interno',
            'barcode': 'Código de barras',
            'sku': 'SKU',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'No permitir venta por debajo del costo',
          column: 'inv_disallow_below_cost',
          value: settings.invDisallowBelowCost,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Trabajar con IMEI / números de serie',
          column: 'inv_imei_mode',
          value: settings.invImeiMode,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Para negocios de celulares: al vender un producto con '
              'IMEI registrados, se eligen cuáles equipos salen.',
        ),
        _BoolRow(
          label: 'No permitir venta de artículos sin stock',
          column: 'inv_disallow_no_stock',
          value: settings.invDisallowNoStock,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Bloquea agregar a la venta cuando stock <= 0.',
        ),
        _BoolRow(
          label: 'Resaltar artículos en stock mínimo',
          column: 'inv_highlight_min_stock',
          value: settings.invHighlightMinStock,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Desactivar calculadora de margen de precio',
          column: 'inv_disable_margin_calculator',
          value: settings.invDisableMarginCalculator,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _PriceTypesEditor(
          values: settings.salePriceTypes,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _CategoriesEditor(isReadOnly: isReadOnly),
        _CashRegistersEditor(isReadOnly: isReadOnly),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 3: Empleado
// ─────────────────────────────────────────────────────────────────────────

class _EmployeeSection extends StatelessWidget {
  const _EmployeeSection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.employee,
      children: [
        _BoolRow(
          label: 'Seleccionar persona de ventas durante la venta',
          column: 'emp_pick_seller_during_sale',
          value: settings.empPickSellerDuringSale,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'El vendedor / mesero es requerido en la venta',
          column: 'emp_seller_required',
          value: settings.empSellerRequired,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Restaurante: obliga asignar mesero al abrir la mesa.',
        ),
        _EnumRow<String>(
          label: 'Vendedor por defecto',
          column: 'emp_default_seller',
          value: settings.empDefaultSeller,
          options: const {
            'logged_in_user': 'Usuario que inició sesión',
            'last_used': 'Último usado',
            'manual': 'Selección manual',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Tasa de comisión (%)',
          column: 'emp_commission_rate',
          value: settings.empCommissionRate,
          min: 0,
          max: 100,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Método de cálculo de comisión',
          column: 'emp_commission_method',
          value: settings.empCommissionMethod,
          options: const {
            'sale_price': 'Sobre precio de venta',
            'profit_margin': 'Sobre margen de ganancia',
            'total_sales': 'Sobre total de ventas',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Exigir login antes de cada venta',
          column: 'emp_require_login_each_sale',
          value: settings.empRequireLoginEachSale,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mantener mismo lugar tras cambiar de empleado',
          column: 'emp_keep_position_after_switch',
          value: settings.empKeepPositionAfterSwitch,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Activar registro de tiempo (entrada/salida)',
          column: 'emp_time_clock_enabled',
          value: settings.empTimeClockEnabled,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 4: Impuestos y Moneda
// ─────────────────────────────────────────────────────────────────────────

class _TaxCurrencySection extends StatelessWidget {
  const _TaxCurrencySection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.taxCurrency,
      children: [
        const _SubHeader('Impuestos'),
        _BoolRow(
          label: 'Marcar "precio incluye impuestos" por defecto en artículos nuevos',
          column: 'tax_default_price_includes_tax',
          value: settings.taxDefaultPriceIncludesTax,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Cargar impuesto sobre recepciones',
          column: 'tax_charge_on_receivings',
          value: settings.taxChargeOnReceivings,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Incluir impuestos en códigos de barras',
          column: 'tax_include_in_barcodes',
          value: settings.taxIncludeInBarcodes,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Moneda'),
        _TextRow(
          label: 'Símbolo de moneda',
          column: 'currency_symbol',
          value: settings.currencySymbol,
          maxLength: 5,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Número de decimales',
          column: 'currency_decimals',
          value: settings.currencyDecimals,
          min: 0,
          max: 4,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Separador de miles',
          column: 'currency_thousands_sep',
          value: settings.currencyThousandsSep,
          maxLength: 1,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Punto decimal',
          column: 'currency_decimal_point',
          value: settings.currencyDecimalPoint,
          maxLength: 1,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s8),
        Text(
          'Denominaciones para arqueo: ${settings.currencyDenominations.length} configuradas. '
          'El editor visual llega en sub-fase 6.G.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTokens.mutedForeground,
              ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 5: Ventas y Recibo (la más densa)
// ─────────────────────────────────────────────────────────────────────────

class _SalesReceiptSection extends StatelessWidget {
  const _SalesReceiptSection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.salesReceipt,
      children: [
        const _SubHeader('Recibo · presentación'),
        _EnumRow<String>(
          label: 'Tamaño del texto del recibo',
          column: 'receipt_text_size',
          value: settings.receiptTextSize,
          options: const {
            'small': 'Pequeño',
            'normal': 'Normal',
            'large': 'Grande',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Ocultar firma en el recibo',
          column: 'receipt_hide_signature',
          value: settings.receiptHideSignature,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar id del artículo en el recibo',
          column: 'receipt_show_item_id',
          value: settings.receiptShowItemId,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Ocultar código de barras en recibos',
          column: 'receipt_hide_barcode',
          value: settings.receiptHideBarcode,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Ocultar saldo de crédito del cliente en recibo',
          column: 'receipt_hide_credit_balance',
          value: settings.receiptHideCreditBalance,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Recibo · comportamiento'),
        _BoolRow(
          label: 'Imprimir recibo después de venta',
          column: 'receipt_print_after_sale',
          value: settings.receiptPrintAfterSale,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Imprimir recibo después de compra/recepción',
          column: 'receipt_print_after_purchase',
          value: settings.receiptPrintAfterPurchase,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Imprimir duplicado automático para tarjeta de crédito',
          column: 'receipt_auto_duplicate_on_credit_card',
          value: settings.receiptAutoDuplicateOnCreditCard,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar recibo después de suspender venta',
          column: 'receipt_show_after_suspend',
          value: settings.receiptShowAfterSuspend,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Envío automático por correo al cliente',
          column: 'receipt_email_customer_auto',
          value: settings.receiptEmailCustomerAuto,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Interfaz de venta'),
        _EnumRow<String>(
          label: 'Columna a mostrar en interfaz de ventas',
          column: 'sale_ui_column',
          value: settings.saleUiColumn,
          options: const {
            'barcode': 'Código de barras',
            'sku': 'SKU',
            'category': 'Categoría',
            'none': 'Ninguna',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Posicionar cursor en el campo del artículo',
          column: 'sale_focus_item_field',
          value: settings.saleFocusItemField,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Ventas recientes por cliente a mostrar',
          column: 'sale_recent_per_customer',
          value: settings.saleRecentPerCustomer,
          min: 0,
          max: 100,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Desactivar confirmación de venta completada',
          column: 'sale_disable_complete_confirmation',
          value: settings.saleDisableCompleteConfirmation,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Desactivar la venta rápida',
          column: 'sale_disable_quick_sale',
          value: settings.saleDisableQuickSale,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Oculta el botón de Venta Rápida en el panel.',
        ),
        _BoolRow(
          label: 'No agrupar elementos iguales',
          column: 'sale_no_group_identical_items',
          value: settings.saleNoGroupIdenticalItems,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Editar precio si es 0 al añadir',
          column: 'sale_edit_zero_price_on_add',
          value: settings.saleEditZeroPriceOnAdd,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Costos'),
        _BoolRow(
          label: 'Calcular costo promedio en compras',
          column: 'sale_calc_avg_purchase_cost',
          value: settings.saleCalcAvgPurchaseCost,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Método de promedio',
          column: 'sale_avg_method',
          value: settings.saleAvgMethod,
          options: const {
            'current_received_price': 'Precio actual recibido',
            'weighted_avg': 'Promedio ponderado',
            'last_purchase': 'Última compra',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Cliente y crédito'),
        _BoolRow(
          label: 'Requerir cliente para venta',
          column: 'customer_required_for_sale',
          value: settings.customerRequiredForSale,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Permitir ventas a crédito',
          column: 'credit_allow_sales',
          value: settings.creditAllowSales,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Permitir compras a crédito',
          column: 'credit_allow_purchases',
          value: settings.creditAllowPurchases,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'No vender a cliente cuando',
          column: 'credit_block_when',
          value: settings.creditBlockWhen,
          options: const {
            'exceeds_balance_limit': 'Excede límite de balance',
            'has_overdue_invoices': 'Tiene facturas vencidas',
            'never': 'Nunca bloquear',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Preguntar por CCV al pasar tarjeta de crédito',
          column: 'credit_ask_ccv_on_card',
          value: settings.creditAskCcvOnCard,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Días de crédito por defecto',
          column: 'credit_default_days',
          value: settings.creditDefaultDays,
          min: 1,
          max: 365,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Avisar cuando faltan X días para vencer',
          column: 'credit_warn_days',
          value: settings.creditWarnDays,
          min: 0,
          max: 90,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Prefijos de documentos'),
        _TextRow(
          label: 'Prefijo de venta',
          column: 'prefix_sale',
          value: settings.prefixSale,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de nota de crédito',
          column: 'prefix_credit_note',
          value: settings.prefixCreditNote,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de nota de débito',
          column: 'prefix_debit_note',
          value: settings.prefixDebitNote,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de conduce',
          column: 'prefix_delivery',
          value: settings.prefixDelivery,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de cotización',
          column: 'prefix_quote',
          value: settings.prefixQuote,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de abono a línea de crédito',
          column: 'prefix_credit_payment',
          value: settings.prefixCreditPayment,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de pago a plazo',
          column: 'prefix_installment_payment',
          value: settings.prefixInstallmentPayment,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de compra',
          column: 'prefix_purchase',
          value: settings.prefixPurchase,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de orden de compra',
          column: 'prefix_purchase_order',
          value: settings.prefixPurchaseOrder,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Prefijo de recibo',
          column: 'prefix_receipt',
          value: settings.prefixReceipt,
          maxLength: 10,
          uppercase: true,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const _SubHeader('Métodos de pago'),
        _EnumRow<String>(
          label: 'Método de pago por defecto',
          column: 'payment_method_default',
          value: settings.paymentMethodDefault,
          options: const {
            'cash': 'Efectivo',
            'card': 'Tarjeta',
            'transfer': 'Transferencia',
            'mobile': 'Pago móvil',
            'credit': 'Crédito',
            'mixed': 'Mixto',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar canales de pago en la venta',
          column: 'payment_show_channels_in_sale',
          value: settings.paymentShowChannelsInSale,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        const SizedBox(height: AppTokens.s8),
        Text(
          'Métodos de pago habilitados: ${settings.paymentMethodsEnabled.join(", ")}. '
          'Editor multi-select disponible en sub-fase 6.I.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTokens.mutedForeground,
              ),
        ),
        const _SubHeader('Formato y políticas'),
        _EnumRow<String>(
          label: 'Formato de factura por defecto',
          column: 'invoice_default_format',
          value: settings.invoiceDefaultFormat,
          options: const {
            'pos_invoice': 'Factura POS (térmica)',
            'letter_invoice': 'Factura tamaño carta',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Formato de factura (B2X)',
          column: 'invoice_b2x_format',
          value: settings.invoiceB2xFormat,
          options: const {
            'b2c': 'B2C - Consumidor',
            'b2b': 'B2B - Empresa',
            'b2g': 'B2G - Gobierno',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Política de devoluciones',
          column: 'return_policy',
          value: settings.returnPolicy,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _TextRow(
          label: 'Anuncios / especiales',
          column: 'announcements',
          value: settings.announcements,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 6: Cuentas abiertas / Suspendidas
// ─────────────────────────────────────────────────────────────────────────

class _SuspendedSalesSection extends StatelessWidget {
  const _SuspendedSalesSection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.suspendedSales,
      children: [
        _BoolRow(
          label: 'Ocultar cuentas por pagar en informes de tienda',
          column: 'suspended_hide_payables_in_reports',
          value: settings.suspendedHidePayablesInReports,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Ocultar pagos de cuenta en totales del informe',
          column: 'suspended_hide_account_payments_in_totals',
          value: settings.suspendedHideAccountPaymentsInTotals,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Cambiar fecha de venta al suspender',
          column: 'suspended_change_date_on_suspend',
          value: settings.suspendedChangeDateOnSuspend,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Cambiar fecha de venta al completar suspendida',
          column: 'suspended_change_date_on_complete',
          value: settings.suspendedChangeDateOnComplete,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar recibo después de suspensión',
          column: 'suspended_show_receipt_after',
          value: settings.suspendedShowReceiptAfter,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sección 7: Aplicación
// ─────────────────────────────────────────────────────────────────────────

class _ApplicationSection extends StatelessWidget {
  const _ApplicationSection({
    super.key,
    required this.settings,
    required this.isReadOnly,
    required this.onSave,
  });

  final AppSettings settings;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      section: AppSettingsSection.application,
      children: [
        _BoolRow(
          label: 'Activar verificación en dos pasos',
          column: 'app_2fa_enabled',
          value: settings.app2faEnabled,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Próximamente — flag guardado, implementación PRD futuro.',
        ),
        _BoolRow(
          label: 'Modo de prueba (ventas no guardan)',
          column: 'app_test_mode',
          value: settings.appTestMode,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Próximamente — flag guardado, implementación PRD futuro.',
        ),
        _BoolRow(
          label: 'Activar cambio rápido de usuario',
          column: 'app_quick_user_switch',
          value: settings.appQuickUserSwitch,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Habilitar conduces',
          column: 'app_enable_delivery_notes',
          value: settings.appEnableDeliveryNotes,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Idioma',
          column: 'app_language',
          value: settings.appLanguage,
          options: const {'es': 'Español', 'en': 'English'},
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Formato de fecha',
          column: 'app_date_format',
          value: settings.appDateFormat,
          options: const {
            'dd-MM-yyyy': 'DD-MM-AAAA (RD)',
            'MM-dd-yyyy': 'MM-DD-AAAA (US)',
            'yyyy-MM-dd': 'AAAA-MM-DD (ISO)',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Formato de hora',
          column: 'app_time_format',
          value: settings.appTimeFormat,
          options: const {'12h': '12 horas', '24h': '24 horas'},
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Ocultar precio en códigos de barras',
          column: 'app_hide_price_in_barcodes',
          value: settings.appHidePriceInBarcodes,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Activar sistema de fidelización',
          column: 'app_loyalty_enabled',
          value: settings.appLoyaltyEnabled,
          isReadOnly: isReadOnly,
          onSave: onSave,
          helper: 'Próximamente — flag guardado, implementación PRD futuro.',
        ),
        _BoolRow(
          label: 'Sonidos para mensajes de estado',
          column: 'app_status_sounds',
          value: settings.appStatusSounds,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Filas por página en búsqueda',
          column: 'app_search_rows_per_page',
          value: settings.appSearchRowsPerPage,
          min: 5,
          max: 100,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _NumRow(
          label: 'Elementos por página en cuadrícula',
          column: 'app_grid_items_per_page',
          value: settings.appGridItemsPerPage,
          min: 5,
          max: 100,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Orden de vista en búsqueda',
          column: 'app_search_sort_order',
          value: settings.appSearchSortOrder,
          options: const {
            'newest_first': 'Más nuevos primero',
            'oldest_first': 'Más viejos primero',
            'alphabetical': 'Alfabético',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Ocultar estadísticas del panel',
          column: 'app_hide_panel_stats',
          value: settings.appHidePanelStats,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar selector de idioma',
          column: 'app_show_language_switcher',
          value: settings.appShowLanguageSwitcher,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Mostrar reloj en cabecera',
          column: 'app_show_header_clock',
          value: settings.appShowHeaderClock,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _BoolRow(
          label: 'Acelerar consultas de búsqueda',
          column: 'app_fast_search_queries',
          value: settings.appFastSearchQueries,
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Formato de hoja de cálculo',
          column: 'app_spreadsheet_format',
          value: settings.appSpreadsheetFormat,
          options: const {'xlsx': 'XLSX (Excel)', 'csv': 'CSV'},
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
        _EnumRow<String>(
          label: 'Comportamiento al cerrar sesión',
          column: 'app_logout_behavior',
          value: settings.appLogoutBehavior,
          options: const {
            'redirect_login': 'Redirigir al login',
            'close_browser': 'Cerrar navegador',
            'lock_screen': 'Bloquear pantalla',
          },
          isReadOnly: isReadOnly,
          onSave: onSave,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Editor de tipos de precios (sale_price_types jsonb)
// ─────────────────────────────────────────────────────────────────────────

class _PriceTypesEditor extends StatefulWidget {
  const _PriceTypesEditor({
    required this.values,
    required this.isReadOnly,
    required this.onSave,
  });

  final List<dynamic> values;
  final bool isReadOnly;
  final void Function(String column, dynamic value) onSave;

  @override
  State<_PriceTypesEditor> createState() => _PriceTypesEditorState();
}

class _PriceTypesEditorState extends State<_PriceTypesEditor> {
  static const _column = 'sale_price_types';
  static const _maxItems = 10;
  late List<_PriceTypeItem> _items;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _items = _fromRemote(widget.values);
  }

  @override
  void didUpdateWidget(covariant _PriceTypesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final remote = widget.values.map((v) => v.toString()).toList();
    final local = _items.map((i) => i.value).toList();
    if (!_listEquals(remote, local)) {
      setState(() => _items = _fromRemote(widget.values));
    }
  }

  List<_PriceTypeItem> _fromRemote(List<dynamic> raw) {
    return [
      for (final v in raw) _PriceTypeItem(id: _nextId++, value: v.toString()),
    ];
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _persist() {
    final out = _items
        .map((i) => i.value.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    widget.onSave(_column, out);
  }

  void _onRowSubmit(int id, String newValue) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    if (_items[idx].value == newValue) return;
    setState(() => _items[idx] = _items[idx].copyWith(value: newValue));
    _persist();
  }

  void _onAdd() {
    if (_items.length >= _maxItems) return;
    setState(() => _items.add(_PriceTypeItem(id: _nextId++, value: '')));
  }

  void _onDelete(int id) {
    setState(() => _items.removeWhere((i) => i.id == id));
    _persist();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tipos de precios',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Hasta $_maxItems listas de precios (p. ej. mayorista, VIP, '
            'distribuidor) que podrás asignar a los clientes. Cada tipo '
            'se mapea a uno de los niveles de precio del producto.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
          const SizedBox(height: AppTokens.s8),
          const _PriceTypesHeader(),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
              child: Text(
                'No hay tipos configurados.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTokens.mutedForeground,
                    ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _items.length,
              onReorder: widget.isReadOnly ? (_, _) {} : _onReorder,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _PriceTypeRow(
                  key: ValueKey('price_type_${item.id}'),
                  index: index,
                  item: item,
                  isReadOnly: widget.isReadOnly,
                  onSubmit: (v) => _onRowSubmit(item.id, v),
                  onDelete: () => _onDelete(item.id),
                );
              },
            ),
          const SizedBox(height: AppTokens.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: (widget.isReadOnly || _items.length >= _maxItems)
                  ? null
                  : _onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                _items.length >= _maxItems
                    ? 'Máximo $_maxItems tipos'
                    : 'Añadir tipo',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceTypesHeader extends StatelessWidget {
  const _PriceTypesHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTokens.mutedForeground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s4,
      ),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('ESPECIE', style: style)),
          const SizedBox(width: AppTokens.s12),
          Expanded(child: Text('TIPO DE PRECIO', style: style)),
          const SizedBox(width: AppTokens.s12),
          SizedBox(
            width: 72,
            child: Text('BORRAR', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _PriceTypeItem {
  const _PriceTypeItem({required this.id, required this.value});
  final int id;
  final String value;
  _PriceTypeItem copyWith({String? value}) =>
      _PriceTypeItem(id: id, value: value ?? this.value);
}

// ─────────────────────────────────────────────────────────────────────────
// Editor de categorías de productos (tabla product_categories)
// ─────────────────────────────────────────────────────────────────────────

class _CategoriesEditor extends ConsumerStatefulWidget {
  const _CategoriesEditor({required this.isReadOnly});

  final bool isReadOnly;

  @override
  ConsumerState<_CategoriesEditor> createState() => _CategoriesEditorState();
}

class _CategoriesEditorState extends ConsumerState<_CategoriesEditor> {
  bool _adding = false;
  final _newNameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _adding = false);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).createCategory(name);
      _newNameCtrl.clear();
      if (mounted) setState(() => _adding = false);
      ref.invalidate(inventoryCategoriesProvider);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo crear', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRename(InventoryCategory cat, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == cat.name) return;
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .updateCategoryName(categoryId: cat.id, newName: trimmed);
      ref.invalidate(inventoryCategoriesProvider);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo renombrar', error);
    }
  }

  Future<void> _onDelete(InventoryCategory cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          '¿Eliminar "${cat.name}"?\n\n'
          'Si tiene productos asignados se desactivará en su lugar '
          '(deja de aparecer en filtros pero los productos no se rompen).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = ref.read(inventoryRepositoryProvider);
    try {
      await repo.deleteCategory(cat.id);
      ref.invalidate(inventoryCategoriesProvider);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        try {
          await repo.setCategoryActive(categoryId: cat.id, isActive: false);
          ref.invalidate(inventoryCategoriesProvider);
          if (!mounted) return;
          AppSnackBar.info(
            context,
            'La categoría tenía productos. Se desactivó en su lugar.',
          );
        } catch (innerError) {
          if (!mounted) return;
          AppSnackBar.error(context, 'No se pudo desactivar', innerError);
        }
      } else {
        if (!mounted) return;
        AppSnackBar.error(context, 'No se pudo eliminar', e);
      }
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo eliminar', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(inventoryCategoriesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Categorías de productos',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Crea las categorías que usarás para clasificar tus productos. '
            'Si una tiene productos vinculados, eliminarla la desactiva en '
            'lugar de borrarla.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
          const SizedBox(height: AppTokens.s8),
          categoriesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.s8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
              child: Text('No se pudieron cargar categorías: $e'),
            ),
            data: (categories) {
              if (categories.isEmpty && !_adding) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppTokens.s8),
                  child: Text(
                    'No hay categorías. Añadí la primera con el botón de abajo.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.mutedForeground,
                        ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final cat in categories)
                    _CategoryRow(
                      key: ValueKey('cat_${cat.id}'),
                      category: cat,
                      isReadOnly: widget.isReadOnly,
                      onRename: (v) => _onRename(cat, v),
                      onDelete: () => _onDelete(cat),
                    ),
                  if (_adding)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppTokens.s4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newNameCtrl,
                              autofocus: true,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                hintText: 'Ej: bebidas, repuestos…',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _onCreate(),
                            ),
                          ),
                          const SizedBox(width: AppTokens.s8),
                          FilledButton(
                            onPressed: _busy ? null : _onCreate,
                            child: const Text('Añadir'),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _newNameCtrl.clear();
                                    setState(() => _adding = false);
                                  },
                            child: const Text('Cancelar'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTokens.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: (widget.isReadOnly || _adding)
                  ? null
                  : () => setState(() => _adding = true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crear categoría'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.isReadOnly,
    required this.onRename,
    required this.onDelete,
  });

  final InventoryCategory category;
  final bool isReadOnly;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.category.name);
    _focus = FocusNode();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _CategoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.name != widget.category.name &&
        !_focus.hasFocus) {
      _ctrl.text = widget.category.name;
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      widget.onRename(_ctrl.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.isReadOnly,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: widget.onRename,
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: widget.isReadOnly ? null : widget.onDelete,
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppTokens.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Editor de cajas registradoras (tabla cash_registers + cash_register_users)
// ─────────────────────────────────────────────────────────────────────────

class _CashRegistersEditor extends ConsumerStatefulWidget {
  const _CashRegistersEditor({required this.isReadOnly});

  final bool isReadOnly;

  @override
  ConsumerState<_CashRegistersEditor> createState() =>
      _CashRegistersEditorState();
}

class _CashRegistersEditorState extends ConsumerState<_CashRegistersEditor> {
  bool _adding = false;
  final _newNameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _adding = false);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cashRegisterRepositoryProvider).createCashRegister(name);
      _newNameCtrl.clear();
      if (mounted) setState(() => _adding = false);
      ref.invalidate(cashRegistersProvider);
      ref.invalidate(myCashRegistersProvider);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo crear la caja', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRename(CashRegisterEntity caja, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == caja.name) return;
    try {
      await ref.read(cashRegisterRepositoryProvider).renameCashRegister(
            cashRegisterId: caja.id,
            newName: trimmed,
          );
      ref.invalidate(cashRegistersProvider);
      ref.invalidate(myCashRegistersProvider);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo renombrar', error);
    }
  }

  Future<void> _onDelete(CashRegisterEntity caja) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar caja'),
        content: Text(
          '¿Eliminar "${caja.name}"?\n\n'
          'Las sesiones históricas vinculadas se conservan. La caja deja '
          'de aparecer en el picker de apertura.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(cashRegisterRepositoryProvider)
          .deactivateCashRegister(caja.id);
      ref.invalidate(cashRegistersProvider);
      ref.invalidate(myCashRegistersProvider);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo eliminar', error);
    }
  }

  Future<void> _onAssignUsers(CashRegisterEntity caja) async {
    final usersAsync = ref.read(usersListProvider);
    final users = usersAsync.valueOrNull ?? const <UserEntity>[];

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CashRegisterUsersDialog(
        cajaName: caja.name,
        allUsers: users,
        initiallySelected: caja.assignedUserIds,
      ),
    );
    if (selected == null) return;

    try {
      await ref.read(cashRegisterRepositoryProvider).setCashRegisterUsers(
            cashRegisterId: caja.id,
            userIds: selected,
          );
      ref.invalidate(cashRegistersProvider);
      ref.invalidate(myCashRegistersProvider);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo guardar la asignación', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cajasAsync = ref.watch(cashRegistersProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cajas registradoras',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Crea las cajas físicas/lógicas de la sucursal y asigna qué '
            'usuarios pueden operar cada una. Al abrir una sesión, el '
            'cajero solo verá las cajas que tenga asignadas.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTokens.mutedForeground,
                ),
          ),
          const SizedBox(height: AppTokens.s8),
          cajasAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.s8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
              child: Text('No se pudieron cargar cajas: $e'),
            ),
            data: (cajas) {
              if (cajas.isEmpty && !_adding) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppTokens.s8),
                  child: Text(
                    'No hay cajas. Añadí la primera con el botón de abajo.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.mutedForeground,
                        ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final caja in cajas)
                    _CashRegisterRow(
                      key: ValueKey('caja_${caja.id}'),
                      caja: caja,
                      isReadOnly: widget.isReadOnly,
                      onRename: (v) => _onRename(caja, v),
                      onDelete: () => _onDelete(caja),
                      onAssign: () => _onAssignUsers(caja),
                    ),
                  if (_adding)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppTokens.s4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newNameCtrl,
                              autofocus: true,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                hintText: 'Ej: Caja Principal, Mostrador 2…',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _onCreate(),
                            ),
                          ),
                          const SizedBox(width: AppTokens.s8),
                          FilledButton(
                            onPressed: _busy ? null : _onCreate,
                            child: const Text('Añadir'),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _newNameCtrl.clear();
                                    setState(() => _adding = false);
                                  },
                            child: const Text('Cancelar'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTokens.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: (widget.isReadOnly || _adding)
                  ? null
                  : () => setState(() => _adding = true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crear caja'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashRegisterRow extends StatefulWidget {
  const _CashRegisterRow({
    super.key,
    required this.caja,
    required this.isReadOnly,
    required this.onRename,
    required this.onDelete,
    required this.onAssign,
  });

  final CashRegisterEntity caja;
  final bool isReadOnly;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;
  final VoidCallback onAssign;

  @override
  State<_CashRegisterRow> createState() => _CashRegisterRowState();
}

class _CashRegisterRowState extends State<_CashRegisterRow> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.caja.name);
    _focus = FocusNode();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _CashRegisterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caja.name != widget.caja.name && !_focus.hasFocus) {
      _ctrl.text = widget.caja.name;
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      widget.onRename(_ctrl.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersCount = widget.caja.assignedUserIds.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.isReadOnly,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: widget.onRename,
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton.icon(
            onPressed: widget.isReadOnly ? null : widget.onAssign,
            icon: const Icon(Icons.people_outline, size: 16),
            label: Text(
              usersCount == 0
                  ? 'Sin usuarios'
                  : usersCount == 1
                      ? '1 usuario'
                      : '$usersCount usuarios',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Eliminar caja',
            onPressed: widget.isReadOnly ? null : widget.onDelete,
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppTokens.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashRegisterUsersDialog extends StatefulWidget {
  const _CashRegisterUsersDialog({
    required this.cajaName,
    required this.allUsers,
    required this.initiallySelected,
  });

  final String cajaName;
  final List<UserEntity> allUsers;
  final List<String> initiallySelected;

  @override
  State<_CashRegisterUsersDialog> createState() =>
      _CashRegisterUsersDialogState();
}

class _CashRegisterUsersDialogState extends State<_CashRegisterUsersDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final activeUsers = widget.allUsers.where((u) => u.isActive).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return AlertDialog(
      title: Text('Usuarios de "${widget.cajaName}"'),
      content: SizedBox(
        width: 380,
        height: 420,
        child: activeUsers.isEmpty
            ? const Center(
                child: Text(
                  'No hay usuarios activos en esta sucursal.\n'
                  'Ve a Usuarios para invitar gente primero.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                itemCount: activeUsers.length,
                itemBuilder: (_, index) {
                  final user = activeUsers[index];
                  final isOn = _selected.contains(user.id);
                  return CheckboxListTile(
                    value: isOn,
                    title: Text(user.fullName),
                    subtitle: Text(
                      user.email ?? user.role,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(user.id);
                        } else {
                          _selected.remove(user.id);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PriceTypeRow extends StatefulWidget {
  const _PriceTypeRow({
    super.key,
    required this.index,
    required this.item,
    required this.isReadOnly,
    required this.onSubmit,
    required this.onDelete,
  });

  final int index;
  final _PriceTypeItem item;
  final bool isReadOnly;
  final ValueChanged<String> onSubmit;
  final VoidCallback onDelete;

  @override
  State<_PriceTypeRow> createState() => _PriceTypeRowState();
}

class _PriceTypeRowState extends State<_PriceTypeRow> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.item.value);
    _focus = FocusNode()..addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _PriceTypeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.value != widget.item.value && !_focus.hasFocus) {
      _ctrl.text = widget.item.value;
    }
  }

  void _handleFocus() {
    if (!_focus.hasFocus) {
      final v = _ctrl.text.trim();
      if (v != widget.item.value) widget.onSubmit(v);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: ReorderableDragStartListener(
              index: widget.index,
              enabled: !widget.isReadOnly,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(
                  Icons.unfold_more,
                  size: 20,
                  color: AppTokens.mutedForeground,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.isReadOnly,
              onSubmitted: (v) => widget.onSubmit(v.trim()),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'p. ej. mayorista',
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          SizedBox(
            width: 72,
            child: TextButton(
              onPressed: widget.isReadOnly ? null : widget.onDelete,
              style: TextButton.styleFrom(
                foregroundColor: AppTokens.destructive,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Borrar'),
            ),
          ),
        ],
      ),
    );
  }
}
