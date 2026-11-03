import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/ecf_request_repository.dart';
import 'settings_providers.dart';

/// Formulario con el que el dueño solicita la facturación electrónica.
///
/// Portado de mangospos (`ecf_request_dialog.dart`). Pide lo que el proveedor
/// necesita para dar de alta la empresa ante la DGII (los datos del
/// contribuyente tal como están en el RNC y el certificado de firma digital
/// con su contraseña) y lo que necesita quien hace la certificación: teléfono,
/// representante legal, sucursales, tipos de comprobante y usuario de la
/// Oficina Virtual.
///
/// El certificado viaja al proveedor en la misma petición. Si el cliente lo
/// autoriza, además se guarda CIFRADO para firmar las pruebas de la DGII desde
/// Configuración → Facturación electrónica; si no, se descarta. La clave de la
/// Oficina Virtual es opcional y también se guarda cifrada. Eso se le dice al
/// usuario en la pantalla, no solo en el código.
class EcfRequestDialog extends ConsumerStatefulWidget {
  const EcfRequestDialog({super.key, required this.status});

  final EcfRequestStatus status;

  static Future<bool?> show(BuildContext context, EcfRequestStatus status) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EcfRequestDialog(status: status),
    );
  }

  @override
  ConsumerState<EcfRequestDialog> createState() => _EcfRequestDialogState();
}

