// lib/features/operator/data/operator_repository.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/pos_operator.dart';

class OperatorRepository {
  OperatorRepository(this._functions, this._auth);
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<List<PosOperator>> listForBusinessUnit({
    required String companyId,
    required String businessUnitId,
  }) async {
    final callable = _functions.httpsCallable('listOperatorsForBusinessUnit');
    final result = await callable.call<Map<String, dynamic>>({
      'companyId': companyId,
      'businessUnitId': businessUnitId,
    });
    final operators = result.data['operators'] as List<dynamic>? ?? [];
    return operators
        .map((o) => PosOperator.fromMap(Map<String, dynamic>.from(o as Map)))
        .toList();
  }

  /// Reuses the exact same PIN-as-password mechanism the Manager app sets
  /// up when an Admin creates/resets an operator - no new auth machinery.
  Future<void> signIn({required String email, required String pin}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: pin);
  }

  Future<void> signOut() => _auth.signOut();
}
