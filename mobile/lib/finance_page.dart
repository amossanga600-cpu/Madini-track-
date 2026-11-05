import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'db_modules.dart';
import 'utils.dart';

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  final _periods = standardPeriods();
  int _sel = 2;
  List<Map<String, dynamic>> _tx = [];
  List<Map<String, dynamic>> _debts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final p = _periods[_sel];
    final tx = await db.getTransactions(from: p.from, to: p.to);
    final debts = await db.getDebts();
    if (!mounted) return;
    setState(() {
      _tx = tx;
      _debts = debts;
      _loading = false;
    });
  }

  Future<void> _addTx(String type) async {
    final isIncome = type == 'Mapato';
    final ok = await showSpecSheet(
      context,
      title: isIncome ? 'Mapato Mapya' : 'Matumizi Mapya',
      fields: [
        FSpec('category', 'Aina',
            type: FType.dropdown,
            options: optsOf(isIncome ? kIncomeCategories : kExpenseCategories)),
        const FSpec('amount', 'Kiasi (TSh)', type: FType.decimal),
        const FSpec('date', 'Tarehe', type: FType.date),
        FSpec('method', 'Njia ya malipo',
            type: FType.dropdown, options: optsOf(kPayMethods)),
        const FSpec('reference', 'Namba ya risiti / rejea',
            required: false),
        const FSpec('desc', 'Maelezo', type: FType.multiline, required: false),
      ],
      note: isIncome
          ? 'Mauzo ya dhahabu yanaingizwa kiotomatiki kupitia Mauzo.'
          : 'Mishahara na uchakataji vinaingizwa kiotomatiki kupitia modules zake.',
      onSubmit: (v) => DatabaseHelper.instance.addTransaction(
        type: type,
        category: v['category']!,
        amount: parseNum(v['amount'])!,
        date: v['date']!,
        description: v['desc']!.isEmpty ? null : v['desc'],
        method: v['method']!,
        reference: v['reference']!.isEmpty ? null : v['reference'],
      ),
    );
    if (ok) {
      if (!mounted) return;
      snack(context, 'Muamala umehifadhiwa.');
      await _load();
    }
  }

  Future<void> _voidTx(Map<String, dynamic> t) async {
    final reason = await askReason(context, 'Futa muamala huu?');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.voidTransaction(t['uuid'] as String, reason);
      if (!mounted) return;
      snack(context, 'Muamala umefutwa (unabaki kwenye historia).');
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _addDebt() async {
    final ok = await showSpecSheet(
      context,
      title: 'Deni Jipya',
      fields: [
        const FSpec(
          'direction',
          'Aina ya deni',
          type: FType.dropdown,
          options: [
            Opt('Tunadaiwa', 'Tunadaiwa (sisi tunadaiwa)'),
            Opt('Tunadai', 'Tunadai (tunadai wengine)'),
          ],
        ),
        const FSpec('party', 'Jina la mhusika'),
        const FSpec('amount', 'Kiasi (TSh)', type: FType.decimal),
        const FSpec('due', 'Tarehe ya mwisho', type: FType.date, required: false),
        const FSpec('desc', 'Maelezo', type: FType.multiline, required: false),
      ],
      onSubmit: (v) => DatabaseHelper.instance.addDebt(
        direction: v['direction']!,
        party: v['party']!,
        amount: parseNum(v['amount'])!,
        dueDate: v['due']!.isEmpty ? null : v['due'],
        description: v['desc']!.isEmpty ? null : v['desc'],
      ),
    );
    if (ok) await _load();
  }

  Future<void> _payDebt(Map<String, dynamic> d) async {
    final balance = dbl(d['amount']) - dbl(d['paid']);
    final weOwe = d['direction'] == 'Tunadaiwa';
    final ok = await showSpecSheet(
      context,
      title: weOwe ? 'Lipa deni: ${d['party']}' : 'Pokea malipo: ${d['party']}',
      note: 'Salio: ${fmtMoney(balance)}',
      fields: [
        FSpec('amount', 'Kiasi (TSh)',
            type: FType.decimal, initial: balance.toStringAsFixed(0)),
        const FSpec('date', 'Tarehe', type: FType.date),
        FSpec('method', 'Njia ya malipo',
            type: FType.dropdown, options: optsOf(kPayMethods)),
        const FSpec('notes', 'Maelezo', required: false),
      ],
      onSubmit: (v) => DatabaseHelper.instance.addDebtPayment(
        debtUuid: d['uuid'] as String,
        amount: parseNum(v['amount'])!,
        date: v['date']!,
        method: v['method']!,
        notes: v['notes']!.isEmpty ? null : v['notes'],
      ),
    );
    if (ok) await _load();
  }

  Future<void> _voidDebt(Map<String, dynamic> d) async {
    final reason = await askReason(context, 'Futa deni la ${d['party']}?');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.voidDebt(d['uuid'] as String, reason);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Widget _txTab() {
    final active = _tx.where((t) => intv(t['voided']) == 0);
    final income = active
        .where((t) => t['type'] == 'Mapato')
        .fold<double>(0, (s, t) => s + dbl(t['amount']));
    final expense = active
        .where((t) => t['type'] == 'Matumizi')
        .fold<double>(0, (s, t) => s + dbl(t['amount']));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PeriodBar(
            periods: _periods,
            selected: _sel,
            onChanged: (i) {
              setState(() => _sel = i);
              _load();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Mapato',
                  value: fmtMoney(income),
                  icon: Icons.south_west,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  label: 'Matumizi',
                  value: fmtMoney(expense),
                  icon: Icons.north_east,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatCard(
            label: 'Salio la kipindi',
            value: fmtMoney(income - expense),
            icon: Icons.account_balance_wallet_outlined,
            color: income - expense >= 0 ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTx('Mapato'),
                  icon: const Icon(Icons.add),
                  label: const Text('Mapato'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _addTx('Matumizi'),
                  icon: const Icon(Icons.remove),
                  label: const Text('Matumizi'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_tx.isEmpty)
            const EmptyCard('Hakuna miamala kwa kipindi hiki.')
          else
            for (final t in _tx)
              Card(
                child: ListTile(
                  leading: Icon(
                    t['type'] == 'Mapato' ? Icons.south_west : Icons.north_east,
                    color: t['type'] == 'Mapato' ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    '${t['category']}  •  ${fmtMoney(dbl(t['amount']))}',
                    style: intv(t['voided']) == 1 ? VoidedStyle.title : null,
                  ),
                  subtitle: Text(
                    '${shortDate(t['trans_date'])} • ${t['method'] ?? ''}'
                    '${t['source'] == 'Mkono' ? '' : ' • Kutoka ${t['source']}'}'
                    '${(t['description'] ?? '').toString().isEmpty ? '' : '\n${t['description']}'}'
                    '${intv(t['voided']) == 1 ? '\nImefutwa: ${t['void_reason']}' : ''}',
                  ),
                  isThreeLine: (t['description'] ?? '').toString().isNotEmpty ||
                      intv(t['voided']) == 1,
                  trailing: (intv(t['voided']) == 1 || t['source'] != 'Mkono')
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (_) => _voidTx(t),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'v', child: Text('Futa kwa sababu')),
                          ],
                        ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _debtTab() {
    final owe = _debts
        .where((d) => d['direction'] == 'Tunadaiwa')
        .fold<double>(0, (s, d) => s + dbl(d['amount']) - dbl(d['paid']));
    final owed = _debts
        .where((d) => d['direction'] == 'Tunadai')
        .fold<double>(0, (s, d) => s + dbl(d['amount']) - dbl(d['paid']));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Tunadaiwa',
                  value: fmtMoney(owe),
                  icon: Icons.arrow_upward,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatCard(
                  label: 'Tunadai',
                  value: fmtMoney(owed),
                  icon: Icons.arrow_downward,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _addDebt,
            icon: const Icon(Icons.add),
            label: const Text('Ongeza Deni'),
          ),
          const SizedBox(height: 12),
          if (_debts.isEmpty)
            const EmptyCard('Hakuna madeni yaliyorekodiwa.')
          else
            for (final d in _debts)
              Card(
                child: ListTile(
                  title: Text('${d['party']}  •  ${fmtMoney(dbl(d['amount']))}'),
                  subtitle: Text(
                    '${d['direction'] == 'Tunadaiwa' ? 'Sisi tunadaiwa' : 'Tunadai'}\n'
                    'Imelipwa ${fmtMoney(dbl(d['paid']))} • '
                    'Salio ${fmtMoney(dbl(d['amount']) - dbl(d['paid']))}'
                    '${(d['due_date'] ?? '').toString().isEmpty ? '' : '\nMwisho: ${d['due_date']}'}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'pay') _payDebt(d);
                      if (v == 'void') _voidDebt(d);
                    },
                    itemBuilder: (_) => [
                      if (dbl(d['amount']) - dbl(d['paid']) > 0.005)
                        PopupMenuItem(
                          value: 'pay',
                          child: Text(d['direction'] == 'Tunadaiwa'
                              ? 'Lipa'
                              : 'Pokea malipo'),
                        ),
                      const PopupMenuItem(
                          value: 'void', child: Text('Futa kwa sababu')),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fedha'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Miamala'), Tab(text: 'Madeni')],
          ),
        ),
        body: TabBarView(children: [_txTab(), _debtTab()]),
      ),
    );
  }
}
