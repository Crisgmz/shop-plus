import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/session_refresher.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Crea cuenta + empresa nueva en un solo flujo (Fase 2 multi-tenant):
  ///   1) `auth.signUp` — crea el usuario en Supabase.
  ///   2) Si Supabase devolvió sesión (email-confirm OFF), llama al RPC
  ///      `bootstrap_new_company` que crea atomicamente company, sucursal,
  ///      profile (admin) y app_settings.
  ///   3) Si la sesión no viene en signUp (email-confirm ON), se devuelve
  ///      `needsEmailConfirmation = true` y el bootstrap queda para cuando
  ///      el usuario confirme y haga login por primera vez.
  Future<SignUpResult> signUpAndBootstrap({
    required String email,
    required String password,
    required String companyName,
    String? fullName,
    String? phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw Exception('No se pudo crear la cuenta.');
    }

    // Si Supabase no devolvió sesión, el email-confirm está activo.
    if (response.session == null) {
      return SignUpResult(needsEmailConfirmation: true);
    }

    try {
      await _client.rpc(
        'bootstrap_new_company',
        params: {
          'p_company_name': companyName,
          'p_full_name': fullName,
          'p_phone': phone,
        },
      );
    } catch (e) {
      // Si el bootstrap falla, dejamos al usuario logueado pero sin company.
      // El router lo va a mandar a /onboarding cuando detecte que falta el
      // profile.
      rethrow;
    }
    return SignUpResult(needsEmailConfirmation: false);
  }

  /// Llama al RPC bootstrap. Se usa cuando el usuario ya tenía sesión
  /// (email-confirm OFF entró directamente, o vuelve a entrar después de
  /// confirmar email).
  Future<void> bootstrapCompany({
    required String companyName,
    String? fullName,
    String? phone,
  }) async {
    await _client.rpc(
      'bootstrap_new_company',
      params: {
        'p_company_name': companyName,
        'p_full_name': fullName,
        'p_phone': phone,
      },
    );
  }

  /// Cierra sesión evitando que un refresh de token en vuelo "resucite" al
  /// usuario anterior: gotrue 2.18 guarda la sesión refrescada aunque ya se
  /// haya hecho signOut mientras esperaba la respuesta de red.
  Future<void> signOut() async {
    final refresher = SessionRefresher.instance;
    await refresher.suspend();
    _client.auth.stopAutoRefresh();
    try {
      await _client.auth.signOut();
      // Un refresh interno del SDK pudo terminar durante la llamada de red
      // del logout y restaurar la sesión: cerrarla de nuevo.
      if (_client.auth.currentSession != null) {
        await _client.auth.signOut();
      }
    } finally {
      _client.auth.startAutoRefresh();
      refresher.resume();
    }
  }
}

class SignUpResult {
  const SignUpResult({required this.needsEmailConfirmation});
  final bool needsEmailConfirmation;
}
