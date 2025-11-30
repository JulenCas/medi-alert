class Medicine {
  final String id;
  final String name;
  final String dosage;
  final DateTime startTime;
  final int intervalHours;
  final int totalDays;
  final bool isActive;
  final String? notes;

  Medicine({
    required this.id,
    required this.name,
    required this.dosage,
    required this.startTime,
    required this.intervalHours,
    required this.totalDays,
    this.isActive = true,
    this.notes,
  });

  // Convertir a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'startTime': startTime.toIso8601String(),
      'intervalHours': intervalHours,
      'totalDays': totalDays,
      'isActive': isActive,
      'notes': notes,
    };
  }

  // Crear desde JSON
  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      id: json['id'],
      name: json['name'],
      dosage: json['dosage'],
      startTime: DateTime.parse(json['startTime']),
      intervalHours: json['intervalHours'],
      totalDays: json['totalDays'],
      isActive: json['isActive'] ?? true,
      notes: json['notes'],
    );
  }

  // Crear copia con modificaciones
  Medicine copyWith({
    String? id,
    String? name,
    String? dosage,
    DateTime? startTime,
    int? intervalHours,
    int? totalDays,
    bool? isActive,
    String? notes,
  }) {
    return Medicine(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      startTime: startTime ?? this.startTime,
      intervalHours: intervalHours ?? this.intervalHours,
      totalDays: totalDays ?? this.totalDays,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
    );
  }

  // Calcular próxima toma
  DateTime? getNextDose() {
    if (!isActive) return null;

    final now = DateTime.now();
    final endTime = startTime.add(Duration(days: totalDays));

    if (now.isAfter(endTime)) return null;

    DateTime nextDose = startTime;
    while (nextDose.isBefore(now)) {
      nextDose = nextDose.add(Duration(hours: intervalHours));
    }

    return nextDose.isBefore(endTime) ? nextDose : null;
  }

  // Obtener todas las tomas restantes
  List<DateTime> getRemainingDoses() {
    if (!isActive) return [];

    final now = DateTime.now();
    final endTime = startTime.add(Duration(days: totalDays));
    List<DateTime> doses = [];

    DateTime currentDose = startTime;
    while (currentDose.isBefore(endTime)) {
      if (currentDose.isAfter(now)) {
        doses.add(currentDose);
      }
      currentDose = currentDose.add(Duration(hours: intervalHours));
    }

    return doses;
  }

  // Verificar si está activa
  bool get isCurrentlyActive {
    if (!isActive) return false;

    final now = DateTime.now();
    final endTime = startTime.add(Duration(days: totalDays));

    return now.isAfter(startTime) && now.isBefore(endTime);
  }
}
