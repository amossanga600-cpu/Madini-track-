import 'package:flutter/material.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'processing_page.dart';
import 'utils.dart';
import 'v8_pages.dart';

class BatchTrackingPage extends StatefulWidget {
  const BatchTrackingPage({super.key});

  @override
  State<BatchTrackingPage> createState() => _BatchTrackingPageState();
}

class _BatchTrackingPageState extends State<BatchTrackingPage> {
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true;
  bool _onlyAvailable = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await DatabaseHelper.instance.getAllBatches();
      if (!mounted) return;
      setState(() {
        _batches = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      snack(context, 'Imeshindikana kusoma Batch: ${errText(e)}');
    }
  }

  Future<void> _register() async {
    final ok = await showSpecSheet(
      context,
      title: 'Sajili Batch',
      note: 'Batch za uzalishaji zinatengenezwa kiotomatiki. '
          'Tumia hapa kwa ore iliyoletwa kutoka nje.',
      fields: const [
        FSpec('batch', 'Batch ID'),
        FSpec('source', 'Eneo ilipotoka / ilipo'),
        FSpec('weight', 'Uzito (KG)', type: FType.decimal),
      ],
      onSubmit: (v) => DatabaseHelper.instance.registerBatch(
        batchId: v['batch']!,
        sourceLocation: v['source']!,
        weightKg: parseNum(v['weight'])!,
      ),
    );
    if (ok) {
      if (mounted) snack(context, 'Batch imesajiliwa.');
      await _load();
    }
  }

  Future<void> _move(Map<String, dynamic> b) async {
    final w = dbl(b['weight_kg']);
    String? created;
    final ok = await showSpecSheet(
      context,
      title: 'Hamisha ${b['batch_id']}',
      note: 'Uzito uliopo: ${fmtNum(w)} kg. Ukihamisha sehemu tu, Batch mpya '
          'itatengenezwa kwa sehemu hiyo.',
      fields: [
        const FSpec('to', 'Eneo linalopelekwa'),
        FSpec('weight', 'Uzito wa kuhamisha (KG)',
            type: FType.decimal, initial: w.toString()),
        FSpec('witness', 'Shahidi (mtu wa pili)',
            required: AppCtx.requireWitness),
        const FSpec('notes', 'Maelezo', type: FType.multiline, required: false),
      ],
      onSubmit: (v) async {
        final id = await DatabaseHelper.instance.moveBatch(
          batchId: b['batch_id'] as String,
          toLocation: v['to']!,
          weightKg: parseNum(v['weight'])!,
          witness: v['witness'],
          notes: (v['notes'] ?? '').isEmpty ? null : v['notes'],
        );
        created = id != b['batch_id'] ? id : null;
      },
    );
    if (ok) {
      if (!mounted) return;
      snack(
        context,
        created == null
            ? 'Uhamisho umehifadhiwa.'
            : 'Batch mpya imetengenezwa: $created',
      );
      await _load();
    }
  }

  Future<void> _process(Map<String, dynamic> b) async {
    final ok = await showProcessForm(context, batchId: b['batch_id'] as String);
    if (ok) {
      if (mounted) snack(context, 'Uchakataji umehifadhiwa.');
      await _load();
    }
  }

  Future<void> _merge(Map<String, dynamic> b) async {
    String? mergedId;
    final ok = await showSpecSheet(
      context,
      title: 'Unganisha Batch ${b['batch_id']}',
      note:
          'Batch nyingine lazima iwe na ore iliyobaki na iwe ya kampuni/mgodi huu huu. '
          'Historia ya kila chanzo itahifadhiwa.',
      fields: [
        const FSpec('other', 'Batch nyingine ID'),
        const FSpec('location', 'Eneo la Batch mpya'),
        FSpec('witness', 'Shahidi (mtu wa pili)',
            required: AppCtx.requireWitness),
        const FSpec('notes', 'Maelezo', type: FType.multiline, required: false),
      ],
      onSubmit: (v) async {
        mergedId = await DatabaseHelper.instance.mergeBatches(
          batchIds: [b['batch_id'] as String, v['other']!],
          targetLocation: v['location']!,
          witness: v['witness'],
          notes: (v['notes'] ?? '').isEmpty ? null : v['notes'],
        );
      },
    );
    if (ok) {
      if (!mounted) return;
      snack(context, 'Batch mpya imeundwa: $mergedId');
      await _load();
    }
  }