class _EcfRequestDialogState extends ConsumerState<EcfRequestDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _rnc;
  late final TextEditingController _legalName;
  late final TextEditingController _tradeName;
  late final TextEditingController _address;
  late final TextEditingController _province;
  late final TextEditingController _municipality;
  late final TextEditingController _email;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _phone;
  late final TextEditingController _legalRep;
  late final TextEditingController _ofvUser;
  final _certPassword = TextEditingController();
  final _ofvPassword = TextEditingController();
  late final List<_BranchFields> _branches;
  late final Set<String> _types;

  bool _alreadyAuthorized = false;
  bool _acceptTerms = false;
  bool _storeCertificate = false;
  bool _sending = false;
  bool _showPassword = false;
  bool _showOfvPassword = false;

  ({Uint8List bytes, String name})? _certificate;

  @override
  void initState() {
    super.initState();
    final d = widget.status.data;
    _rnc = TextEditingController(text: d.rnc ?? '');
    _legalName = TextEditingController(text: d.legalName ?? '');
    _tradeName = TextEditingController(text: d.tradeName ?? '');
    _address = TextEditingController(text: d.fiscalAddress ?? '');
    _province = TextEditingController(text: d.province ?? '');
    _municipality = TextEditingController(text: d.municipality ?? '');
    _email = TextEditingController(text: d.email ?? '');
    _contactName = TextEditingController(text: widget.status.contactName ?? '');
    _contactPhone = TextEditingController(
      text: widget.status.contactPhone ?? '',
    );
    _alreadyAuthorized = widget.status.alreadyAuthorized ?? false;
    final x = widget.status.details;
    _phone = TextEditingController(text: x.phone ?? '');
    _legalRep = TextEditingController(text: x.legalRepName ?? '');
    // El usuario de la OFV casi siempre es el RNC: se sugiere, no se impone.
    _ofvUser = TextEditingController(text: x.ofvUser ?? d.rnc ?? '');
    _branches = [
      for (final b in x.branches)
        _BranchFields(name: b.name, address: b.address),
    ];
    _types = x.ecfTypes.where(emittableEcfTypes.contains).toSet();
  }

  @override
  void dispose() {
    for (final c in [
      _rnc,
      _legalName,
      _tradeName,
      _address,
      _province,
      _municipality,
      _email,
      _contactName,
      _contactPhone,
      _phone,
      _legalRep,
      _ofvUser,
      _certPassword,
      _ofvPassword,
    ]) {
      c.dispose();
    }
    for (final b in _branches) {
      b.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solicitar facturación electrónica'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Estos datos tienen que estar tal como los tiene la DGII en '
                  'tu RNC. Si algo no coincide, el proveedor rechaza el alta.',
                  style: TextStyle(color: AppTokens.mutedForeground),
                ),
                const SizedBox(height: AppTokens.s16),

                _section('Datos del contribuyente'),
                _field(
                  controller: _rnc,
                  label: 'RNC o cédula',
                  hint: '131974602',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.isEmpty) return 'Falta el RNC.';
                    if (digits.length != 9 && digits.length != 11) {
                      return 'El RNC lleva 9 dígitos y la cédula 11.';
                    }
                    return null;
                  },
                ),
                _field(
                  controller: _legalName,
                  label: 'Razón social',
                  hint: 'Como aparece en el RNC',
                  validator: _required('Falta la razón social.'),
                ),
                _field(
                  controller: _tradeName,
                  label: 'Nombre comercial',
                  hint: 'El nombre con el que te conocen',
                  validator: _required('Falta el nombre comercial.'),
                ),
                _field(
                  controller: _address,
                  label: 'Domicilio fiscal',
                  hint: 'El registrado en la DGII',
                  maxLength: 100,
                  validator: _required('Falta el domicilio fiscal.'),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        controller: _province,
                        label: 'Provincia',
                        hint: 'Santo Domingo',
                        validator: _required('Falta la provincia.'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s12),
                    Expanded(
                      child: _field(
                        controller: _municipality,
                        label: 'Municipio',
                        hint: 'Santo Domingo Norte',
                        validator: _required('Falta el municipio.'),
                      ),
                    ),
                  ],
                ),
                _field(
                  controller: _email,
                  label: 'Correo para los comprobantes',
                  hint: 'facturacion@empresa.com',
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 80,
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Falta el correo.';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                      return 'Ese correo no parece válido.';
                    }
                    return null;
                  },
                ),
                _field(
                  controller: _phone,
                  label: 'Teléfono de la empresa',
                  hint: '809-555-1234',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.isEmpty) {
                      return 'Falta el teléfono de la empresa.';
                    }
                    if (digits.length < 10 || digits.length > 15) {
                      return 'Incluye el código de área.';
                    }
                    return null;
                  },
                ),
                _field(
                  controller: _legalRep,
                  label: 'Representante legal',
                  hint: 'Nombre completo, como ante la DGII',
                  maxLength: 120,
                  validator: _required('Falta el representante legal.'),
                ),

                const SizedBox(height: AppTokens.s8),
                _section('Sucursales'),
                const Text(
                  'Cada local donde vas a facturar, con su dirección.',
                  style: TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                for (final b in _branches) _branchRow(b),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _sending
                        ? null
                        : () => setState(() => _branches.add(_BranchFields())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar sucursal'),
                  ),
                ),

                const SizedBox(height: AppTokens.s8),
                _section('Comprobantes que vas a usar'),
                Wrap(
                  spacing: AppTokens.s8,
                  runSpacing: AppTokens.s8,
                  children: [
                    for (final t in emittableEcfTypes)
                      FilterChip(
                        label: Text('$t · ${ecfTypeLabels[t]}'),
                        selected: _types.contains(t),
                        onSelected: _sending
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  _types.add(t);
                                } else {
                                  _types.remove(t);
                                }
                              }),
                      ),
                  ],
                ),

                const SizedBox(height: AppTokens.s16),
                _section('Oficina Virtual de la DGII'),
                _field(
                  controller: _ofvUser,
                  label: 'Usuario',
                  hint: 'Casi siempre es tu RNC o cédula',
                  maxLength: 60,
                  validator: _required(
                    'Falta el usuario de la Oficina Virtual.',
                  ),
                ),
                TextFormField(
                  controller: _ofvPassword,
                  obscureText: !_showOfvPassword,
                  decoration: InputDecoration(
                    labelText: widget.status.details.ofvPasswordSaved
                        ? 'Clave de la Oficina Virtual (ya guardada)'
                        : 'Clave de la Oficina Virtual (opcional)',
                    helperText: widget.status.details.ofvPasswordSaved
                        ? 'Déjala en blanco para conservar la que guardaste.'
                        : 'Se guarda cifrada. Solo un administrador de tu '
                              'empresa la puede volver a ver.',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _showOfvPassword = !_showOfvPassword,
                      ),
                      icon: Icon(
                        _showOfvPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppTokens.s16),
                _section('Con quién coordinamos'),
                _field(
                  controller: _contactName,
                  label: 'Nombre de contacto',
                  hint: 'Quien atiende el proceso ante la DGII',
                  maxLength: 80,
                  validator: _required('Falta el nombre de contacto.'),
                ),
                _field(
                  controller: _contactPhone,
                  label: 'Teléfono de contacto',
                  hint: '809-555-1234',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.isEmpty) return 'Falta el teléfono.';
                    if (digits.length < 10) {
                      return 'El teléfono lleva 10 dígitos.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppTokens.s8),
                _section('Certificado de firma digital'),
                const Text(
                  'Es el archivo .p12 que te entregó la entidad certificadora '
                  '(Avansi, Camarasoft…). Se envía al proveedor para firmar '
                  'tus comprobantes.',
                  style: TextStyle(
                    color: AppTokens.mutedForeground,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppTokens.s8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _sending ? null : _pickCertificate,
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(
                        _certificate == null
                            ? 'Elegir certificado'
                            : 'Cambiar archivo',
                      ),
                    ),
                    const SizedBox(width: AppTokens.s12),
                    Expanded(
                      child: Text(
                        _certificate?.name ?? 'Ningún archivo elegido',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _certificate == null
                              ? AppTokens.mutedForeground
                              : AppTokens.foreground,
                          fontWeight: _certificate == null
                              ? FontWeight.normal
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s12),
                TextFormField(
                  controller: _certPassword,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña del certificado',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Falta la contraseña.' : null,
                ),

                const SizedBox(height: AppTokens.s16),
                CheckboxListTile(
                  value: _alreadyAuthorized,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _alreadyAuthorized = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ya soy emisor electrónico autorizado por la DGII',
                  ),
                  subtitle: const Text(
                    'Si no lo eres, te acompañamos en el trámite.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                CheckboxListTile(
                  value: _acceptTerms,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _acceptTerms = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Autorizo a registrar mi certificado con el proveedor de '
                    'facturación electrónica',
                  ),
                ),
                CheckboxListTile(
                  value: _storeCertificate,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _storeCertificate = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Autorizo guardar mi certificado cifrado para firmar las '
                    'pruebas de la DGII',
                  ),
                  subtitle: const Text(
                    'Lo necesitas si vas a hacer la certificación desde aquí. '
                    'Si no lo autorizas, se te pedirá cada vez que firmes.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined, size: 18),
          label: Text(_sending ? 'Enviando...' : 'Enviar solicitud'),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.s8),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppTokens.foreground,
      ),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
        ),
        validator: validator,
      ),
    );
  }

  String? Function(String?) _required(String message) =>
      (v) => (v ?? '').trim().isEmpty ? message : null;

  Widget _branchRow(_BranchFields b) {
    return Row(
      key: ObjectKey(b),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _field(controller: b.name, label: 'Nombre', maxLength: 80),
        ),
        const SizedBox(width: AppTokens.s12),
        Expanded(
          flex: 3,
          child: _field(
            controller: b.address,
            label: 'Dirección',
            maxLength: 150,
            // Una fila con nombre y sin dirección no le sirve a la DGII; una
            // fila vacía se ignora.
            validator: (v) =>
                (v ?? '').trim().isEmpty && b.name.text.trim().isNotEmpty
                    ? 'Falta la dirección.'
                    : null,
          ),
        ),
        IconButton(
          tooltip: 'Quitar sucursal',
          onPressed: _sending ? null : () => _removeBranch(b),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }

  void _removeBranch(_BranchFields b) {
    setState(() => _branches.remove(b));
    // Sus campos siguen montados hasta el próximo frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => b.dispose());
  }

  Future<void> _pickCertificate() async {
    final picked = await FileIoHelper.pickCertificateFile();
    if (picked == null || !mounted) return;
    // Un .p12 de firma no pasa de 100 KB; el servidor lo rechaza igual, pero
    // avisar acá evita subir un PDF y esperar el viaje de ida y vuelta.
    if (picked.bytes.length > 100 * 1024) {
      AppSnackBar.error(
        context,
        'Ese archivo pesa ${(picked.bytes.length / 1024).round()} KB. Un '
        'certificado .p12 no pasa de 100 KB: revisa que sea el archivo '
        'correcto.',
      );
      return;
    }
    setState(() => _certificate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_types.isEmpty) {
      AppSnackBar.error(context, 'Elige al menos un tipo de comprobante.');
      return;
    }
    if (_certificate == null) {
      AppSnackBar.error(context, 'Falta elegir el certificado .p12.');
      return;
    }
    if (!_acceptTerms) {
      AppSnackBar.error(
        context,
        'Falta autorizar el registro de tu certificado con el proveedor.',
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await ref
          .read(ecfRequestRepositoryProvider)
          .submit(
            EcfRequestSubmission(
              data: EcfRequestData(
                rnc: _rnc.text.trim(),
                legalName: _legalName.text.trim(),
                tradeName: _tradeName.text.trim(),
                fiscalAddress: _address.text.trim(),
                province: _province.text.trim(),
                municipality: _municipality.text.trim(),
                email: _email.text.trim(),
              ),
              details: EcfRequestDetails(
                phone: _phone.text.trim(),
                legalRepName: _legalRep.text.trim(),
                branches: [
                  for (final b in _branches)
                    if (b.address.text.trim().isNotEmpty)
                      EcfRequestBranch(
                        name: b.name.text.trim().isEmpty
                            ? null
                            : b.name.text.trim(),
                        address: b.address.text.trim(),
                      ),
                ],
                // En el orden del catálogo, no en el que se tocaron.
                ecfTypes: emittableEcfTypes.where(_types.contains).toList(),
                ofvUser: _ofvUser.text.trim(),
                ofvPassword: _ofvPassword.text.isEmpty
                    ? null
                    : _ofvPassword.text,
              ),
              contactName: _contactName.text.trim(),
              contactPhone: _contactPhone.text.trim(),
              alreadyAuthorized: _alreadyAuthorized,
              certificateFilename: _certificate!.name,
              certificateBytes: _certificate!.bytes,
              certificatePassword: _certPassword.text,
              acceptCertificateStorage: _storeCertificate,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppSnackBar.success(
        context,
        result.message ??
            (result.companyRegistered
                ? 'Solicitud enviada. Tu empresa quedó registrada con el proveedor.'
                : 'Solicitud enviada. Te vamos a contactar.'),
      );
    } on EcfRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'No se pudo enviar', e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _BranchFields {
  _BranchFields({String? name, String? address})
    : name = TextEditingController(text: name ?? ''),
      address = TextEditingController(text: address ?? '');

  final TextEditingController name;
  final TextEditingController address;

  void dispose() {
    name.dispose();
    address.dispose();
  }
}
