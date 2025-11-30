import 'package:flutter/material.dart';
import 'package:medialert/core/error/failures.dart';
import 'package:medialert/core/services/alarm_service.dart'; // Añadir esta importación
import 'package:medialert/core/services/notification_service.dart';
import 'package:medialert/core/usecases/usecase.dart';
import 'package:medialert/domain/entities/cima_medication.dart';
import 'package:medialert/domain/entities/medication.dart';
import 'package:medialert/domain/entities/medication_intake.dart';
import 'package:medialert/domain/usecases/get_filtered_intakes.dart';
import 'package:medialert/domain/usecases/get_medication_by_id.dart';
import 'package:medialert/domain/usecases/get_medications.dart';
import 'package:medialert/domain/usecases/save_medication.dart';
import 'package:medialert/domain/usecases/save_medication_intake.dart';
import 'package:medialert/domain/usecases/search_cima_medications.dart';
import 'package:medialert/domain/usecases/update_medication.dart';
import 'package:medialert/domain/usecases/update_medication_intake.dart';
import 'package:uuid/uuid.dart';

class MedicationProvider extends ChangeNotifier {
  final GetMedications getMedications;
  final GetMedicationById getMedicationById;
  final SaveMedication saveMedication;
  final UpdateMedication updateMedication;
  final GetFilteredIntakes getFilteredIntakes;
  final SaveMedicationIntake saveMedicationIntake;
  final UpdateMedicationIntake updateMedicationIntake;
  final SearchCimaMedications searchCimaMedications;
  final NotificationService notificationService;
  final AlarmService alarmService; // Añadir el servicio de alarmas

  MedicationProvider({
    required this.getMedications,
    required this.getMedicationById,
    required this.saveMedication,
    required this.updateMedication,
    required this.getFilteredIntakes,
    required this.saveMedicationIntake,
    required this.updateMedicationIntake,
    required this.searchCimaMedications,
    required this.notificationService,
    required this.alarmService, // Añadir el servicio de alarmas
  });

  List<Medication> _medications = [];
  List<Medication> get medications => _medications;

  List<MedicationIntake> _intakes = [];
  List<MedicationIntake> get intakes => _intakes;

