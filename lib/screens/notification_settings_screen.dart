import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notification_settings.dart';
import '../services/storage_service.dart';
import '../utils/theme.dart';
import '../widgets/custom_app_bar.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late NotificationSettings _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final storageService = context.read<StorageService>();
      final settings = await storageService.getNotificationSettings();
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error cargando configuración: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final storageService = context.read<StorageService>();
      await storageService.saveNotificationSettings(_settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configuración guardada'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error guardando configuración: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al guardar'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Configuración de Sonidos'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(title: 'Configuración de Sonidos'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sección: Habilitar Sonido
          Card(
            color: AppTheme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🔔 Habilitar Sonido',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: _settings.enableSound,
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings.copyWith(enableSound: value);
                          });
                          _saveSettings();
                        },
                        activeColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _settings.enableSound
                        ? 'Las notificaciones sonarán'
                        : 'Las notificaciones serán silenciosas',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sección: Habilitar Vibración
          Card(
            color: AppTheme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '📳 Habilitar Vibración',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: _settings.enableVibration,
                        onChanged: (value) {
                          setState(() {
                            _settings =
                                _settings.copyWith(enableVibration: value);
                          });
                          _saveSettings();
                        },
                        activeColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _settings.enableVibration
                        ? 'Las notificaciones vibrarán'
                        : 'Las notificaciones no vibrarán',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sección: Tono de Notificación
          Card(
            color: AppTheme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎵 Tono de Notificación',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tono seleccionado: ${_settings.selectedRingtone == 'default' ? 'Por defecto del sistema' : _settings.selectedRingtone}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _showRingtoneOptions,
                    icon: const Icon(Icons.music_note),
                    label: const Text('Seleccionar Tono'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nota: El tono seleccionado se reproducirá en las notificaciones y alarmas.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Información
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ℹ️ Información',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '• Los cambios se guardan automáticamente\n'
                  '• El tono por defecto es el del sistema\n'
                  '• Selecciona un tono de tu preferencia\n'
                  '• Las alarmas urgentes siempre sonarán',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRingtoneOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        color: AppTheme.surfaceColor,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Selecciona un tono',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(color: AppTheme.borderColor),

            // Opción: Tono por defecto
            ListTile(
              leading: Icon(
                _settings.selectedRingtone == 'default'
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: AppTheme.primaryColor,
              ),
              title: const Text('Tono por defecto del sistema'),
              subtitle: const Text('Usa el sonido predeterminado'),
              onTap: () {
                setState(() {
                  _settings = _settings.copyWith(selectedRingtone: 'default');
                });
                _saveSettings();
                Navigator.pop(context);
              },
            ),

            const Divider(color: AppTheme.borderColor),

            // Opciones de tonos comunes (estos se pueden ampliar)
            ..._getToneOptions().map((tone) {
              return ListTile(
                leading: Icon(
                  _settings.selectedRingtone == tone['id']
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: AppTheme.primaryColor,
                ),
                title: Text(tone['name'] ?? ''),
                subtitle: Text(tone['description'] ?? ''),
                onTap: () {
                  setState(() {
                    _settings =
                        _settings.copyWith(selectedRingtone: tone['id']);
                  });
                  _saveSettings();
                  Navigator.pop(context);
                },
              );
            }),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _getToneOptions() {
    return [
      {
        'id': 'tone_1',
        'name': 'Alerta Suave',
        'description': 'Notificación discreta'
      },
      {
        'id': 'tone_2',
        'name': 'Alerta Moderada',
        'description': 'Notificación clara'
      },
      {
        'id': 'tone_3',
        'name': 'Alerta Fuerte',
        'description': 'Notificación urgente'
      },
      {
        'id': 'tone_4',
        'name': 'Campana',
        'description': 'Sonido de campana'
      },
      {
        'id': 'tone_5',
        'name': 'Digital',
        'description': 'Sonido digital moderno'
      },
    ];
  }
}
