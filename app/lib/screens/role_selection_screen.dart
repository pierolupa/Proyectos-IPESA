import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rol_usuario.dart';
import '../state/app_state.dart';
import 'login_screen.dart';
import 'tracking/public_tracking_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _entrar(BuildContext context, RolUsuario rol) {
    if (rol == RolUsuario.comercial) {
      context.read<AppState>().entrarComoComercial();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PublicTrackingScreen()),
      );
      return;
    }
    // Transportista y Administrador comparten la misma pantalla de login;
    // a dónde se navega después depende del rol real que devuelva el
    // backend, no del botón que se tocó aquí.
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_shipping, size: 56, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'IPESA · Control de Guías',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Conectado a Google Sheets en vivo.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              Text(
                'Ingresa como:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final rol in RolUsuario.values) ...[
                _RolTile(rol: rol, onTap: () => _entrar(context, rol)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RolTile extends StatelessWidget {
  const _RolTile({required this.rol, required this.onTap});

  final RolUsuario rol;
  final VoidCallback onTap;

  IconData get _icono => switch (rol) {
    RolUsuario.transportista => Icons.two_wheeler,
    RolUsuario.administrador => Icons.admin_panel_settings,
    RolUsuario.comercial => Icons.search,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        onTap: onTap,
        leading: Icon(_icono, color: Colors.blue),
        title: Text(
          rol.etiqueta,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(rol.descripcion),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
