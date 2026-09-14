// lib/features/sales/data/sales_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/item_category.dart';
import '../domain/item_group.dart';
import '../domain/pos_customer.dart';
import '../domain/pos_item.dart';
import '../domain/pos_location.dart';
import '../domain/table_claim.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';
import '../domain/zone.dart';

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

  CollectionReference<Map<String, dynamic>> _tableClaimsRef(
    String companyId,
    String businessUnitId,
  ) =>
      _firestore
          .collection('companies')
          .doc(companyId)
          .collection('businessUnits')
          .doc(businessUnitId)
          .collection('tableClaims');

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

  /// Ownership/occupied info for one table — the source of truth for
  /// "who has this table open" independent of whether an order has been
  /// started on it yet (see [claimTable]).
  Stream<TableClaim?> watchTableClaim({
    required String companyId,
    required String businessUnitId,
    required String tableId,
  }) {
    return _tableClaimsRef(companyId, businessUnitId)
        .doc(tableId)
        .snapshots()
        .map((snap) => TableClaim.fromDoc(snap.data()));
  }

  Future<String> createTicket({
    required String companyId,
    required String businessUnitId,
    required String label,
    required String customerCode,
    required String locationCode,
    required String operatorUid,
    required String operatorName,
    String? tableId,
    String? zoneId,
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
      'tableId': tableId,
      'zoneId': zoneId,
      'currentRound': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Atomically opens a table for [operatorUid] — or, if someone already
  /// has it, says who instead of taking it over. This is what prevents the
  /// double-booking race where two operators tap the same "free" table at
  /// the same moment: whichever transaction's write commits first wins on
  /// the server, and the loser is told who already has it.
  ///
  /// Opening a table does NOT create an order/invoice — a table can sit
  /// open with nothing on it yet (matches how a waiter actually works: seat
  /// the guests, then take the order once they're ready). The first order
  /// is created lazily by [addOrIncrementItem] once an item is actually
  /// added.
  Future<({bool claimedByMe, String ownerUid, String ownerName})> claimTable({
    required String companyId,
    required String businessUnitId,
    required String tableId,
    required String customerCode,
    required String locationCode,
    required String operatorUid,
    required String operatorName,
  }) {
    final claimRef = _tableClaimsRef(companyId, businessUnitId).doc(tableId);

    return _firestore.runTransaction((tx) async {
      final claimSnap = await tx.get(claimRef);
      final claim = claimSnap.data();
      if (claim != null && claim['status'] == 'occupied') {
        return (
          claimedByMe: false,
          ownerUid: claim['operatorUid'] as String? ?? '',
          ownerName: claim['operatorName'] as String? ?? '',
        );
      }

      tx.set(claimRef, {
        'status': 'occupied',
        'operatorUid': operatorUid,
        'operatorName': operatorName,
        'customerCode': customerCode,
        'locationCode': locationCode,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return (claimedByMe: true, ownerUid: operatorUid, ownerName: operatorName);
    });
  }

  /// Leaves a table that was opened but never had an order started on it
  /// (e.g. guests left before ordering) — just frees the claim, there's no
  /// ticket to cancel.
  Future<void> leaveEmptyTable({
    required String companyId,
    required String businessUnitId,
    required String tableId,
  }) {
    return _releaseTableClaim(companyId, businessUnitId, tableId);
  }

  Future<void> _releaseTableClaim(
    String companyId,
    String businessUnitId,
    String tableId,
  ) {
    return _tableClaimsRef(companyId, businessUnitId).doc(tableId).set({
      'status': 'free',
      'operatorUid': null,
      'operatorName': null,
      'customerCode': null,
      'locationCode': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  /// Plain optimistic update computed from [currentLines] — the caller's
  /// already-fresh local ticket state (from the same `watchOpenTickets`
  /// stream this screen renders from, which itself reflects Firestore's
  /// latency-compensated pending writes). A transaction re-reading from the
  /// server here would trade that instant local echo for a network round
  /// trip on every tap, which is what actually caused visible lag — the
  /// same-device tap sequence this guards is not truly concurrent, so the
  /// extra round trip bought correctness the flow didn't need.
  ///
  /// Only merges into a *pending* (not yet sent) line with the same item
  /// code — an already-sent line from an earlier round is left alone so a
  /// re-order starts a fresh pending line instead of reopening history.
  ///
  /// [ticketId] null means no order exists yet for this table (it's open
  /// but nothing's been ordered) — this is where that first order gets
  /// created, lazily, with just this one line. Returns the ticket id
  /// (unchanged if one was already passed in).
  Future<String> addOrIncrementItem({
    required String companyId,
    required String businessUnitId,
    required String? ticketId,
    required List<TicketLine> currentLines,
    required String itemCode,
    required String description,
    required num unitPrice,
    String? tableId,
    String? zoneId,
    String? label,
    String? customerCode,
    String? locationCode,
    String? operatorUid,
    String? operatorName,
  }) async {
    if (ticketId == null) {
      final ref = _ticketsRef(companyId, businessUnitId).doc();
      await ref.set({
        'status': 'open',
        'label': label,
        'customerCode': customerCode,
        'locationCode': locationCode,
        'lines': [
          TicketLine(
            itemCode: itemCode,
            description: description,
            unitPrice: unitPrice,
            qty: 1,
          ).toMap(),
        ],
        'operatorUid': operatorUid,
        'operatorName': operatorName,
        'tableId': tableId,
        'zoneId': zoneId,
        'currentRound': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }

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
    await _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ticketId;
  }

  /// Same optimistic-from-local-state approach as [addOrIncrementItem].
  /// qty <= 0 removes the line. Only ever targets pending lines — quantity
  /// on an already-sent round isn't editable from the cart.
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
      lines.removeWhere((l) => l.itemCode == itemCode && l.isPending);
    } else {
      final index = lines.indexWhere((l) => l.itemCode == itemCode && l.isPending);
      if (index >= 0) lines[index] = lines[index].copyWith(qty: newQty);
    }
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// BAR/RESTAURANT mode: stamps every pending line with the next round
  /// number so it's locked into that round's history, then bumps
  /// [Ticket.currentRound]. The table keeps accumulating rounds until
  /// completeTicket closes it with one summary invoice over every line.
  Future<void> sendRound({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    required List<TicketLine> currentLines,
    required int currentRound,
  }) {
    final nextRound = currentRound + 1;
    final lines = currentLines
        .map((l) => l.isPending ? l.copyWith(roundNumber: nextRound) : l)
        .toList();
    return _ticketsRef(companyId, businessUnitId).doc(ticketId).update({
      'lines': lines.map((l) => l.toMap()).toList(),
      'currentRound': nextRound,
      'updatedAt': FieldValue.serverTimestamp(),
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

  /// Closes the table's order out into an invoice (the fiscal document —
  /// real fiscalization is future work, but this is the state-machine
  /// boundary it will hang off). [tableId] is passed (rather than re-read
  /// from the ticket) so this stays a plain caller-supplied write; when
  /// present, the table's claim is released in the same transaction so a
  /// stalled release can never leave an invoiced table stuck looking
  /// occupied — a table can only be reopened once every order on it has
  /// been invoiced.
  Future<void> completeTicket({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    String? tableId,
  }) {
    return _firestore.runTransaction((tx) async {
      tx.update(_ticketsRef(companyId, businessUnitId).doc(ticketId), {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (tableId != null) {
        tx.set(_tableClaimsRef(companyId, businessUnitId).doc(tableId), {
          'status': 'free',
          'operatorUid': null,
          'operatorName': null,
          'customerCode': null,
          'locationCode': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> cancelTicket({
    required String companyId,
    required String businessUnitId,
    required String ticketId,
    String? tableId,
  }) {
    return _firestore.runTransaction((tx) async {
      tx.update(_ticketsRef(companyId, businessUnitId).doc(ticketId), {
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (tableId != null) {
        tx.set(_tableClaimsRef(companyId, businessUnitId).doc(tableId), {
          'status': 'free',
          'operatorUid': null,
          'operatorName': null,
          'customerCode': null,
          'locationCode': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
