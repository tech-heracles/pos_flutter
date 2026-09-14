import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Offline mode: everything this app reads (master data, open tickets,
  // open orders) is a plain Firestore read/listener and everything it
  // writes is a plain set/update — with disk persistence on, those keep
  // working straight off the local cache when connectivity drops, and
  // queued writes replay automatically once it's back. No custom
  // local-storage/sync-queue layer needed. The one thing this can't cover
  // is a real transaction (SalesRepository.createInvoice) — those need a
  // live round trip, so that action alone is gated offline; see
  // isOnlineProvider.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: MyApp()));
}
