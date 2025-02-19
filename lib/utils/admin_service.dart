import 'package:firebase_database/firebase_database.dart';

class AdminService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  Future<void> updateParkingSlotStatus(String slotId, bool isAvailable) async {
    try {
      final slotRef = _dbRef.child('parkingSlots/$slotId');
      await slotRef.update({
        'isAvailable': isAvailable,
        'databaseChangeTime': ServerValue.timestamp,
      });
      print('Parking slot $slotId updated: isAvailable=$isAvailable');
    } catch (e) {
      print('Error updating parking slot status: $e');
      throw e;
    }
  }

  Future<void> cancelReservation(String userId, String reservationId) async {
    try {
      final reservationRef =
          _dbRef.child('reservations/$userId/$reservationId');
      final snapshot = await reservationRef.get();
      if (!snapshot.exists) {
        throw Exception('Reservation not found.');
      }
      final reservationData = Map<String, dynamic>.from(snapshot.value as Map);
      final historyRef = _dbRef.child('history/$userId/$reservationId');
      await historyRef.set({
        ...reservationData,
        'status': 'Canceled',
        'databaseChangeTime': ServerValue.timestamp,
      });
      await reservationRef.remove();
      final slotId = reservationData['slot'];
      final upcomingRef = _dbRef
          .child('parkingSlots/$slotId/upcomingReservations/$reservationId');
      await upcomingRef.remove();
      print('Reservation $reservationId canceled for user $userId.');
    } catch (e) {
      print('Error canceling reservation: $e');
      throw e;
    }
  }

  Future<void> resolveDoubleBooking(String userId, String reservationId) async {
    try {
      await cancelReservation(userId, reservationId);
      print(
          'Double booking resolved by canceling reservation $reservationId for user $userId.');
    } catch (e) {
      print('Error resolving double booking: $e');
      throw e;
    }
  }

  Future<void> extendReservation(
      String userId, String reservationId, String newCheckOutTime) async {
    try {
      final reservationRef =
          _dbRef.child('reservations/$userId/$reservationId');
      await reservationRef.update({
        'checkOut': newCheckOutTime,
        'databaseChangeTime': ServerValue.timestamp,
      });
      print(
          'Reservation $reservationId extended with new check-out time $newCheckOutTime.');
    } catch (e) {
      print('Error extending reservation: $e');
      throw e;
    }
  }
}
