import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/tipo_entrega.dart';

/// Nombre del transportista "logueado" en este scaffold de demostración.
const transportistaActualDemo = 'Juan Pérez';

List<Guia> guiasIniciales() {
  final ahora = DateTime.now();
  return [
    Guia(
      numeroGuia: 'IPE-2026-004821',
      estado: EstadoGuia.enRuta,
      tipoEntrega: TipoEntrega.clienteFinal,
      origen: 'Almacén Callao',
      destino: 'Av. La Marina 1450, San Miguel',
      transportista: transportistaActualDemo,
      destinatario: 'María Torres',
      fechaActualizacion: ahora.subtract(const Duration(hours: 1)),
    ),
    Guia(
      numeroGuia: 'IPE-2026-004822',
      estado: EstadoGuia.enRuta,
      tipoEntrega: TipoEntrega.agencia,
      origen: 'Almacén Callao',
      destino: 'Agencia Shalom Surco',
      transportista: transportistaActualDemo,
      destinatario: 'Agencia Shalom',
      fechaActualizacion: ahora.subtract(const Duration(hours: 2)),
    ),
    Guia(
      numeroGuia: 'IPE-2026-004790',
      estado: EstadoGuia.enProcesoTrasbordo,
      tipoEntrega: TipoEntrega.entreSucursales,
      origen: 'Almacén Callao',
      destino: 'Sucursal Ate',
      transportista: transportistaActualDemo,
      destinatario: 'Sucursal Ate',
      fechaActualizacion: ahora.subtract(const Duration(hours: 3)),
    ),
    Guia(
      numeroGuia: 'IPE-2026-004780',
      estado: EstadoGuia.recepcionSucursal,
      tipoEntrega: TipoEntrega.entreSucursales,
      origen: 'Almacén Callao',
      destino: 'Sucursal Ate',
      transportista: 'Luis Ramírez',
      destinatario: 'Sucursal Ate',
      fechaActualizacion: ahora.subtract(const Duration(hours: 5)),
    ),
    Guia(
      numeroGuia: 'IPE-2026-004750',
      estado: EstadoGuia.entregado,
      tipoEntrega: TipoEntrega.clienteFinal,
      origen: 'Almacén Callao',
      destino: 'Jr. Lampa 800, Lima',
      transportista: 'Luis Ramírez',
      destinatario: 'Carlos Díaz',
      fechaActualizacion: ahora.subtract(const Duration(days: 1)),
    ),
    Guia(
      numeroGuia: 'IPE-2026-004711',
      estado: EstadoGuia.finalizado,
      tipoEntrega: TipoEntrega.agencia,
      origen: 'Almacén Callao',
      destino: 'Agencia Olva Ate',
      transportista: 'Juan Pérez',
      destinatario: 'Agencia Olva',
      fechaActualizacion: ahora.subtract(const Duration(days: 2)),
    ),
    Guia(
      numeroGuia: 'IPE-2026-004699',
      estado: EstadoGuia.entregado,
      tipoEntrega: TipoEntrega.clienteFinal,
      origen: 'Almacén Callao',
      destino: 'Av. Javier Prado 3200, La Molina',
      transportista: 'Rosa Alvarado',
      destinatario: 'Fernando Quispe',
      fechaActualizacion: ahora.subtract(const Duration(days: 3)),
      corregidoPorAdmin: true,
    ),
  ];
}
