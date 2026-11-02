import 'batch_tracking_page.dart';
import 'package:flutter/material.dart';

class ModuleHub extends StatelessWidget {
  const ModuleHub({super.key});

  static const List<Map<String, dynamic>> modules = [
    {
      'title': 'Uzalishaji',
      'subtitle': 'Rekodi za madini yanayochimbwa',
      'icon': Icons.factory_outlined,
      'features': ['Rekodi za uzalishaji', 'Zamu za kazi', 'Uzito na magunia'],
    },
    {
      'title': 'Ore & Batch Tracking',
      'subtitle': 'Fuatilia safari ya kila Batch',
      'icon': Icons.qr_code_scanner,
      'features': ['Batch ID', 'Mahali ilipo', 'Historia ya uhamisho'],
    },
    {
      'title': 'Processing & Gold Recovery',
      'subtitle': 'Uchakataji na dhahabu iliyopatikana',
      'icon': Icons.precision_manufacturing_outlined,
      'features': ['Ore iliyochakatwa', 'Gold recovered', 'Mabaki na upotevu'],
    },
    {
      'title': 'Wafanyakazi & Payroll',
      'subtitle': 'Usimamizi wa wafanyakazi',
      'icon': Icons.people_outline,
      'features': ['Orodha ya wafanyakazi', 'Mahudhurio', 'Mishahara'],
    },
    {
      'title': 'Fedha',
      'subtitle': 'Mapato, matumizi na madeni',
      'icon': Icons.account_balance_wallet_outlined,
      'features': ['Mapato', 'Matumizi', 'Madeni na faida'],
    },
    {
      'title': 'Inventory',
      'subtitle': 'Usimamizi wa vifaa na bidhaa',
      'icon': Icons.inventory_2_outlined,
      'features': ['Mafuta', 'Zana na vifaa', 'Stock inayoingia na kutoka'],
    },
    {
      'title': 'Mauzo',
      'subtitle': 'Usimamizi wa mauzo ya madini',
      'icon': Icons.sell_outlined,
      'features': ['Rekodi za mauzo', 'Wanunuzi', 'Risiti na malipo'],
    },
    {
      'title': 'Reports',
      'subtitle': 'Ripoti za kampuni na migodi',
      'icon': Icons.bar_chart_outlined,
      'features': ['Ripoti za uzalishaji', 'Ripoti za fedha', 'PDF na Excel'],
    },
    {
      'title': 'Kampuni na Migodi',
      'subtitle': 'Usimamizi wa kampuni na maeneo',
      'icon': Icons.business_outlined,
      'features': ['Kampuni', 'Migodi', 'Watumiaji na ruhusa'],
    },
    {
      'title': 'Mipangilio',
      'subtitle': 'Mipangilio ya mfumo',
      'icon': Icons.settings_outlined,
      'features': ['Wasifu', 'Lugha', 'Mipangilio ya mfumo'],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modules za Madini Track'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usimamizi wa shughuli za mgodi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chagua sehemu ya mfumo unayotaka kutumia.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...modules.map((module) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(module['icon'] as IconData),
                ),
                title: Text(module['title'] as String),
                subtitle: Text(module['subtitle'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => module['title'] == 'Ore & Batch Tracking'
                          ? const BatchTrackingPage()
                          : ModuleDetailPage(module: module),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ModuleDetailPage extends StatelessWidget {
  final Map<String, dynamic> module;

  const ModuleDetailPage({
    super.key,
    required this.module,
  });

  @override
  Widget build(BuildContext context) {
    final features = module['features'] as List<String>;

    return Scaffold(
      appBar: AppBar(
        title: Text(module['title'] as String),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(
            module['icon'] as IconData,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            module['title'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            module['subtitle'] as String,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text(
            'Vipengele vitakavyojengwa:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...features.map(
            (feature) => Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(feature),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ukurasa huu ni msingi wa muundo. Fomu, database na '
            'utendaji wa kipengele hiki vitaunganishwa katika hatua '
            'yake ya ujenzi.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
