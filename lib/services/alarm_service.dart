import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../models/recordatorio.dart';
import '../models/alarma_config.dart';
import 'notification_service.dart';
import 'storage_service.dart';

// Callback para cuando se dispara una alarma
typedef AlarmFireCallback =
    void Function(String cliente, String equipo, String fecha);

class AlarmService {
  final NotificationService _notificationService;
  final StorageService _storageService;
  Timer? _alarmTimer;
  bool _alarmaActiva = false;
  int _repeticiones = 0;

  // Callback cuando se dispara una alarma programada
  AlarmFireCallback? _alarmFireCallback;

  // === Estado de Snooze ===
  // Notifier que emite los segundos restantes del snooze (0 = no hay snooze activo)
  final ValueNotifier<int> snoozeSecondsLeft = ValueNotifier<int>(0);
  String? snoozeCliente;
  String? snoozeEquipo;
  Timer? _snoozeTicker;
  DateTime? _snoozeEndTime;
  static const int snoozeDurationMinutes = 5;

  AlarmService()
    : _notificationService = NotificationService(),
      _storageService = StorageService();

  // Registrar callback para cuando se dispara una alarma
  void setAlarmFireCallback(AlarmFireCallback callback) {
    _alarmFireCallback = callback;
    debugPrint('✅ Callback de alarma registrado en AlarmService');
  }

  // Limpiar callback
  void clearAlarmFireCallback() {
    _alarmFireCallback = null;
    debugPrint('✅ Callback de alarma limpiado');
  }

  // Programar alarma para un recordatorio
  Future<void> programarAlarma(Recordatorio recordatorio) async {
    try {
      final fechaAlarma = recordatorio.calcularFechaAlarma();

      // Si la fecha ya pasó, no programar
      if (fechaAlarma.isBefore(DateTime.now())) {
        debugPrint('La fecha de alarma ya pasó para: ${recordatorio.cliente}');
        return;
      }

      // Calcular delay en segundos
      final delay = fechaAlarma.difference(DateTime.now());
      final delaySegundos = delay.inSeconds;

      if (delaySegundos <= 0) {
        debugPrint('Delay negativo o cero para: ${recordatorio.cliente}');
        return;
      }

      debugPrint('✅ Alarma programada para: ${recordatorio.cliente}');

      // Programar notificación local con sonido y vibración
      await _notificationService.scheduleNotification(
        title: '🚨 Alarma: ${recordatorio.cliente}',
        body: recordatorio.equipo,
        scheduleTime: fechaAlarma,
        channelId: 'alarmas_channel',
        id: recordatorio.id.hashCode,
        payload:
            'alarma|${recordatorio.id}|${recordatorio.cliente}|${recordatorio.equipo}',
      );

      debugPrint(
        '✅ Notificación de alarma programada para: ${recordatorio.cliente}',
      );

      // Actualizar recordatorio
      final recordatorioActualizado = recordatorio.copyWith(
        alarmaProgramada: true,
        fechaAlarma: fechaAlarma,
      );

      await _storageService.actualizarRecordatorio(recordatorioActualizado);
    } catch (e) {
      debugPrint('❌ Error programando alarma: $e');
      rethrow;
    }
  }

  // Programar notificaciones previas (2 días antes y 1 día antes)
  Future<void> programarNotificacionPrevia(Recordatorio recordatorio) async {
    try {
      // === NOTIFICACIÓN 2 DÍAS ANTES ===
      final dia2Antes = recordatorio.fechaProximoMantenimiento.subtract(
        const Duration(days: 2),
      );
      final fecha2DiasAntes = DateTime(
        dia2Antes.year,
        dia2Antes.month,
        dia2Antes.day,
        18, // 6:00 PM
        0,
        0,
      );

      if (fecha2DiasAntes.isAfter(DateTime.now())) {
        await _notificationService.scheduleNotification(
          title: '🔔 Recordatorio: ${recordatorio.cliente}',
          body: 'Mantenimiento en 2 días - ${recordatorio.equipo}',
          scheduleTime: fecha2DiasAntes,
          channelId: 'recordatorios_channel',
          id: recordatorio.id.hashCode + 2000,
          payload: 'recordatorio|${recordatorio.id}|${recordatorio.cliente}',
        );
        debugPrint(
          '✅ Notificación 2 días antes programada: ${recordatorio.cliente}',
        );
      }

      // === NOTIFICACIÓN 1 DÍA ANTES ===
      final fechaNotificacion = recordatorio.calcularFechaNotificacion();

      if (fechaNotificacion.isAfter(DateTime.now())) {
        await _notificationService.scheduleNotification(
          title: '🔔 Recordatorio: ${recordatorio.cliente}',
          body: 'Mantenimiento mañana - ${recordatorio.equipo}',
          scheduleTime: fechaNotificacion,
          channelId: 'recordatorios_channel',
          id: recordatorio.id.hashCode + 1000,
          payload: 'recordatorio|${recordatorio.id}|${recordatorio.cliente}',
        );
        debugPrint(
          '✅ Notificación 1 día antes programada: ${recordatorio.cliente}',
        );
      }

      final recordatorioActualizado = recordatorio.copyWith(
        notificacionProgramada: true,
        fechaNotificacion: fechaNotificacion,
      );

      await _storageService.actualizarRecordatorio(recordatorioActualizado);
    } catch (e) {
      debugPrint('❌ Error programando notificación: $e');
    }
  }

