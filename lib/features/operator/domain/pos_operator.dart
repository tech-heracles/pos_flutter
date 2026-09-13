// lib/features/operator/domain/pos_operator.dart
class PosOperator {
  const PosOperator({
    required this.uid,
    required this.displayName,
    required this.email,
  });

  final String uid;
  final String displayName;

  /// Synthetic account email (not real) - only used internally for
  /// signInWithEmailAndPassword(email, pin).
  final String email;

  factory PosOperator.fromMap(Map<String, dynamic> data) {
    return PosOperator(
      uid: data['uid'] as String,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String,
    );
  }
}
