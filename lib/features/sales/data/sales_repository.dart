// lib/features/sales/data/sales_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/item_category.dart';
import '../domain/item_group.dart';
import '../domain/pos_customer.dart';
import '../domain/pos_item.dart';
import '../domain/pos_location.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';
import '../domain/zone.dart';

/// Fetches Items/Categories/Groups/Customers in full (no pagination) since
/// the sale screen needs everything in memory at once for instant
/// search/grouping/pricing — and this doubles as the data set Phase 3
/// (offline) will cache locally.
///
/// Two parallel sets of ticket-shaped methods live here: the `Ticket`-named
/// ones back simple/retail mode's free-form `tickets` collection (auto-id
/// docs, several open at once); the `Order`-named ones back BAR/RESTAURANT
/// mode's `orders` collection, where the document id is the tableId itself
/// (at most one active, non-invoiced order per table) and completing one
/// copies it into a separate `invoices` collection rather than just
/// flipping a status field — see [createInvoice] for why.
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

  Future<
      ({
        String? defaultCustomerCode,
        String? defaultLocationCode,
        List<String>? visibleItemGroupCodes,
        String salesMode,
        List<Zone> zones,
      })> fetchBusinessUnitDefaults({
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
      visibleItemGroupCodes: (data?['visibleItemGroupCodes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      salesMode: data?['salesMode'] as String? ?? 'simple',
      zones: (data?['zones'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Zone.fromMap)
          .toList(),
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

  CollectionReference<Map<String, dynamic>> _ordersRef(
    String companyId,
    String businessUnitId,
  ) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('businessUnits')
          .doc(businessUnitId)
          .collection('orders');

  CollectionReference<Map<String, dynamic>> _invoicesRef(
    String companyId,
    String businessUnitId,
  ) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('businessUnits')
          .doc(businessUnitId)
          .collection('invoices');

  // ---------------------------------------------------------------------
  // Simple mode: free-form tickets
  // ---------------------------------------------------------------------

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

  /// Plain optimistic update computed from [currentLines] — the caller's
  /// already-fresh local ticket state (from the same `watchOpenTickets`
  /// stream this screen renders from, which itself reflects Firestore's
  /// latency-compensated pending writes). A transaction re-reading from the
  /// server here would trade that instant local echo for a network round
  /// trip on every tap, which is what actually caused visible lag — the
  /// same-device tap sequence this guards is not truly concurrent, so the
  /// extra round trip bought correctness the flow didn't need.
  Future<void> addOrIncrementItem({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required List<TicketLine> currentLines,
    required String itemCode,
    required String description,
    required num unitPrice,
  }) {
    final lines = List<TicketLine>.from(currentLines);
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
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setItemQty({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required List<TicketLine> currentLines,
    required String itemCode,
    required num newQty,
  }) {
    final lines = List<TicketLine>.from(currentLines);
    if (newQty <= 0) {
      lines.removeWhere((l) => l.itemCode == itemCode);
    } else {
      final index = lines.indexWhere((l) => l.itemCode == itemCode);
      if (index >= 0) lines[index] = lines[index].copyWith(qty: newQty);
    }
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateTicketCustomer({
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

  Future<void> updateTicketLines({
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

  // ---------------------------------------------------------------------
  // BAR/RESTAURANT mode: table-keyed orders -> invoices
  // ---------------------------------------------------------------------

  /// All tables' active (not yet invoiced) orders for the BU. A table with
  /// no order here is simply free — there's no separate "table is open"
  /// marker; tapping into a table is pure navigation with no write (see
  /// TablesScreen), so occupancy is exactly "does this table have an order
  /// going," nothing more.
  Stream<List<Ticket>> watchOpenOrders({
    required String companyId,
    required String businessUnitId,
  }) {
    return _ordersRef(companyId, businessUnitId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Ticket.fromDoc(d.id, d.data())).toList());
  }

  /// [currentLines] empty means (as far as this device's local state knows)
  /// no order exists yet for this table. That first-ever add used to go
  /// through a transaction that re-read the server and merged into a
  /// winner's order if one already existed — but a transaction needs a
  /// live round trip, so offline it just hangs with no optimistic echo,
  /// which is exactly the case offline mode most needs to keep working.
  /// This is a plain `set()` instead: it queues and echoes through the
  /// listener like every other write here, online or off. If another
  /// operator's order already exists server-side by the time this reaches
  /// the backend (two devices tapping the same never-ordered table at
  /// once, or two offline devices both starting one) there's no silent
  /// clobber — Firestore evaluates a `set()` against an existing doc as an
  /// update, and the `orders` rule rejects that unless `operatorUid`
  /// matches, so the loser's write is rejected outright and its local
  /// cache entry is rolled back automatically (see TableSalesScreen's
  /// permission-denied handling). What's lost versus the old transaction
  /// is the convenience of auto-merging the loser's tap into the winner's
  /// order — an acceptable trade since that convenience only ever applied
  /// to a same-instant double-tap, not the offline case this is really
  /// for.
  Future<void> addOrIncrementOrderItem({
    required String companyId,
    required String businessUnitId,
    required String tableId,
    required List<TicketLine> currentLines,
    required String itemCode,
    required String description,
    required num unitPrice,
    String? zoneId,
    String? label,
    String? customerCode,
    String? locationCode,
    String? operatorUid,
    String? operatorName,
  }) {
    final ref = _ordersRef(companyId, businessUnitId).doc(tableId);
    final lines = List<TicketLine>.from(currentLines);
    final index = lines.indexWhere((l) => l.itemCode == itemCode && l.isPending);
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

    if (currentLines.isEmpty) {
      return ref.set({
        'label': label,
        'customerCode': customerCode,
        'locationCode': locationCode,
        'lines': lines.map((l) => l.toMap()).toList(),
        'operatorUid': operatorUid,
        'operatorName': operatorName,
        'tableId': tableId,
        'zoneId': zoneId,
        'currentRound': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    return ref.update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setOrderItemQty({
    required String companyId,
    required String businessUnitId,
    required String tableId,
    required List<TicketLine> currentLines,
    required String itemCode,
    required num newQty,
  }) {
    final lines = List<TicketLine>.from(currentLines);
    if (newQty <= 0) {
      lines.removeWhere((l) => l.itemCode == itemCode && l.isPending);
    } else {
      final index = lines.indexWhere((l) => l.itemCode == itemCode && l.isPending);
      if (index >= 0) lines[index] = lines[index].copyWith(qty: newQty);
    }
    return _ordersRef(companyId, businessUnitId).doc(tableId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stamps every pending line with the next round number so it's locked
  /// into that round's history (one "send" = one kitchen/bar slip), then
  /// bumps [Ticket.currentRound]. The order keeps accumulating rounds
  /// until [createInvoice] closes it out.
  Future<void> sendOrderRound({
    required String companyId,
    required String businessUnitId,
    required String tableId,
    required List<TicketLine> currentLines,
    required int currentRound,
  }) {
    final nextRound = currentRound + 1;
    final lines = currentLines
        .map((l) => l.isPending ? l.copyWith(roundNumber: nextRound) : l)
        .toList();
    return _ordersRef(companyId, businessUnitId).doc(tableId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'currentRound': nextRound,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateOrderCustomer({
    required String companyId,
    required String businessUnitId,
    required String tableId,
    required String customerCode,
  }) {
    return _ordersRef(companyId, businessUnitId).doc(tableId).update({
      'customerCode': customerCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateOrderLines({
    required String companyId,
    required String businessUnitId,
    required String tableId,
    required List<TicketLine> lines,
  }) {
    return _ordersRef(companyId, businessUnitId).doc(tableId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Closes a table's order out into an invoice — the fiscal document
  /// (real fiscalization is future work, but this is the boundary it will
  /// hang off). Orders and invoices are deliberately separate collections
  /// rather than one doc with a status flip: once invoiced, the table's
  /// order slot (keyed by tableId) is freed immediately for the next
  /// party, while the invoice keeps its own permanent, never-reused id.
  ///
  /// Deliberately still a transaction, unlike [addOrIncrementOrderItem] —
  /// which means it needs a live connection and simply won't resolve
  /// offline. That's intentional, not an oversight: closing out a table is
  /// the fiscal boundary, and fiscalization itself will require a
  /// real-time round trip anyway, so there's no point pretending this step
  /// can be queued. The UI gates the button on isOnlineProvider so an
  /// operator never taps it into a silent hang.
  Future<void> createInvoice({
    required String companyId,
    required String businessUnitId,
    required String tableId,
  }) {
    final orderRef = _ordersRef(companyId, businessUnitId).doc(tableId);
    final invoiceRef = _invoicesRef(companyId, businessUnitId).doc();
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      final data = snap.data();
      if (data == null) return;
      tx.set(invoiceRef, {
        ...data,
        'invoicedAt': FieldValue.serverTimestamp(),
      });
      tx.delete(orderRef);
    });
  }

  /// Discards an in-progress order without invoicing it — the table is
  /// immediately free again.
  Future<void> cancelOrder({
    required String companyId,
    required String businessUnitId,
    required String tableId,
  }) {
    return _ordersRef(companyId, businessUnitId).doc(tableId).delete();
  }
}
