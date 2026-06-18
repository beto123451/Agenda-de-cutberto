class NotificationSettings {
  final String selectedRingtone; // URI del tono seleccionado
  final bool enableSound;
  final bool enableVibration;

  NotificationSettings({
    this.selectedRingtone = 'default', // default = sonido por defecto del sistema
    this.enableSound = true,
    this.enableVibration = true,
  });

  // Convertir a JSON
  Map<String, dynamic> toJson() => {
    'selectedRingtone': selectedRingtone,
    'enableSound': enableSound,
    'enableVibration': enableVibration,
  };

  // Crear desde JSON
  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      selectedRingtone: json['selectedRingtone'] ?? 'default',
      enableSound: json['enableSound'] ?? true,
      enableVibration: json['enableVibration'] ?? true,
    );
  }

  // Copiar con cambios
  NotificationSettings copyWith({
    String? selectedRingtone,
    bool? enableSound,
    bool? enableVibration,
  }) {
    return NotificationSettings(
      selectedRingtone: selectedRingtone ?? this.selectedRingtone,
      enableSound: enableSound ?? this.enableSound,
      enableVibration: enableVibration ?? this.enableVibration,
    );
  }
}
