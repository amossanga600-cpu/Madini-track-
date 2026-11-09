import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'db_modules.dart';
import 'utils.dart';

const List<String> kPayTypes = ['Siku', 'Mwezi', 'Mgawo'];
const List<String> kRoles = [
  'Mchimbaji',
  'Msimamizi',
  'Mchakataji',
  'Mlinzi',
  'Dereva',
  'Fundi',
  'Mpishi',
  'Mhasibu',
  'Nyingine',
];

String payTypeHelp(String t) {
  switch (t) {
    case 'Siku':
      return 'Analipwa kwa siku alizohudhuria';
    case 'Mwezi':
      return 'Mshahara wa kudumu wa mwezi';
    default:
      return 'Mgawo wa ore/dhahabu (kiasi huingizwa kwa mkono)';
  }
}

class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key});

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  List<Map<String, dynamic>> _workers = [];
  Map<String, String> _attendance = {};
  String _attDate = todayStr();

  String _from =
      dateStr(DateTime(DateTime.now().year, DateTime.now().month, 1));
  String _to = todayStr();
  final Map<String, int> _days = {};
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final db = DatabaseHelper.instance;
    final workers = await db.getWorkers();
    final att = await db.getAttendanceForDate(_attDate);
    final pays = await db.getPayments();
    _days.clear();
    for (final w in workers.where((w) => intv(w['active']) == 1)) {
      _days[w['uuid'] as String] =
          await db.daysPresent(w['uuid'] as String, _from, _to);
    }
    if (!mounted) return;
    setState(() {
      _workers = workers;
      _attendance = att;
      _payments = pays;
      _loading = false;
    });
  }

  // ----- Wafanyakazi -----
  Future<void> _addWorker() async {
    final ok = await showSpecSheet(
      context,
      title: 'Mfanyakazi Mpya',
      fields: [
        const FSpec('name', 'Jina kamili'),
        const FSpec('phone', 'Simu', required: false, type: FType.text),
        FSpec('role', 'Kazi', type: FType.dropdown, options: optsOf(kRoles)),
        FSpec('payType', 'Aina ya malipo',
            type: FType.dropdown, options: optsOf(kPayTypes)),
        const FSpec('rate', 'Kiwango (TSh kwa siku / kwa mwezi)',
            type: FType.decimal, required: false, hint: '0 kwa Mgawo'),
      ],
      note: 'Siku = kiwango kwa siku. Mwezi = mshahara wa mwezi. '
          'Mgawo = kiasi kinaingizwa wakati wa kulipa.',
      onSubmit: (v) => DatabaseHelper.instance.addWorker(
        fullName: v['name']!,
        phone: v['phone']!.isEmpty ? null : v['phone'],
        role: v['role']!,
        payType: v['payType']!,
        payRate: parseNum(v['rate']) ?? 0,
      ),
    );
    if (ok) await _loadAll();
  }

  Future<void> _editWorker(Map<String, dynamic> w) async {
    final ok = await showSpecSheet(
      context,
      title: 'Hariri: ${w['full_name']}',
      fields: [
        FSpec('phone', 'Simu',
            required: false, initial: (w['phone'] ?? '').toString()),
        FSpec('role', 'Kazi',
            type: FType.dropdown,
            options: optsOf(kRoles),
            initial: w['role'] as String),
        FSpec('payType', 'Aina ya malipo',
            type: FType.dropdown,
            options: optsOf(kPayTypes),
            initial: w['pay_type'] as String),
        FSpec('rate', 'Kiwango (TSh)',
            type: FType.decimal,
            required: false,
            initial: dbl(w['pay_rate']).toString()),
      ],
      onSubmit: (v) => DatabaseHelper.instance.updateWorker(
        w['uuid'] as String,
        role: v['role']!,
        payType: v['payType']!,
        payRate: parseNum(v['rate']) ?? 0,
        phone: v['phone']!.isEmpty ? null : v['phone'],
      ),
    );
    if (ok) await _loadAll();
  }

  Future<void> _toggleActive(Map<String, dynamic> w) async {
    final active = intv(w['active']) == 1;
    final yes = await confirmDialog(
      context,
      active ? 'Ondoa kazini?' : 'Rudisha kazini?',
      '${w['full_name']}. Rekodi zake za zamani zitabaki.',
    );
    if (!yes) return;
    await DatabaseHelper.instance.setWorkerActive(w['uuid'] as String, !active);
    await _loadAll();
  }

  Widget _workersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _addWorker,
          icon: const Icon(Icons.person_add),
          label: const Text('Ongeza Mfanyakazi'),
        ),
        const SizedBox(height: 12),
        if (_workers.isEmpty)
          const EmptyCard('Bado hakuna wafanyakazi.')
        else
          for (final w in _workers)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                      (w['full_name'] as String).substring(0, 1).toUpperCase()),
                ),
                title: Text(
                  w['full_name'] as String,
                  style: intv(w['active']) == 1 ? null : VoidedStyle.title,
                ),
                subtitle: Text(
                  '${w['role']} • ${w['pay_type']}'
                  '${w['pay_type'] == 'Mgawo' ? '' : ' • ${fmtMoney(dbl(w['pay_rate']))}'}'
                  '${(w['phone'] ?? '').toString().isEmpty ? '' : '\n${w['phone']}'}',
                ),
                isThreeLine: (w['phone'] ?? '').toString().isNotEmpty,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _editWorker(w);
                    if (v == 'active') _toggleActive(w);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Hariri')),
                    PopupMenuItem(
                      value: 'active',
                      child: Text(intv(w['active']) == 1
                          ? 'Ondoa kazini'
                          : 'Rudisha kazini'),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ----- Mahudhurio -----
  Future<void> _setAtt(String uuid, String status) async {
    await DatabaseHelper.instance.setAttendance(uuid, _attDate, status);
    final att = await DatabaseHelper.instance.getAttendanceForDate(_attDate);
    if (!mounted) return;
    setState(() => _attendance = att);
  }

  Future<void> _shiftDate(int delta) async {
    final d = DateTime.parse(_attDate);
    _attDate = dateStr(DateTime(d.year, d.month, d.day + delta));
    await _loadAll();
  }

  Widget _attendanceTab() {
    final active = _workers.where((w) => intv(w['active']) == 1).toList();
    final present = _attendance.values.where((s) => s == 'Amehudhuria').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => _shiftDate(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickDateStr(context, _attDate);
                  if (d != null) {
                    _attDate = d;
                    await _loadAll();
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(_attDate),
              ),
            ),
            IconButton(
              onPressed: () => _shiftDate(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Waliohudhuria: $present kati ya ${active.length}'),
        const SizedBox(height: 8),
        if (active.isEmpty)
          const EmptyCard('Ongeza wafanyakazi kwanza.')
        else
          for (final w in active)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w['full_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final st in const [
                          'Amehudhuria',
                          'Hajafika',
                          'Ruhusa'
                        ])
                          ChoiceChip(
                            label: Text(st),
                            selected: _attendance[w['uuid']] == st,
                            onSelected: (_) => _setAtt(w['uuid'] as String, st),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ----- Malipo -----
  Future<void> _pay(Map<String, dynamic> w) async {
    final uuid = w['uuid'] as String;
    final days = _days[uuid] ?? 0;
    final suggested =
        calcPay(w['pay_type'] as String, dbl(w['pay_rate']), days);

    final ok = await showSpecSheet(
      context,
      title: 'Lipa: ${w['full_name']}',
      note: 'Kipindi: $_from hadi $_to • Siku alizohudhuria: $days\n'
          '${payTypeHelp(w['pay_type'] as String)}',
      fields: [
        FSpec('gross', 'Kiasi cha malipo (TSh)',
            type: FType.decimal,
            initial: suggested > 0 ? suggested.toStringAsFixed(0) : null),
        const FSpec('ded', 'Makato (TSh)',
            type: FType.decimal, required: false, initial: '0'),
        FSpec('method', 'Njia ya malipo',
            type: FType.dropdown, options: optsOf(kPayMethods)),
        const FSpec('date', 'Tarehe ya malipo', type: FType.date),
        const FSpec('notes', 'Maelezo', type: FType.multiline, required: false),
      ],
      preview: (v) {
        final g = parseNum(v['gross']) ?? 0;
        final d = parseNum(v['ded']) ?? 0;
        return 'Atapokea: ${fmtMoney(g - d)}';
      },
      onSubmit: (v) => DatabaseHelper.instance.payWorker(
        workerUuid: uuid,
        periodFrom: _from,
        periodTo: _to,
        daysPresentCount: days,
        gross: parseNum(v['gross'])!,
        deductions: parseNum(v['ded']) ?? 0,
        paidDate: v['date']!,
        method: v['method']!,
        notes: v['notes']!.isEmpty ? null : v['notes'],
      ),
    );
    if (ok) {
      if (!mounted) return;
      snack(context, 'Malipo yamehifadhiwa na kuingizwa kwenye Fedha.');
      await _loadAll();
    }
  }

  Future<void> _voidPay(Map<String, dynamic> p) async {
    final reason =
        await askReason(context, 'Futa malipo ya ${p['full_name']}?');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.voidPayment(p['uuid'] as String, reason);
      if (!mounted) return;
      snack(context, 'Malipo yamefutwa.');
      await _loadAll();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Widget _payrollTab() {
    final active = _workers.where((w) => intv(w['active']) == 1).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Kipindi cha malipo',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final d = await pickDateStr(context, _from);
                  if (d != null) {
                    _from = d;
                    await _loadAll();
                  }
                },
                child: Text('Kuanzia $_from'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final d = await pickDateStr(context, _to);
                  if (d != null) {
                    _to = d;
                    await _loadAll();
                  }
                },
                child: Text('Hadi $_to'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (active.isEmpty)
          const EmptyCard('Ongeza wafanyakazi kwanza.')
        else
          for (final w in active)
            Card(
              child: ListTile(
                title: Text(w['full_name'] as String),
                subtitle: Text(
                  'Amehudhuria siku ${_days[w['uuid']] ?? 0} • ${w['pay_type']}\n'
                  'Anastahili: ${w['pay_type'] == 'Mgawo' ? 'kwa mkono' : fmtMoney(calcPay(w['pay_type'] as String, dbl(w['pay_rate']), _days[w['uuid']] ?? 0))}',
                ),
                isThreeLine: true,
                trailing: FilledButton(
                  onPressed: () => _pay(w),
                  child: const Text('Lipa'),
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text('Malipo ya Karibuni',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_payments.isEmpty)
          const EmptyCard('Bado hakuna malipo.')
        else
          for (final p in _payments.take(30))
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(
                  '${p['full_name'] ?? '-'}  •  ${fmtMoney(dbl(p['net']))}',
                  style: intv(p['voided']) == 1 ? VoidedStyle.title : null,
                ),
                subtitle: Text(
                  '${shortDate(p['paid_date'])} • ${p['method'] ?? ''}\n'
                  'Kipindi ${p['period_from']} - ${p['period_to']} • '
                  'Siku ${p['days_present']}'
                  '${intv(p['voided']) == 1 ? '\nImefutwa: ${p['void_reason']}' : ''}',
                ),
                isThreeLine: true,
                trailing: intv(p['voided']) == 1
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (_) => _voidPay(p),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'v', child: Text('Futa kwa sababu')),
                        ],
                      ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wafanyakazi & Payroll'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Wafanyakazi'),
              Tab(text: 'Mahudhurio'),
              Tab(text: 'Malipo'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [_workersTab(), _attendanceTab(), _payrollTab()],
              ),
      ),
    );
  }
}
