import 'package:flutter/material.dart';

/// Diálogo que pregunta al usuario si desea migrar datos locales a Firestore
class MigracionDialog extends StatelessWidget {
  final int cantidadRecordatorios;

  const MigracionDialog({super.key, required this.cantidadRecordatorios});

  static Future<bool?> mostrar(
    BuildContext context, {
    required int cantidadRecordatorios,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          MigracionDialog(cantidadRecordatorios: cantidadRecordatorios),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.cloud_upload_rounded,
        size: 48,
        color: Colors.blueAccent,
      ),
      title: const Text('Respaldo en la nube'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tienes $cantidadRecordatorios recordatorio${cantidadRecordatorios == 1 ? '' : 's'} '
            'guardado${cantidadRecordatorios == 1 ? '' : 's'} localmente.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            '¿Te gustaría guardarlos en la nube para que no se pierdan?',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Tus datos también se mantendrán en tu almacenamiento local.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ahora no'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Migrar datos'),
        ),
      ],
    );
  }
}

/// Diálogo de progreso de migración
class MigracionProgressDialog extends StatelessWidget {
  const MigracionProgressDialog({super.key});

  static void mostrar(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MigracionProgressDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Migrando datos a la nube...', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Diálogo de advertencia de almacenamiento casi lleno
class AlmacenamientoWarningDialog extends StatelessWidget {
  final int cantidadDocumentos;

  const AlmacenamientoWarningDialog({
    super.key,
    required this.cantidadDocumentos,
  });

  static Future<String?> mostrar(
    BuildContext context, {
    required int cantidadDocumentos,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) =>
          AlmacenamientoWarningDialog(cantidadDocumentos: cantidadDocumentos),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        size: 48,
        color: Colors.orange,
      ),
      title: const Text('Almacenamiento casi lleno'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tienes $cantidadDocumentos registros en la nube.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'El almacenamiento está a punto de llenarse en la base de datos.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '¿Deseas eliminar datos de la nube o continuar? '
            'Tus datos seguirán guardados en tu almacenamiento local.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('continuar'),
          child: const Text('Continuar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop('eliminar'),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar de la nube'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
        ),
      ],
    );
  }
}
