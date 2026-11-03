import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/module_page.dart';
import '../../inventory/data/file_io_helper.dart';
import '../../shell/presentation/shell_providers.dart';
import '../data/ecf_onboarding_models.dart';
import '../data/ecf_onboarding_repository.dart';
import '../data/ecf_print_pdf.dart';
import '../data/ecf_request_repository.dart';
import 'ecf_onboarding_dialogs.dart';
import 'ecf_request_dialog.dart';
import 'ecf_sequence_dialog.dart';
import 'settings_providers.dart';

/// Ruta de la página (dentro del ShellRoute de Configuración).
const ecfOnboardingRoute = '/configuracion/facturacion-electronica';

/// Configuración → Facturación electrónica: el trámite e-CF paso a paso.
///
/// Portado del panel de MangoPOS (`ecf_onboarding_section.dart`), donde lo
/// hace un operador. Aquí lo hace el administrador de la empresa, sobre su
/// propia empresa:
///   1. Datos del contribuyente, certificado de firma y Oficina Virtual.
///   2. Empresa con el proveedor (la registra la solicitud).
///   3. Certificación ante la DGII: postulación, set de pruebas, aprobaciones
///      comerciales, simulación, declaración jurada y roles. Los XML y Excel
///      los da la DGII en su portal; aquí se firman y se mandan.
///   4. Secuencias e-NCF.
///   5. Encender la facturación electrónica.
///
/// Cada paso lo valida el servidor (`ecf-onboarding`); aquí solo se presenta.
/// Bajar y subir archivos en el portal de la DGII sigue siendo manual.
class EcfOnboardingPage extends ConsumerWidget {
  const EcfOnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El servidor exige `profiles.role = admin`, el mismo rol que este.
    final userAsync = ref.watch(shellUserInfoProvider);

    return ModulePage(
      title: 'Facturación electrónica',
      description:
          'Tu trámite e-CF paso a paso: datos, certificación ante la DGII, '
          'secuencias e-NCF y encendido.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/configuracion/cuenta'),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Mi cuenta / NCF'),
        ),
      ],
      child: userAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTokens.s24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => EcfNote(
          color: AppTokens.destructive,
          text: 'No se pudo leer tu usuario: $e',
        ),
        data: (user) => user.roleCode == 'admin'
            ? const EcfOnboardingSection()
            : const EcfNote(
                color: AppTokens.mutedForeground,
                text:
                    'Solo un administrador de la empresa puede gestionar la '
                    'facturación electrónica.',
              ),
      ),
    );
  }
}

class EcfOnboardingSection extends ConsumerStatefulWidget {
  const EcfOnboardingSection({super.key});

  @override
  ConsumerState<EcfOnboardingSection> createState() =>
      _EcfOnboardingSectionState();
}

class _EcfOnboardingSectionState extends ConsumerState<EcfOnboardingSection> {
  /// Qué está corriendo, para deshabilitar botones y decirlo.
  String? _busy;

  /// Datos de la postulación: no cambian en la sesión, se piden una vez.
  EcfPostulationInfo? _postulationInfo;

  bool _revealingOfv = false;

  EcfOnboardingRepository get _repo =>
      ref.read(ecfOnboardingRepositoryProvider);

  /// Relee el trámite y, de paso, la tarjeta de Configuración y la modalidad
  /// (lo que se hace aquí cambia lo que muestran).
  void _refresh() {
    ref.invalidate(ecfOnboardingStatusProvider);
    ref.invalidate(ecfRequestStatusProvider);
    ref.invalidate(companyEcfSettingsProvider);
  }