  List<CimaMedication> _searchResults = [];
  List<CimaMedication> get searchResults => _searchResults;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> loadMedications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await getMedications(NoParams());
    result.fold(
      (failure) {
        _errorMessage = _mapFailureToMessage(failure);
      },
      (medicationModels) {
        _medications = medicationModels
            .map((model) => Medication(
                  id: model.id,
                  name: model.name,
                  dosage: model.dosage,
                  frequency: model.frequency,
                  reminders: model.reminders,
                  notes: model.notes,
                  registrationNumber: model.registrationNumber,
                ))
            .toList();
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addMedication({
    required String name,
    required String dosage,
    required String frequency,
    required List<DateTime> reminders,
    String? notes,
    String? registrationNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final medication = Medication(
      id: const Uuid().v4(),
      name: name,
      dosage: dosage,
      frequency: frequency,
      reminders: reminders,
      notes: notes,
      registrationNumber: registrationNumber,
    );

    final result =
        await saveMedication(SaveMedicationParams(medication: medication));
    result.fold(
      (failure) {
        _errorMessage = _mapFailureToMessage(failure);
      },
      (_) {
        _medications.add(medication);
        _scheduleRemindersForMedication(medication); // Método actualizado
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> editMedication({
    required String id,
    required String name,
    required String dosage,
    required String frequency,
    required List<DateTime> reminders,
    String? notes,
    String? registrationNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final medicationIndex = _medications.indexWhere((med) => med.id == id);
    if (medicationIndex != -1) {
      // Cancelar recordatorios existentes (notificaciones y alarmas)
      await _cancelRemindersForMedication(id);

      final updatedMedication = _medications[medicationIndex].copyWith(
        name: name,
        dosage: dosage,
        frequency: frequency,
        reminders: reminders,
        notes: notes,
        registrationNumber: registrationNumber,
      );

      final result = await updateMedication(
          UpdateMedicationParams(medication: updatedMedication));
      result.fold(
        (failure) {
          _errorMessage = _mapFailureToMessage(failure);
        },
        (_) {
          _medications[medicationIndex] = updatedMedication;
          _scheduleRemindersForMedication(
              updatedMedication); // Método actualizado
        },
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMedicationIntakes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await getFilteredIntakes(const FilterParams());
    result.fold(
      (failure) {
        _errorMessage = _mapFailureToMessage(failure);
      },
      (intakes) {
        _intakes = intakes;
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> filterIntakes({
    String? medicationName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await getFilteredIntakes(
      FilterParams(
        medicationName: medicationName,
        startDate: startDate,
        endDate: endDate,
      ),
    );

    result.fold(
      (failure) {
        _errorMessage = _mapFailureToMessage(failure);
      },
      (filteredIntakes) {
        _intakes = filteredIntakes;
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> recordMedicationIntake({
    required String medicationId,
    required String medicationName,
    required String dosage,
    required DateTime intakeTime,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final intake = MedicationIntake(
      id: const Uuid().v4(),
      medicationId: medicationId,
      medicationName: medicationName,
      dosage: dosage,
      intakeTime: intakeTime,
      taken: true,
    );

    final result = await saveMedicationIntake(
      SaveIntakeParams(intake: intake),
    );

    result.fold(
      (failure) {
        _errorMessage = _mapFailureToMessage(failure);
      },
      (_) {
        _intakes.add(intake);
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> searchCimaMedicationsByName(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await searchCimaMedications(SearchParams(query: query));
    result.fold(
      (failure) {
        _errorMessage = _mapFailureToMessage(failure);
        _searchResults = [];
      },
      (medications) {
        _searchResults = medications;
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  // Método actualizado para programar recordatorios usando alarmas nativas y notificaciones
  Future<void> _scheduleRemindersForMedication(Medication medication) async {
    final isEnabled =
        await notificationService.isNotificationPermissionEnabled();
    if (!isEnabled) return;

    // Si no hay recordatorios, no hacer nada
    if (medication.reminders.isEmpty) {
      print(
          'El medicamento ${medication.name} no tiene recordatorios configurados');
      return;
    }

    try {
      // Intentar programar alarmas nativas primero
      final hasAlarmPermission = await alarmService.checkExactAlarmPermission();

      if (hasAlarmPermission) {
        // Usar alarmas nativas
        print('Usando alarmas nativas para ${medication.name}');
        await alarmService.scheduleAllAlarmsForMedication(medication);
      } else {
        // Si no hay permiso para alarmas, usar notificaciones como respaldo
        print('Usando notificaciones como respaldo para ${medication.name}');
        await _scheduleNotificationsForMedication(medication);
      }
    } catch (e) {
      // Si hay algún error con las alarmas, usar notificaciones como respaldo
      print(
          'Error al programar alarmas: $e. Usando notificaciones como respaldo.');
      await _scheduleNotificationsForMedication(medication);
    }
  }

  // Método original para programar notificaciones (ahora como respaldo)
  Future<void> _scheduleNotificationsForMedication(
      Medication medication) async {
    final now = DateTime.now();
    for (final reminderTime in medication.reminders) {
      final today = DateTime(now.year, now.month, now.day);
      final scheduledTime = DateTime(
        today.year,
        today.month,
        today.day,
        reminderTime.hour,
        reminderTime.minute,
      );

      final finalTime = scheduledTime.isBefore(now)
          ? scheduledTime.add(const Duration(days: 1))
          : scheduledTime;

      await notificationService.scheduleMedicationReminder(
          medication, finalTime);
    }
  }

  // Método para cancelar todos los recordatorios de un medicamento
  Future<void> _cancelRemindersForMedication(String medicationId) async {
    try {
      // Cancelar alarmas nativas
      await alarmService.cancelAlarmsForMedication(medicationId);
    } catch (e) {
      print('Error al cancelar alarmas: $e');
    }

    // Cancelar notificaciones (como respaldo)
    await notificationService.cancelMedicationReminder(medicationId);
  }

  // Método actualizado para reprogramar todos los recordatorios
  Future<void> rescheduleAllNotifications() async {
    try {
      // Cancelar todas las alarmas
      await alarmService.cancelAllAlarms();
    } catch (e) {
      print('Error al cancelar todas las alarmas: $e');
    }

    // Cancelar todas las notificaciones
    await notificationService.cancelAllReminders();

    // Reprogramar recordatorios para todos los medicamentos activos
    for (final medication in _medications.where((med) => med.isActive)) {
      await _scheduleRemindersForMedication(medication);
    }
  }

  String _mapFailureToMessage(Failure failure) {
    switch (failure.runtimeType) {
      case ServerFailure:
        return 'Error de servidor. Inténtalo de nuevo más tarde.';
      case CacheFailure:
        return 'Error de almacenamiento local. Reinicia la aplicación.';
      case NetworkFailure:
        return 'Sin conexión a Internet. Verifica tu conexión.';
      default:
        return 'Error inesperado. Inténtalo de nuevo.';
    }
  }
}
