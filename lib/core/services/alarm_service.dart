import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:medialert/core/services/notification_service.dart';
import 'package:medialert/domain/entities/medication.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;

  final NotificationService _notificationService = NotificationService();

  // Clave para guardar el mapeo de IDs de medicamentos a IDs de alarmas
  static const String ALARM_MAPPING_KEY = 'ALARM_MAPPING';

  AlarmService._internal();

  Future<void> init() async {
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
      print('AlarmService inicializado correctamente');
    }
  }

  // Verificar si los permisos de alarma exacta están habilitados (Android 12+)
  Future<bool> checkExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // Verificar si estamos en Android 12 o superior
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // Si es Android 12+ (API 31+), verificar el permiso
      if (sdkInt >= 31) {
        // Usar permission_handler para verificar el permiso
        final status = await Permission.scheduleExactAlarm.status;
        return status.isGranted;
      }

      // En versiones anteriores, el permiso en el manifest es suficiente
      return true;
    } catch (e) {
      print('Error al verificar permiso de alarma exacta: $e');
      return false;
    }
  }

  // Solicitar permiso de alarma exacta (Android 12+)
  Future<bool> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // Verificar si estamos en Android 12 o superior
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // Si es Android 12+ (API 31+), solicitar el permiso
      if (sdkInt >= 31) {
        // Usar permission_handler para solicitar el permiso
        final status = await Permission.scheduleExactAlarm.request();
        return status.isGranted;
      }

      // En versiones anteriores, el permiso en el manifest es suficiente
      return true;
    } catch (e) {
      print('Error al solicitar permiso de alarma exacta: $e');
      return false;
    }
  }

  // Método para programar una alarma para un medicamento
  Future<bool> scheduleAlarm(
      Medication medication, DateTime reminderTime) async {
    if (!Platform.isAndroid) {
      // En iOS, usar el sistema de notificaciones normal
      await _notificationService.scheduleMedicationReminder(
          medication, reminderTime);
      return true;
    }

    // Verificar permisos
    final hasPermission = await checkExactAlarmPermission();
    if (!hasPermission) {
      final granted = await requestExactAlarmPermission();
      if (!granted) {
        print('No se concedieron permisos para alarmas exactas');
        return false;
      }
    }

    // Generar un ID único para la alarma basado en el ID del medicamento y la hora
    final alarmId =
        medication.id.hashCode + reminderTime.millisecondsSinceEpoch.hashCode;

    // Guardar la información de la alarma para poder recuperarla cuando se active
    await _saveAlarmInfo(alarmId, medication.id, medication.name,
        medication.dosage, reminderTime);

    // Programar la alarma
    final success = await AndroidAlarmManager.oneShotAt(
      reminderTime,
      alarmId,
      _alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      alarmClock: true, // Esto hace que aparezca en las alarmas del sistema
    );

    if (success) {
      print(
          'Alarma programada con éxito para ${medication.name} a las ${reminderTime.hour}:${reminderTime.minute}');

      // Guardar el mapeo de ID de medicamento a ID de alarma
      await _saveAlarmMapping(medication.id, alarmId);
    } else {
      print('Error al programar la alarma para ${medication.name}');
    }

    return success;
  }

  // Método para programar todas las alarmas de un medicamento
  Future<void> scheduleAllAlarmsForMedication(Medication medication) async {
    if (medication.reminders.isEmpty) {
      print(
          'El medicamento ${medication.name} no tiene recordatorios configurados');
      return;
    }

    // Cancelar alarmas existentes para este medicamento
    await cancelAlarmsForMedication(medication.id);

    // Programar nuevas alarmas para cada recordatorio
    for (final reminderTime in medication.reminders) {
      await scheduleAlarm(medication, reminderTime);
    }
  }

  // Método para cancelar todas las alarmas de un medicamento
  Future<void> cancelAlarmsForMedication(String medicationId) async {
    if (!Platform.isAndroid) {
      await _notificationService.cancelMedicationReminder(medicationId);
      return;
    }

    // Obtener los IDs de alarma asociados con este medicamento
    final alarmIds = await _getAlarmIdsForMedication(medicationId);

    // Cancelar cada alarma
    for (final alarmId in alarmIds) {
      await AndroidAlarmManager.cancel(alarmId);
      print('Alarma $alarmId cancelada para el medicamento $medicationId');
    }

    // Limpiar el mapeo
    await _removeAlarmMapping(medicationId);
  }

  // Método para cancelar todas las alarmas
  Future<void> cancelAllAlarms() async {
    if (!Platform.isAndroid) {
      await _notificationService.cancelAllReminders();
      return;
    }

    // Obtener todos los mapeos de alarmas
    final prefs = await SharedPreferences.getInstance();
    final alarmMappingString = prefs.getString(ALARM_MAPPING_KEY);

    if (alarmMappingString != null && alarmMappingString.isNotEmpty) {
      final alarmMapping = Map<String, List<int>>.from(
          Map<String, dynamic>.from(Map<String, dynamic>.from(
                  await jsonDecode(alarmMappingString)))
              .map((key, value) => MapEntry(key, List<int>.from(value))));

      // Cancelar todas las alarmas
      for (final entry in alarmMapping.entries) {
        for (final alarmId in entry.value) {
          await AndroidAlarmManager.cancel(alarmId);
        }
      }

      // Limpiar todos los mapeos
      await prefs.remove(ALARM_MAPPING_KEY);
    }
  }

  // Método para guardar información de la alarma
  Future<void> _saveAlarmInfo(int alarmId, String medicationId,
      String medicationName, String dosage, DateTime reminderTime) async {
    final prefs = await SharedPreferences.getInstance();
    final alarmInfo = {
      'medicationId': medicationId,
      'medicationName': medicationName,
      'dosage': dosage,
      'reminderTime': reminderTime.millisecondsSinceEpoch,
    };

    await prefs.setString('alarm_$alarmId', jsonEncode(alarmInfo));
  }

  // Método para guardar el mapeo de ID de medicamento a IDs de alarma
  Future<void> _saveAlarmMapping(String medicationId, int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final alarmMappingString = prefs.getString(ALARM_MAPPING_KEY);

    Map<String, List<int>> alarmMapping = {};

    if (alarmMappingString != null && alarmMappingString.isNotEmpty) {
      alarmMapping = Map<String, List<int>>.from(
          Map<String, dynamic>.from(await jsonDecode(alarmMappingString))
              .map((key, value) => MapEntry(key, List<int>.from(value))));
    }

    if (!alarmMapping.containsKey(medicationId)) {
      alarmMapping[medicationId] = [];
    }

    alarmMapping[medicationId]!.add(alarmId);

    await prefs.setString(ALARM_MAPPING_KEY, jsonEncode(alarmMapping));
  }

  // Método para obtener los IDs de alarma asociados con un medicamento
  Future<List<int>> _getAlarmIdsForMedication(String medicationId) async {
    final prefs = await SharedPreferences.getInstance();
    final alarmMappingString = prefs.getString(ALARM_MAPPING_KEY);

    if (alarmMappingString == null || alarmMappingString.isEmpty) {
      return [];
    }

    final alarmMapping = Map<String, List<int>>.from(
        Map<String, dynamic>.from(await jsonDecode(alarmMappingString))
            .map((key, value) => MapEntry(key, List<int>.from(value))));

    return alarmMapping[medicationId] ?? [];
  }

  // Método para eliminar el mapeo de un medicamento
  Future<void> _removeAlarmMapping(String medicationId) async {
    final prefs = await SharedPreferences.getInstance();
    final alarmMappingString = prefs.getString(ALARM_MAPPING_KEY);

    if (alarmMappingString == null || alarmMappingString.isEmpty) {
      return;
    }

    final alarmMapping = Map<String, List<int>>.from(
        Map<String, dynamic>.from(await jsonDecode(alarmMappingString))
            .map((key, value) => MapEntry(key, List<int>.from(value))));

    alarmMapping.remove(medicationId);

    await prefs.setString(ALARM_MAPPING_KEY, jsonEncode(alarmMapping));
  }
}

// Callback que se ejecutará cuando se active la alarma
@pragma('vm:entry-point')
void _alarmCallback(int alarmId) async {
  // Necesitamos inicializar WidgetsFlutterBinding para poder usar SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();

  // Obtener la información de la alarma
  final prefs = await SharedPreferences.getInstance();
  final alarmInfoString = prefs.getString('alarm_$alarmId');

  if (alarmInfoString != null) {
    final alarmInfo =
        Map<String, dynamic>.from(await jsonDecode(alarmInfoString));

    // Mostrar una notificación
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Inicializar el plugin de notificaciones
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Mostrar la notificación
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'medication_reminders',
      'Recordatorios de Medicamentos',
      channelDescription:
          'Notificaciones para recordarte tomar tus medicamentos',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      alarmId,
      'Recordatorio de medicamento',
      'Es hora de tomar ${alarmInfo['medicationName']} - ${alarmInfo['dosage']}',
      platformChannelSpecifics,
      payload: alarmInfo['medicationId'],
    );

    print('Notificación mostrada para la alarma $alarmId');
  }
}
