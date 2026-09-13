// lib/features/sales/data/sales_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/item_category.dart';
import '../domain/item_group.dart';
import '../domain/pos_customer.dart';
import '../domain/pos_item.dart';
import '../domain/pos_location.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';

/// Fetches Items/Categories/Groups/Customers in full (no pagination) since
/// the sale screen needs everything in memory at once for instant
/// search/grouping/pricing — and this doubles as the data set Phase 3
/// (offline) will cache locally.
class SalesRepository {
  SalesRepository(this._firestore);
  final FirebaseFirestore _firestore;

  static const _bulkLimit = 5000;

  CollectionReference<Map<String, dynamic>> _companyCollection(
    String companyId,
    String name,
  ) =>
      _firestore.collection('companies').doc(companyId).collection(name);

  Future<List<PosItem>> fetchAllItems(String companyId) async {
    final snap = await _companyCollection(companyId, 'ITEM').limit(_bulkLimit).get();
    return snap.docs.map((d) => PosItem.fromDoc(d.data())).toList();
  }

  Future<List<ItemGroup>> fetchAllItemGroups(String companyId) async {
    final snap = await _companyCollection(companyId, 'ITEM_GROUP').limit(_bulkLimit).get();
    return snap.docs.map((d) => ItemGroup.fromDoc(d.id, d.data())).toList();
  }

  Future<List<ItemCategory>> fetchAllItemCategories(String companyId) async {
    final snap = await _companyCollection(companyId, 'ITEM_CATEGORY').limit(_bulkLimit).get();
    return snap.docs.map((d) => ItemCategory.fromDoc(d.id, d.data())).toList();
  }

  Future<List<PosCustomer>> fetchAllCustomers(String companyId) async {
    final snap = await _companyCollection(companyId, 'CUSTOMER').limit(_bulkLimit).get();
    return snap.docs.map((d) => PosCustomer.fromDoc(d.id, d.data())).toList();
  }

  Future<List<PosLocation>> fetchAllLocations(String companyId) async {
    final snap = await _companyCollection(companyId, 'LOCATION').limit(_bulkLimit).get();
    return snap.docs.map((d) => PosLocation.fromDoc(d.id, d.data())).toList();
  }

  Future<({String? defaultCustomerCode, String? defaultLocationCode})>
      fetchBusinessUnitDefaults({
    required String companyId,
    required String businessUnitId,
  }) async {
    final snap = await _firestore
        .collection('companies')
        .doc(companyId)
        .collection('businessUnits')
        .doc(businessUnitId)
        .get();
    final data = snap.data();
    return (
      defaultCustomerCode: data?['defaultCustomerCode'] as String?,
      defaultLocationCode: data?['defaultLocationCode'] as String?,
    );
  }

  CollectionReference<Map<String, dynamic>> _ticketsRef(
    String companyId,
    String businessUnitId,
  ) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('businessUnits')
          .doc(businessUnitId)
          .collection('tickets');

  Stream<List<Ticket>> watchOpenTickets({
    required String companyId,
    required String businessUnitId,
  }) {
    return _ticketsRef(companyId, businessUnitId)
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Ticket.fromDoc(d.id, d.data())).toList());
  }

  Future<String> createTicket({
    required String companyId,
    required String businessUnitId,
    required String label,
    required String customerCode,
    required String locationCode,
    required String operatorUid,
    required String operatorName,
  }) async {
    final ref = _ticketsRef(companyId, businessUnitId).doc();
    await ref.set({
      'status': 'open',
      'label': label,
      'customerCode': customerCode,
      'locationCode': locationCode,
      'lines': <Map<String, dynamic>>[],
      'operatorUid': operatorUid,
      'operatorName': operatorName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Full-array rewrite — only safe for mutations that aren't racing rapid
  /// taps (e.g. re-pricing every line after a deliberate customer change).
  Future<void> updateLines({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required List<TicketLine> lines,
  }) {
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<TicketLine> _linesFrom(DocumentSnapshot<Map<String, dynamic>> snap) {
    return (snap.data()?['lines'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TicketLine.fromMap)
        .toList();
  }

  /// Runs as a transaction (reads the current lines fresh from the server
  /// inside it) so rapid taps never clobber each other the way a plain
  /// read-modify-write from possibly-stale client state would.
  Future<void> addOrIncrementItem({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required String itemCode,
    required String description,
    required num unitPrice,
  }) {
    final ref = _ticketsRef(companyId, businessUnitId).doc(ticketId);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final lines = _linesFrom(snap);
      final index = lines.indexWhere((l) => l.itemCode == itemCode);
      if (index >= 0) {
        lines[index] = lines[index].copyWith(qty: lines[index].qty + 1);
      } else {
        lines.add(TicketLine(
          itemCode: itemCode,
          description: description,
          unitPrice: unitPrice,
          qty: 1,
        ));
      }
      tx.update(ref, {
        'lines': lines.map((l) => l.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Same transactional safety as [addOrIncrementItem]; qty <= 0 removes
  /// the line.
  Future<void> setItemQty({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required String itemCode,
    required num newQty,
  }) {
    final ref = _ticketsRef(companyId, businessUnitId).doc(ticketId);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final lines = _linesFrom(snap);
      if (newQty <= 0) {
        lines.removeWhere((l) => l.itemCode == itemCode);
      } else {
        final index = lines.indexWhere((l) => l.itemCode == itemCode);
        if (index >= 0) lines[index] = lines[index].copyWith(qty: newQty);
      }
      tx.update(ref, {
        'lines': lines.map((l) => l.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateCustomer({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required String customerCode,
  }) {
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'customerCode': customerCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeTicket({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
  }) {
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelTicket({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
  }) {
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
