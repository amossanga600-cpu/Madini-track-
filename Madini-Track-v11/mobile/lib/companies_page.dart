import 'package:flutter/material.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'utils.dart';

/// Karatasi ya kubadilisha kampuni/mgodi ulio hai. Inarudisha true ikibadilika.
Future<bool> showContextSwitcher(BuildContext context) async {
  final db = DatabaseHelper.instance;
  final companies = await db.getCompanies();
  final mines = <String, List<Map<String, dynamic>>>{};
  for (final c in companies) {
    final name = c['name'] as String;
    mines[name] = await db.getMines(name);
  }
  if (!context.mounted) return false;

  final r = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        Text('Chagua Kampuni na Mgodi',
            style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final c in companies) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(c['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final m in mines[c['name']] ?? const <Map<String, dynamic>>[])
            ListTile(
              dense: true,
              leading: Icon(
                (c['name'] == AppCtx.company && m['name'] == AppCtx.mine)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: Colors.orange,
              ),
              title: Text(m['name'] as String),
              subtitle: (m['location'] ?? '').toString().isEmpty
                  ? null
                  : Text(m['location'] as String),
              onTap: () async {
                await AppCtx.setActive(
                    c['name'] as String, m['name'] as String);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
            ),
        ],
      ],
    ),
  );
  return r ?? false;
}

class CompaniesPage extends StatefulWidget {
  const CompaniesPage({super.key});

  @override
  State<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends State<CompaniesPage> {
  List<Map<String, dynamic>> _companies = [];
  final Map<String, List<Map<String, dynamic>>> _mines = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final companies = await db.getCompanies();
    _mines.clear();
    for (final c in companies) {
      final n = c['name'] as String;
      _mines[n] = await db.getMines(n);
    }
    if (!context.mounted) return;
    setState(() {
      _companies = companies;
      _loading = false;
    });
  }

  Future<void> _addCompany() async {
    final ok = await showSpecSheet(
      context,
      title: 'Kampuni Mpya',
      fields: const [
        FSpec('company', 'Jina la kampuni'),
        FSpec('mine', 'Jina la mgodi wa kwanza'),
        FSpec('location', 'Mahali', required: false),
      ],
      onSubmit: (v) => DatabaseHelper.instance.addCompany(
        name: v['company']!,
        mineName: v['mine']!,
        location: v['location']!.isEmpty ? null : v['location'],
      ),
    );
    if (ok) await _load();
  }

  Future<void> _addMine(String company) async {
    final ok = await showSpecSheet(
      context,
      title: 'Mgodi Mpya: $company',
      fields: const [
        FSpec('mine', 'Jina la mgodi'),
        FSpec('location', 'Mahali', required: false),
      ],
      onSubmit: (v) => DatabaseHelper.instance.addMine(
        company: company,
        name: v['mine']!,
        location: v['location']!.isEmpty ? null : v['location'],
      ),
    );
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kampuni na Migodi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCompany,
        icon: const Icon(Icons.add_business),
        label: const Text('Kampuni'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Watumiaji na ruhusa'),
                    subtitle: Text(
                      'Kwa sasa app inatumika na mtu mmoja kwa kila simu. '
                      'Watumiaji wengi na ruhusa za kila mgodi vitaongezwa na backend.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final c in _companies)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.business, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c['name'] as String,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _addMine(c['name'] as String),
                                icon: const Icon(Icons.add),
                                label: const Text('Mgodi'),
                              ),
                            ],
                          ),
                          for (final m in _mines[c['name']] ??
                              const <Map<String, dynamic>>[])
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                (c['name'] == AppCtx.company &&
                                        m['name'] == AppCtx.mine)
                                    ? Icons.check_circle
                                    : Icons.terrain,
                                color: (c['name'] == AppCtx.company &&
                                        m['name'] == AppCtx.mine)
                                    ? Colors.green
                                    : null,
                              ),
                              title: Text(m['name'] as String),
                              subtitle: (m['location'] ?? '').toString().isEmpty
                                  ? null
                                  : Text(m['location'] as String),
                              trailing: (c['name'] == AppCtx.company &&
                                      m['name'] == AppCtx.mine)
                                  ? const Text('Unatumia')
                                  : TextButton(
                                      onPressed: () async {
                                        await AppCtx.setActive(
                                          c['name'] as String,
                                          m['name'] as String,
                                        );
                                        if (!context.mounted) return;
                                        snack(context, 'Umebadilisha mgodi.');
                                        setState(() {});
                                      },
                                      child: const Text('Tumia'),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
