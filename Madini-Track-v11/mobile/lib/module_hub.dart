import 'package:flutter/material.dart';
import 'app_context.dart';
import 'batch_tracking_page.dart';
import 'companies_page.dart';
import 'finance_page.dart';
import 'inventory_page.dart';
import 'processing_page.dart';
import 'production_page.dart';
import 'reports_page.dart';
import 'l10n.dart';
import 'local_auth.dart';
import 'sales_page.dart';
import 'v8_pages.dart';
import 'settings_page.dart';
import 'workers_page.dart';

class ModuleHub extends StatelessWidget {
  const ModuleHub({super.key});

  static final List<Map<String, dynamic>> modules = [
    {
      'title': 'Uzalishaji',
      'subtitle': 'Rekodi za madini yanayochimbwa',
      'icon': Icons.factory_outlined,
      'page': () => const ProductionPage(),
    },
    {
      'title': 'Ore & Batch Tracking',
      'subtitle': 'Fuatilia safari ya kila Batch',
      'icon': Icons.qr_code_scanner,
      'page': () => const BatchTrackingPage(),
    },
    {
      'title': 'Processing & Gold Recovery',
      'subtitle': 'Uchakataji na dhahabu iliyopatikana',
      'icon': Icons.precision_manufacturing_outlined,
      'page': () => const ProcessingPage(),
    },
    {
      'title': 'Wafanyakazi & Payroll',
      'subtitle': 'Wafanyakazi, mahudhurio na mishahara',
      'icon': Icons.people_outline,
      'page': () => const WorkersPage(),
    },
    {
      'title': 'Fedha',
      'subtitle': 'Mapato, matumizi na madeni',
      'icon': Icons.account_balance_wallet_outlined,
      'page': () => const FinancePage(),
    },
    {
      'title': 'Inventory',
      'subtitle': 'Mafuta, zana na vifaa',
      'icon': Icons.inventory_2_outlined,
      'page': () => const InventoryPage(),
    },
    {
      'title': 'Mauzo',
      'subtitle': 'Mauzo ya dhahabu, mrabaha na malipo',
      'icon': Icons.sell_outlined,
      'page': () => const SalesPage(),
    },
    {
      'title': 'Usalama Mgodini',
      'subtitle': 'Ajali, near miss, PPE na follow-up',
      'icon': Icons.health_and_safety_outlined,
      'page': () => const SafetyPage(),
    },
    {
      'title': 'Rejista ya Ushahidi',
      'subtitle': 'Picha na nyaraka za ushahidi',
      'icon': Icons.photo_library_outlined,
      'page': () => const EvidenceRegisterPage(),
    },
    {
      'title': 'Ukaguzi wa Data',
      'subtitle': 'Mass balance, gharama kwa Batch na uadilifu',
      'icon': Icons.fact_check_outlined,
      'page': () => const DataHealthPage(),
    },
    {
      'title': 'Viwango vya Kodi na Ada',
      'subtitle': 'Mrabaha na ada zenye tarehe na chanzo',
      'icon': Icons.percent,
      'page': () => const TaxRatesPage(),
    },
    {
      'title': 'Usawazishaji (Sync)',
      'subtitle': 'Tuma rekodi kwenye seva kwa usalama',
      'icon': Icons.sync,
      'page': () => const SyncPage(),
    },
    {
      'title': 'Reports',
      'subtitle': 'Ripoti za kampuni na migodi',
      'icon': Icons.bar_chart_outlined,
      'page': () => const ReportsPage(),
    },
    {
      'title': 'Kampuni na Migodi',
      'subtitle': 'Usimamizi wa kampuni na maeneo',
      'icon': Icons.business_outlined,
      'page': () => const CompaniesPage(),
    },
    {
      'title': 'Watumiaji wa Kifaa',
      'subtitle': 'Kuingia kwa PIN, majukumu na shahidi aliyethibitishwa',
      'icon': Icons.badge_outlined,
      'page': () => const LocalUsersPage(),
    },
    {
      'title': 'Mipangilio',
      'subtitle': 'Wasifu, PIN, backup na viwango',
      'icon': Icons.settings_outlined,
      'page': () => const SettingsPage(),
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
                  Text('${AppCtx.company} • ${AppCtx.mine}'),
                  const SizedBox(height: 4),
                  const Text('Chagua sehemu ya mfumo unayotaka kutumia.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...modules
              .where((m) =>
                  !AppCtx.localAuthActive ||
                  roleCanOpenModule(AppCtx.role, m['title'] as String))
              .map((module) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(module['icon'] as IconData),
                ),
                title: Text(tr(module['title'] as String)),
                subtitle: Text(module['subtitle'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => (module['page'] as Widget Function())(),
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
