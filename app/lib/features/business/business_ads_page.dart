import 'package:flutter/material.dart';

import '../../core/widgets/app_back_button.dart';

class BusinessAdsPage extends StatelessWidget {
  final String businessId;
  const BusinessAdsPage({super.key, required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Publicités'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Ads: page prête côté UI.\nÉtape suivante: créer campagnes + ciblage + stats.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
