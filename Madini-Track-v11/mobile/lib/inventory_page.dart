import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'db_modules.dart';
import 'utils.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await DatabaseHelper.instance.getItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  bool _isLow(Map<String, dynamic> i) =>
      dbl(i['min_level']) > 0 && dbl(i['stock']) <= dbl(i['min_level']);

  Future<void> _addItem() async {
    final ok = await showSpecSheet(
      context,
      title: 'Kifaa Kipya',
      fields: [
        const FSpec('name', 'Jina la kifaa', hint: 'Mfano: Dizeli'),
        FSpec('category', 'Aina',
            type: FType.dropdown, options: optsOf(kInventoryCategories)),
        const FSpec('unit', 'Kipimo', hint: 'lita, kg, pcs, mfuko'),
        const FSpec('min', 'Kiwango cha tahadhari (stock ikifika hapa)',
            type: FType.decimal, required: false, initial: '0'),
      ],
      onSubmit: (v) => DatabaseHelper.instance.addItem(
        name: v['name']!,
        category: v['category']!,
        unit: v['unit']!,
        minLevel: parseNum(v['min']) ?? 0,
      ),
    );
    if (ok) await _load();
  }

  Future<void> _move(Map<String, dynamic> item, String type) async {
    final isIn = type == 'Ingia';
    final ok = await showSpecSheet(
      context,
      title: '${isIn ? 'Ingiza' : 'Toa'}: ${item['name']}',
      note: 'Stock iliyopo: ${fmtNum(dbl(item['stock']))} ${item['unit']}',
      fields: [
        FSpec('qty', 'Kiasi (${item['unit']})', type: FType.decimal),
        if (isIn)
          const FSpec('cost', 'Bei kwa kipimo kimoja (TSh)',
              type: FType.decimal, required: false),
        if (isIn)
          const FSpec(
            'expense',
            'Rekodi gharama kwenye Fedha?',
            type: FType.dropdown,
            options: [Opt('Ndiyo', 'Ndiyo'), Opt('Hapana', 'Hapana')],
          ),
        const FSpec('date', 'Tarehe', type: FType.date),
        FSpec('notes', isIn ? 'Muuzaji / maelezo' : 'Imetumika wapi / maelezo',
            required: false),
      ],
      preview: isIn
          ? (v) {
              final q = parseNum(v['qty']) ?? 0;
              final c = parseNum(v['cost']) ?? 0;
              return c > 0 && q > 0 ? 'Gharama jumla: ${fmtMoney(q * c)}' : '';
            }
          : null,
      onSubmit: (v) => DatabaseHelper.instance.addStockMovement(
        itemUuid: item['uuid'] as String,
        moveType: type,
        quantity: parseNum(v['qty'])!,
        unitCost: isIn ? parseNum(v['cost']) : null,
        date: v['date']!,
        recordExpense: isIn && v['expense'] == 'Ndiyo',
        notes: v['notes']!.isEmpty ? null : v['notes'],
      ),
    );
    if (ok) await _load();
  }

  Future<void> _history(Map<String, dynamic> item) async {
    final rows =
        await DatabaseHelper.instance.getStockMovements(item['uuid'] as String);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text('Historia: ${item['name']}',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('Bado hakuna mwendo wa stock.')
            else
              for (final m in rows)
                Card(
                  child: ListTile(
                    leading: Icon(
                      m['move_type'] == 'Ingia'
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                      color:
                          m['move_type'] == 'Ingia' ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      '${m['move_type']}: ${fmtNum(dbl(m['quantity']))} ${item['unit']}',
                      style: intv(m['voided']) == 1 ? VoidedStyle.title : null,
                    ),
                    subtitle: Text(
                      '${shortDate(m['move_date'])} • ${m['created_by'] ?? ''}'
                      '${m['unit_cost'] == null ? '' : ' • ${fmtMoney(dbl(m['unit_cost']))}/kipimo'}'
                      '${(m['notes'] ?? '').toString().isEmpty ? '' : '\n${m['notes']}'}'
                      '${intv(m['voided']) == 1 ? '\nImefutwa: ${m['void_reason']}' : ''}',
                    ),
                    trailing: intv(m['voided']) == 1
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Futa kwa sababu',
                            onPressed: () async {
                              final reason =
                                  await askReason(ctx, 'Futa rekodi hii?');
                              if (reason == null) return;
                              try {
                                await DatabaseHelper.instance.voidStockMovement(
                                    m['uuid'] as String, reason);
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _load();
                              } catch (e) {
                                if (ctx.mounted) snack(ctx, errText(e));
                              }
                            },
                          ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Kifaa'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_items.isEmpty)
              const EmptyCard('Bado hakuna vifaa. Bonyeza "Kifaa" kuongeza.')
            else
              for (final i in _items)
                Card(
                  color: _isLow(i) ? Colors.red.shade50 : null,
                  child: ListTile(
                    leading: Icon(
                      _isLow(i)
                          ? Icons.warning_amber
                          : Icons.inventory_2_outlined,
                      color: _isLow(i) ? Colors.red : null,
                    ),
                    title: Text(i['name'] as String),
                    subtitle: Text(
                      '${i['category']}'
                      '${dbl(i['min_level']) > 0 ? ' • Tahadhari: ${fmtNum(dbl(i['min_level']))}' : ''}',
                    ),
                    trailing: Text(
                      '${fmtNum(dbl(i['stock']))} ${i['unit']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.add_circle_outline),
                              title: const Text('Ingiza stock'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _move(i, 'Ingia');
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.remove_circle_outline),
                              title: const Text('Toa stock'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _move(i, 'Toka');
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.history),
                              title: const Text('Historia'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _history(i);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
