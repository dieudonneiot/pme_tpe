import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/business/data/business_repository.dart';

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return BusinessRepository();
});
