import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/role_selection_screen.dart';
import 'state/app_state.dart';

class IpesaGuiasApp extends StatelessWidget {
  const IpesaGuiasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'IPESA · Control de Guías',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const RoleSelectionScreen(),
      ),
    );
  }
}
