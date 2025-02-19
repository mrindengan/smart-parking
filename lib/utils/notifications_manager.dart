import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationManager {
  /// Initialize Awesome Notifications
  static void initialize() {
    print("Initializing Notification Manager...");
    try {
      AwesomeNotifications().initialize(
        'resource://drawable/res_app_icon', // Ensure this is a valid resource
        [
          NotificationChannel(
            channelKey: 'reminder_channel',
            channelName: 'Reminder Notifications',
            channelDescription: 'Notification channel for reminders',
            defaultColor: const Color(0xFF9D50DD),
            ledColor: Colors.white,
            importance: NotificationImportance.High,
            channelShowBadge: true,
          ),
        ],
      );

      // Request permission to send notifications
      AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
        if (!isAllowed) {
          print("Requesting notification permissions...");
          AwesomeNotifications().requestPermissionToSendNotifications(
            permissions: [
              NotificationPermission.Alert,
              NotificationPermission.Sound,
              NotificationPermission.Badge,
              NotificationPermission.Light,
              NotificationPermission.Vibration,
            ],
          );
        } else {
          print("Notification permissions already granted.");
        }
      });

      // Set notification listeners
      AwesomeNotifications().setListeners(
        onActionReceivedMethod: handleNotificationAction,
        onNotificationCreatedMethod: onNotificationCreated,
        onNotificationDisplayedMethod: handleNotificationDisplayed,
        onDismissActionReceivedMethod: handleNotificationDismissed,
      );

      print("Notification Manager initialized successfully.");
    } catch (e) {
      print("Error initializing Notification Manager: $e");
    }
  }

  /// Handle notification creation
  static Future<void> onNotificationCreated(
      ReceivedNotification receivedNotification) async {
    print("Notification created: ${receivedNotification.title}");
    // Add additional logic if needed, e.g., logging or UI updates
  }

  /// Handle notification action (when a user interacts with a notification)
  static Future<void> handleNotificationAction(
      ReceivedAction receivedAction) async {
    print("Notification action received: ${receivedAction.title}");
    // Navigate to specific pages or handle custom actions based on the notification
    if (receivedAction.payload != null) {
      print("Payload data: ${receivedAction.payload}");
      // Add logic to navigate or process based on the payload
    }
  }

  /// Handle notification display
  static Future<void> handleNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    print("Notification displayed: ${receivedNotification.title}");
    // Add additional logic if needed, e.g., tracking analytics
  }

  /// Handle notification dismissal
  static Future<void> handleNotificationDismissed(
      ReceivedAction receivedAction) async {
    print("Notification dismissed: ${receivedAction.title}");
    // Add additional logic if needed, e.g., updating server-side state
  }

  /// Schedule a notification
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    Map<String, String>? payload,
  }) async {
    try {
      // Validate that the scheduled time is in the future
      if (scheduledTime.isBefore(DateTime.now())) {
        print(
            "Error: Scheduled time is in the past. Notification not scheduled.");
        return;
      }

      print("Scheduling notification: $title at $scheduledTime");

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: 'reminder_channel',
          title: title,
          body: body,
          payload: payload, // Optional payload for custom data
        ),
        schedule: NotificationCalendar(
          year: scheduledTime.year,
          month: scheduledTime.month,
          day: scheduledTime.day,
          hour: scheduledTime.hour,
          minute: scheduledTime.minute,
          second: 0,
          millisecond: 0,
          preciseAlarm: true,
        ),
      );

      print("Notification scheduled successfully.");
    } catch (e) {
      print("Error scheduling notification: $e");
    }
  }

  /// Cancel a specific notification by ID
  static Future<void> cancelNotification(int id) async {
    try {
      print("Cancelling notification with ID: $id");
      await AwesomeNotifications().cancel(id);
      print("Notification cancelled successfully.");
    } catch (e) {
      print("Error cancelling notification with ID $id: $e");
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      print("Cancelling all notifications...");
      await AwesomeNotifications().cancelAll();
      print("All notifications cancelled successfully.");
    } catch (e) {
      print("Error cancelling all notifications: $e");
    }
  }

  /// Utility method to check if notifications are allowed
  static Future<bool> areNotificationsAllowed() async {
    return await AwesomeNotifications().isNotificationAllowed();
  }

  /// Request permissions if not granted
  static Future<void> requestPermissionsIfNeeded() async {
    final isAllowed = await areNotificationsAllowed();
    if (!isAllowed) {
      print("Requesting notification permissions...");
      await AwesomeNotifications().requestPermissionToSendNotifications(
        permissions: [
          NotificationPermission.Alert,
          NotificationPermission.Sound,
          NotificationPermission.Badge,
          NotificationPermission.Vibration,
          NotificationPermission.Light,
        ],
      );
    } else {
      print("Notification permissions already granted.");
    }
  }

  /// Retrieve all scheduled notifications (for debugging or displaying in the app)
  static Future<List<NotificationModel>> getScheduledNotifications() async {
    try {
      final notifications =
          await AwesomeNotifications().listScheduledNotifications();
      print("Scheduled notifications retrieved: ${notifications.length}");
      return notifications;
    } catch (e) {
      print("Error retrieving scheduled notifications: $e");
      return [];
    }
  }

  static void handleCheckInReminders(Map<String, dynamic> reservations) {
    final now = DateTime.now();

    for (final userEntry in reservations.entries) {
      final userReservations = Map<String, dynamic>.from(userEntry.value);

      for (final reservationEntry in userReservations.entries) {
        final reservation = Map<String, dynamic>.from(reservationEntry.value);

        final String slotId = reservation['slot'];
        final String checkIn = reservation['checkIn'];
        final String date = reservation['date'];

        final DateTime? checkInTime = _parseDateTime(checkIn, date);
        if (checkInTime == null) continue;

        final int minutesUntilCheckIn = checkInTime.difference(now).inMinutes;

        if (checkInTime.isAfter(now) &&
            (minutesUntilCheckIn == 30 || minutesUntilCheckIn == 5)) {
          final String body = minutesUntilCheckIn == 30
              ? "Your reserved slot $slotId is scheduled for $checkIn. Please check in on time."
              : "Your reserved slot $slotId is about to begin. Please check in to confirm your reservation.";
          scheduleNotification(
            id: int.tryParse(slotId) ?? 0, // Safe parsing
            title: "Reservation Reminder",
            body: body,
            scheduledTime:
                checkInTime.subtract(Duration(minutes: minutesUntilCheckIn)),
          );
        }
      }
    }
  }

  static Future<void> handleMissedCheckIns(
    Map<String, dynamic> reservations,
    Future<void> Function(
            String userId, String reservationId, String slotId, String status)
        updateDatabase,
  ) async {
    final now = DateTime.now();

    for (final userEntry in reservations.entries) {
      final userId = userEntry.key;
      final userReservations = Map<String, dynamic>.from(userEntry.value);

      for (final reservationEntry in userReservations.entries) {
        final reservationId = reservationEntry.key;
        final reservation = Map<String, dynamic>.from(reservationEntry.value);

        final String slotId = reservation['slot'];
        final String checkIn = reservation['checkIn'];
        final String date = reservation['date'];
        final bool isCheckedIn = reservation['isCheckedIn'] ?? false;

        final DateTime? checkInTime = _parseDateTime(checkIn, date);
        if (checkInTime == null) {
          print('DEBUG: Invalid check-in time for reservation $reservationId.');
          continue;
        }

        if (now.isAfter(checkInTime.add(const Duration(minutes: 30))) &&
            !isCheckedIn) {
          print(
              'DEBUG: Missed check-in detected for reservation $reservationId.');

          // Move reservation to history
          await updateDatabase(
              userId, reservationId, slotId, 'Missed Check-In');

          // Notify the user
          await scheduleNotification(
            id: int.tryParse(slotId) ?? 0, // Safe parsing
            title: "Reservation Canceled",
            body:
                "You missed your reservation for slot $slotId scheduled at $checkIn. The slot is now available for others.",
            scheduledTime:
                now.add(const Duration(seconds: 1)), // Immediate notification
          );
        }
      }
    }
  }

  static void handleCheckOutReminders(Map<String, dynamic> reservations) {
    final now = DateTime.now();

    for (final userEntry in reservations.entries) {
      final userReservations = Map<String, dynamic>.from(userEntry.value);

      for (final reservationEntry in userReservations.entries) {
        final reservation = Map<String, dynamic>.from(reservationEntry.value);

        final String slotId = reservation['slot'];
        final String checkOut = reservation['checkOut'];
        final String date = reservation['date'];

        final DateTime? checkOutTime = _parseDateTime(checkOut, date);
        if (checkOutTime == null) continue;

        final int minutesUntilCheckOut = checkOutTime.difference(now).inMinutes;

        if (checkOutTime.isAfter(now) &&
            (minutesUntilCheckOut == 15 || minutesUntilCheckOut == 5)) {
          final String body = minutesUntilCheckOut == 15
              ? "Your reserved slot $slotId will end at $checkOut. Please prepare to check out."
              : "Your reserved slot $slotId is about to end. Extend your reservation or check out and move your vehicle.";

          scheduleNotification(
            id: int.tryParse(slotId) ?? 0,
            title: "Check-Out Reminder",
            body: body,
            scheduledTime:
                checkOutTime.subtract(Duration(minutes: minutesUntilCheckOut)),
          );
        }
      }
    }
  }

  static Future<void> handleOverdueCheckOuts(
    Map<String, dynamic> reservations,
    Future<void> Function(
            String userId, String reservationId, String slotId, String status)
        updateDatabase,
  ) async {
    final now = DateTime.now();

    for (final userEntry in reservations.entries) {
      final userId = userEntry.key;
      final userReservations = Map<String, dynamic>.from(userEntry.value);

      for (final reservationEntry in userReservations.entries) {
        final reservationId = reservationEntry.key;
        final reservation = Map<String, dynamic>.from(reservationEntry.value);

        final String slotId = reservation['slot'];
        final String checkOut = reservation['checkOut'];
        final String date = reservation['date'];
        final bool isCheckedOut = reservation['isCheckedOut'] ?? false;

        final DateTime? checkOutTime = _parseDateTime(checkOut, date);
        if (checkOutTime == null || isCheckedOut) {
          print(
              'DEBUG: Invalid or already checked-out reservation $reservationId.');
          continue;
        }

        final int minutesOverdue = now.difference(checkOutTime).inMinutes;

        if (minutesOverdue > 0 &&
            minutesOverdue % 5 == 0 &&
            minutesOverdue <= 25) {
          print(
              'DEBUG: Overdue check-out detected for reservation $reservationId. Sending notification.');
          // Notify the user about overdue check-out
          await scheduleNotification(
            id: int.tryParse(slotId) ?? 0, // Safe parsing
            title: "Check-Out Overdue",
            body:
                "Your reservation for slot $slotId ended at $checkOut. Please check out immediately.",
            scheduledTime:
                now.add(const Duration(seconds: 1)), // Immediate notification
          );
        }

        if (minutesOverdue > 30) {
          print(
              'DEBUG: Automatically archiving overdue reservation $reservationId.');
          // Automatically move the reservation to history
          await updateDatabase(
              userId, reservationId, slotId, 'Auto Checked-Out');
        }
      }
    }
  }

  static DateTime? _parseDateTime(String? time, String? date) {
    if (time == null || date == null) {
      print('DEBUG: Invalid time or date input. Returning null.');
      return null;
    }

    try {
      final dateParts = date.split('-'); // Format: DD-MM-YYYY
      final timeParts = time.split(':'); // Format: HH:MM AM/PM
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1].split(' ')[0]);
      final isPM = time.toUpperCase().contains('PM');

      final parsedDate = DateTime(
        int.parse(dateParts[2]), // Year
        int.parse(dateParts[1]), // Month
        int.parse(dateParts[0]), // Day
        isPM ? (hour % 12) + 12 : hour,
        minute,
      );

      print('Parsed DateTime: $parsedDate');
      return parsedDate;
    } catch (e) {
      print('ERROR: Failed to parse date/time: $e');
      return null;
    }
  }
}
