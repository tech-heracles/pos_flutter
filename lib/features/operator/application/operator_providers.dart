// lib/features/operator/application/operator_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/operator_repository.dart';

final operatorRepositoryProvider = Provider<OperatorRepository>(
  (ref) => OperatorRepository(
    ref.watch(functionsProvider),
    ref.watch(firebaseAuthProvider),
  ),
);
