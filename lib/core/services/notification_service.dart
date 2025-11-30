import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:medialert/domain/entities/medication.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  Future<void> init() async {
    await initialize();
  }

  // Inicializar el servicio de notificaciones
  static Future<void> initialize() async {
    if (_initialized) return;

    // Inicializar timezone
    tz.initializeTimeZones();

    // Configuración para Android
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configuración para iOS
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  Future<bool> isNotificationPermissionEnabled() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    await initialize();
    if (await Permission.notification.isDenied) {
      final status = await Permission.notification.request();
      return status == PermissionStatus.granted;
    }
    return true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (!enabled) {
      await cancelAllReminders();
    }
  }

  /// Programa un recordatorio para una medicación específica.
  Future<void> scheduleMedicationReminder(
      Medication medication, DateTime scheduledTime) async {
    await initialize();

    await _notifications.zonedSchedule(
      _generateId(medication.id, scheduledTime.millisecondsSinceEpoch),
      'Recordatorio de medicación',
      'Es hora de tomar ${medication.name} (${medication.dosage})',
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medicine_channel',
          'Recordatorios de Medicina',
          channelDescription: 'Notificaciones para recordar tomar medicinas',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'medication:${medication.id}',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Cancela todos los recordatorios asociados a una medicación concreta.
  Future<void> cancelMedicationReminder(String medicationId) async {
    await initialize();

    final pendingNotifications =
        await _notifications.pendingNotificationRequests();

    for (final notification in pendingNotifications) {
      if (notification.payload?.contains('medication:$medicationId') == true) {
        await _notifications.cancel(notification.id);
      }
    }
  }

  /// Cancela todas las notificaciones programadas.
  Future<void> cancelAllReminders() async {
    await initialize();
    await _notifications.cancelAll();
  }

  // Manejar cuando se toca una notificación
  static void _onNotificationTapped(NotificationResponse response) {
    // Aquí puedes navegar a una pantalla específica
    print('Notificación tocada: ${response.payload}');
  }

  // Programar notificación única
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    await initialize();
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medicine_channel',
          'Recordatorios de Medicina',
          channelDescription: 'Notificaciones para recordar tomar medicinas',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Programar notificaciones repetitivas
  static Future<void> scheduleRepeatingMedicineAlerts({
    required String medicineName,
    required DateTime startTime,
    required int intervalHours,
    required int totalDays,
  }) async {
    // Limpiar notificaciones anteriores de esta medicina
    await cancelMedicineNotifications(medicineName);

    // Calcular todas las fechas de notificación
    List<DateTime> notificationTimes = _calculateNotificationTimes(
      startTime,
      intervalHours,
      totalDays,
    );

    // Crear notificaciones individuales
    for (int i = 0; i < notificationTimes.length; i++) {
      await scheduleNotification(
        id: _generateId(medicineName, i),
        title: '💊 Hora de tu medicina',
        body: 'Es hora de tomar $medicineName',
        scheduledTime: notificationTimes[i],
        payload: 'medicine:$medicineName',
      );
    }
  }

  // Calcular todas las fechas de notificación
  static List<DateTime> _calculateNotificationTimes(
    DateTime startTime,
    int intervalHours,
    int totalDays,
  ) {
    List<DateTime> times = [];
    DateTime currentTime = startTime;
    DateTime endTime = startTime.add(Duration(days: totalDays));

    while (currentTime.isBefore(endTime)) {
      times.add(currentTime);
      currentTime = currentTime.add(Duration(hours: intervalHours));
    }

    return times;
  }

  // Generar ID único para cada notificación
  static int _generateId(String reference, int index) {
    return '$reference$index'.hashCode.abs();
  }

  // Cancelar notificaciones de una medicina específica
  static Future<void> cancelMedicineNotifications(String medicineName) async {
    await initialize();
    final pendingNotifications =
        await _notifications.pendingNotificationRequests();

    for (final notification in pendingNotifications) {
      if (notification.payload?.contains('medicine:$medicineName') == true) {
        await _notifications.cancel(notification.id);
      }
    }
  }

  // Cancelar todas las notificaciones
  static Future<void> cancelAllNotifications() async {
    await initialize();
    await _notifications.cancelAll();
  }

  // Obtener notificaciones pendientes
  static Future<List<PendingNotificationRequest>>
      getPendingNotifications() async {
    await initialize();
    return await _notifications.pendingNotificationRequests();
  }

  // Mostrar notificación inmediata (para testing)
  static Future<void> showImmediateNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Test Notifications',
          channelDescription: 'Canal para notificaciones de prueba',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
