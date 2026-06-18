import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../utils/theme.dart';

class AppTutorial {
  static const String _prefsTutorialShown = 'tutorial_shown_v1';

  /// Verifica si el tutorial ya fue mostrado
  static Future<bool> shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_prefsTutorialShown) ?? false);
  }

  /// Marca el tutorial como visto
  static Future<void> markTutorialAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTutorialShown, true);
  }

  /// Reinicia el tutorial para que se muestre de nuevo
  static Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTutorialShown);
  }

  /// Crea y muestra el tutorial guiado con scroll automático
  static void showTutorial({
    required BuildContext context,
    required ScrollController scrollController,
    required GlobalKey keyWelcomeCard,
    required GlobalKey keyStatistics,
    required GlobalKey keySearchBar,
    required GlobalKey keyFilters,
    required GlobalKey keyQuickActions,
    required GlobalKey keyUpcoming,
    required GlobalKey keyFab,
    required GlobalKey keyNotifications,
    required GlobalKey keySettings,
    VoidCallback? onFinish,
  }) {
    // Order of targets with their keys for scrolling
    final targetKeys = [
      keyNotifications,  // 1 - visible in appbar
      keySettings,       // 2 - visible in appbar
      keyWelcomeCard,    // 3 - top of scroll
      keyStatistics,     // 4 - needs scroll
      keySearchBar,      // 5 - needs scroll
      keyFilters,        // 6 - needs scroll
      keyQuickActions,   // 7 - needs scroll
      keyUpcoming,       // 8 - needs scroll
      keyFab,            // 9 - always visible (floating)
    ];

    final targets = <TargetFocus>[
      // 1. Notificaciones (en appbar, siempre visible)
      _buildTarget(
        identify: 'notifications',
        keyTarget: keyNotifications,
        shape: ShapeLightFocus.Circle,
        title: '¡Bienvenido! 👋',
        description:
            'Te voy a enseñar cómo usar la app paso a paso.\n\n'
            '🔔 Aquí revisas tus notificaciones pendientes.',
        stepNumber: 1,
        totalSteps: 9,
        alignContent: ContentAlign.bottom,
      ),

      // 2. Configuración (en appbar, siempre visible)
      _buildTarget(
        identify: 'settings',
        keyTarget: keySettings,
        shape: ShapeLightFocus.Circle,
        title: 'Configuración ⚙️',
        description:
            'Aquí activas los permisos: ubicación, notificaciones, alarmas y más.',
        stepNumber: 2,
        totalSteps: 9,
        alignContent: ContentAlign.bottom,
      ),

      // 3. Tarjeta de bienvenida
      _buildTarget(
        identify: 'welcome',
        keyTarget: keyWelcomeCard,
        shape: ShapeLightFocus.RRect,
        title: 'Tu Perfil 👤',
        description:
            'Tu tarjeta de perfil con el resumen de recordatorios: pendientes, próximos y total.',
        stepNumber: 3,
        totalSteps: 9,
        alignContent: ContentAlign.bottom,
      ),

      // 4. Estadísticas
      _buildTarget(
        identify: 'statistics',
        keyTarget: keyStatistics,
        shape: ShapeLightFocus.RRect,
        title: 'Resumen del Día 📊',
        description:
            'Cuántos mantenimientos tienes pendientes, próximos y vencidos.',
        stepNumber: 4,
        totalSteps: 9,
        alignContent: ContentAlign.bottom,
      ),

      // 5. Barra de búsqueda
      _buildTarget(
        identify: 'searchBar',
        keyTarget: keySearchBar,
        shape: ShapeLightFocus.RRect,
        title: 'Buscar 🔍',
        description:
            'Busca por nombre de cliente, equipo o ubicación.',
        stepNumber: 5,
        totalSteps: 9,
        alignContent: ContentAlign.bottom,
      ),

      // 6. Filtros
      _buildTarget(
        identify: 'filters',
        keyTarget: keyFilters,
        shape: ShapeLightFocus.RRect,
        title: 'Filtros 🏷️',
        description:
            'Filtra por: Todos, Pendientes, Próximos o Vencidos.',
        stepNumber: 6,
        totalSteps: 9,
        alignContent: ContentAlign.bottom,
      ),

      // 7. Acciones rápidas
      _buildTarget(
        identify: 'quickActions',
        keyTarget: keyQuickActions,
        shape: ShapeLightFocus.RRect,
        title: 'Acciones Rápidas ⚡',
        description:
            '• Nuevo Recordatorio\n'
            '• Ver Todos los servicios\n'
            '• Mapa de ubicaciones\n'
            '• Probar Alarma',
        stepNumber: 7,
        totalSteps: 9,
        alignContent: ContentAlign.top,
      ),

      // 8. Próximos mantenimientos
      _buildTarget(
        identify: 'upcoming',
        keyTarget: keyUpcoming,
        shape: ShapeLightFocus.RRect,
        title: 'Próximos Mantenimientos 📅',
        description:
            'Los servicios por vencer. Toca uno para ver detalles o editarlo.',
        stepNumber: 8,
        totalSteps: 9,
        alignContent: ContentAlign.top,
      ),

      // 9. Botón de agregar (FAB, siempre visible)
      _buildTarget(
        identify: 'fab',
        keyTarget: keyFab,
        shape: ShapeLightFocus.Circle,
        title: 'Crear Recordatorio ➕',
        description:
            '¡Lo más importante! Toca aquí para agregar un nuevo mantenimiento.\n\n'
            '¡Eso es todo! Ya estás listo. 🎉',
        stepNumber: 9,
        totalSteps: 9,
        alignContent: ContentAlign.top,
      ),
    ];

    int currentStep = 0;

    /// Scrollea al siguiente target antes de mostrarlo
    Future<void> _scrollToTarget(int stepIndex) async {
      if (stepIndex >= targetKeys.length) return;
      final key = targetKeys[stepIndex];
      final keyContext = key.currentContext;
      if (keyContext != null) {
        await Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.3, // centrar un poco arriba
        );
        // Pequeña pausa para que el scroll termine
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // Scroll al primer target antes de empezar
    _scrollToTarget(0).then((_) {
      final tutorial = TutorialCoachMark(
        targets: targets,
        colorShadow: Colors.black,
        opacityShadow: 0.88,
        textSkip: 'SALTAR',
        textStyleSkip: const TextStyle(
          color: AppTheme.accentColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        paddingFocus: 8,
        hideSkip: false,
        focusAnimationDuration: const Duration(milliseconds: 300),
        unFocusAnimationDuration: const Duration(milliseconds: 300),
        onClickTarget: (target) {
          currentStep++;
          _scrollToTarget(currentStep);
        },
        onClickOverlay: (target) {
          currentStep++;
          _scrollToTarget(currentStep);
        },
        onFinish: () {
          markTutorialAsShown();
          // Scroll de vuelta al inicio
          scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
          onFinish?.call();
        },
        onSkip: () {
          markTutorialAsShown();
          scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
          onFinish?.call();
          return true;
        },
      );

      tutorial.show(context: context);
    });
  }

  static TargetFocus _buildTarget({
    required String identify,
    required GlobalKey keyTarget,
    required ShapeLightFocus shape,
    required String title,
    required String description,
    required int stepNumber,
    required int totalSteps,
    ContentAlign alignContent = ContentAlign.bottom,
  }) {
    return TargetFocus(
      identify: identify,
      keyTarget: keyTarget,
      shape: shape,
      radius: 12,
      enableOverlayTab: true,
      enableTargetTab: true,
      contents: [
        TargetContent(
          align: alignContent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          builder: (context, controller) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.accentColor.withOpacity(0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentColor.withOpacity(0.15),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step indicator + progress bar
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.accentColor.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          '$stepNumber / $totalSteps',
                          style: TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: stepNumber / totalSteps,
                            backgroundColor:
                                AppTheme.textSecondaryColor.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.accentColor,
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Description
                  Text(
                    description,
                    style: TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Tap hint
                  Center(
                    child: Text(
                      'Toca para continuar →',
                      style: TextStyle(
                        color: AppTheme.accentColor.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
