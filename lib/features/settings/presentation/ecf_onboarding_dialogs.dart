import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/ecf_onboarding_models.dart';

/// Diálogos del trámite de facturación electrónica (ver
/// `ecf_onboarding_page.dart`). Capturan datos y muestran lo recibido; las
/// reglas las valida el servidor. Portados del panel de MangoPOS
/// (`ecf_onboarding_dialogs.dart`).

typedef EcfPickedFile = ({Uint8List bytes, String name});

// ---------------------------------------------------------------------------
// Datos del contribuyente
// ---------------------------------------------------------------------------

class EcfTaxpayerDialog extends StatefulWidget {
  const EcfTaxpayerDialog({
    required this.initial,
    required this.rncLocked,
    super.key,
  });

  final EcfTaxpayerDraft initial;

  /// Con la empresa ya registrada con el proveedor el RNC no se cambia.
  final bool rncLocked;

  @override
  State<EcfTaxpayerDialog> createState() => _EcfTaxpayerDialogState();
}

class _EcfTaxpayerDialogState extends State<EcfTaxpayerDialog> {
  late final _rnc = TextEditingController(text: widget.initial.rnc ?? '');
  late final _legal = TextEditingController(
    text: widget.initial.legalName ?? '',
  );
  late final _trade = TextEditingController(
    text: widget.initial.tradeName ?? '',
  );
  late final _address = TextEditingController(
    text: widget.initial.fiscalAddress ?? '',
  );
  late final _province = TextEditingController(
    text: widget.initial.province ?? '',
  );
  late final _municipality = TextEditingController(
    text: widget.initial.municipality ?? '',
  );
  late final _email = TextEditingController(text: widget.initial.email ?? '');
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _rnc,
      _legal,
      _trade,
      _address,
      _province,
      _municipality,
      _email,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _submit() {
    final digits = _rnc.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length != 9 && digits.length != 11) {
      setState(
        () => _error = 'El RNC debe tener 9 dígitos (u 11 si es cédula).',
      );
      return;
    }
    Navigator.pop(
      context,
      EcfTaxpayerDraft(
        rnc: digits.isEmpty ? null : digits,
        legalName: _clean(_legal),
        tradeName: _clean(_trade),
        fiscalAddress: _clean(_address),
        province: _clean(_province),
        municipality: _clean(_municipality),
        email: _clean(_email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Datos del contribuyente'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppTokens.mutedForeground,
                text:
                    'Cópialos tal como aparecen en la DGII (consulta de RNC o '
                    'la autorización de secuencias), no como llamas a tu '
                    'negocio.',
              ),
              const SizedBox(height: AppTokens.s14),
              TextField(
                controller: _rnc,
                enabled: !widget.rncLocked,
                autofocus: !widget.rncLocked,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'RNC',
                  helperText: widget.rncLocked
                      ? 'Tu empresa ya está registrada con el proveedor con '
                            'este RNC.'
                      : null,
                ),
              ),
              const SizedBox(height: AppTokens.s10),
              TextField(
                controller: _legal,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Razón social'),
              ),
              const SizedBox(height: AppTokens.s10),
              TextField(
                controller: _trade,
                decoration: const InputDecoration(
                  labelText: 'Nombre comercial (opcional)',
                ),
              ),
              const SizedBox(height: AppTokens.s10),
              TextField(
                controller: _address,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Dirección fiscal',
                  helperText:
                      'La registrada en la DGII. Puede no ser la del local.',
                ),
              ),
              const SizedBox(height: AppTokens.s4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _province,
                      decoration: const InputDecoration(labelText: 'Provincia'),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s10),
                  Expanded(
                    child: TextField(
                      controller: _municipality,
                      decoration: const InputDecoration(labelText: 'Municipio'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.s8),
                EcfNote(color: AppTokens.destructive, text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Oficina Virtual
// ---------------------------------------------------------------------------

/// Muestra el acceso guardado a la Oficina Virtual (la consulta queda
/// auditada en el servidor).
class EcfOfvCredentialsDialog extends StatefulWidget {
  const EcfOfvCredentialsDialog({required this.credentials, super.key});

  final EcfOfvCredentials credentials;

  @override
  State<EcfOfvCredentialsDialog> createState() =>
      _EcfOfvCredentialsDialogState();
}

class _EcfOfvCredentialsDialogState extends State<EcfOfvCredentialsDialog> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Acceso a la Oficina Virtual'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EcfLine('Usuario OFV', widget.credentials.ofvUser ?? '—'),
              const SizedBox(height: AppTokens.s12),
              const Text(
                'Contraseña OFV',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTokens.mutedForeground,
                ),
              ),
              const SizedBox(height: AppTokens.s4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      _visible ? widget.credentials.ofvPassword : '••••••••',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _visible
                        ? 'Ocultar contraseña OFV'
                        : 'Mostrar contraseña OFV',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar contraseña OFV',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: widget.credentials.ofvPassword),
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Guarda o cambia el usuario y la clave de la Oficina Virtual.
class EcfOfvEditDialog extends StatefulWidget {
  const EcfOfvEditDialog({this.initialUser, super.key});

  final String? initialUser;

  @override
  State<EcfOfvEditDialog> createState() => _EcfOfvEditDialogState();
}

class _EcfOfvEditDialogState extends State<EcfOfvEditDialog> {
  late final _user = TextEditingController(text: widget.initialUser ?? '');
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready => _user.text.trim().isNotEmpty && _password.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Acceso a la Oficina Virtual'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppTokens.mutedForeground,
                text:
                    'Es el acceso de la Oficina Virtual (OFV) de la DGII. La '
                    'clave se guarda cifrada y solo un administrador de tu '
                    'empresa la puede volver a ver.',
              ),
              const SizedBox(height: AppTokens.s14),
              TextField(
                controller: _user,
                maxLength: 60,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  helperText: 'Casi siempre es tu RNC o cédula.',
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppTokens.s10),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Clave',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: !_ready
              ? null
              : () => Navigator.pop(context, (
                  user: _user.text.trim(),
                  password: _password.text,
                )),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Certificado de firma
// ---------------------------------------------------------------------------

/// Lo que se eligió en [EcfSigningCertificateDialog]: un archivo con su
/// contraseña, o el certificado ya guardado en el servidor.
class EcfCertificateInput {
  const EcfCertificateInput({
    required String this.filename,
    required Uint8List this.bytes,
    required String this.password,
  });

  const EcfCertificateInput.stored()
    : filename = null,
      bytes = null,
      password = null;

  final String? filename;
  final Uint8List? bytes;
  final String? password;

  bool get usesStoredCertificate => bytes == null;
}

/// Elige el certificado guardado o un archivo .p12/.pfx.
class EcfSigningCertificateDialog extends StatefulWidget {
  const EcfSigningCertificateDialog({
    required this.title,
    required this.intro,
    required this.confirmLabel,
    this.savedCertificateFilename,
    this.consentLabel,
    super.key,
  });

  final String title;
  final String intro;
  final String confirmLabel;
  final String? savedCertificateFilename;

  /// Si viene, hay que marcar esta casilla para confirmar (p. ej. autorizar
  /// que se guarde el certificado cifrado).
  final String? consentLabel;

  @override
  State<EcfSigningCertificateDialog> createState() =>
      _EcfSigningCertificateDialogState();
}

class _EcfSigningCertificateDialogState
    extends State<EcfSigningCertificateDialog> {
  final _password = TextEditingController();
  late bool _useSaved = widget.savedCertificateFilename != null;
  bool _consent = false;
  EcfPickedFile? _file;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await FileIoHelper.pickCertificateFile();
      if (picked == null || !mounted) return;
      // Un .p12 de firma no pasa de 100 KB: el servidor lo rechaza igual.
      if (picked.bytes.length > 100 * 1024) {
        setState(
          () => _error =
              'Ese archivo pesa ${(picked.bytes.length / 1024).round()} KB. '
              'Un certificado .p12 no pasa de 100 KB: revisa que sea el '
              'archivo correcto.',
        );
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        (_useSaved || (_file != null && _password.text.isNotEmpty)) &&
        (widget.consentLabel == null || _consent);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EcfNote(color: AppTokens.mutedForeground, text: widget.intro),
              const SizedBox(height: AppTokens.s14),
              if (widget.savedCertificateFilename != null) ...[
                DropdownButtonFormField<bool>(
                  initialValue: _useSaved,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Certificado'),
                  items: const [
                    DropdownMenuItem(
                      value: true,
                      child: Text('Usar el certificado guardado'),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text('Subir otro certificado'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _useSaved = value;
                        _error = null;
                      });
                    }
                  },
                ),
                if (_useSaved) ...[
                  const SizedBox(height: AppTokens.s10),
                  EcfLine('Archivo', widget.savedCertificateFilename!),
                ],
                const SizedBox(height: AppTokens.s10),
              ],
              if (!_useSaved) ...[
                OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: Text(
                    _file == null ? 'Elegir certificado (.p12)' : _file!.name,
                  ),
                ),
                const SizedBox(height: AppTokens.s10),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Contraseña del certificado',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
              ],
              const Text(
                'Usa el certificado de la empresa o de su representante '
                'autorizado ante la DGII.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTokens.mutedForeground,
                ),
              ),
              if (widget.consentLabel != null) ...[
                const SizedBox(height: AppTokens.s8),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    widget.consentLabel!,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppTokens.s10),
                EcfNote(color: AppTokens.destructive, text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: !ready
              ? null
              : () => Navigator.pop(
                  context,
                  _useSaved
                      ? const EcfCertificateInput.stored()
                      : EcfCertificateInput(
                          filename: _file!.name,
                          bytes: _file!.bytes,
                          password: _password.text,
                        ),
                ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Certificación DGII
// ---------------------------------------------------------------------------

/// Datos que pide el formulario de postulación de la Oficina Virtual.
class EcfPostulationInfoDialog extends StatelessWidget {
  const EcfPostulationInfoDialog({required this.info, super.key});

  final EcfPostulationInfo info;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Datos para la postulación'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppTokens.mutedForeground,
                text:
                    'Cópialos en el formulario de postulación como emisor '
                    'electrónico de la Oficina Virtual de la DGII. Al '
                    'enviarlo, la DGII genera el XML de postulación que se '
                    'firma en el paso siguiente.',
              ),
              const SizedBox(height: AppTokens.s14),
              const _GroupTitle('Software / proveedor'),
              _CopyLine('Tipo de software', info.softwareType),
              _CopyLine('Nombre del software', info.softwareName),
              _CopyLine('Versión', info.softwareVersion),
              _CopyLine('RNC del proveedor', info.providerRnc),
              _CopyLine('Razón social del proveedor', info.providerName),
              _CopyLine('Nombre comercial', info.providerTradeName),
              const SizedBox(height: AppTokens.s12),
              const _GroupTitle('URLs de tu empresa'),
              if (info.companyError != null)
                EcfNote(color: AppTokens.destructive, text: info.companyError!)
              else ...[
                _CopyLine('Recepción', info.receptionUrl),
                _CopyLine('Aprobación comercial', info.approvalUrl),
                _CopyLine('Autenticación', info.authenticationUrl),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTokens.mutedForeground,
        ),
      ),
    );
  }
}

class _CopyLine extends StatelessWidget {
  const _CopyLine(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Row(
      children: [
        Expanded(child: EcfLine(label, v ?? '—')),
        IconButton(
          tooltip: 'Copiar',
          visualDensity: VisualDensity.compact,
          onPressed: v == null
              ? null
              : () => Clipboard.setData(ClipboardData(text: v)),
          icon: const Icon(Icons.copy_outlined, size: 16),
        ),
      ],
    );
  }
}

/// Elige el XML que dio la DGII para que el proveedor lo firme.
class EcfSignDocumentDialog extends StatefulWidget {
  const EcfSignDocumentDialog({required this.kind, super.key});

