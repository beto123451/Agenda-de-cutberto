import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/recordatorio.dart';
import '../models/ubicacion.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../utils/theme.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/recordatorio_card.dart';
import '../widgets/welcome_card.dart';
import '../widgets/firestore_dialogs.dart';
import '../widgets/app_tutorial.dart';
import 'edit_recordatorio_screen.dart';
import 'add_recordatorio_screen.dart';
import 'recordatorios_list_screen.dart';
import 'mapas_screen.dart';
import 'notification_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fabAnimation;
  late Animation<double> _contentAnimation;

  List<Recordatorio> _recordatorios = [];
  bool _isLoading = true;

  String _searchQuery = '';
  int _selectedFilter = 0;

  // ScrollController para el tutorial
  final ScrollController _scrollController = ScrollController();

  // GlobalKey para el Scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // GlobalKeys para el tutorial
  final _keyWelcomeCard = GlobalKey();
  final _keyStatistics = GlobalKey();
  final _keySearchBar = GlobalKey();
  final _keyFilters = GlobalKey();
  final _keyQuickActions = GlobalKey();
  final _keyUpcoming = GlobalKey();
  final _keyFab = GlobalKey();
  final _keyNotifications = GlobalKey();
  final _keySettings =
      GlobalKey(); // 0: Todos, 1: Pendientes, 2: Próximos, 3: Vencidos

  final List<String> _filterOptions = [
    'Todos',
    'Pendientes',
    'Próximos',
    'Vencidos',
  ];

  // Map para rastrear timers de alarmas por ID de recordatorio
  final Map<int, Timer> _alarmTimers = {};

  // Calendario
  late DateTime _selectedDay;
  late DateTime _focusedDay;
  late Map<DateTime, List<Recordatorio>> _eventsByDate;

  // Mapa
  late LocationService _locationService;
  LatLng? _posicionActual;
  final List<Marker> _mapMarkers = [];
  final Map<String, Ubicacion> _ubicacionesCache = {};
  bool _cargandoMapa = true;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    _eventsByDate = {};

    // Inicializar LocationService y MapController
    _locationService = LocationService();
    _mapController = MapController();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fabAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.6, 1.0, curve: Curves.elasticOut),
      ),
    );

    _contentAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Iniciar animaciones
    _animationController.forward();

    // Cargar datos iniciales
    _loadRecordatorios();

    // Cargar mapa después de cargar recordatorios
    Future.delayed(const Duration(milliseconds: 300), () {
      _inicializarMapa();
    });

    // Obtener servicios
    final alarmService = context.read<AlarmService>();
    final notificationService = context.read<NotificationService>();

    // Registrar callback para cuando se dispara una alarma programada
    // La alarma nativa del teléfono (app Clock) se encarga de sonar
    alarmService.setAlarmFireCallback((cliente, equipo, fecha) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ ⏰ ALARMA DISPARADA AUTOMÁTICAMENTE');
      debugPrint('║ Cliente: $cliente');
      debugPrint('║ Equipo: $equipo');
      debugPrint('╚════════════════════════════════════════╝');
      debugPrint('La alarma nativa del Reloj se encargará de sonar.');
    });

    // Registrar callback para acciones de notificación (snooze/dismiss)
    notificationService.setNotificationActionCallback((
      actionId,
      cliente,
      equipo,
      fecha,
    ) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ 🔔 ACCIÓN DE NOTIFICACIÓN: $actionId');
      debugPrint('║ Cliente: $cliente');
      debugPrint('║ Equipo: $equipo');
      debugPrint('╚════════════════════════════════════════╝');

      if (actionId == 'snooze') {
        debugPrint('⏸️  Ejecutando posponer...');
        alarmService.posponderAlarma(cliente, equipo, fecha, null);
      } else if (actionId == 'dismiss') {
        debugPrint('✅ Ejecutando detener alarma...');
        alarmService.detenerAlarma();
      }
    });

    // Registrar callback para cuando se toque una alarma desde notificación
    notificationService.setAlarmTapCallback((cliente, equipo, fecha) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ 📱 CALLBACK DE ALARMA DESDE NOTIFICACIÓN');
      debugPrint('║ Cliente: $cliente');
      debugPrint('║ Equipo: $equipo');
      debugPrint('╚════════════════════════════════════════╝');
      debugPrint('La alarma nativa del Reloj se encargará de sonar.');
    });

    // Verificar y programar alarmas de hoy
    Future.delayed(const Duration(milliseconds: 500), () {
      _verificarYProgramarAlarmas();
    });

    // Verificar migración y almacenamiento después de cargar
    Future.delayed(const Duration(seconds: 1), () {
      _verificarMigracionFirestore();
    });

    // Mostrar tutorial si es la primera vez
    Future.delayed(const Duration(seconds: 2), () {
      _checkAndShowTutorial();
    });
  }

  /// Sincronizar todos los datos locales con Firestore automáticamente
  Future<void> _verificarMigracionFirestore() async {
    final firestoreService = FirestoreService();
    if (!firestoreService.isInitialized) return;

    try {
      // Sincronizar todos los recordatorios existentes a Firestore
      if (_recordatorios.isNotEmpty) {
        debugPrint(
          '🔄 Sincronizando ${_recordatorios.length} recordatorios con Firestore...',
        );

        final storageService = context.read<StorageService>();
        final config = await storageService.getConfigAlarma();

        final yaMigrado = await firestoreService.yaMigrado();
        if (!yaMigrado) {
          await firestoreService.migrarRecordatorios(_recordatorios);
          await firestoreService.migrarConfigAlarma(config);
          debugPrint(
            '✅ ${_recordatorios.length} recordatorios sincronizados con Firestore',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '☁️ ${_recordatorios.length} recordatorio${_recordatorios.length == 1 ? '' : 's'} respaldado${_recordatorios.length == 1 ? '' : 's'} en la nube',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }

      // Verificar almacenamiento
      await _verificarAlmacenamientoFirestore();
    } catch (e) {
      debugPrint('❌ Error sincronizando con Firestore: $e');
    }
  }

  /// Verificar si el almacenamiento de Firestore se está llenando
  Future<void> _verificarAlmacenamientoFirestore() async {
    final firestoreService = FirestoreService();
    if (!firestoreService.isInitialized) return;

    try {
      final casiLleno = await firestoreService.almacenamientoCasiLleno();
      if (!casiLleno || !mounted) return;

      final count = await firestoreService.contarDocumentos();
      final accion = await AlmacenamientoWarningDialog.mostrar(
        context,
        cantidadDocumentos: count,
      );

      if (accion == 'eliminar' && mounted) {
        await firestoreService.eliminarTodosLosDatos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Datos eliminados de la nube. Tus datos locales se mantienen.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error verificando almacenamiento: $e');
    }
  }

  // Verificar y programar alarmas de hoy
  Future<void> _verificarYProgramarAlarmas() async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║ 🔍 VERIFICANDO ALARMAS DE HOY');
    debugPrint('╚════════════════════════════════════════╝');

    final alarmService = context.read<AlarmService>();
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final manana = hoy.add(const Duration(days: 1));

    // Recordatorios con alarma para hoy o mañana
    final recordatoriosCercanos = _recordatorios.where((r) {
      final fecha = r.fechaProximoMantenimiento;
      final diaFecha = DateTime(fecha.year, fecha.month, fecha.day);
      return (diaFecha == hoy || diaFecha == manana) &&
          r.alarmaProgramada &&
          !r.estaVencido();
    }).toList();

    debugPrint(
      '📋 Recordatorios encontrados para hoy/mañana: ${recordatoriosCercanos.length}',
    );

    for (var recordatorio in recordatoriosCercanos) {
      // Usar calcularFechaAlarma() para respetar la hora ajustada
      // (si el usuario no puso hora, se usa 8:00 AM en vez de 00:00)
      final horaAlarma = recordatorio.calcularFechaAlarma();

      // Si la hora de alarma ya pasó, saltar
      if (horaAlarma.isBefore(ahora)) {
        debugPrint('⏭️  Saltando: ${recordatorio.cliente} - hora ya pasó');
        continue;
      }

      final tiempoHasta = horaAlarma.difference(ahora);
      final segundos = tiempoHasta.inSeconds;

      debugPrint('📅 Recordatorio: ${recordatorio.cliente}');
      debugPrint('   Equipo: ${recordatorio.equipo}');
      debugPrint(
        '   Hora alarma: ${horaAlarma.hour}:${horaAlarma.minute.toString().padLeft(2, '0')}',
      );
      debugPrint(
        '   Tiempo hasta alarma: ${tiempoHasta.inMinutes}min ${tiempoHasta.inSeconds % 60}seg',
      );

      if (segundos > 0 && segundos < 86400) {
        // Menos de 24 horas - programar timer para disparar alarma
        final timer = Timer(Duration(seconds: segundos), () {
          // Verificar que el recordatorio aún existe antes de disparar
          Recordatorio? recordatorioAun;
          try {
            recordatorioAun = _recordatorios.firstWhere(
              (r) => r.id == recordatorio.id,
            );
          } catch (e) {
            recordatorioAun = null;
          }

          if (recordatorioAun == null) {
            debugPrint(
              '⏭️  Recordatorio ${recordatorio.cliente} fue eliminado, cancelando alarma',
            );
            return;
          }

          if (mounted) {
            debugPrint('');
            debugPrint('╔════════════════════════════════════════╗');
            debugPrint('║ ⏰ HORA DE LA ALARMA: ${recordatorio.cliente}');
            debugPrint('╚════════════════════════════════════════╝');

            // activarAlarmaInmediata() ejecutará el callback y
            // creará la alarma nativa en la app Reloj del teléfono
            alarmService.activarAlarmaInmediata(
              cliente: recordatorio.cliente,
              equipo: recordatorio.equipo,
              fecha: '${horaAlarma.day}/${horaAlarma.month}/${horaAlarma.year}',
              fechaAlarma: horaAlarma,
            );
          }
        });

        // Guardar referencia del timer para poder cancelarlo después
        _alarmTimers[recordatorio.id ?? 0] = timer;

        debugPrint('✅ Alarma programada en timer');
      }
    }

    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║ ✓ Verificación completada');
    debugPrint('╚════════════════════════════════════════╝');
    debugPrint('');
  }

  Future<void> _checkAndShowTutorial() async {
    if (!mounted) return;
    final shouldShow = await AppTutorial.shouldShowTutorial();
    if (shouldShow && mounted) {
      _startTutorial();
    }
  }

  void _startTutorial() {
    if (!mounted) return;
    AppTutorial.showTutorial(
      context: context,
      scrollController: _scrollController,
      keyWelcomeCard: _keyWelcomeCard,
      keyStatistics: _keyStatistics,
      keySearchBar: _keySearchBar,
      keyFilters: _keyFilters,
      keyQuickActions: _keyQuickActions,
      keyUpcoming: _keyUpcoming,
      keyFab: _keyFab,
      keyNotifications: _keyNotifications,
      keySettings: _keySettings,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();

    // Cancelar todos los timers de alarmas
    for (final timer in _alarmTimers.values) {
      timer.cancel();
    }
    _alarmTimers.clear();

    // Limpiar callbacks cuando se cierra la pantalla
    final alarmService = context.read<AlarmService>();
    alarmService.clearAlarmFireCallback();

    final notificationService = context.read<NotificationService>();
    notificationService.clearAlarmTapCallback();
    notificationService.clearNotificationActionCallback();

    super.dispose();
  }

  Future<void> _loadRecordatorios() async {
    try {
      final storageService = context.read<StorageService>();
      final loadedRecordatorios = await storageService.getRecordatorios();

      // Cancelar timers de recordatorios que ya no existen
      final idsActuales = loadedRecordatorios.map((r) => r.id).toSet();
      for (final id in List.from(_alarmTimers.keys)) {
        if (!idsActuales.contains(id)) {
          _alarmTimers[id]?.cancel();
          _alarmTimers.remove(id);
          debugPrint('🗑️  Timer cancelado para recordatorio eliminado: $id');
        }
      }

      setState(() {
        _recordatorios = loadedRecordatorios;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error cargando recordatorios: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    await _loadRecordatorios();
  }

  int get _pendientesCount =>
      _recordatorios.where((r) => !r.estaVencido()).length;
  int get _proximosCount =>
      _recordatorios.where((r) => r.esProximo() && !r.estaVencido()).length;
  int get _vencidosCount => _recordatorios.where((r) => r.estaVencido()).length;

  // Drawer con categorías de servicios
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppTheme.surfaceColor,
      child: ListView(
        padding: const EdgeInsets.only(top: 100.0),
        children: [
          // Opción: Servicios Vencidos
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            iconColor: const Color(0xFFFF5252),
            title: const Text('Vencidos'),
            subtitle: Text('$_vencidosCount servicios'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_vencidosCount',
                style: const TextStyle(
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const RecordatoriosListScreen(initialFilter: 'vencidos'),
                ),
              );
            },
          ),
          Divider(color: AppTheme.borderColor),
          // Opción: Servicios Próximos
          ListTile(
            leading: const Icon(Icons.schedule),
            iconColor: const Color(0xFFFF9800),
            title: const Text('Próximos'),
            subtitle: Text('$_proximosCount servicios'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_proximosCount',
                style: const TextStyle(
                  color: Color(0xFFFF9800),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const RecordatoriosListScreen(initialFilter: 'proximos'),
                ),
              );
            },
          ),
          Divider(color: AppTheme.borderColor),
          // Opción: Servicios Pendientes
          ListTile(
            leading: const Icon(Icons.calendar_today),
            iconColor: const Color(0xFF4CAF50),
            title: const Text('Pendientes'),
            subtitle: Text(
              '${_pendientesCount - _proximosCount} servicios',
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_pendientesCount - _proximosCount}',
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const RecordatoriosListScreen(initialFilter: 'pendientes'),
                ),
              );
            },
          ),
          Divider(color: AppTheme.borderColor),
          // Opción: Ver Todos
          ListTile(
            leading: const Icon(Icons.list),
            iconColor: AppTheme.primaryColor,
            title: const Text('Ver Todos'),
            subtitle: Text('$_pendientesCount servicios totales'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_pendientesCount',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const RecordatoriosListScreen(initialFilter: 'todos'),
                ),
              );
            },
          ),
          Divider(color: AppTheme.borderColor),
          // Sección de Almacenamiento en la Nube
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '☁️ Almacenamiento en la Nube',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<Map<String, dynamic>>(
                  future: FirestoreService().getFirestoreStorageInfo(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 20,
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: AppTheme.borderColor,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                        ),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Text(
                        'No hay conexión',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondaryColor,
                        ),
                      );
                    }

                    final storageInfo = snapshot.data!;
                    final docCount = storageInfo['documentCount'] as int? ?? 0;
                    final sizeFormatted =
                        storageInfo['estimatedBytesFormatted'] as String? ??
                            '0 B';
                    final maxDocs = storageInfo['maxDocuments'] as int? ?? 0;
                    final usagePercent =
                        maxDocs > 0 ? (docCount / maxDocs * 100).toStringAsFixed(0) : '0';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Documentos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Documentos:',
                              style: TextStyle(fontSize: 11),
                            ),
                            Text(
                              '$docCount',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Tamaño estimado
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tamaño est.:',
                              style: TextStyle(fontSize: 11),
                            ),
                            Text(
                              sizeFormatted,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Barra de uso
                        LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: AppTheme.borderColor,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            double.parse(usagePercent) > 80
                                ? const Color(0xFFFF5252)
                                : AppTheme.primaryColor,
                          ),
                          value: docCount > 0 ? docCount / maxDocs : 0,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Uso: $usagePercent%',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                            Text(
                              '$docCount/$maxDocs',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Sección de Almacenamiento del Dispositivo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📱 Almacenamiento del Dispositivo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<Map<String, dynamic>>(
                  future: StorageService().getAlmacenamientoInfo(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 20,
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: AppTheme.borderColor,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                        ),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Text(
                        'No hay información',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondaryColor,
                        ),
                      );
                    }

                    final storageInfo = snapshot.data!;
                    final dbSizeFormatted =
                        storageInfo['dbSizeFormatted'] as String? ?? '0 B';
                    final freeDiskSpaceFormatted =
                        storageInfo['freeDiskSpaceFormatted'] as String? ??
                            'N/A';
                    final usagePercentage =
                        storageInfo['usagePercentage'] as double? ?? 0.0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Base de datos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Base de datos:',
                              style: TextStyle(fontSize: 11),
                            ),
                            Text(
                              dbSizeFormatted,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Espacio libre
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Espacio libre:',
                              style: TextStyle(fontSize: 11),
                            ),
                            Text(
                              freeDiskSpaceFormatted,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Barra de uso
                        LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: AppTheme.borderColor,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            usagePercentage > 80
                                ? const Color(0xFFFF5252)
                                : AppTheme.primaryColor,
                          ),
                          value: usagePercentage / 100,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Uso: ${usagePercentage.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Obtener el recordatorio más próximo sin vencer
  Recordatorio? get _recordatorioMasProximo {
    if (_recordatorios.isEmpty) return null;

    final noVencidos = _recordatorios.where((r) => !r.estaVencido()).toList();
    if (noVencidos.isEmpty) return null;

    // Ordenar por fecha más cercana
    noVencidos.sort(
      (a, b) =>
          a.fechaProximoMantenimiento.compareTo(b.fechaProximoMantenimiento),
    );
    return noVencidos.first;
  }

  // Construir mapa de eventos por fecha
  void _buildEventMap() {
    _eventsByDate.clear();
    for (final recordatorio in _recordatorios) {
      final fecha = DateTime(
        recordatorio.fechaProximoMantenimiento.year,
        recordatorio.fechaProximoMantenimiento.month,
        recordatorio.fechaProximoMantenimiento.day,
      );
      if (_eventsByDate.containsKey(fecha)) {
        _eventsByDate[fecha]!.add(recordatorio);
      } else {
        _eventsByDate[fecha] = [recordatorio];
      }
    }
  }

  // Obtener eventos de un día específico
  List<Recordatorio> _getEventsForDay(DateTime day) {
    final fecha = DateTime(day.year, day.month, day.day);
    return _eventsByDate[fecha] ?? [];
  }

  Widget _buildCalendar() {
    _buildEventMap();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calendario de Servicios',
            style: AppTheme.heading3.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TableCalendar<Recordatorio>(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2026, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            eventLoader: _getEventsForDay,
            onHeaderTapped: (focusedDay) {
              setState(() {
                _focusedDay = DateTime.now();
              });
            },
            calendarStyle: CalendarStyle(
              defaultDecoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              defaultTextStyle: const TextStyle(color: AppTheme.textColor),
              weekendDecoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              weekendTextStyle: const TextStyle(color: AppTheme.textColor),
              selectedDecoration: BoxDecoration(
                color: AppTheme.accentColor,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: TextStyle(
                color: AppTheme.backgroundColor,
                fontWeight: FontWeight.bold,
              ),
              todayDecoration: BoxDecoration(
                color: AppTheme.infoColor.withOpacity(0.3),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.infoColor, width: 2),
              ),
              todayTextStyle: const TextStyle(
                color: AppTheme.textColor,
                fontWeight: FontWeight.bold,
              ),
              outsideDecoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.backgroundColor,
              ),
              outsideTextStyle: TextStyle(
                color: AppTheme.textSecondaryColor.withOpacity(0.3),
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              leftChevronIcon: const Icon(
                Icons.navigate_before,
                color: AppTheme.accentColor,
                size: 16,
              ),
              rightChevronIcon: const Icon(
                Icons.navigate_next,
                color: AppTheme.accentColor,
                size: 16,
              ),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (date, locale) {
                return DateFormat('E', 'es_ES').format(date)[0].toUpperCase();
              },
              decoration: BoxDecoration(color: AppTheme.cardColor),
              weekdayStyle: const TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              weekendStyle: const TextStyle(
                color: AppTheme.warningColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Mostrar eventos del día seleccionado
          if (_getEventsForDay(_selectedDay).isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.successColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Servicios: ${DateFormat('EEEE, d MMMM', 'es_ES').format(_selectedDay)}',
                    style: TextStyle(
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._getEventsForDay(_selectedDay)
                      .map(
                        (evento) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 8,
                                  color: AppTheme.backgroundColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      evento.cliente,
                                      style: const TextStyle(
                                        color: AppTheme.textColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      evento.equipo,
                                      style: TextStyle(
                                        color: AppTheme.textSecondaryColor,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Sin servicios este día',
                  style: TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Inicializar el mapa y obtener ubicación actual
  Future<void> _inicializarMapa() async {
    try {
      final position = await _locationService.obtenerPosicionActual();
      if (position != null) {
        setState(() {
          _posicionActual = LatLng(position.latitude, position.longitude);
        });
      } else {
        // Ubicación por defecto (Bogotá, Colombia)
        setState(() {
          _posicionActual = LatLng(4.5709, -74.2973);
        });
      }

      // Cargar ubicaciones de recordatorios en el mapa
      await _cargarUbicacionesEnMapa();

      if (mounted) {
        setState(() {
          _cargandoMapa = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error inicializando mapa: $e');
      setState(() {
        _cargandoMapa = false;
      });
    }
  }

  /// Cargar ubicaciones de recordatorios en el mapa
  Future<void> _cargarUbicacionesEnMapa() async {
    _mapMarkers.clear();

    // Agregar marcador de ubicación actual
    if (_posicionActual != null) {
      _mapMarkers.add(
        Marker(
          point: _posicionActual!,
          child: Tooltip(
            message: 'Tu ubicación',
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accentColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on,
                color: AppTheme.secondaryColor,
                size: 24,
              ),
            ),
          ),
        ),
      );
    }

    // Agregar marcadores para cada recordatorio con ubicación
    for (var recordatorio in _recordatorios) {
      if (recordatorio.ubicacion.isNotEmpty) {
        // Verificar si ya está en caché
        if (!_ubicacionesCache.containsKey(recordatorio.ubicacion)) {
          final ubicacion = await _locationService.obtenerCoordenadasDeDir(
            recordatorio.ubicacion,
          );
          if (ubicacion != null) {
            _ubicacionesCache[recordatorio.ubicacion] = ubicacion;
          }
        }

        // Agregar marcador si la ubicación está en caché
        if (_ubicacionesCache.containsKey(recordatorio.ubicacion)) {
          final ubicacion = _ubicacionesCache[recordatorio.ubicacion]!;
          _mapMarkers.add(
            Marker(
              point: LatLng(ubicacion.latitud, ubicacion.longitud),
              child: Tooltip(
                message: recordatorio.cliente,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accentColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentColor.withOpacity(0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.business,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Widget embebido del mapa
  Widget _buildMapWidget() {
    if (_cargandoMapa) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration,
        height: 300,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
      decoration: AppTheme.cardDecoration,
      height: 350,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Ubicación de Servicios',
                  style: AppTheme.heading3.copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
          // Mapa
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(AppTheme.defaultBorderRadius),
                bottomRight: Radius.circular(AppTheme.defaultBorderRadius),
              ),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      _posicionActual ?? const LatLng(4.5709, -74.2973),
                  initialZoom: 12.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.agenda_flutter',
                  ),
                  MarkerLayer(markers: _mapMarkers),
                ],
              ),
            ),
          ),
          // Footer con info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              border: Border(top: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 14,
                  color: AppTheme.textSecondaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_mapMarkers.length} ubicaciones en el mapa',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _navigateToMapa,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver completo',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 10,
                        color: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration.copyWith(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surfaceColor, AppTheme.cardColor],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Resumen del Día',
                style: AppTheme.heading3.copyWith(fontSize: 18),
              ),
              IconButton(
                icon: const Icon(Icons.sync, size: 16),
                onPressed: _refreshData,
                color: AppTheme.textSecondaryColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  value: _pendientesCount,
                  label: 'Pendientes',
                  color: AppTheme.successColor,
                  icon: Icons.event_available,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  value: _proximosCount,
                  label: 'Próximos',
                  color: AppTheme.warningColor,
                  icon: Icons.schedule,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  value: _vencidosCount,
                  label: 'Vencidos',
                  color: AppTheme.errorColor,
                  icon: Icons.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required int value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value.toString(),
          style: TextStyle(
            color: AppTheme.textColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textSecondaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Widget que muestra el servicio más próximo en grande
  Widget _buildProximoServicio() {
    final proximo = _recordatorioMasProximo;

    if (proximo == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
        padding: const EdgeInsets.all(24),
        decoration: AppTheme.cardDecoration,
        child: Column(
          children: [
            Icon(
              Icons.check_circle,
              color: AppTheme.successColor,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '¡Todos los servicios al día!',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No hay servicios próximos vencidos',
              style: TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final diasRestantes = proximo.diasParaProximo();
    final estado = proximo.estado;
    final estadoColor = Color(proximo.colorEstado);
    final fecha = DateFormat(
      'd MMM yyyy',
      'es_ES',
    ).format(proximo.fechaProximoMantenimiento);

    return GestureDetector(
      onTap: () => _showRecordatorioDetails(proximo),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              estadoColor.withOpacity(0.15),
              estadoColor.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.defaultBorderRadius),
          border: Border.all(color: estadoColor.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: estadoColor.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background decorativo
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: estadoColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Contenido
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header con etiqueta
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.star,
                                color: AppTheme.accentColor,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PRÓXIMO SERVICIO',
                                style: TextStyle(
                                  color: AppTheme.accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            proximo.cliente,
                            style: const TextStyle(
                              color: AppTheme.textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      // Badge con días
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: estadoColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: estadoColor.withOpacity(0.5),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              diasRestantes.toString(),
                              style: TextStyle(
                                color: estadoColor,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'días',
                              style: TextStyle(
                                color: estadoColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Detalles
                  Row(
                    children: [
                      // Equipo
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.build,
                                  size: 14,
                                  color: AppTheme.textSecondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Equipo',
                                  style: TextStyle(
                                    color: AppTheme.textSecondaryColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              proximo.equipo,
                              style: const TextStyle(
                                color: AppTheme.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Ubicación
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: AppTheme.textSecondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Ubicación',
                                  style: TextStyle(
                                    color: AppTheme.textSecondaryColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              proximo.ubicacion.isEmpty
                                  ? 'Sin ubicación'
                                  : proximo.ubicacion.split('\n').first,
                              style: TextStyle(
                                color: proximo.ubicacion.isEmpty
                                    ? AppTheme.textSecondaryColor.withOpacity(
                                        0.6,
                                      )
                                    : AppTheme.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Fecha y estado
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month,
                              size: 14,
                              color: AppTheme.textSecondaryColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              fecha,
                              style: const TextStyle(
                                color: AppTheme.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Estado badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: estadoColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: estadoColor.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          estado,
                          style: TextStyle(
                            color: estadoColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Botón de acción
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _editRecordatorio(proximo),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: estadoColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text(
                        'Editar Recordatorio',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Formato mm:ss para el countdown
  String _formatSnoozeTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildSnoozeBanner() {
    final alarmService = context.read<AlarmService>();

    return ValueListenableBuilder<int>(
      valueListenable: alarmService.snoozeSecondsLeft,
      builder: (context, secondsLeft, _) {
        if (secondsLeft <= 0) return const SizedBox.shrink();

        final cliente = alarmService.snoozeCliente ?? '';
        final equipo = alarmService.snoozeEquipo ?? '';

        return Container(
          margin: const EdgeInsets.only(
            left: AppTheme.defaultPadding,
            right: AppTheme.defaultPadding,
            bottom: 16,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.upcomingColor.withOpacity(0.15),
                AppTheme.upcomingColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.upcomingColor.withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.upcomingColor.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.upcomingColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.schedule,
                      size: 16,
                      color: AppTheme.upcomingColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ALARMA POSPUESTA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.upcomingColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cliente,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Countdown
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.upcomingColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.upcomingColor.withOpacity(0.5),
                      ),
                    ),
                    child: Text(
                      _formatSnoozeTime(secondsLeft),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.upcomingColor,
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
              if (equipo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 42), // Align with text above
                    Icon(
                      Icons.build,
                      size: 11,
                      color: AppTheme.textSecondaryColor.withOpacity(0.7),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        equipo,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondaryColor.withOpacity(0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:
                      secondsLeft / (AlarmService.snoozeDurationMinutes * 60),
                  backgroundColor: AppTheme.surfaceColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.upcomingColor,
                  ),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sonará de nuevo en ${_formatSnoozeTime(secondsLeft)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondaryColor.withOpacity(0.7),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      alarmService.detenerAlarma();
                    },
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.errorColor.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Acciones Rápidas',
              style: AppTheme.heading3.copyWith(fontSize: 18),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildQuickActionCard(
                icon: Icons.add_circle,
                label: 'Nuevo Recordatorio',
                color: AppTheme.primaryColor,
                onTap: () => _navigateToAddRecordatorio(),
              ),
              _buildQuickActionCard(
                icon: Icons.list,
                label: 'Ver Todos',
                color: AppTheme.accentColor,
                onTap: () => _navigateToRecordatoriosList(),
              ),
              _buildQuickActionCard(
                icon: Icons.location_on,
                label: 'Mapa',
                color: const Color(0xFF2196F3),
                onTap: () => _navigateToMapa(),
              ),
              _buildQuickActionCard(
                icon: Icons.notifications,
                label: 'Probar Alarma',
                color: const Color(0xFFFF9800),
                onTap: _probarAlarma,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(AppTheme.defaultBorderRadius),
          border: Border.all(color: AppTheme.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingReminders() {
    // Mostrar los próximos mantenimientos sin aplicar filtros actuales
    final upcoming = _recordatorios
        .where((r) => r.esProximo() && !r.estaVencido())
        .toList();

    if (upcoming.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
        padding: const EdgeInsets.all(24),
        decoration: AppTheme.cardDecoration,
        child: Column(
          children: [
            Icon(
              Icons.add_box,
              color: AppTheme.textSecondaryColor,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay mantenimientos próximos',
              style: TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega un nuevo recordatorio para comenzar',
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Próximos Mantenimientos',
                  style: AppTheme.heading3.copyWith(fontSize: 18),
                ),
                TextButton(
                  onPressed: _navigateToRecordatoriosList,
                  child: Text(
                    'Ver todos',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...upcoming.map((recordatorio) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RecordatorioCard(
                recordatorio: recordatorio,
                compact: true,
                onTap: () => _showRecordatorioDetails(recordatorio),
                onEdit: () => _editRecordatorio(recordatorio),
                onAlarm: () => _toggleAlarma(recordatorio),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.defaultPadding),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final label = entry.value;
            final isSelected = _selectedFilter == index;
            final count = index == 0
                ? _recordatorios.length
                : index == 1
                ? _pendientesCount
                : index == 2
                ? _proximosCount
                : _vencidosCount;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.2)
                            : AppTheme.textSecondaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textSecondaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedFilter = index;
                  });
                },
                backgroundColor: AppTheme.surfaceColor,
                selectedColor: AppTheme.primaryColor,
                labelStyle: TextStyle(
                  color: isSelected
                      ? AppTheme.secondaryColor
                      : AppTheme.textColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.borderColor,
                  ),
                ),
                showCheckmark: false,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.defaultPadding,
        vertical: 8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.defaultBorderRadius),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: 16,
            color: AppTheme.textSecondaryColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: const InputDecoration(
                hintText: 'Buscar cliente, equipo o ubicación...',
                hintStyle: TextStyle(color: AppTheme.textSecondaryColor),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(color: AppTheme.textColor, fontSize: 14),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
              },
              color: AppTheme.textSecondaryColor,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.backgroundColor,
      drawer: _buildDrawer(),
      appBar: CustomAppBar(
        title: 'Agenda Téran',
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
          color: AppTheme.primaryColor,
          tooltip: 'Menú',
        ),
        actions: [
          IconButton(
            key: _keyNotifications,
            icon: const Icon(Icons.notifications),
            onPressed: _showNotifications,
            color: AppTheme.primaryColor,
          ),
          IconButton(
            key: _keySettings,
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
            color: AppTheme.primaryColor,
          ),
          IconButton(
            icon: const Icon(Icons.help),
            onPressed: () {
              AppTutorial.resetTutorial();
              _startTutorial();
            },
            color: AppTheme.accentColor,
            tooltip: 'Tutorial',
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _contentAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _contentAnimation.value,
            child: Transform.translate(
              offset: Offset(0, 50 * (1 - _contentAnimation.value)),
              child: child,
            ),
          );
        },
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              )
            : RefreshIndicator(
                onRefresh: _refreshData,
                color: AppTheme.primaryColor,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Tarjeta de bienvenida
                      Container(
                        key: _keyWelcomeCard,
                        child: WelcomeCard(
                          userName: 'Cutberto Terán Morales',
                          userRole: 'Técnico Especializado',
                          userCompany: 'Téran Mantenimientos',
                          pendingCount: _pendientesCount,
                          upcomingCount: _proximosCount,
                          totalCount: _recordatorios.length,
                          onProfileTap: _showProfile,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Servicio más próximo en grande
                      _buildProximoServicio(),

                      const SizedBox(height: 24),

                      // Banner de snooze (cuenta atrás)
                      _buildSnoozeBanner(),

                      // Estadísticas
                      Container(key: _keyStatistics, child: _buildStatistics()),

                      const SizedBox(height: 24),

                      // Mapa de ubicaciones
                      _buildMapWidget(),

                      const SizedBox(height: 24),

                      // Calendario de Servicios
                      _buildCalendar(),

                      const SizedBox(height: 24),

                      // Barra de búsqueda
                      Container(key: _keySearchBar, child: _buildSearchBar()),

                      const SizedBox(height: 16),

                      // Filtros
                      Container(key: _keyFilters, child: _buildFilterChips()),

                      const SizedBox(height: 24),

                      // Acciones rápidas
                      Container(
                        key: _keyQuickActions,
                        child: _buildQuickActions(),
                      ),

                      const SizedBox(height: 24),

                      // Próximos recordatorios
                      Container(
                        key: _keyUpcoming,
                        child: _buildUpcomingReminders(),
                      ),

                      const SizedBox(height: 80), // Espacio para FAB
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _fabAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _fabAnimation.value,
            child: Transform.translate(
              offset: Offset(0, 50 * (1 - _fabAnimation.value)),
              child: child,
            ),
          );
        },
        child: FloatingActionButton(
          key: _keyFab,
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: AppTheme.secondaryColor,
          onPressed: _navigateToAddRecordatorio,
          elevation: 4,
          child: const Icon(Icons.add, size: 24),
        ),
      ),
    );
  }

  // Métodos de navegación y acciones

  void _navigateToAddRecordatorio() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddRecordatorioScreen()),
    );

    if (result == true) {
      await _refreshData();

      // Verificar nuevas alarmas después de crear recordatorio
      await Future.delayed(const Duration(milliseconds: 300));
      await _verificarYProgramarAlarmas();
    }
  }

  void _navigateToRecordatoriosList() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecordatoriosListScreen()),
    );

    if (result == true) {
      await _refreshData();
    }
  }

  void _navigateToMapa() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MapasScreen()),
    );
  }

  void _showRecordatorioDetails(Recordatorio recordatorio) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(
          '📋 Detalles del Mantenimiento',
          style: AppTheme.heading3.copyWith(fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('👤 Cliente:', recordatorio.cliente),
              _buildDetailRow('🔧 Equipo:', recordatorio.equipo),
              _buildDetailRow(
                '📞 Teléfono:',
                recordatorio.telefono.isNotEmpty
                    ? recordatorio.telefono
                    : 'No especificado',
              ),
              _buildDetailRow(
                '📧 Email:',
                recordatorio.email.isNotEmpty
                    ? recordatorio.email
                    : 'No especificado',
              ),
              _buildDetailRow(
                '📅 Fecha del servicio:',
                recordatorio.fechaServicioCompleta(),
              ),
              _buildDetailRow('⏰ Frecuencia:', recordatorio.frecuencia),
              _buildDetailRow(
                '📅 Próximo mantenimiento:',
                recordatorio.fechaProximoCompleta(),
              ),
              _buildDetailRow(
                '📍 Ubicación:',
                recordatorio.ubicacion.isNotEmpty
                    ? recordatorio.ubicacion
                    : 'No especificada',
              ),
              if (recordatorio.observaciones.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      '📝 Observaciones:',
                      style: TextStyle(
                        color: AppTheme.textSecondaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recordatorio.observaciones,
                      style: const TextStyle(
                        color: AppTheme.textColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _editRecordatorio(recordatorio);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Editar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _editRecordatorio(Recordatorio recordatorio) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditRecordatorioScreen(recordatorio: recordatorio),
      ),
    );

    if (result == true) {
      await _refreshData();
    }
  }

  void _toggleAlarma(Recordatorio recordatorio) async {
    try {
      final alarmService = context.read<AlarmService>();

      if (recordatorio.alarmaProgramada) {
        await alarmService.cancelarAlarma(recordatorio);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarma cancelada para ${recordatorio.cliente}'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      } else {
        await alarmService.programarAlarma(recordatorio);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarma programada para ${recordatorio.cliente}'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      }

      await _refreshData();
    } catch (e) {
      debugPrint('Error al programar/cancelar alarma: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al gestionar la alarma'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _probarAlarma() async {
    final alarmService = context.read<AlarmService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text(
          '🔔 Probar Alarma',
          style: TextStyle(color: AppTheme.textColor),
        ),
        content: const Text(
          'Se mostrará una alarma en pantalla completa.\n\n'
          'Funcionará incluso si cierras la app.\n'
          'Asegúrate de que el volumen esté alto.',
          style: TextStyle(color: AppTheme.textSecondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                final cliente = 'Cliente de Prueba';
                final equipo = 'Aire Acondicionado Split';
                final fecha = DateFormat('dd/MM/yyyy').format(DateTime.now());

                // Activar alarma inmediata (funciona en background)
                await alarmService.activarAlarmaInmediata(
                  cliente: cliente,
                  equipo: equipo,
                  fecha: fecha,
                  esPrueba: true,
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Alarma de prueba activada'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error probando alarma: $e');
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('❌ Error al probar la alarma'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Probar Ahora'),
          ),
        ],
      ),
    );
  }

  void _showNotifications() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        title: const Text(
          'Centro de Notificaciones',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'No hay notificaciones pendientes',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings() async {
    // Obtener estado de permisos
    final locationStatus = await Permission.location.status;
    final notificationStatus = await Permission.notification.status;
    final alarmStatus = await Permission.scheduleExactAlarm.status;
    final systemAlertStatus = await Permission.systemAlertWindow.status;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        title: const Text(
          'Configuración',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Divider(color: Colors.white24),

              // SECCIÓN DE PERMISOS
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '🔐 PERMISOS',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Permiso de Ubicación
              _buildPermissionTile(
                icon: Icons.location_on,
                title: 'Ubicación',
                subtitle: 'Acceso a ubicación GPS',
                status: locationStatus,
                onTap: () async {
                  await Permission.location.request();
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24),

              // Permiso de Notificaciones
              _buildPermissionTile(
                icon: Icons.notifications,
                title: 'Notificaciones',
                subtitle: 'Recibir alertas y recordatorios',
                status: notificationStatus,
                onTap: () async {
                  await Permission.notification.request();
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24),

              // Permiso de Alarmas Exactas
              _buildPermissionTile(
                icon: Icons.alarm,
                title: 'Alarmas Exactas',
                subtitle: 'Programar alarmas en horas específicas',
                status: alarmStatus,
                onTap: () async {
                  await Permission.scheduleExactAlarm.request();
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24),

              // Permiso de Mostrar sobre otras apps
              _buildPermissionTile(
                icon: Icons.layers,
                title: 'Mostrar sobre otras apps',
                subtitle: 'Las alarmas aparecerán sobre otras aplicaciones',
                status: systemAlertStatus,
                onTap: () async {
                  await Permission.systemAlertWindow.request();
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24),

              // SECCIÓN DE NOTIFICACIONES
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '🔔 NOTIFICACIONES',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Configuración de sonidos
              ListTile(
                leading: const Icon(
                  Icons.music_note,
                  color: AppTheme.primaryColor,
                ),
                title: const Text(
                  'Configuración de Sonidos',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Elige el tono de notificaciones',
                  style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(
                  Icons.navigate_next,
                  color: AppTheme.primaryColor,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const NotificationSettingsScreen(),
                    ),
                  );
                },
                tileColor: AppTheme.accentColor.withOpacity(0.1),
              ),
              const Divider(color: Colors.white24),

              // SECCIÓN DE SINCRONIZACIÓN
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  '☁️ SINCRONIZACIÓN',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Botón de sincronización manual
              ListTile(
                leading: const Icon(
                  Icons.cloud_upload,
                  color: AppTheme.primaryColor,
                ),
                title: const Text(
                  'Sincronizar datos',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Guardar recordatorios en la nube',
                  style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(
                  Icons.navigate_next,
                  color: AppTheme.primaryColor,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _sincronizarManualmente();
                },
                tileColor: AppTheme.accentColor.withOpacity(0.1),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required PermissionStatus status,
    required VoidCallback onTap,
  }) {
    final isGranted = status.isGranted;
    final statusColor = isGranted ? Colors.green : Colors.red;
    final statusIcon = isGranted ? Icons.check_circle : Icons.cancel;

    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
      trailing: Icon(statusIcon, color: statusColor, size: 24),
      onTap: onTap,
      tileColor: isGranted
          ? Colors.green.withOpacity(0.1)
          : Colors.red.withOpacity(0.1),
    );
  }

  void _showProfile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Perfil de Cutberto Terán Morales'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  /// Sincronizar datos manualmente
  Future<void> _sincronizarManualmente() async {
    final firestoreService = FirestoreService();
    if (!firestoreService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebase no está inicializado'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_recordatorios.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay recordatorios para sincronizar'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      // Mostrar diálogo de progreso
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: AppTheme.backgroundColor,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primaryColor),
                SizedBox(height: 16),
                Text(
                  'Sincronizando datos con la nube...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }

      // Realizar sincronización
      final sincronizados = await firestoreService.sincronizarForzadamente(
        _recordatorios,
      );

      // Cerrar diálogo de progreso
      if (mounted) {
        Navigator.pop(context);
      }

      // Mostrar resultado
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ $sincronizados recordatorio${sincronizados == 1 ? '' : 's'} sincronizado${sincronizados == 1 ? '' : 's'} exitosamente',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Cerrar diálogo de progreso
      if (mounted) {
        Navigator.pop(context);
      }

      // Mostrar error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sincronizando: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
