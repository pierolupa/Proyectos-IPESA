import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

class IpesaGuiasApp extends StatelessWidget {
  const IpesaGuiasApp({super.key, this.appState});

  /// Inyectable para tests; en la app real se crea uno propio.
  final AppState? appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => appState ?? AppState(),
      child: MaterialApp(
        title: 'IPESA · Tracking Distribución',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // Calendarios y textos de Material (p. ej. el selector de fechas
        // del rastreo) en español.
        locale: const Locale('es', 'PE'),
        supportedLocales: const [Locale('es', 'PE'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const LoginScreen(),
      ),
    );
  }
}