  /// Corre [action] con el indicador de ocupado. Devuelve false si falló (el
  /// error ya se mostró).
  Future<bool> _run(
    String label,
    Future<void> Function() action, {
    String? success,
    bool refresh = true,
  }) async {
    setState(() => _busy = label);
    try {
      await action();
      if (refresh) _refresh();
      if (success != null && mounted) AppSnackBar.success(context, success);
      return true;
    } catch (e) {
      if (mounted) await _showError(e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _showError(Object e) {
    final message = e is EcfRequestException ? e.message : '$e';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se pudo completar'),
        content: SizedBox(
          width: 460,
          child: SelectableText(
            message,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    Color? color,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: color == null
                ? null
                : FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  /// Abre el formulario de solicitud (el mismo de la tarjeta). Sirve para
  /// pedirla por primera vez o reenviarla con otro certificado.
  Future<void> _openRequest() async {
    EcfRequestStatus? status;
    final ok = await _run(
      'Cargando la solicitud…',
      () async => status = await ref.read(ecfRequestStatusProvider.future),
      refresh: false,
    );
    if (!ok || status == null || !mounted) return;
    final sent = await EcfRequestDialog.show(context, status!);
    if (sent == true && mounted) _refresh();
  }

  Future<void> _showOfvPassword() async {
    if (_revealingOfv) return;
    setState(() => _revealingOfv = true);
    try {
      final credentials = await _repo.revealOfvPassword();
      if (!mounted) return;
      setState(() => _revealingOfv = false);
      await showDialog<void>(
        context: context,
        builder: (_) => EcfOfvCredentialsDialog(credentials: credentials),
      );
    } catch (e) {
      if (mounted) await _showError(e);
    } finally {
      if (mounted) setState(() => _revealingOfv = false);
    }
  }

  Future<void> _editOfv(EcfOnboardingStatus s) async {
    final result = await showDialog<({String user, String password})>(
      context: context,
      builder: (_) =>
          EcfOfvEditDialog(initialUser: s.draft?.ofvUser ?? s.draft?.rnc),
    );
    if (result == null) return;
    await _run(
      'Guardando el acceso a la Oficina Virtual…',
      () => _repo.saveOfvCredentials(
        ofvUser: result.user,
        ofvPassword: result.password,
      ),
      success: 'Acceso a la Oficina Virtual guardado.',
    );
  }

  Future<void> _editData(EcfOnboardingStatus s) async {
    final result = await showDialog<EcfTaxpayerDraft>(
      context: context,
      builder: (_) => EcfTaxpayerDialog(
        initial: s.draft ?? const EcfTaxpayerDraft(),
        rncLocked: s.hasCompany,
      ),
    );
    if (result == null) return;
    await _run(
      'Guardando datos…',
      () => _repo.saveData(result),
      success: 'Datos guardados.',
    );
  }

  Future<void> _saveCertificate() async {
    final input = await showDialog<EcfCertificateInput>(
      context: context,
      builder: (_) => const EcfSigningCertificateDialog(
        title: 'Guardar certificado digital',
        intro:
            'Carga el certificado de firma de tu empresa (.p12) para firmar '
            'las pruebas de facturación electrónica ante la DGII. Se guarda '
            'cifrado en el servidor y nunca vuelve al navegador.',
        confirmLabel: 'Guardar certificado',
        consentLabel:
            'Autorizo guardar mi certificado cifrado para firmar las pruebas '
            'de la DGII.',
      ),
    );
    if (input == null || input.usesStoredCertificate || !mounted) return;
    await _run(
      'Guardando certificado…',
      () => _repo.saveCertificate(
        filename: input.filename!,
        bytes: input.bytes!,
        password: input.password!,
      ),
      success: 'Certificado guardado.',
    );
  }

  Future<void> _addSequence(EcfOnboardingStatus s) async {
    final saved = await EcfSequenceDialog.show(context, s.branches);
    if (saved == true && mounted) _refresh();
  }

  Future<void> _toggleEcf(bool enable) async {
    final confirmed = await _confirm(
      title: enable
          ? 'Encender facturación electrónica'
          : 'Apagar facturación electrónica',
      body: enable
          ? 'Desde la próxima venta, tus comprobantes salen como electrónicos '
                '(serie E) y se mandan a la DGII.\n\n'
                'Haz enseguida una venta de prueba pequeña en E32 y confirma '
                'que la DGII la acepta. Cada rechazo gasta un número de la '
                'secuencia.'
          : 'Vuelves a comprobantes en papel (serie B). Las facturas '
                'electrónicas ya emitidas no se tocan.',
      confirmLabel: enable ? 'Encender' : 'Apagar',
      color: enable ? AppTokens.primary : AppTokens.destructive,
    );
    if (!confirmed) return;
    await _run(
      enable ? 'Encendiendo…' : 'Apagando…',
      () => ref.read(ecfRequestRepositoryProvider).setEnabled(enable),
      success: enable
          ? 'Facturación electrónica encendida.'
          : 'Facturación electrónica apagada. Vuelves a comprobantes en papel.',
    );
  }

  Future<EcfPostulationInfo?> _loadPostulationInfo() async {
    if (_postulationInfo != null) return _postulationInfo;
    EcfPostulationInfo? info;
    await _run(
      'Consultando al proveedor…',
      () async => info = await _repo.postulationInfo(),
      refresh: false,
    );
    if (info != null && mounted) setState(() => _postulationInfo = info);
    return info;
  }

  Future<void> _showPostulationInfo() async {
    final info = await _loadPostulationInfo();
    if (info == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EcfPostulationInfoDialog(info: info),
    );
  }

  Future<void> _sign(EcfSignKind kind) async {
    final file = await showDialog<EcfPickedFile>(
      context: context,
      builder: (_) => EcfSignDocumentDialog(kind: kind),
    );
    if (file == null) return;
    EcfSignedDocument? signed;
    final ok = await _run(
      'Firmando ${kind.label.toLowerCase()}…',
      () async => signed = await _repo.signDocument(
        kind: kind,
        filename: file.name,
        bytes: file.bytes,
      ),
    );
    if (!ok || signed == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EcfSignedDocumentDialog(document: signed!),
    );
  }

  /// Lotes de `send_test_set` antes de rendirse (cada uno trabaja ~30 s).
  static const _maxSendBatches = 12;

  /// Carga un Excel de la DGII en su paso: [kind] `ecf` (pruebas de datos
  /// e-CF) o `acecf` (aprobaciones comerciales).
  Future<void> _importTestSet(EcfTestSet? current, String kind) async {
    final approvals = kind == 'acecf';
    if (current != null && current.cases.any((c) => c.status != 'pending')) {
      final ok = await _confirm(
        title: approvals
            ? 'Cargar otras aprobaciones comerciales'
            : 'Cargar otro set de pruebas',
        body:
            'Se reemplazan '
            '${approvals ? 'las ${current.cases.length} aprobaciones cargadas' : 'los ${current.cases.length} comprobantes cargados'} '
            'y lo que respondió la DGII. Hazlo si reiniciaste ese paso en el '
            'portal de la DGII y descargaste el archivo nuevo.',
        confirmLabel: 'Reemplazar',
        color: AppTokens.destructive,
      );
      if (!ok) return;
    }
    final EcfPickedFile? picked;
    try {
      picked = await FileIoHelper.pickImportFile();
    } catch (e) {
      if (mounted) await _showError(e);
      return;
    }
    if (picked == null || !mounted) return;
    final file = picked;
    final name = file.name.toLowerCase();
    if (!name.endsWith('.xlsx') && !name.endsWith('.csv')) {
      await _showError(
        'Tiene que ser el .xlsx que da la DGII o un .csv de su hoja.',
      );
      return;
    }
    if (file.bytes.length > 5 * 1024 * 1024) {
      await _showError('El archivo pesa más de 5 MB: no parece el de la DGII.');
      return;
    }
    EcfTestSet? loaded;
    final ok = await _run(
      'Leyendo el archivo de la DGII…',
      () async => loaded = await _repo.importTestSet(
        setKind: kind,
        filename: file.name,
        bytes: file.bytes,
      ),
    );
    if (!ok || loaded == null || !mounted) return;
    final l = loaded!;
    AppSnackBar.success(
      context,
      approvals
          ? 'Aprobaciones comerciales cargadas: ${l.cases.length}.'
          : 'Set cargado: ${l.cases.length} comprobantes'
                '${l.summaries > 0 ? ' (${l.summaries} de consumo van como resumen)' : ''}.',
    );
  }

  Future<void> _sendTestSet(EcfTestSet t, EcfOnboardingStatus status) async {
    final approvals = t.isApprovals;
    final cert = await showDialog<EcfCertificateInput>(
      context: context,
      builder: (_) => EcfSigningCertificateDialog(
        title: approvals
            ? 'Enviar las aprobaciones a la DGII'
            : 'Enviar el set a la DGII',
        intro: approvals
            ? 'Se firman ${t.toSend} aprobación(es) comercial(es) con el '
                  'certificado de tu empresa, que aprueba como compradora, y '
                  'se mandan al ambiente de certificación de la DGII tal cual '
                  'el archivo. La DGII responde en el acto.'
            : 'Se firman ${t.toSend} comprobante(s) con el certificado de tu '
                  'empresa y se mandan al ambiente de certificación de la '
                  'DGII, tal cual el archivo: primero las facturas y al final '
                  'las notas que las modifican. Puede tardar unos minutos; no '
                  'cierres esta página.',
        confirmLabel: 'Firmar y enviar',
        savedCertificateFilename: status.draft?.hasCertificate == true
            ? status.draft!.certificateFilename
            : null,
      ),
    );
    if (cert == null || !mounted) return;

    setState(() => _busy = 'Firmando y enviando a la DGII…');
    String? notice;
    var sent = 0;
    var failed = false;
    var renewedSession = false;
    try {
      for (var batch = 0; batch < _maxSendBatches; batch++) {
        if (!mounted) break;
        final EcfTestSetSendResult r;
        try {
          r = await _repo.sendTestSet(
            setKind: t.kind,
            certificateFilename: cert.filename,
            certificateBytes: cert.bytes,
            certificatePassword: cert.password,
          );
        } on EcfRequestException catch (e) {
          // La DGII cerró la sesión guardada: el servidor ya la olvidó y el
          // siguiente lote abre otra con el mismo certificado.
          if (e.code == 'dgii_session_expired' && !renewedSession) {
            renewedSession = true;
            continue;
          }
          rethrow;
        }
        sent += r.sent;
        final ts = r.testSet;
        if (mounted) {
          setState(
            () => _busy =
                'Enviando a la DGII… ${ts.accepted} de ${ts.cases.length} '
                '${approvals ? 'aceptadas' : 'aceptados'}'
                '${ts.inProcess > 0 ? ', ${ts.inProcess} en proceso' : ''}',
          );
        }
        notice = r.stoppedReason;
        if (!r.more) break;
        if (batch == _maxSendBatches - 1) {
          notice =
              'La DGII sigue procesando. Usa Consultar en un momento y, si '
              'quedan comprobantes por enviar, Enviar otra vez.';
        }
      }
    } catch (e) {
      failed = true;
      if (mounted) await _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        _refresh();
      }
    }
    if (failed || !mounted) return;
    if (notice != null) {
      await _showError(notice);
    } else {
      AppSnackBar.success(
        context,
        approvals
            ? 'Se mandaron $sent aprobación(es) comercial(es) a la DGII.'
            : 'Se mandaron $sent comprobante(s) a la DGII.',
      );
    }
  }

  Future<void> _checkTestSet(String kind, EcfOnboardingStatus status) async {
    setState(() => _busy = 'Consultando a la DGII…');
    try {
      await _repo.checkTestSet(setKind: kind);
      if (mounted) _refresh();
      return;
    } on EcfRequestException catch (e) {
      if (e.code != 'dgii_session_expired') {
        if (mounted) await _showError(e);
        return;
      }
    } catch (e) {
      if (mounted) await _showError(e);
      return;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    // La sesión con la DGII (una hora) venció: se abre otra con el certificado.
    final cert = await showDialog<EcfCertificateInput>(
      context: context,
      builder: (_) => EcfSigningCertificateDialog(
        title: 'Consultar a la DGII',
        intro:
            'La sesión con la DGII del último envío venció (dura una hora). '
            'Elige el certificado de tu empresa para abrir otra y consultar.',
        confirmLabel: 'Consultar',
        savedCertificateFilename: status.draft?.hasCertificate == true
            ? status.draft!.certificateFilename
            : null,
      ),
    );
    if (cert == null || !mounted) return;
    await _run(
      'Consultando a la DGII…',
      () => _repo.checkTestSet(
        setKind: kind,
        certificateFilename: cert.filename,
        certificateBytes: cert.bytes,
        certificatePassword: cert.password,
      ),
    );
  }

  Future<void> _downloadTestCase(EcfTestCase c) async {
    try {
      final file = await _repo.testCaseXml(c.id);
      await FileIoHelper.saveBytes(
        bytes: Uint8List.fromList(utf8.encode(file.xml)),
        fileName: file.filename,
        dialogTitle: 'Guardar XML firmado',
        extension: 'xml',
      );
    } catch (e) {
      if (mounted) await _showError(e);
    }
  }

  /// Paso 4 del portal: arma los e-CF de la simulación con el set de datos
  /// como modelo.
  Future<void> _generateSimulation(EcfOnboardingStatus s) async {
    final current = s.simulationSet;
    if (current != null && current.cases.isNotEmpty) {
      final ok = await _confirm(
        title: 'Generar la simulación de nuevo',
        body:
            'Se descartan los ${current.cases.length} e-CF actuales y se arman '
            'otros con números nuevos (la DGII no deja reusar los ya '
            'enviados). Hazlo solo si la DGII rechazó alguno y reiniciaste las '
            'pruebas de simulación en su portal.',
        confirmLabel: 'Generar de nuevo',
        color: AppTokens.destructive,
      );
      if (!ok) return;
    }
    // Modelos que hay por categoría (el set de datos ya aceptado).
    final available = <String, int>{};
    for (final c in s.testSet?.cases ?? const <EcfTestCase>[]) {
      available.update(c.simulationCategory, (n) => n + 1, ifAbsent: () => 1);
    }
    if (!mounted) return;
    final counts = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => EcfSimulationCountsDialog(available: available),
    );
    if (counts == null || !mounted) return;
    EcfTestSet? built;
    final ok = await _run(
      'Generando los e-CF de la simulación…',
      () async => built = await _repo.generateSimulationSet(counts: counts),
    );
    if (!ok || built == null || !mounted) return;
    AppSnackBar.success(
      context,
      'Simulación lista: ${built!.cases.length} e-CF con los datos de tu '
      'empresa y fecha de hoy.',
    );
  }

  String _pdfName(String xmlName) =>
      xmlName.replaceFirst(RegExp(r'\.xml$'), '.pdf');

  /// Representación impresa (PDF) de un e-CF ya firmado.
  Future<void> _printTestCase(EcfTestCase c) async {
    try {
      final file = await _repo.testCaseXml(c.id);
      final model = file.print;
      if (model == null) {
        throw const EcfRequestException(
          'El servidor no devolvió los datos de la representación impresa.',
        );
      }
      final pdf = await buildEcfPrintPdf(model);
      await FileIoHelper.saveBytes(
        bytes: pdf,
        fileName: _pdfName(file.filename),
        dialogTitle: 'Guardar representación impresa',
        extension: 'pdf',
      );
    } catch (e) {
      if (mounted) await _showError(e);
    }
  }

  /// Todas las representaciones impresas del set (las que ya se firmaron).
  Future<void> _printAll(EcfTestSet t) async {
    final signed = t.cases.where((c) => c.hasXml && !c.isApproval).toList();
    var done = 0;
    String? failure;
    try {
      for (final c in signed) {
        if (!mounted) return;
        setState(
          () => _busy =
              'Generando representaciones impresas… ${done + 1} de '
              '${signed.length}',
        );
        final file = await _repo.testCaseXml(c.id);
        final model = file.print;
        if (model == null) {
          failure =
              '${c.encf}: el servidor no devolvió los datos de la '
              'representación impresa.';
          break;
        }
        final pdf = await buildEcfPrintPdf(model);
        await FileIoHelper.saveBytes(
          bytes: pdf,
          fileName: _pdfName(file.filename),
          dialogTitle: 'Guardar representación impresa',
          extension: 'pdf',
        );
        done++;
      }
    } catch (e) {
      failure = e is EcfRequestException ? e.message : '$e';
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    if (failure != null) {
      await _showError('Se descargaron $done de ${signed.length}. $failure');
    } else {
      AppSnackBar.success(
        context,
        'Se descargaron $done representaciones impresas. Si el navegador '
        'pregunta, permite descargar varios archivos.',
      );
    }
  }

  Future<void> _showTestSet(EcfTestSet t) {
    return showDialog<void>(
      context: context,
      builder: (_) => EcfTestSetDialog(
        testSet: t,
        onDownload: _downloadTestCase,
        onPrint: t.isApprovals ? null : _printTestCase,
      ),
    );
  }

  Future<void> _setDgiiAuthorized(bool authorized) async {
    final confirmed = await _confirm(
      title: authorized ? 'Marcar como autorizado' : 'Quitar la marca',
      body: authorized
          ? 'Confirma que la DGII ya autorizó a tu empresa como emisor '
                'electrónico (o que ya lo estaba). Siguiente paso: cargar las '
                'secuencias e-NCF que la DGII te asigne.'
          : 'El paso de certificación vuelve a quedar pendiente.',
      confirmLabel: authorized ? 'Marcar' : 'Quitar',
    );
    if (!confirmed) return;
    await _run('Guardando…', () => _repo.setDgiiAuthorized(authorized));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(ecfOnboardingStatusProvider);
    final status = statusAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: AppTokens.primary,
            ),
            const SizedBox(width: AppTokens.s8),
            const Expanded(
              child: Text(
                'Facturación electrónica (e-CF)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.foreground,
                ),
              ),
            ),
            if (status != null) ...[
              _Pill(
                text: status.isProduction ? 'Producción' : 'Pruebas (sandbox)',
                color: status.isProduction
                    ? AppTokens.primary
                    : AppTokens.warning,
              ),
              const SizedBox(width: AppTokens.s4),
            ],
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _busy == null ? _refresh : null,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.s12),
        if (_busy != null) ...[
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppTokens.s10),
              Expanded(
                child: Text(
                  _busy!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTokens.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s12),
        ],
        statusAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EcfNote(
                color: AppTokens.destructive,
                text:
                    'No se pudo leer el estado de la facturación electrónica: '
                    '${e is EcfRequestException ? e.message : e}',
              ),
              const SizedBox(height: AppTokens.s8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
              ),
            ],
          ),
          data: _buildSteps,
        ),
      ],
    );
  }

  Widget _buildSteps(EcfOnboardingStatus s) {
    final step = s.currentStep;
    final locked = _busy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (step == 6)
          const Padding(
            padding: EdgeInsets.only(bottom: AppTokens.s12),
            child: EcfNote(
              color: AppTokens.success,
              text: 'Tu empresa ya emite comprobantes electrónicos.',
            ),
          ),
        _StepCard(
          number: 1,
          title: 'Datos del contribuyente',
          current: step,
          child: _dataStep(s, locked),
        ),
        _StepCard(
          number: 2,
          title: 'Empresa con el proveedor',
          current: step,
          child: _companyStep(s, locked),
        ),
        _StepCard(
          number: 3,
          title: 'Certificación DGII',
          current: step,
          child: _certificationStep(s, locked),
        ),
        _StepCard(
          number: 4,
          title: 'Secuencias e-NCF',
          current: step,
          child: _sequencesStep(s, locked),
        ),
        _StepCard(
          number: 5,
          title: 'Encender la facturación electrónica',
          current: step,
          isLast: true,
          child: _activateStep(s, locked),
        ),
      ],
    );
  }

  Widget _dataStep(EcfOnboardingStatus s, bool locked) {
    final d = s.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d?.requestedAt != null) ...[
          EcfNote(
            color: AppTokens.primary,
            text:
                'Solicitada el ${formatDateTime(d!.requestedAt)}. '
                'Contacto: ${d.contactName ?? '—'}'
                '${d.contactPhone != null ? ' · ${d.contactPhone}' : ''}. '
                '${d.alreadyAuthorized == true ? 'Declaraste que YA eres emisor electrónico autorizado.' : 'Declaraste que todavía no eres emisor electrónico.'}',
          ),
          const SizedBox(height: AppTokens.s10),
        ],
        if (d == null) ...[
          const Text(
            'Todavía no has pedido la facturación electrónica. Empieza con la '
            'solicitud: datos de tu empresa como están en la DGII y tu '
            'certificado de firma digital.',
            style: TextStyle(fontSize: 12.5, color: AppTokens.mutedForeground),
          ),
          const SizedBox(height: AppTokens.s10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: locked ? null : _openRequest,
              icon: const Icon(Icons.bolt_outlined, size: 18),
              label: const Text('Solicitar facturación electrónica'),
            ),
          ),
        ] else ...[
          EcfLine('RNC', d.rnc ?? '—'),
          EcfLine('Razón social', d.legalName ?? '—'),
          if (d.tradeName != null) EcfLine('Nombre comercial', d.tradeName!),
          EcfLine('Dirección fiscal', d.fiscalAddress ?? '—'),
          EcfLine(
            'Provincia / municipio',
            _orDash(
              [d.province, d.municipality].whereType<String>().join(' · '),
            ),
          ),
          EcfLine('Correo', d.email ?? '—'),
          const SizedBox(height: AppTokens.s12),
          const Text(
            'Acceso a la Oficina Virtual (DGII)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTokens.s6),
          EcfLine('Usuario OFV', d.ofvUser ?? 'No guardado'),
          EcfLine(
            'Contraseña OFV',
            d.hasOfvPassword
                ? 'Guardada el ${formatDate(d.ofvPasswordUpdatedAt)}'
                : 'No guardada',
          ),
          const SizedBox(height: AppTokens.s4),
          Wrap(
            spacing: AppTokens.s8,
            runSpacing: AppTokens.s8,
            children: [
              if (d.hasOfvPassword)
                OutlinedButton.icon(
                  onPressed: locked || _revealingOfv ? null : _showOfvPassword,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(
                    _revealingOfv
                        ? 'Consultando contraseña…'
                        : 'Ver contraseña',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: locked ? null : () => _editOfv(s),
                icon: const Icon(Icons.key_outlined, size: 18),
                label: Text(d.hasOfvPassword ? 'Cambiar' : 'Guardar acceso'),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppTokens.s12),
        const Text(
          'Certificado digital para firmar las pruebas',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppTokens.s6),
        if (d?.hasCertificate == true) ...[
          EcfLine('Archivo guardado', d!.certificateFilename!),
          EcfLine('Guardado el', formatDateTime(d.certificateUpdatedAt)),
        ] else
          const EcfLine('Estado', 'No guardado'),
        const SizedBox(height: AppTokens.s4),
        Wrap(
          spacing: AppTokens.s8,
          runSpacing: AppTokens.s8,
          children: [
            OutlinedButton.icon(
              onPressed: locked ? null : _saveCertificate,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(
                d?.hasCertificate == true
                    ? 'Reemplazar certificado'
                    : 'Cargar certificado',
              ),
            ),
            if (d != null)
              OutlinedButton.icon(
                onPressed: locked ? null : () => _editData(s),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar datos'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _companyStep(EcfOnboardingStatus s, bool locked) {
    final c = s.company;
    if (!s.hasCompany) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.hasRequest
                ? 'Tu solicitud llegó, pero tu empresa no quedó registrada con '
                      'el proveedor. Casi siempre es la contraseña del '
                      'certificado o un archivo que no es el de firma: '
                      'reenvíala con el certificado correcto. Si el RNC ya '
                      'estaba registrado, te vamos a contactar.'
                : 'Tu empresa se registra con el proveedor al enviar la '
                      'solicitud.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTokens.mutedForeground,
            ),
          ),
          if (s.hasRequest) ...[
            const SizedBox(height: AppTokens.s10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: locked ? null : _openRequest,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reenviar solicitud'),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: EcfLine('ID', s.companyId!)),
            IconButton(
              tooltip: 'Copiar ID',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: s.companyId!)),
              icon: const Icon(Icons.copy_outlined, size: 16),
            ),
          ],
        ),
        if (s.companyError != null)
          EcfNote(color: AppTokens.destructive, text: s.companyError!)
        else if (c != null) ...[
          EcfLine(
            'Empresa',
            '${c.name ?? '—'} · RNC ${c.identification ?? '—'}',
          ),
          EcfLine(
            'Certificado',
            !c.hasCertificate
                ? 'Sin certificado'
                : '${c.certificateName}'
                      '${c.certificateIssuer != null ? ' · ${c.certificateIssuer}' : ''}'
                      '${c.certificateEndDate != null ? ' · vence ${formatDate(c.certificateEndDate)}' : ''}',
            valueColor: !c.hasCertificate || c.certificateExpired
                ? AppTokens.destructive
                : null,
          ),
          EcfLine(
            'Avisos del proveedor',
            c.webhooksOk == true
                ? 'Configurados'
                : 'Faltan (las facturas se quedarían en "enviado")',
            valueColor: c.webhooksOk == true ? null : AppTokens.warning,
          ),
        ],
        if (s.draft?.companyLinkedVia != null)
          EcfLine(
            'Origen',
            s.draft!.companyLinkedVia == 'registered'
                ? 'Registrada con tu solicitud'
                : 'Ya existía con el proveedor',
            valueColor: AppTokens.mutedForeground,
          ),
      ],
    );
  }

  Widget _certificationStep(EcfOnboardingStatus s, bool locked) {
    if (!s.hasCompany) {
      return const Text(
        'Primero tu empresa tiene que quedar registrada con el proveedor.',
        style: TextStyle(fontSize: 12.5, color: AppTokens.mutedForeground),
      );
    }
    final draft = s.draft;
    if (s.isCertified) {
      final marked = draft?.dgiiAuthorizedAt;
      return Row(
        children: [
          Expanded(
            child: Text(
              marked != null
                  ? 'Autorizada por la DGII (marcado el ${formatDate(marked)}).'
                  : 'Autorizada por la DGII: ya eres emisor electrónico, '
                        'tienes secuencias electrónicas o ya emites.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          if (marked != null && !s.hasSequences && !s.ecfEnabled)
            TextButton(
              onPressed: locked ? null : () => _setDgiiAuthorized(false),
              child: const Text('Quitar marca'),
            ),
        ],
      );
    }

    String signedText(DateTime? at, String pending) => at == null
        ? pending
        : 'Firmado el ${formatDate(at)}. Súbelo a la Oficina Virtual si no lo '
              'has hecho.';

    final t = s.testSet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Solo si todavía no eres emisor electrónico. Los XML y los Excel los '
          'genera la DGII en su Oficina Virtual; aquí se firman y se mandan.',
          style: TextStyle(fontSize: 12, color: AppTokens.mutedForeground),
        ),
        const SizedBox(height: AppTokens.s10),
        _SubStep(
          label: 'Postulación en la Oficina Virtual',
          detail:
              'Llena el formulario con los datos del proveedor y las URLs de '
              'tu empresa.',
          done: draft?.postulationSignedAt != null,
          action: OutlinedButton(
            onPressed: locked ? null : _showPostulationInfo,
            child: const Text('Ver datos'),
          ),
        ),
        _SubStep(
          label: 'Firmar XML de postulación',
          detail: signedText(
            draft?.postulationSignedAt,
            'La DGII lo genera al enviar la postulación.',
          ),
          done: draft?.postulationSignedAt != null,
          action: OutlinedButton(
            onPressed: locked ? null : () => _sign(EcfSignKind.postulation),
            child: Text(
              draft?.postulationSignedAt == null ? 'Firmar XML' : 'Firmar otro',
            ),
          ),
        ),
        _SubStep(
          label: 'Pruebas de datos e-CF',
          detail: _testSetDetail(t),
          detailColor:
              t != null && (t.rejected.isNotEmpty || t.failed.isNotEmpty)
              ? AppTokens.destructive
              : null,
          done: t?.isComplete ?? false,
          action: _testSetActions(t, 'ecf', locked, status: s),
        ),
        _SubStep(
          label: 'Pruebas de aprobación comercial',
          detail: _approvalSetDetail(s.approvalSet),
          detailColor: (s.approvalSet?.failed.isNotEmpty ?? false)
              ? AppTokens.destructive
              : null,
          done: s.approvalSet?.isComplete ?? false,
          action: _testSetActions(s.approvalSet, 'acecf', locked, status: s),
        ),
        _SubStep(
          label: 'Pruebas de simulación e-CF',
          detail: _simulationDetail(s),
          detailColor:
              (s.simulationSet?.rejected.isNotEmpty ?? false) ||
                  (s.simulationSet?.failed.isNotEmpty ?? false)
              ? AppTokens.destructive
              : null,
          done: s.simulationSet?.isComplete ?? false,
          action: _testSetActions(s.simulationSet, 'sim', locked, status: s),
        ),
        _SubStep(
          label: 'Firmar declaración jurada',
          detail: signedText(
            draft?.declarationSignedAt,
            'La DGII la entrega al aprobar el set de pruebas.',
          ),
          done: draft?.declarationSignedAt != null,
          action: OutlinedButton(
            onPressed: locked ? null : () => _sign(EcfSignKind.declaration),
            child: Text(
              draft?.declarationSignedAt == null ? 'Firmar XML' : 'Firmar otro',
            ),
          ),
        ),
        _SubStep(
          label: 'Asignar roles al proveedor',
          detail: draft?.rolesSignedAt != null
              ? signedText(draft?.rolesSignedAt, '')
              : 'Lo hace el representante legal en la Oficina Virtual. Si la '
                    'DGII entrega un XML, se firma aquí.',
          done: draft?.rolesSignedAt != null,
          isLast: true,
          action: OutlinedButton(
            onPressed: locked ? null : () => _sign(EcfSignKind.roles),
            child: const Text('Firmar XML'),
          ),
        ),
        const SizedBox(height: AppTokens.s12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: locked ? null : () => _setDgiiAuthorized(true),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('La DGII ya me autorizó'),
          ),
        ),
      ],
    );
  }

  /// Botones de un set de la DGII: enviar, consultar, ver y cargar (o, en la
  /// simulación, generar y bajar las representaciones impresas).
  Widget _testSetActions(
    EcfTestSet? t,
    String kind,
    bool locked, {
    required EcfOnboardingStatus status,
  }) {
    final simulation = kind == 'sim';
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        if (t != null && t.canSend)
          FilledButton(
            onPressed: locked ? null : () => _sendTestSet(t, status),
            child: Text(
              t.cases.every((c) => c.status == 'pending')
                  ? 'Enviar a la DGII'
                  : 'Continuar envío',
            ),
          ),
        if (t != null && t.canCheck)
          OutlinedButton(
            onPressed: locked ? null : () => _checkTestSet(kind, status),
            child: const Text('Consultar'),
          ),
        if (t != null && !t.isEmpty)
          OutlinedButton(
            onPressed: () => _showTestSet(t),
            child: Text(
              kind == 'acecf' ? 'Ver aprobaciones' : 'Ver comprobantes',
            ),
          ),
        if (simulation && t != null && t.cases.any((c) => c.hasXml))
          OutlinedButton(
            onPressed: locked ? null : () => _printAll(t),
            child: const Text('Representaciones (PDF)'),
          ),
        if (simulation)
          OutlinedButton(
            onPressed: locked ? null : () => _generateSimulation(status),
            child: Text(
              t == null || t.isEmpty
                  ? 'Generar comprobantes'
                  : 'Generar de nuevo',
            ),
          )
        else
          OutlinedButton(
            onPressed: locked ? null : () => _importTestSet(t, kind),
            child: Text(
              t == null || t.isEmpty ? 'Cargar archivo' : 'Cargar otro',
            ),
          ),
      ],
    );
  }

  String _simulationDetail(EcfOnboardingStatus s) {
    final t = s.simulationSet;
    if (t == null || t.isEmpty) {
      return 'La DGII pide e-CF de la operación real (paso 4 del portal) y no '
          'da nada para descargar: se generan aquí con los datos de tu '
          'empresa, fecha de hoy y e-NCF nuevos, sobre el set de prueba de la '
          'DGII (el del paso de datos si lo cargaste aquí; si no, el '
          'genérico). Después de enviarlos, sube en el portal el XML de la de '
          'consumo menor de 250 mil y baja las representaciones impresas '
          '(PDF) para el paso 5.';
    }
    final text = StringBuffer(_testSetDetail(t));
    if (t.isComplete) {
      text.write(
        ' Baja las representaciones impresas (PDF) para el paso 5'
        '${t.summaries > 0 ? ' y sube en el portal los XML de las de consumo menores de 250 mil' : ''}.',
      );
    }
    return text.toString();
  }

  String _approvalSetDetail(EcfTestSet? a) {
    if (a == null || a.isEmpty) {
      return 'Después de las pruebas de e-CF, el portal da otro Excel (Pruebas '
          'de datos aprobación comercial): tu empresa aprueba, como '
          'compradora, e-CF que le "emitió" la DGII. Súbelo tal cual.';
    }
    final text = StringBuffer(
      [
        '${a.cases.length} aprobaciones',
        '${a.accepted} aceptadas',
        if (a.toSend > 0) '${a.toSend} por enviar',
      ].join(' · '),
    );
    text.write('.');
    if (a.failed.isNotEmpty) {
      text.write(
        ' No se pudieron enviar ${a.failed.map((c) => c.encf).join(', ')} '
        '(detalle en Ver aprobaciones).',
      );
    }
    return text.toString();
  }

  String _testSetDetail(EcfTestSet? t) {
    if (t == null || t.isEmpty) {
      return 'Después de subir la postulación firmada, la DGII da en su portal '
          'de certificación (Pruebas de datos e-CF) un Excel con los '
          'comprobantes a probar. Súbelo tal cual (.xlsx) o su hoja ECF en '
          '.csv.';
    }
    final text = StringBuffer(
      [
        '${t.cases.length} comprobantes'
            '${t.summaries > 0 ? ' (${t.summaries} de consumo van como resumen)' : ''}',
        '${t.accepted} aceptados',
        if (t.inProcess > 0) '${t.inProcess} en proceso',
        if (t.toSend > 0) '${t.toSend} por enviar',
      ].join(' · '),
    );
    text.write('.');
    if (t.rejected.isNotEmpty) {
      text.write(
        ' La DGII rechazó ${t.rejected.map((c) => c.encf).join(', ')}: '
        'reinicia esas pruebas en su portal y '
        '${t.isSimulation ? 'genera la simulación de nuevo' : 'carga el archivo nuevo'}.',
      );
    } else if (t.failed.isNotEmpty) {
      text.write(
        ' No se pudieron enviar ${t.failed.map((c) => c.encf).join(', ')} '
        '(detalle en Ver comprobantes).',
      );
    } else if (t.isComplete && t.summaries > 0 && !t.isSimulation) {
      text.write(
        ' Falta subir en el portal los XML de las facturas de consumo menores '
        'de 250 mil (Ver comprobantes → descargar).',
      );
    }
    return text.toString();
  }

  Widget _sequencesStep(EcfOnboardingStatus s, bool locked) {
    final types = s.sequences.map((e) => e.ncfType).toSet();
    String branchName(String id) =>
        s.branches.where((b) => b.id == id).map((b) => b.name).firstOrNull ??
        'Sucursal';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.sequences.isEmpty)
          const Text(
            'Sin secuencias electrónicas. Cárgalas del PDF de autorización '
            'que te da la DGII en la Oficina Virtual. Una por sucursal: dos '
            'sucursales con el mismo rango emitirían el mismo e-NCF.',
            style: TextStyle(fontSize: 12.5, color: AppTokens.mutedForeground),
          )
        else
          for (final q in s.sequences)
            Container(
              margin: const EdgeInsets.only(bottom: AppTokens.s6),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s12,
                vertical: AppTokens.s8,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: q.isUsable
                      ? AppTokens.border
                      : AppTokens.destructive.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${q.ncfType} · ${ecfTypeLabels[q.ncfType] ?? q.ncfType}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (s.branches.length > 1) branchName(q.branchId),
                      'hasta ${q.rangeEnd}',
                      'quedan ${q.remaining < 0 ? 0 : q.remaining}',
                      q.expirationDate != null
                          ? 'vence ${formatDate(q.expirationDate)}'
                          : q.missingExpiration
                          ? 'FALTA vencimiento'
                          : 'vence N/A',
                      if (!q.isActive) 'inactiva',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: q.isUsable
                          ? AppTokens.mutedForeground
                          : AppTokens.destructive,
                    ),
                  ),
                ],
              ),
            ),
        if (!types.contains('E32')) ...[
          const SizedBox(height: AppTokens.s4),
          const EcfNote(
            color: AppTokens.warning,
            text: 'Sin E32 no hay factura de consumo.',
          ),
        ],
        const SizedBox(height: AppTokens.s10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: locked || !s.hasCompany ? null : () => _addSequence(s),
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Cargar secuencia e-NCF'),
          ),
        ),
      ],
    );
  }

  Widget _activateStep(EcfOnboardingStatus s, bool locked) {
    if (!s.hasCompany) {
      return const Text(
        'Primero tu empresa tiene que quedar registrada con el proveedor.',
        style: TextStyle(fontSize: 12.5, color: AppTokens.mutedForeground),
      );
    }
    final mode = s.settings?.mode ?? 'physical';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EcfLine(
          'Modalidad',
          s.ecfEnabled
              ? 'Electrónica ($mode) · ${s.isProduction ? 'producción' : 'pruebas'}'
              : 'Comprobantes en papel',
          valueColor: s.ecfEnabled ? null : AppTokens.mutedForeground,
        ),
        const SizedBox(height: AppTokens.s6),
        Text(
          s.ecfEnabled
              ? 'Si el proveedor no responde, la venta no se detiene: el '
                    'comprobante queda en cola y se emite después.'
              : s.hasSequences
              ? 'Todo listo. Al encenderla, tus ventas empiezan a salir como '
                    'comprobantes electrónicos. Al encender se compara el RNC '
                    'de tus facturas con el de tu empresa en el proveedor.'
              : 'Para encenderla hace falta una secuencia e-NCF activa, '
                    'vigente y con números.',
          style: const TextStyle(
            fontSize: 12.5,
            color: AppTokens.mutedForeground,
          ),
        ),
        const SizedBox(height: AppTokens.s10),
        Align(
          alignment: Alignment.centerLeft,
          child: s.ecfEnabled
              ? OutlinedButton.icon(
                  onPressed: locked ? null : () => _toggleEcf(false),
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Apagar'),
                )
              : FilledButton.icon(
                  onPressed: locked || !s.hasSequences
                      ? null
                      : () => _toggleEcf(true),
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Encender facturación electrónica'),
                ),
        ),
      ],
    );
  }
}