  final EcfSignKind kind;

  @override
  State<EcfSignDocumentDialog> createState() => _EcfSignDocumentDialogState();
}

class _EcfSignDocumentDialogState extends State<EcfSignDocumentDialog> {
  EcfPickedFile? _file;
  String? _error;

  String get _help {
    switch (widget.kind) {
      case EcfSignKind.postulation:
        return 'La DGII lo genera al enviar la postulación en la Oficina '
            'Virtual. Firmado, se sube en la misma Oficina Virtual para '
            'activar el ambiente de certificación.';
      case EcfSignKind.declaration:
        return 'La DGII la entrega cuando aprueba el set de pruebas. '
            'Firmada, se sube a la Oficina Virtual.';
      case EcfSignKind.roles:
        return 'Solo si la DGII lo pide al asignar los roles al proveedor. '
            'Firmado, se sube a la Oficina Virtual.';
    }
  }

  Future<void> _pick() async {
    try {
      final picked = await FileIoHelper.pickXmlFile();
      if (picked == null || !mounted) return;
      if (!picked.name.toLowerCase().endsWith('.xml')) {
        setState(() => _error = 'Tiene que ser el archivo .xml de la DGII.');
        return;
      }
      if (picked.bytes.length > 2 * 1024 * 1024) {
        setState(
          () => _error =
              'Ese archivo pesa más de 2 MB: no parece un XML de la DGII.',
        );
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Firmar ${widget.kind.label.toLowerCase()}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EcfNote(color: AppTokens.mutedForeground, text: _help),
            const SizedBox(height: AppTokens.s14),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(_file == null ? 'Elegir XML' : _file!.name),
            ),
            const SizedBox(height: AppTokens.s8),
            const Text(
              'Se firma con el certificado que tu empresa tiene registrado '
              'con el proveedor.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTokens.mutedForeground,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppTokens.s10),
              EcfNote(color: AppTokens.destructive, text: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _file == null ? null : () => Navigator.pop(context, _file),
          child: const Text('Firmar'),
        ),
      ],
    );
  }
}

/// Resultado de la firma: el XML firmado para subirlo a la Oficina Virtual.
///
/// Si el servidor alcanzó a bajarlo, se descarga desde aquí. Si no, queda el
/// enlace del proveedor para copiarlo (esta app no abre enlaces externos).
class EcfSignedDocumentDialog extends StatelessWidget {
  const EcfSignedDocumentDialog({required this.document, super.key});