  Future<void> _history(Map<String, dynamic> b) async {
    final rows =
        await DatabaseHelper.instance.getBatchHistory(b['batch_id'] as String);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Text('Historia ya ${b['batch_id']}',
              style: Theme.of(ctx).textTheme.titleLarge),
          if ((b['parent_batch_id'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Imetokana na Batch ${b['parent_batch_id']}'),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      TraceabilityPage(batchUuid: b['uuid'] as String)),
            ),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Chanzo na historia kamili'),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text('Bado haijahamishwa.')
          else
            for (final m in rows)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: Text('${m['from_location']} → ${m['to_location']}'),
                  subtitle: Text(
                    '${fmtKg(dbl(m['weight_kg']))} • ${shortDate(m['movement_date'])}\n'
                    'Na: ${m['moved_by']}'
                    '${(m['witness'] ?? '').toString().isEmpty ? '' : ' • Shahidi: ${m['witness']}'}'
                    '${(m['notes'] ?? '').toString().isEmpty ? '' : '\n${m['notes']}'}',
                  ),
                  isThreeLine: true,
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _onlyAvailable
        ? _batches
            .where((b) => dbl(b['weight_kg']) > 0 && b['status'] != 'Imefutwa')
            .toList()
        : _batches;
    final totalKg = shown.fold<double>(0, (s, b) => s + dbl(b['weight_kg']));

    return Scaffold(
      appBar: AppBar(title: const Text('Ore & Batch Tracking')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _register,
        icon: const Icon(Icons.add),
        label: const Text('Batch'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            StatCard(
              label: _onlyAvailable ? 'Ore iliyopo kwenye Batch' : 'Batch zote',
              value: fmtKg(totalKg),
              icon: Icons.inventory_2_outlined,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Onyesha zenye ore iliyobaki tu'),
              value: _onlyAvailable,
              onChanged: (v) => setState(() => _onlyAvailable = v),
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (shown.isEmpty)
              const EmptyCard(
                  'Hakuna Batch. Rekodi uzalishaji kwenye Dashboard.')
            else
              for (final b in shown)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_scanner),
                    title: Text(
                      'Batch ${b['batch_id']}',
                      style:
                          b['status'] == 'Imefutwa' ? VoidedStyle.title : null,
                    ),
                    subtitle: Text(
                      'Eneo: ${b['current_location']}\n'
                      'Imebaki ${fmtKg(dbl(b['weight_kg']))} '
                      'kati ya ${fmtKg(dbl(b['initial_weight_kg']))}\n'
                      'Hali: ${b['status']}',
                    ),
                    isThreeLine: true,
                    trailing: b['status'] == 'Imefutwa'
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'move') _move(b);
                              if (v == 'process') _process(b);
                              if (v == 'merge') _merge(b);
                              if (v == 'history') _history(b);
                            },
                            itemBuilder: (_) => [
                              if (dbl(b['weight_kg']) > 0)
                                const PopupMenuItem(
                                    value: 'move', child: Text('Hamisha')),
                              if (dbl(b['weight_kg']) > 0)
                                const PopupMenuItem(
                                    value: 'process', child: Text('Chakata')),
                              if (dbl(b['weight_kg']) > 0)
                                const PopupMenuItem(
                                    value: 'merge',
                                    child: Text('Unganisha Batch')),
                              const PopupMenuItem(
                                  value: 'history', child: Text('Historia')),
                            ],
                          ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