  // Cancelar alarma de un recordatorio
  Future<void> cancelarAlarma(Recordatorio recordatorio) async {
    try {
      // Cancelar notificaciones locales programadas
      await _notificationService.cancelNotification(recordatorio.id.hashCode);
      await _notificationService.cancelNotification(
        recordatorio.id.hashCode + 1000,
      );
      await _notificationService.cancelNotification(
        recordatorio.id.hashCode + 2000,
      );

      debugPrint('✅ Alarmas canceladas para: ${recordatorio.cliente}');
    } catch (e) {
      debugPrint('❌ Error cancelando alarma: $e');
    }
  }

  // Eliminar alarma del BD después de atenderla
  Future<void> marcarAlarmaAtendida(Recordatorio recordatorio) async {
    try {
      final recordatorioActualizado = recordatorio.copyWith(
        alarmaProgramada: false,
        fechaAlarma: null,
        notificacionProgramada: false,
        fechaNotificacion: null,
      );

      await _storageService.actualizarRecordatorio(recordatorioActualizado);

      debugPrint('✅ Alarma marcada como atendida: ${recordatorio.cliente}');
    } catch (e) {
      debugPrint('❌ Error marcando alarma como atendida: $e');
    }
  }

  // Activar alarma inmediatamente (para pruebas)
  Future<void> activarAlarmaInmediata({
    required String cliente,
    required String equipo,
    required String fecha,
    DateTime? fechaAlarma,
    AlarmaConfig? config,
    bool esPrueba = false,
  }) async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║ 🚨 ACTIVANDO ALARMA');

    if (_alarmaActiva) {
      debugPrint('⚠️ Alarma ya activa, deteniendo anterior...');
      await detenerAlarma();
    }

    _alarmaActiva = true;

    // PASO 1: Mostrar notificación en Flutter como recordatorio
    debugPrint('▼ PASO 1: Mostrar notificación completa de alarma');
    try {
      await _notificationService.showFullScreenAlarm(
        cliente: cliente,
        equipo: equipo,
        fecha: fecha,
        esPrueba: esPrueba,
      );
      debugPrint('✅ Notificación mostrada');
    } catch (e) {
      debugPrint('⚠️ Error en notificación: $e');
    }

    // PASO 2: Ejecutar callback si está registrado
    debugPrint('▼ PASO 2: Ejecutar callback');
    if (_alarmFireCallback != null) {
      _alarmFireCallback!(cliente, equipo, fecha);
      debugPrint('✅ Callback de alarma ejecutado');
    } else {
      debugPrint('⚠️ No hay callback registrado');
    }

