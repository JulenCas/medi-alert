import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/medicine.dart';
import 'notification_service.dart';

class MedicineManager extends ChangeNotifier {
  List<Medicine> _medicines = [];
  static const String _storageKey = 'medicines';

  List<Medicine> get medicines => _medicines;
  List<Medicine> get activeMedicines =>
      _medicines.where((m) => m.isActive).toList();

  // Inicializar el manager
  Future<void> initialize() async {
    await NotificationService.initialize();
    await loadMedicines();
  }

  // Cargar medicinas desde almacenamiento local
  Future<void> loadMedicines() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final medicinesJson = prefs.getString(_storageKey);

      if (medicinesJson != null) {
        final List<dynamic> decoded = json.decode(medicinesJson);
        _medicines = decoded.map((json) => Medicine.fromJson(json)).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Error cargando medicinas: $e');
    }
  }

  // Guardar medicinas en almacenamiento local
  Future<void> saveMedicines() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final medicinesJson = json.encode(
        _medicines.map((m) => m.toJson()).toList(),
      );
      await prefs.setString(_storageKey, medicinesJson);
    } catch (e) {
      print('Error guardando medicinas: $e');
    }
  }

  // Agregar nueva medicina
  Future<void> addMedicine(Medicine medicine) async {
    _medicines.add(medicine);
    await saveMedicines();
    await _scheduleNotifications(medicine);
    notifyListeners();
  }

  // Actualizar medicina existente
  Future<void> updateMedicine(Medicine updatedMedicine) async {
    final index = _medicines.indexWhere((m) => m.id == updatedMedicine.id);
    if (index != -1) {
      // Cancelar notificaciones anteriores
      await NotificationService.cancelMedicineNotifications(
        _medicines[index].name,
      );

      _medicines[index] = updatedMedicine;
      await saveMedicines();

      // Programar nuevas notificaciones si está activa
      if (updatedMedicine.isActive) {
        await _scheduleNotifications(updatedMedicine);
      }

      notifyListeners();
    }
  }

  // Eliminar medicina
  Future<void> removeMedicine(String medicineId) async {
    final medicine = _medicines.firstWhere((m) => m.id == medicineId);
    await NotificationService.cancelMedicineNotifications(medicine.name);

    _medicines.removeWhere((m) => m.id == medicineId);
    await saveMedicines();
    notifyListeners();
  }

  // Activar/desactivar medicina
  Future<void> toggleMedicine(String medicineId) async {
    final index = _medicines.indexWhere((m) => m.id == medicineId);
    if (index != -1) {
      final medicine = _medicines[index];
      final updatedMedicine = medicine.copyWith(isActive: !medicine.isActive);

      if (updatedMedicine.isActive) {
        await _scheduleNotifications(updatedMedicine);
      } else {
        await NotificationService.cancelMedicineNotifications(medicine.name);
      }

      _medicines[index] = updatedMedicine;
      await saveMedicines();
      notifyListeners();
    }
  }

  // Programar notificaciones para una medicina
  Future<void> _scheduleNotifications(Medicine medicine) async {
    if (!medicine.isActive) return;

    await NotificationService.scheduleRepeatingMedicineAlerts(
      medicineName: medicine.name,
      startTime: medicine.startTime,
      intervalHours: medicine.intervalHours,
      totalDays: medicine.totalDays,
    );
  }

  // Reprogramar todas las notificaciones
  Future<void> rescheduleAllNotifications() async {
    await NotificationService.cancelAllNotifications();

    for (final medicine in activeMedicines) {
      await _scheduleNotifications(medicine);
    }
  }

  // Obtener próximas tomas
  List<Map<String, dynamic>> getUpcomingDoses({int limit = 10}) {
    List<Map<String, dynamic>> upcomingDoses = [];

    for (final medicine in activeMedicines) {
      final remainingDoses = medicine.getRemainingDoses();

      for (final doseTime in remainingDoses) {
        upcomingDoses.add({
          'medicine': medicine,
          'time': doseTime,
          'timeUntil': doseTime.difference(DateTime.now()),
        });
      }
    }

    // Ordenar por tiempo
    upcomingDoses.sort((a, b) => a['time'].compareTo(b['time']));

    return upcomingDoses.take(limit).toList();
  }

  // Marcar dosis como tomada
  Future<void> markDoseTaken(String medicineId, DateTime doseTime) async {
    // Aquí podrías implementar un historial de dosis tomadas
    // Por ahora solo mostramos una notificación de confirmación
    await NotificationService.showImmediateNotification(
      title: '✅ Dosis registrada',
      body: 'Has registrado que tomaste tu medicina correctamente',
    );
  }

  // Obtener estadísticas
  Map<String, dynamic> getStatistics() {
    final now = DateTime.now();
    final activeMeds = activeMedicines;

    int totalUpcomingDoses = 0;
    int medicinesEndingThisWeek = 0;

    for (final medicine in activeMeds) {
      totalUpcomingDoses += medicine.getRemainingDoses().length;

      final endTime =
          medicine.startTime.add(Duration(days: medicine.totalDays));
      final daysUntilEnd = endTime.difference(now).inDays;

      if (daysUntilEnd <= 7 && daysUntilEnd > 0) {
        medicinesEndingThisWeek++;
      }
    }

    return {
      'totalMedicines': _medicines.length,
      'activeMedicines': activeMeds.length,
      'upcomingDoses': totalUpcomingDoses,
      'endingThisWeek': medicinesEndingThisWeek,
    };
  }
}
