import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BusinessPostDetailPage extends StatelessWidget {
  final String businessId;
  final String postId;

  const BusinessPostDetailPage({
    super.key,
    required this.businessId,
    required this.postId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.push('/business/$businessId/posts'),
        ),
        title: const Text('Détail Post'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('TODO: afficher/éditer le post $postId'),
      ),
    );
  }
}
