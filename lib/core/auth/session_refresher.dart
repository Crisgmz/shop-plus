import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mantiene la sesión de Supabase viva cuando la app vuelve al foreground.
///
/// Problema que arregla: en Flutter web, si la pestaña queda en background
/// mucho tiempo el browser throttlea los setTimeout del SDK y el JWT
/// expira sin que el auto-refresh se dispare. Al volver, cualquier query
/// falla con `PGRST303 JWT expired`.
///
/// Solución: escucha [AppLifecycleState.resumed] y dispara
/// `refreshSession()`. Si el refresh falla (refresh token expirado o
/// sesión revocada), el SDK emite `signedOut` y el router redirige a
/// /login automáticamente.
///
/// También revalida cada 4 minutos mientras la app está activa para
/// adelantar el fallo de refresh — los JWT de Supabase suelen durar
/// 3600s (1h), así que cualquier ventana < 1h alcanza. Solo refresca si
/// al token le quedan menos de [_refreshThreshold]: forzar un refresh en
/// cada resume abría una carrera con el logout (ver [suspend]).
class SessionRefresher with WidgetsBindingObserver {
  SessionRefresher._();
  static final SessionRefresher instance = SessionRefresher._();

  Timer? _periodicTimer;
  bool _started = false;
  bool _suspended = false;
  Future<void>? _inFlight;

  static const _periodicInterval = Duration(minutes: 4);
  static const _refreshThreshold = Duration(minutes: 10);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _periodicTimer = Timer.periodic(_periodicInterval, (_) => _refreshIfActive());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Pausa los refresh y espera el que esté en vuelo. Se llama ANTES de
  /// `signOut`: con gotrue 2.18 un refresh que termina después del signOut
  /// vuelve a guardar la sesión vieja (`tokenRefreshed`) y el usuario
  /// anterior "reaparece" (el router lo manda de vuelta al panel y, en web,
  /// la sesión queda persistida en localStorage para el reload).
  Future<void> suspend() async {
    _suspended = true;
    final pending = _inFlight;
    if (pending != null) await pending;
  }

  void resume() => _suspended = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfActive();
    }
  }

  Future<void> _refreshIfActive() {
    if (_suspended) return Future.value();
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  Future<void> _refresh() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return;
    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      if (expiry.difference(DateTime.now()) > _refreshThreshold) return;
    }
    try {
      await client.auth.refreshSession();
    } catch (e) {
      // Refresh token caducó o fue revocado — el SDK ya emitió signedOut
      // y el router redirige a /login. Solo logueamos para diagnóstico.
      if (kDebugMode) debugPrint('SessionRefresher: refresh falló: $e');
    }
  }
}