  final EcfSignedDocument document;

  String get _filename {
    final name = document.filename;
    if (name != null && name.isNotEmpty) return name;
    return 'firmado-${document.kind.code}.xml';
  }

  Future<void> _download(BuildContext context) async {
    try {
      final saved = await FileIoHelper.saveBytes(
        bytes: base64Decode(document.xmlBase64!),
        fileName: _filename,
        dialogTitle: 'Guardar XML firmado',
        extension: 'xml',
      );
      if (saved && context.mounted) {
        AppSnackBar.success(context, 'XML firmado descargado.');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, 'No se pudo descargar el XML', e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = document.url;
    final canDownload = document.xmlBase64 != null;
    return AlertDialog(
      title: Text('${document.kind.label} firmado'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EcfNote(
              color: AppTokens.primary,
              text: canDownload
                  ? 'Descárgalo y súbelo a la Oficina Virtual de la DGII.'
                  : 'Copia el enlace, ábrelo en el navegador para descargar '
                        'el XML y súbelo a la Oficina Virtual de la DGII. '
                        'Hazlo enseguida: el enlace puede vencer.',
            ),
            if (url != null) ...[
              const SizedBox(height: AppTokens.s12),
              SelectableText(
                url,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTokens.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (url != null)
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                AppSnackBar.info(context, 'Enlace copiado.');
              }
            },
            child: const Text('Copiar enlace'),
          ),
        if (canDownload)
          FilledButton.icon(
            onPressed: () => _download(context),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Descargar'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Listo'),
          ),
      ],
    );
  }
}

/// Lo que cuenta el portal de la DGII en "Estado actual de las pruebas de
/// simulación", en el mismo orden.
const ecfSimulationCategories = <String, String>{
  '31': 'Comprobantes tipo 31',
  '32': 'Comprobantes tipo 32 >= 250Mil',
  '33': 'Comprobantes tipo 33',
  '34': 'Comprobantes tipo 34',
  '41': 'Comprobantes tipo 41',
  '43': 'Comprobantes tipo 43',
  '44': 'Comprobantes tipo 44',
  '45': 'Comprobantes tipo 45',
  '46': 'Comprobantes tipo 46',
  '47': 'Comprobantes tipo 47',
  '32rfce': 'Comprobantes tipo 32 RFCE',
};

/// Cuántos e-CF de cada tipo generar para la simulación: los que dice el
/// portal ("0/1 Comprobantes tipo 31"…). Arranca en 1, que es lo que pide al
/// reiniciar; el tope es lo que trae el set de datos para usar de modelo.
class EcfSimulationCountsDialog extends StatefulWidget {
  const EcfSimulationCountsDialog({required this.available, super.key});

