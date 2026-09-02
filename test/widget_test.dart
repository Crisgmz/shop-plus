import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_app/app/app.dart';

void main() {
  // `Supabase.initialize` guarda la sesión en shared_preferences, que en un
  // test no tiene implementación de plataforma: sin este mock el setUpAll
  // falla con MissingPluginException(getAll) y toda la suite se cae.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test-anon-key',
      );
    } catch (_) {
      // Ignore if already initialized by another test.
    }
  });

  testWidgets('shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ShopPlusApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Inicia sesión para continuar'), findsOneWidget);
  });
}
