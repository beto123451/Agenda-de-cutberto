import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recordatorio.dart';
import '../models/alarma_config.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? _deviceId;
  bool _initialized = false;

  static const String _prefsDeviceId = 'firestore_device_id';
  static const String _prefsMigrated = 'firestore_migrated';
  static const int _maxDocumentos = 800; // Umbral de advertencia

  bool get isInitialized => _initialized;

  /// Inicializar el servicio y obtener/crear ID de dispositivo
  Future<void> init() async {
    try {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ 🔥 CONECTANDO A FIRESTORE...');
      debugPrint('║ Base de datos: (default)');
      debugPrint('╚════════════════════════════════════════╝');

      // Habilitar persistencia offline para que los datos
      // se guarden localmente y se sincronicen al tener internet
      _db.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString(_prefsDeviceId);

      if (_deviceId == null) {
        _deviceId = await _obtenerDeviceId();
        await prefs.setString(_prefsDeviceId, _deviceId!);
      }

      // Marcar como inicializado ANTES de verificar conexión
      // para que las escrituras offline funcionen
      _initialized = true;

      // Verificar conexión real con Firestore
      await _verificarConexion();

      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ ✅ FIRESTORE CONECTADO (online)');
      debugPrint('║ BD: (default)');
      debugPrint('║ Device: $_deviceId');
      debugPrint('╚════════════════════════════════════════╝');
    } catch (e) {
      // Aún sin internet, Firestore funciona en modo offline
      if (_deviceId != null) {
        _initialized = true;
        debugPrint('╔════════════════════════════════════════╗');
        debugPrint('║ ⚠️ FIRESTORE EN MODO OFFLINE');
        debugPrint('║ Los datos se guardarán localmente');
        debugPrint('║ y se sincronizarán al tener internet');
        debugPrint('║ Device: $_deviceId');
        debugPrint('╚════════════════════════════════════════╝');
      } else {
        debugPrint('╔════════════════════════════════════════╗');
        debugPrint('║ ❌ ERROR CONECTANDO A FIRESTORE');
        debugPrint('║ $e');
        debugPrint('╚════════════════════════════════════════╝');
      }
    }
  }

  /// Verificar que la conexión a Firestore funcione
  Future<void> _verificarConexion() async {
    try {
      final testDoc = _db.collection('devices').doc(_deviceId);
      // Timeout de 10s: si no hay internet, no bloquear la app
      await testDoc
          .set({
            'ultimo_acceso': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Sin conexión a internet'),
          );
      debugPrint('║ 🟢 Escritura de prueba exitosa');
    } catch (e) {
      debugPrint('║ 🔴 Error en escritura de prueba: $e');
      rethrow;
    }
  }

  /// Obtener ID único del dispositivo
  Future<String> _obtenerDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } catch (e) {
      // Fallback: generar un ID basado en timestamp
      return 'device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Referencia base del dispositivo
  DocumentReference get _deviceDoc => _db.collection('devices').doc(_deviceId);
  CollectionReference get _recordatoriosRef =>
      _deviceDoc.collection('recordatorios');
  DocumentReference get _configRef =>
      _deviceDoc.collection('config').doc('alarma');
  DocumentReference get _estadisticasRef =>
      _deviceDoc.collection('config').doc('estadisticas');

  // =================== CRUD Recordatorios ===================

  /// Guardar recordatorio en Firestore
  Future<String> guardarRecordatorio(Recordatorio recordatorio) async {
    if (!_initialized) throw Exception('FirestoreService no inicializado');

    try {
      final data = recordatorio.toJson();
      // Remover el id de SQLite, Firestore usa su propio ID
      data.remove('id');

      if (recordatorio.id != null) {
        // Buscar documento existente por sqlite_id
        final existing = await _recordatoriosRef
            .where('sqlite_id', isEqualTo: recordatorio.id)
            .get();

        if (existing.docs.isNotEmpty) {
          await existing.docs.first.reference.update(data);
          debugPrint(
            '✅ Recordatorio actualizado en Firestore: ${recordatorio.cliente}',
          );
          return existing.docs.first.id;
        }
      }

      // Guardar sqlite_id como referencia
      if (recordatorio.id != null) {
        data['sqlite_id'] = recordatorio.id;
      }

      final docRef = await _recordatoriosRef.add(data);
      debugPrint(
        '✅ Recordatorio guardado en Firestore: ${recordatorio.cliente} (${docRef.id})',
      );
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Error guardando recordatorio en Firestore: $e');
      rethrow;
    }
  }

  /// Obtener todos los recordatorios
  Future<List<Recordatorio>> getRecordatorios() async {
    if (!_initialized) throw Exception('FirestoreService no inicializado');

    try {
      final snapshot = await _recordatoriosRef
          .orderBy('fecha_proximo_mantenimiento')
          .get();

      final recordatorios = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // Usar sqlite_id como id si existe
        if (data.containsKey('sqlite_id')) {
          data['id'] = data['sqlite_id'];
        }
        return Recordatorio.fromJson(data);
      }).toList();

      debugPrint('📋 Recordatorios desde Firestore: ${recordatorios.length}');
      return recordatorios;
    } catch (e) {
      debugPrint('❌ Error obteniendo recordatorios de Firestore: $e');
      rethrow;
    }
  }

  /// Eliminar recordatorio por sqlite_id
  Future<void> eliminarRecordatorio(int sqliteId) async {
    if (!_initialized) throw Exception('FirestoreService no inicializado');

    try {
      final snapshot = await _recordatoriosRef
          .where('sqlite_id', isEqualTo: sqliteId)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
      debugPrint('🗑️ Recordatorio eliminado de Firestore: ID $sqliteId');
    } catch (e) {
      debugPrint('❌ Error eliminando recordatorio de Firestore: $e');
    }
  }

  // =================== Configuración ===================

  /// Guardar configuración de alarma
  Future<void> guardarConfigAlarma(AlarmaConfig config) async {
    if (!_initialized) return;

    try {
      await _configRef.set(config.toJson());
      debugPrint('✅ Config alarma guardada en Firestore');
    } catch (e) {
      debugPrint('❌ Error guardando config en Firestore: $e');
    }
  }

  /// Obtener configuración de alarma
  Future<AlarmaConfig?> getConfigAlarma() async {
    if (!_initialized) return null;

    try {
      final doc = await _configRef.get();
      if (doc.exists) {
        return AlarmaConfig.fromJson(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo config de Firestore: $e');
      return null;
    }
  }

  // =================== Migración ===================

  /// Verificar si ya se migró la data local
  Future<bool> yaMigrado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsMigrated) ?? false;
  }

  /// Marcar como migrado
  Future<void> marcarComoMigrado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsMigrated, true);
  }

  /// Migrar recordatorios locales a Firestore
  Future<int> migrarRecordatorios(List<Recordatorio> recordatorios) async {
    if (!_initialized) throw Exception('FirestoreService no inicializado');

    int migrados = 0;
    try {
      // Usar batch para eficiencia
      final batch = _db.batch();

      for (final recordatorio in recordatorios) {
        final data = recordatorio.toJson();
        if (recordatorio.id != null) {
          data['sqlite_id'] = recordatorio.id;
        }
        data.remove('id');

        final docRef = _recordatoriosRef.doc();
        batch.set(docRef, data);
        migrados++;
      }

      await batch.commit();
      await marcarComoMigrado();

      debugPrint('✅ Migración completada: $migrados recordatorios');
      return migrados;
    } catch (e) {
      debugPrint('❌ Error en migración: $e');
      rethrow;
    }
  }

  /// Migrar configuración de alarma
  Future<void> migrarConfigAlarma(AlarmaConfig config) async {
    if (!_initialized) return;
    await guardarConfigAlarma(config);
  }

  /// Sincronizar datos forzadamente a Firestore (ignora el flag de migración)
  Future<int> sincronizarForzadamente(List<Recordatorio> recordatorios) async {
    if (!_initialized) throw Exception('FirestoreService no inicializado');

    int sincronizados = 0;
    try {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ 🔄 SINCRONIZANDO DATOS A FIRESTORE...');
      debugPrint('║ Recordatorios a sincronizar: ${recordatorios.length}');
      debugPrint('╚════════════════════════════════════════╝');

      if (recordatorios.isEmpty) {
        debugPrint('ℹ️  No hay recordatorios para sincronizar');
        return 0;
      }

      // Usar batch para eficiencia
      final batch = _db.batch();

      for (final recordatorio in recordatorios) {
        final data = recordatorio.toJson();
        if (recordatorio.id != null) {
          data['sqlite_id'] = recordatorio.id;
        }
        data.remove('id');

        // Buscar si ya existe este recordatorio
        final existing = await _recordatoriosRef
            .where('sqlite_id', isEqualTo: recordatorio.id)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          // Actualizar existente
          batch.set(
            existing.docs.first.reference,
            data,
            SetOptions(merge: true),
          );
          debugPrint('  ↻ Actualizado: ${recordatorio.cliente}');
        } else {
          // Crear nuevo
          final docRef = _recordatoriosRef.doc();
          batch.set(docRef, data);
          debugPrint('  ✚ Nuevo: ${recordatorio.cliente}');
        }
        sincronizados++;
      }

      await batch.commit();

      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║ ✅ SINCRONIZACIÓN COMPLETADA');
      debugPrint('║ Registros sincronizados: $sincronizados');
      debugPrint('╚════════════════════════════════════════╝');

      return sincronizados;
    } catch (e) {
      debugPrint('❌ Error en sincronización: $e');
      rethrow;
    }
  }

  // =================== Almacenamiento ===================

  /// Obtener cantidad de documentos del usuario
  Future<int> contarDocumentos() async {
    if (!_initialized) return 0;

    try {
      final snapshot = await _recordatoriosRef.count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('❌ Error contando documentos: $e');
      return 0;
    }
  }

  /// Obtener información de almacenamiento en Firestore
  Future<Map<String, dynamic>> getFirestoreStorageInfo() async {
    try {
      final count = await contarDocumentos();
      // Estimación: cada documento Firestore usa ~1-2KB
      const estimatedBytesPerDoc = 1500; // 1.5 KB por documento
      final estimatedBytes = count * estimatedBytesPerDoc;

      return {
        'documentCount': count,
        'estimatedBytes': estimatedBytes,
        'estimatedBytesFormatted': _formatBytes(estimatedBytes),
        'maxDocuments': _maxDocumentos,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo info de almacenamiento: $e');
      return {
        'documentCount': 0,
        'estimatedBytes': 0,
        'estimatedBytesFormatted': '0 B',
        'maxDocuments': _maxDocumentos,
      };
    }
  }

  /// Formattear bytes a formato legible
  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 B';

    const List<String> suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int suffixIndex = 0;
    double displaySize = bytes.toDouble();

    while (displaySize >= 1024 && suffixIndex < suffixes.length - 1) {
      displaySize /= 1024;
      suffixIndex++;
    }

    return '${displaySize.toStringAsFixed(2)} ${suffixes[suffixIndex]}';
  }

  /// Verificar si el almacenamiento se está llenando
  Future<bool> almacenamientoCasiLleno() async {
    final count = await contarDocumentos();
    return count >= _maxDocumentos;
  }

  /// Eliminar todos los datos de Firestore del dispositivo
  Future<void> eliminarTodosLosDatos() async {
    if (!_initialized) return;

    try {
      final snapshot = await _recordatoriosRef.get();
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      // Eliminar config
      batch.delete(_configRef);
      batch.delete(_estadisticasRef);

      await batch.commit();
      debugPrint('🧹 Datos de Firestore eliminados');
    } catch (e) {
      debugPrint('❌ Error eliminando datos de Firestore: $e');
    }
  }
}
