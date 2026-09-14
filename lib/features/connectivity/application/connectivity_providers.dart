// lib/features/connectivity/application/connectivity_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../pairing/application/pairing_providers.dart';

/// Whether this device currently has a live round trip to Firestore — not
/// just a network interface. Reads and writes keep working from the local
/// cache/queue regardless of this; it only matters for (a) an "offline"
/// heads-up banner and (b) gating the one action that genuinely can't be
/// queued offline: closing a table's order into an invoice
/// (SalesRepository.createInvoice), which needs a real transaction.
///
/// Piggybacks on a snapshot listener rather than adding an OS-level
/// connectivity package: `metadata.isFromCache` flips to false only once
/// the server has actually acknowledged this listener, and back to true
/// the moment it falls back to cache — a truer "can I reach Firestore"
/// signal than network-interface state (which can be up with no real
/// route to the internet, or down over a captive portal).
final isOnlineProvider = StreamProvider<bool>((ref) {
  final paired = ref.watch(pairedDeviceProvider).value;
  if (paired == null) return Stream.value(true);
  return FirebaseFirestore.instance
      .collection('companies')
      .doc(paired.companyId)
      .snapshots(includeMetadataChanges: true)
      .map((snap) => !snap.metadata.isFromCache);
});
