import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'state/app_state.dart';

class IpesaGuiasApp extends StatelessWidget {
  const IpesaGuiasApp({super.key, this.appState});

  /// Inyectable para tests; en la app real se crea uno propio.
  final AppState? appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => appState ?? AppState(),
      child: MaterialApp(
        title: 'IPESA · Control de Guías',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