String _orDash(String s) => s.isEmpty ? '—' : s;

// ---------------------------------------------------------------------------
// Piezas chicas
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.current,
    required this.child,
    this.isLast = false,
  });

  final int number;
  final String title;

  /// Paso en curso de la empresa (6 = todo listo).
  final int current;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final done = number < current;
    final active = number == current;
    final color = done
        ? AppTokens.success
        : active
        ? AppTokens.primary
        : AppTokens.mutedForeground;
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : AppTokens.s10),
      padding: const EdgeInsets.all(AppTokens.s14),
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppTokens.primary.withValues(alpha: 0.5)
              : AppTokens.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: done
                ? Icon(Icons.check, size: 14, color: color)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
          ),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.foreground,
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subpaso de la certificación: estado, explicación y su botón.
class _SubStep extends StatelessWidget {
  const _SubStep({
    required this.label,
    required this.detail,
    required this.done,
    required this.action,
    this.detailColor,
    this.isLast = false,
  });

  final String label;
  final String detail;
  final bool done;
  final Widget action;
  final Color? detailColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppTokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: done ? AppTokens.success : AppTokens.mutedForeground,
            ),
          ),
          const SizedBox(width: AppTokens.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: detailColor ?? AppTokens.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s10),
          Flexible(
            child: Align(alignment: Alignment.topRight, child: action),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