  /// Modelos disponibles por categoría (del set de datos ya aceptado). Vacío
  /// si no se cargó: el servidor usa el set genérico de la DGII y valida.
  final Map<String, int> available;

  @override
  State<EcfSimulationCountsDialog> createState() =>
      _EcfSimulationCountsDialogState();
}

class _EcfSimulationCountsDialogState extends State<EcfSimulationCountsDialog> {
  bool get _knowsAvailable => widget.available.isNotEmpty;

  bool _offers(String key) =>
      !_knowsAvailable || (widget.available[key] ?? 0) > 0;

  late final Map<String, TextEditingController> _fields = {
    for (final k in ecfSimulationCategories.keys)
      k: TextEditingController(text: _offers(k) ? '1' : '0'),
  };
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final counts = <String, int>{};
    for (final e in _fields.entries) {
      final n = int.tryParse(e.value.text.trim()) ?? 0;
      final max = widget.available[e.key] ?? 0;
      if (_knowsAvailable && n > max) {
        setState(
          () => _error =
              '${ecfSimulationCategories[e.key]}: el set de datos solo trae '
              '$max para usar de modelo.',
        );
        return;
      }
      if (n > 0) counts[e.key] = n;
    }
    if (counts.isEmpty) {
      setState(
        () => _error = 'Pon cuántos pide el portal de al menos un tipo.',
      );
      return;
    }
    Navigator.pop(context, counts);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generar la simulación'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfNote(
                color: AppTokens.mutedForeground,
                text:
                    'Copia lo que pide el portal en "Estado actual de las '
                    'pruebas de simulación" (el número de la derecha: 0/1 → '
                    '1). Se arman con el set de datos ya aceptado, los datos '
                    'de tu empresa, fecha de hoy y e-NCF nuevos. Las notas de '
                    'crédito y débito van con una factura de esta tanda.',
              ),
              const SizedBox(height: AppTokens.s12),
              Wrap(
                spacing: AppTokens.s10,
                runSpacing: AppTokens.s4,
                children: [
                  for (final e in ecfSimulationCategories.entries)
                    SizedBox(
                      width: 240,
                      child: TextField(
                        key: ValueKey('sim-count-${e.key}'),
                        controller: _fields[e.key],
                        enabled: _offers(e.key),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: e.value,
                          helperText: _knowsAvailable
                              ? 'máx. ${widget.available[e.key] ?? 0}'
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.s10),
                EcfNote(color: AppTokens.destructive, text: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Generar')),
      ],
    );
  }
}

/// Nombre de cada tipo de e-CF del set de pruebas.
const ecfTestTypeLabels = <String, String>{
  '31': 'Crédito fiscal',
  '32': 'Consumo',
  '33': 'Nota de débito',
  '34': 'Nota de crédito',
  '41': 'Compras',
  '43': 'Gastos menores',
  '44': 'Regímenes especiales',
  '45': 'Gubernamental',
  '46': 'Exportaciones',
  '47': 'Pagos al exterior',
};

/// Los comprobantes del set con lo que respondió la DGII.
class EcfTestSetDialog extends StatelessWidget {
  const EcfTestSetDialog({
    required this.testSet,
    required this.onDownload,
    this.onPrint,
    super.key,
  });