    debugPrint('✅ ALARMA PROGRAMADA CORRECTAMENTE');
    debugPrint('');
  }

  // Detener alarma activa
  Future<void> detenerAlarma() async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║ ⏹️  DETENIENDO ALARMA');
    debugPrint('╚════════════════════════════════════════╝');

    try {
      // Cancelar timer
      if (_alarmTimer != null) {
        _alarmTimer!.cancel();
        _alarmTimer = null;
        debugPrint('✅ Timer cancelado');
      } else {
        debugPrint('ℹ️ No había timer activo');
      }

      // Detener vibración
      try {
        await Vibration.cancel();
        debugPrint('✅ Vibración cancelada');
      } catch (e) {
        debugPrint('⚠️ Error cancelando vibración: $e');
      }

      // Cancelar notificación
      try {
        await _notificationService.cancelAllNotifications();
        debugPrint('✅ Notificaciones canceladas');
      } catch (e) {
        debugPrint('⚠️ Error cancelando notificaciones: $e');
      }

      _alarmaActiva = false;
      _repeticiones = 0;

      // Limpiar estado de snooze si estaba activo
      _cancelSnoozeState();

      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ ✅ ALARMA DETENIDA');
      debugPrint('╚════════════════════════════════════════╝');
      debugPrint('');
    } catch (e) {
      debugPrint('❌ Error deteniendo alarma: $e');
      debugPrint('   Stack: ${StackTrace.current}');
    }
  }

  // Iniciar el ticker de cuenta atrás para snooze
  void _startSnoozeTicker() {
    _snoozeTicker?.cancel();
    _snoozeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_snoozeEndTime == null) {
        _cancelSnoozeState();
        return;
      }
      final remaining = _snoozeEndTime!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        snoozeSecondsLeft.value = 0;
        _cancelSnoozeState();
      } else {
        snoozeSecondsLeft.value = remaining;
      }
    });
  }

  // Cancelar el estado visual del snooze
  void _cancelSnoozeState() {
    _snoozeTicker?.cancel();
    _snoozeTicker = null;
    _snoozeEndTime = null;
    snoozeCliente = null;
    snoozeEquipo = null;
    snoozeSecondsLeft.value = 0;
  }

  // Posponer alarma 5 minutos
  Future<void> posponderAlarma(
    String cliente,
    String equipo,
    String fecha,
    DateTime? fechaAlarma,
  ) async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║ ⏸️  POSPONIENDO ALARMA $snoozeDurationMinutes MINUTOS');
    debugPrint('║ Cliente: $cliente');
    debugPrint('║ Equipo: $equipo');
    debugPrint('╚════════════════════════════════════════╝');

    try {
      // Detener alarma actual
      await detenerAlarma();

      // Programar nueva alarma en 5 minutos usando Timer (más confiable)
      final ahora = DateTime.now();
      final proximaAlarma = ahora.add(Duration(minutes: snoozeDurationMinutes));

      debugPrint(
        '⏰ Nueva alarma programada para: ${proximaAlarma.hour}:${proximaAlarma.minute.toString().padLeft(2, '0')}',
      );

      // === Activar estado de snooze visible en la UI ===
      snoozeCliente = cliente;
      snoozeEquipo = equipo;
      _snoozeEndTime = proximaAlarma;
      snoozeSecondsLeft.value = Duration(
        minutes: snoozeDurationMinutes,
      ).inSeconds;
      _startSnoozeTicker();

      // Usar Timer para disparar la alarma después del snooze
      _alarmTimer = Timer(Duration(minutes: snoozeDurationMinutes), () async {
        // Limpiar estado visual de snooze
        _cancelSnoozeState();

        if (_alarmFireCallback != null) {
          debugPrint('');
          debugPrint('╔════════════════════════════════════════╗');
          debugPrint('║ 🔔 SNOOZE: ALARMA POSPONIDA SE DISPARA');
          debugPrint('║ Cliente: $cliente');
          debugPrint('║ Equipo: $equipo');
          debugPrint('╚════════════════════════════════════════╝');
          debugPrint('');

          // Activar la alarma nuevamente después del snooze
          await activarAlarmaInmediata(
            cliente: cliente,
            equipo: equipo,
            fecha: fecha,
            fechaAlarma: fechaAlarma,
          );
        }
      });

      debugPrint(
        '✅ Alarma posponida exitosamente (Timer + Countdown configurado)',
      );
      debugPrint('');
    } catch (e) {
      debugPrint('❌ Error posponiendo alarma: $e');
      debugPrint('   Stack: ${StackTrace.current}');
    }
  }

  // Verificar alarmas pendientes
  Future<void> checkPendingAlarms() async {
    try {
      final recordatorios = await _storageService.getRecordatorios();
      final ahora = DateTime.now();

      for (final recordatorio in recordatorios) {
        if (recordatorio.alarmaProgramada && recordatorio.fechaAlarma != null) {
          final diferencia = recordatorio.fechaAlarma!.difference(ahora);

          if (diferencia.inSeconds <= 0 && diferencia.inSeconds >= -300) {
            // 5 minutos de tolerancia
            debugPrint('⚠️ Alarma vencida detectada: ${recordatorio.cliente}');
            await _activarAlarmaVencida(recordatorio);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error verificando alarmas: $e');
    }
  }

  // Activar alarma vencida
  Future<void> _activarAlarmaVencida(Recordatorio recordatorio) async {
    await activarAlarmaInmediata(
      cliente: recordatorio.cliente,
      equipo: recordatorio.equipo,
      fecha: recordatorio.fechaProximoFormateada(),
      fechaAlarma: recordatorio.fechaProximoMantenimiento,
      config: AlarmaConfig.configMaxima,
    );
  }

  // Re-programar todas las alarmas (útil después de reiniciar dispositivo)
  Future<void> reprogramarTodasLasAlarmas() async {
    try {
      final recordatorios = await _storageService.getRecordatorios();

      for (final recordatorio in recordatorios) {
        if (recordatorio.alarmaProgramada) {
          await cancelarAlarma(recordatorio);
          await programarAlarma(recordatorio);
        }

        if (recordatorio.notificacionProgramada) {
          await programarNotificacionPrevia(recordatorio);
        }
      }

      debugPrint('✅ Todas las alarmas reprogramadas');
    } catch (e) {
      debugPrint('❌ Error reprogramando alarmas: $e');
    }
  }

  // Verificar si hay alarma activa
  bool get alarmaActiva => _alarmaActiva;

  // Obtener estado de la alarma
  String get estadoAlarma {
    if (!_alarmaActiva) return 'Inactiva';
    if (_repeticiones > 0) return 'Repitiendo ($_repeticiones)';
    return 'Activa';
  }

  // Limpiar recursos
  void dispose() {
    _alarmTimer?.cancel();
    _snoozeTicker?.cancel();
    snoozeSecondsLeft.dispose();
  }
}
