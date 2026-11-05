import 'package:flutter/material.dart';
import 'app_context.dart';
import 'companies_page.dart';
import 'database_helper.dart';
import 'lock_page.dart';
import 'module_hub.dart';
import 'production_page.dart';
import 'setup_page.dart';
import 'utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MadiniTrackApp());
}

class MadiniTrackApp extends StatelessWidget {
  const MadiniTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Madini Track Tanzania',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
        ),
        useMaterial3: true,
      ),
      home: const AppRoot(),
    );
  }
}

/// Inafungua database, inapakia hali ya app, kisha inaamua ukurasa wa kuonyesha.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = AppCtx.load();
  }

  void _reload() {
    setState(() => _init = AppCtx.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Imeshindikana kufungua database:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (!AppCtx.ready) {
          return SetupScreen(onDone: _reload);
        }
        return const LockGate(child: DashboardScreen());
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recent = [];
  String _suggestedBatch = '';
  int _formKey = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final db = DatabaseHelper.instance;
      final stats = await db.dashboardStats();
      final recent = await db.getProductionRecords(limit: 5);
      final next = await db.nextBatchId();

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _recent = recent;
        _suggestedBatch = next;
        _formKey++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      snack(context, 'Imeshindikana kusoma database: ${errText(e)}');
    }
  }

  Future<void> _openHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ModuleHub()),
    );
    if (!mounted) return;
    await _loadAll();
  }

  Future<void> _switchContext() async {
    final changed = await showContextSwitcher(context);
    if (changed) await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final lowStock = intv(s['low_stock']);
    final pending = intv(s['pending']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Madini Track Tanzania'),
        actions: [
          IconButton(
            tooltip: 'Tafuta taarifa',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GlobalSearchPage()),
            ),
          ),
          IconButton(
            tooltip: 'Modules',
            icon: const Icon(Icons.apps),
            onPressed: _openHub,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.business, color: Colors.orange),
                title: Text(AppCtx.company),
                subtitle: Text('Mgodi: ${AppCtx.mine}  •  ${AppCtx.user}'),
                trailing: const Icon(Icons.swap_horiz),
                onTap: _switchContext,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.3,
                children: [
                  StatCard(
                    label: 'Uzalishaji leo',
                    value: fmtKg(dbl(s['today_kg'])),
                    icon: Icons.factory_outlined,
                  ),
                  StatCard(
                    label: 'Ore iliyopo (${intv(s['stock_batches'])} Batch)',
                    value: fmtKg(dbl(s['stock_kg'])),
                    icon: Icons.inventory_2_outlined,
                  ),
                  StatCard(
                    label: 'Dhahabu haijauzwa',
                    value: fmtG(dbl(s['gold_balance_g'])),
                    icon: Icons.diamond_outlined,
                    color: Colors.amber.shade800,
                  ),
                  StatCard(
                    label: 'Salio la mwezi',
                    value: fmtMoney(dbl(s['income']) - dbl(s['expense'])),
                    icon: Icons.account_balance_wallet_outlined,
                    color: (dbl(s['income']) - dbl(s['expense'])) >= 0
                        ? Colors.green
                        : Colors.red,
                  ),
                ],
              ),
              if (lowStock > 0)
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.red),
                    title: Text('Vifaa $lowStock vinakaribia kuisha'),
                    subtitle: const Text('Fungua Inventory kuona orodha.'),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uingizaji wa Uzalishaji',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Kila rekodi inatengeneza Batch yake kiotomatiki.',
                    ),
                    const SizedBox(height: 16),
                    SpecForm(
                      key: ValueKey(_formKey),
                      submitLabel: 'Hifadhi Rekodi',
                      fields: [
                        const FSpec('shaft', 'Shaft / Eneo'),
                        FSpec('batch', 'Batch ID', initial: _suggestedBatch),
                        const FSpec('bags', 'Idadi ya magunia',
                            type: FType.integer),
                        const FSpec('weight', 'Uzito (KG)', type: FType.decimal),
                        const FSpec('grade', 'Estimated Grade (g/t)',
                            type: FType.decimal, required: false),
                        const FSpec(
                          'shift',
                          'Zamu',
                          type: FType.dropdown,
                          options: [Opt('Mchana', 'Mchana'), Opt('Usiku', 'Usiku')],
                        ),
                        const FSpec('date', 'Tarehe', type: FType.date),
                        FSpec('witness', 'Shahidi (mtu wa pili)',
                            required: AppCtx.requireWitness),
                      ],
                      onSubmit: (v) async {
                        await DatabaseHelper.instance.recordProduction(
                          shaft: v['shaft']!,
                          batchId: v['batch']!,
                          shiftDate: v['date']!,
                          shiftType: v['shift']!,
                          bags: int.parse(v['bags']!),
                          weightKg: parseNum(v['weight'])!,
                          grade: parseNum(v['grade']),
                          witness: v['witness'],
                        );
                      },
                      onSaved: () {
                        snack(context, 'Rekodi imehifadhiwa kwenye simu.');
                        _loadAll();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(
                  pending == 0 ? Icons.cloud_done : Icons.cloud_off,
                  color: Colors.orange,
                ),
                title: const Text('Rekodi zinazosubiri sync'),
                subtitle: const Text('Zitatumwa server ikiunganishwa.'),
                trailing: Text(
                  '$pending',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rekodi za Karibuni',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProductionPage()),
                    );
                    if (mounted) _loadAll();
                  },
                  child: const Text('Zote'),
                ),
              ],
            ),
            if (!_loading && _recent.isEmpty)
              const EmptyCard('Bado hakuna rekodi.')
            else
              ..._recent.map((record) {
                final voided = intv(record['voided']) == 1;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(
                      'Batch: ${record['batch_id']}',
                      style: voided ? VoidedStyle.title : null,
                    ),
                    subtitle: Text(
                      'Mgodi: ${record['mine_id']}  •  ${shortDate(record['shift_date'])}\n'
                      'Uzito: ${fmtKg(dbl(record['weight_kg']))}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      voided ? 'Imefutwa' : '${record['sync_status']}',
                      style: TextStyle(
                        color: voided
                            ? Colors.red
                            : (record['sync_status'] == 'Synced'
                                ? Colors.green
                                : Colors.orange),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}


class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      setState(() { _results = []; _error = null; _loading = false; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await DatabaseHelper.instance.searchAllRecords(value);
      if (!mounted) return;
      setState(() { _results = rows; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = errText(e); });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tafuta taarifa')),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Batch ID, eneo, mfanyakazi, mnunuzi...',
            suffixIcon: IconButton(
              tooltip: 'Futa',
              onPressed: () { _controller.clear(); _search(''); },
              icon: const Icon(Icons.clear),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Padding(
        padding: const EdgeInsets.all(16), child: Text(_error!),
      ),
      Expanded(
        child: _results.isEmpty
          ? Center(child: Text(_controller.text.trim().isEmpty
              ? 'Andika neno au Batch ID kutafuta.'
              : 'Hakuna taarifa zilizopatikana.'))
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final row = _results[index];
                return ListTile(
                  leading: const Icon(Icons.search),
                  title: Text('${row['title'] ?? ''}'),
                  subtitle: Text('${row['module'] ?? ''} • ${row['details'] ?? ''}'),
                  trailing: Text('${row['record_date'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
      ),
    ]),
  );
}