  final EcfTestSet testSet;

  /// Descarga el XML firmado de un caso (lo hace la página: usa el repo).
  final Future<void> Function(EcfTestCase c) onDownload;

  /// Descarga la representación impresa (PDF). Solo para e-CF, no para
  /// aprobaciones comerciales.
  final Future<void> Function(EcfTestCase c)? onPrint;

  Color _statusColor(EcfTestCase c) {
    switch (c.status) {
      case 'accepted':
        return AppTokens.success;
      case 'conditional':
      case 'sent':
        return AppTokens.warning;
      case 'rejected':
      case 'error':
        return AppTokens.destructive;
      default:
        return AppTokens.mutedForeground;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaries = testSet.cases.where((c) => c.isSummary).toList();
    return AlertDialog(
      title: Text(
        testSet.filename ??
            (testSet.isSimulation ? 'Simulación e-CF' : 'Set de pruebas'),
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (summaries.isNotEmpty) ...[
                EcfNote(
                  color: AppTokens.mutedForeground,
                  text:
                      'Las facturas de consumo menores de RD\$250 mil '
                      '(${summaries.map((c) => c.encf).join(', ')}) van a la '
                      'DGII como resumen. Cuando el resumen quede aceptado, '
                      'descarga su XML y súbelo en "Facturas de consumo < '
                      '250Mil" del portal de certificación.',
                ),
                const SizedBox(height: AppTokens.s12),
              ],
              for (final c in testSet.cases)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppTokens.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.encf} · '
                              '${ecfTestTypeLabels[c.ecfType] ?? 'E${c.ecfType}'}'
                              '${c.isSummary ? ' · resumen' : ''}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (c.total != null) money(c.total),
                                if (c.modifies != null)
                                  'modifica ${c.modifies}',
                                if (c.securityCode != null && c.isSummary)
                                  'código ${c.securityCode}',
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTokens.mutedForeground,
                              ),
                            ),
                            for (final m in c.messages)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: SelectableText(
                                  '${m.code != null ? '[${m.code}] ' : ''}'
                                  '${m.message}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.3,
                                    color: _statusColor(c),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppTokens.s10),
                      Text(
                        c.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(c),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Descargar XML firmado',
                        visualDensity: VisualDensity.compact,
                        onPressed: c.hasXml ? () => onDownload(c) : null,
                        icon: const Icon(Icons.download, size: 18),
                      ),
                      if (onPrint != null && !c.isApproval)
                        IconButton(
                          tooltip: 'Representación impresa (PDF)',
                          visualDensity: VisualDensity.compact,
                          onPressed: c.hasXml ? () => onPrint!(c) : null,
                          icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas compartidas con la página
// ---------------------------------------------------------------------------

class EcfLine extends StatelessWidget {
  const EcfLine(this.label, this.value, {this.valueColor, super.key});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTokens.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EcfNote extends StatelessWidget {
  const EcfNote({required this.color, required this.text, super.key});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.42, color: color),
      ),
    );
  }
}
