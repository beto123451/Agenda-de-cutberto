import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mapas_screen.dart';
import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'services/firestore_service.dart';
import 'utils/theme.dart';

void main() async {
  // Inicialización de zonas horarias
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Firebase
  bool firebaseOk = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseOk = true;
    debugPrint('✅ Firebase inicializado - Proyecto: cutberto');
  } catch (e) {
    debugPrint('⚠️ Firebase no configurado: $e');
  }

  // Inicializar localización
  await initializeDateFormatting('es_ES', null);

  // Inicializar servicios
  final alarmService = AlarmService();
  final notificationService = NotificationService();
  final storageService = StorageService();
  final firestoreService = FirestoreService();

  await storageService.init();
  if (firebaseOk) {
    await firestoreService.init();
  }

  // ⚠️ IMPORTANTE: Inicializar los servicios
  await notificationService.initialize();

  // Inyectar AlarmService en NotificationService para manejar acciones
  notificationService.setAlarmService(alarmService);

  runApp(
    MultiProvider(
      providers: [
        Provider<AlarmService>(create: (_) => alarmService),
        Provider<NotificationService>(create: (_) => notificationService),
        Provider<StorageService>(create: (_) => storageService),
        Provider<FirestoreService>(create: (_) => firestoreService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda Téran',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const WelcomeScreen(),
      // Rutas nombradas para navegación
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/home': (context) => const HomeScreen(),
        '/mapas': (context) => const MapasScreen(),
      },
    );
  }
}
