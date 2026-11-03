import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/ecf_onboarding_models.dart';
import '../data/ecf_onboarding_repository.dart';
import '../data/ecf_request_repository.dart';
import '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SettingsRepository(client);
});

final settingsDataProvider = FutureProvider<SettingsData>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.fetchSettings();
});

final businessProfileProvider =
    FutureProvider<BusinessProfile?>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.fetchBusinessProfile();
});

/// Config e-CF (facturación electrónica) de la empresa actual. Null si la
/// empresa nunca la ha configurado (modalidad física por defecto).
final companyEcfSettingsProvider =
    FutureProvider<CompanyEcfSettings?>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.fetchCompanyEcfSettings();
});

/// Solicitud de facturación electrónica de la empresa: en qué etapa va, con
/// qué datos y con qué secuencias e-NCF.
///
/// Va contra la Edge Function `ecf-onboarding` y no contra una tabla: la
/// etapa se DERIVA en el servidor de lo que ya existe (empresa registrada,
/// certificación, secuencias, modalidad). Un estado guardado aparte se
/// desincroniza.
final ecfRequestRepositoryProvider = Provider<EcfRequestRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return EcfRequestRepository(client);
});

final ecfRequestStatusProvider = FutureProvider<EcfRequestStatus>((ref) async {
  final repository = ref.watch(ecfRequestRepositoryProvider);
  return repository.status();
});

/// El trámite paso a paso (Configuración → Facturación electrónica). Misma
/// Edge Function que la solicitud.
final ecfOnboardingRepositoryProvider = Provider<EcfOnboardingRepository>((
  ref,
) {
  return EcfOnboardingRepository(ref.watch(ecfRequestRepositoryProvider));
});

/// Todo lo que pinta la página del trámite. Sin secretos: el certificado, la
/// clave de la Oficina Virtual y la sesión con la DGII nunca vienen aquí.
/// autoDispose: al volver a la página se lee de nuevo (lo que se hizo desde
/// la tarjeta, o la DGII respondiendo, no queda viejo en caché).
final ecfOnboardingStatusProvider =
    FutureProvider.autoDispose<EcfOnboardingStatus>((ref) async {
  return ref.watch(ecfOnboardingRepositoryProvider).status();
});
