import 'package:flutter/material.dart';

import 'app_context.dart';
import 'database_helper.dart';
import 'db_v8.dart';
import 'evidence.dart';
import 'l10n.dart';
import 'local_auth.dart';
import 'sync_service.dart';
import 'utils.dart';

const List<Opt> _kYesNo = [Opt('0', 'Hapana'), Opt('1', 'Ndiyo')];
const List<Opt> _kYesNoUnknown = [
  Opt('u', 'Haijulikani'),
  Opt('1', 'Ndiyo'),
  Opt('0', 'Hapana'),
];

// ===========================================================================
// USALAMA (Safety)
// ===========================================================================
class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key});

  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getSafetyIncidents();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    String? createdUuid;
    final ok = await showSpecSheet(
      context,
      title: 'Ripoti Tukio la Usalama',
      note: 'Baada ya kuhifadhi utaombwa kupiga picha za eneo/tukio.',
      fields: [
        FSpec('type', 'Aina',
            type: FType.dropdown, options: optsOf(kSafetyTypes)),
        FSpec('severity', 'Ukubwa',
            type: FType.dropdown, options: optsOf(kSafetySeverities)),
        const FSpec('date', 'Tarehe', type: FType.date),
        const FSpec('location', 'Eneo / shaft', required: false),
        FSpec('category', 'Kundi la tukio',
            type: FType.dropdown,
            options: optsOf(kIncidentCategories),
            initial: 'Nyingine'),
        FSpec('class', 'Kiwango cha jeraha',
            type: FType.dropdown,
            options: optsOf(kInjuryClasses),
            initial: 'Hakuna'),
        const FSpec('injured', 'Idadi ya majeruhi',
            type: FType.integer, required: false, initial: '0'),
        const FSpec('injured_name', 'Jina la aliyejeruhiwa', required: false),
        const FSpec('body_part', 'Sehemu ya mwili iliyoathirika',
            required: false),
        const FSpec('lost_days', 'Siku za kupoteza kazi',
            type: FType.integer, required: false, initial: '0'),
        const FSpec('ppe', 'PPE ilivaliwa?',
            type: FType.dropdown, options: _kYesNoUnknown, initial: 'u'),
        const FSpec('equipment', 'Kifaa/mashine husika', required: false),
        const FSpec('witnesses', 'Mashahidi', required: false),
        const FSpec('desc', 'Kilichotokea', type: FType.multiline),
        FSpec('cause', 'Chanzo (root cause)',
            type: FType.dropdown,
            options: optsOf(kRootCauses),
            initial: 'Haijulikani bado'),
        const FSpec('action', 'Hatua zilizochukuliwa',
            type: FType.multiline, required: false),
        const FSpec('stopped', 'Kazi imesimamishwa eneo hilo?',
            type: FType.dropdown, options: _kYesNo, initial: '0'),
        const FSpec('reported', 'Limeripotiwa kwa mamlaka?',
            type: FType.dropdown, options: _kYesNo, initial: '0'),
        const FSpec('authority_ref', 'Namba ya rejea ya ripoti',
            required: false),
        const FSpec('officer', 'Afisa anayehusika', required: false),
      ],
      onSubmit: (v) async {
        createdUuid = await DatabaseHelper.instance.addSafetyIncident(
          type: v['type']!,
          severity: v['severity']!,
          occurredAt: v['date']!,
          location: v['location'],
          description: v['desc']!,
          injured: parseNum(v['injured'])?.round() ?? 0,
          actionTaken: v['action'],
          officer: v['officer'],
          category: v['category'],
          rootCause: v['cause'],
          injuryClass: v['class'],
          injuredName: v['injured_name'],
          bodyPart: v['body_part'],
          lostWorkDays: parseNum(v['lost_days'])?.round() ?? 0,
          witnesses: v['witnesses'],
          equipment: v['equipment'],
          ppeWorn: v['ppe'] == '1' ? true : (v['ppe'] == '0' ? false : null),
          workStopped: v['stopped'] == '1',
          reportedToAuthority: v['reported'] == '1',
          authorityReference: v['authority_ref'],
        );
      },
    );
    if (!ok) return;
    await _load();
    final uuid = createdUuid;
    if (uuid != null && mounted) {
      await showAttachSheet(context, 'safety_incidents', uuid);
    }
  }

  Future<void> _followUp(Map<String, dynamic> r) async {
    final ok = await showSpecSheet(
      context,
      title: 'Follow-up',
      fields: [
        FSpec('status', 'Hali',
            type: FType.dropdown,
            options: optsOf(kFollowUp),
            initial: r['follow_up_status'] as String?),
        FSpec('cause', 'Chanzo (root cause)',
            type: FType.dropdown,
            options: optsOf(kRootCauses),
            initial: (r['root_cause'] ?? 'Haijulikani bado') as String),
        FSpec('corrective', 'Hatua ya kurekebisha',
            type: FType.multiline,
            required: false,
            initial: r['corrective_action'] as String?),
        FSpec('due', 'Tarehe ya kukamilisha',
            type: FType.date,
            required: false,
            initial: r['corrective_due'] as String?),
        FSpec('reported', 'Limeripotiwa kwa mamlaka?',
            type: FType.dropdown,
            options: _kYesNo,
            initial: intv(r['reported_to_authority']) == 1 ? '1' : '0'),
        FSpec('authority_ref', 'Namba ya rejea ya ripoti',
            required: false, initial: r['authority_reference'] as String?),
        const FSpec('note', 'Maelezo', required: false),
      ],
      onSubmit: (v) => DatabaseHelper.instance.updateSafetyFollowUp(
        r['uuid'] as String,
        v['status']!,
        v['note'],
        rootCause: v['cause'],
        correctiveAction: v['corrective'],
        correctiveDue: v['due'],
        reportedToAuthority: v['reported'] == '1',
        authorityReference: v['authority_ref'],
      ),
    );
    if (ok) await _load();
  }

  Future<void> _void(Map<String, dynamic> r) async {
    final reason = await askReason(context, 'Futa rekodi ya usalama');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance
          .voidSafetyIncident(r['uuid'] as String, reason);
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  List<Widget> _extra(Map<String, dynamic> r) {
    String s(String k) => (r[k] ?? '').toString();
    final severe = r['severity'] == 'Kubwa' || r['severity'] == 'Kifo';
    return [
      if (s('incident_category').isNotEmpty)
        KV('Kundi', s('incident_category')),
      if (s('injury_class').isNotEmpty && s('injury_class') != 'Hakuna')
        KV('Kiwango cha jeraha', s('injury_class')),
      if (s('injured_name').isNotEmpty) KV('Aliyejeruhiwa', s('injured_name')),
      if (s('body_part').isNotEmpty) KV('Sehemu ya mwili', s('body_part')),
      if (intv(r['lost_work_days']) > 0)
        KV('Siku zilizopotea', '${r['lost_work_days']}'),
      if (r['ppe_worn'] != null)
        KV('PPE', intv(r['ppe_worn']) == 1 ? 'Ilivaliwa' : 'Haikuvaliwa'),
      if (s('equipment_involved').isNotEmpty)
        KV('Kifaa', s('equipment_involved')),
      if (s('witnesses').isNotEmpty) KV('Mashahidi', s('witnesses')),
      if (s('root_cause').isNotEmpty) KV('Chanzo', s('root_cause')),
      if (s('corrective_action').isNotEmpty)
        KV('Hatua ya kurekebisha', s('corrective_action')),
      if (intv(r['reported_to_authority']) == 1)
        KV('Ripoti kwa mamlaka', s('authority_reference')),
      if (s('closed_by').isNotEmpty)
        KV('Imefungwa na', '${s('closed_by')} • ${shortDate(s('closed_at'))}'),
      if (severe && intv(r['reported_to_authority']) != 1)
        const Text('⚠ Haijaripotiwa kwa mamlaka',
            style: TextStyle(color: Colors.red)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usalama Mgodini')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Ripoti tukio'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: EmptyCard('Hakuna matukio ya usalama yaliyorekodiwa.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  children: [
                    for (final r in _rows)
                      Card(
                        child: ExpansionTile(
                          leading: Icon(
                            Icons.health_and_safety_outlined,
                            color: (r['severity'] == 'Kubwa' ||
                                    r['severity'] == 'Kifo')
                                ? Colors.red
                                : Colors.orange,
                          ),
                          title:
                              Text('${r['incident_type']} • ${r['severity']}'),
                          subtitle: Text(
                              '${shortDate(r['occurred_at'])} • ${r['follow_up_status']}'),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          children: [
                            KV('Kilichotokea', '${r['description']}'),
                            if ((r['location'] ?? '').toString().isNotEmpty)
                              KV('Eneo', '${r['location']}'),
                            KV('Majeruhi', '${r['injured_count']}'),
                            if ((r['action_taken'] ?? '').toString().isNotEmpty)
                              KV('Hatua', '${r['action_taken']}'),
                            if ((r['responsible_officer'] ?? '')
                                .toString()
                                .isNotEmpty)
                              KV('Afisa', '${r['responsible_officer']}'),
                            KV('Aliyeripoti', '${r['reported_by']}'),
                            ..._extra(r),
                            Wrap(spacing: 4, children: [
                              TextButton.icon(
                                onPressed: () => _followUp(r),
                                icon: const Icon(Icons.flag_outlined),
                                label: const Text('Follow-up'),
                              ),
                              TextButton.icon(
                                onPressed: () => showAttachSheet(context,
                                    'safety_incidents', r['uuid'] as String),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: const Text('Ushahidi'),
                              ),
                              TextButton.icon(
                                onPressed: () => _void(r),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Futa'),
                              ),
                            ]),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ===========================================================================
// VIWANGO VYA KODI (tax_rates) — bila viwango vya kubuni
// ===========================================================================
class TaxRatesPage extends StatefulWidget {
  const TaxRatesPage({super.key});

  @override
  State<TaxRatesPage> createState() => _TaxRatesPageState();
}

class _TaxRatesPageState extends State<TaxRatesPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getTaxRates();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final ok = await showSpecSheet(
      context,
      title: 'Kiwango Kipya',
      note:
          'Weka kiwango kutoka chanzo rasmi (Tume ya Madini / TRA / kanuni za serikali) '
          'pamoja na rejea yake. Kiwango kinaanza kama DRAFT na hakitumiki hadi kithibitishwe.',
      fields: [
        FSpec('type', 'Aina',
            type: FType.dropdown, options: optsOf(kTaxRateTypes)),
        const FSpec('percent', 'Asilimia (%)', type: FType.decimal),
        const FSpec('from', 'Inaanza kutumika', type: FType.date),
        const FSpec('to', 'Inaisha (YYYY-MM-DD, si lazima)', required: false),
        const FSpec('ref', 'Rejea ya chanzo (kanuni/tangazo/namba)'),
        const FSpec('url', 'Kiungo cha chanzo (si lazima)', required: false),
      ],
      onSubmit: (v) => DatabaseHelper.instance.addTaxRate(
        type: v['type']!,
        percent: parseNum(v['percent'])!,
        effectiveFrom: v['from']!,
        effectiveTo: v['to'],
        sourceReference: v['ref']!,
        sourceUrl: v['url'],
      ),
    );
    if (ok) await _load();
  }

  Future<void> _verify(Map<String, dynamic> r) async {
    final yes = await confirmDialog(
      context,
      'Thibitisha kiwango?',
      'Thibitisha kuwa ${r['percent']}% ya ${r['rate_type']} inalingana na chanzo: '
          '${r['source_reference']}. Baada ya kuthibitishwa kitatumika kwenye mauzo mapya.',
      yes: 'Thibitisha',
    );
    if (!yes) return;
    try {
      await DatabaseHelper.instance.verifyTaxRate(r['uuid'] as String);
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _retire(Map<String, dynamic> r) async {
    await DatabaseHelper.instance.retireTaxRate(r['uuid'] as String);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Viwango vya Kodi na Ada')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Kiwango'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'Madini Track haina viwango vya kisheria vilivyojengwa ndani. '
                        'Ingiza viwango vilivyothibitishwa rasmi pamoja na tarehe za uhalali. '
                        'Bila kiwango kilichothibitishwa, mipangilio ya mkono ya Mipangilio inatumika.'),
                  ),
                ),
                if (_rows.isEmpty)
                  const EmptyCard('Bado hakuna kiwango kilichowekwa.'),
                for (final r in _rows)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        r['status'] == 'verified'
                            ? Icons.verified_outlined
                            : (r['status'] == 'retired'
                                ? Icons.block
                                : Icons.edit_note),
                        color: r['status'] == 'verified'
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: Text(
                          '${r['rate_type']}: ${fmtNum(dbl(r['percent']))}%'),
                      subtitle: Text(
                          '${r['effective_from']} → ${r['effective_to'] ?? 'bila mwisho'}\n'
                          'Chanzo: ${r['source_reference']}\nHali: ${r['status']}'),
                      isThreeLine: true,
                      trailing: r['status'] == 'draft'
                          ? TextButton(
                              onPressed: () => _verify(r),
                              child: const Text('Thibitisha'))
                          : (r['status'] == 'verified'
                              ? TextButton(
                                  onPressed: () => _retire(r),
                                  child: const Text('Staafisha'))
                              : null),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ===========================================================================
// USAWAZISHAJI (Sync)
// ===========================================================================
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  Map<String, int> _stats = {};
  String? _url;
  bool _hasToken = false;
  bool _busy = false;
  String? _result;
  String? _companyUuid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DatabaseHelper.instance.outboxStats();
    final u = await SyncService.serverUrl();
    final t = await SyncService.hasToken();
    final cu = await SyncService.localCompanyUuid();
    if (!mounted) return;
    setState(() {
      _stats = s;
      _url = u;
      _hasToken = t;
      _companyUuid = cu;
    });
  }

  Future<void> _setUrl() async {
    final ok = await showSpecSheet(
      context,
      title: 'Anwani ya Seva',
      fields: [FSpec('url', 'URL (https://...)', initial: _url)],
      onSubmit: (v) => SyncService.saveServerUrl(v['url']!),
    );
    if (ok) await _load();
  }

  Future<void> _login() async {
    final user = TextEditingController();
    final pass = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ingia kwenye seva'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: user,
              decoration: const InputDecoration(labelText: 'Jina la mtumiaji')),
          TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nywila')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ghairi')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ingia')),
        ],
      ),
    );
    if (go != true) return;
    try {
      await SyncService.login(username: user.text, password: pass.text);
      if (mounted) snack(context, 'Umeingia.');
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
    pass.clear();
    await _load();
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await SyncService.syncNow();
      _result = r.toString();
    } catch (e) {
      _result = 'Imeshindikana: ${errText(e)}';
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _pull() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      _result = (await SyncService.pullNow()).toString();
    } catch (e) {
      _result = 'Imeshindikana: ${errText(e)}';
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = (_stats['pending'] ?? 0) +
        (_stats['failed'] ?? 0) +
        (_stats['sending'] ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Usawazishaji')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Seva'),
                subtitle: Text(_url ?? 'Haijawekwa'),
                onTap: _setUrl,
              ),
              ListTile(
                leading: Icon(_hasToken ? Icons.lock_open : Icons.lock_outline),
                title: Text(_hasToken ? 'Umeingia' : 'Hujaingia'),
                trailing: _hasToken
                    ? TextButton(
                        onPressed: () async {
                          await SyncService.logout();
                          await _load();
                        },
                        child: const Text('Toka'))
                    : TextButton(
                        onPressed: _url == null ? null : _login,
                        child: const Text('Ingia')),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text(
                  'Kitambulisho cha kampuni (kwa msimamizi wa seva)'),
              subtitle:
                  SelectableText('${AppCtx.company}\n${_companyUuid ?? '-'}'),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              KV('Zinasubiri / zinajaribu tena', '$pending'),
              KV('Zimesawazishwa', '${_stats['synced'] ?? 0}'),
              KV('Migongano (inahitaji uamuzi)', '${_stats['conflict'] ?? 0}'),
              KV('Zilizokataliwa na seva', '${_stats['rejected'] ?? 0}'),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (_busy || _url == null || !_hasToken) ? null : _sync,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sawazisha sasa'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_busy || _url == null || !_hasToken) ? null : _pull,
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(tr('Pakua mabadiliko')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_url == null || !_hasToken)
                ? null
                : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ConflictsPage())),
            icon: const Icon(Icons.merge_type),
            label: Text(tr('Migongano')),
          ),
          if (_result != null)
            Padding(
                padding: const EdgeInsets.only(top: 12), child: Text(_result!)),
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
                'Rekodi inahesabiwa "imesawazishwa" TU baada ya seva kuthibitisha kuihifadhi. '
                'Bila mtandao, rekodi zinabaki salama kwenye simu na zinajaribiwa tena.'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// UKAGUZI WA DATA, MASS BALANCE NA GHARAMA KWA BATCH
// ===========================================================================
class DataHealthPage extends StatefulWidget {
  const DataHealthPage({super.key});

  @override
  State<DataHealthPage> createState() => _DataHealthPageState();
}

class _DataHealthPageState extends State<DataHealthPage> {
  Map<String, int> _integrity = {};
  List<Map<String, dynamic>> _mass = [];
  List<Map<String, dynamic>> _costs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final i = await db.integrityReport();
    final m = await db.massBalanceReport();
    final c = await db.batchCostReport();
    if (!mounted) return;
    setState(() {
      _integrity = i;
      _mass = m;
      _costs = c;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Ukaguzi wa Data')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final orphans = _integrity.entries
        .where((e) => e.key != 'foreign_keys_on' && e.value > 0)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Ukaguzi wa Data')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Column(children: [
              ListTile(
                leading: Icon(
                    _integrity['foreign_keys_on'] == 1
                        ? Icons.check_circle
                        : Icons.error,
                    color: _integrity['foreign_keys_on'] == 1
                        ? Colors.green
                        : Colors.red),
                title: Text(
                    'Foreign keys: ${_integrity['foreign_keys_on'] == 1 ? 'zimewashwa' : 'HAZIJAWASHWA'}'),
              ),
              ListTile(
                leading: Icon(
                    orphans.isEmpty ? Icons.check_circle : Icons.warning_amber,
                    color: orphans.isEmpty ? Colors.green : Colors.orange),
                title: Text(orphans.isEmpty
                    ? 'Hakuna rekodi zisizo na mzazi'
                    : 'Kuna rekodi zisizo na mzazi'),
                subtitle: orphans.isEmpty
                    ? null
                    : Text(
                        orphans.map((e) => '${e.key}: ${e.value}').join('\n')),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Mass balance ya Batch',
              style: Theme.of(context).textTheme.titleMedium),
          if (_mass.isEmpty) const EmptyCard('Hakuna Batch.'),
          for (final r in _mass)
            Card(
              child: ListTile(
                dense: true,
                title: Text('${r['batch_id']}'),
                subtitle: Text(
                    'Awali ${fmtKg(dbl(r['initial_kg']))} = iliyobaki ${fmtKg(dbl(r['remaining_kg']))} + '
                    'iliyochakatwa ${fmtKg(dbl(r['processed_kg']))} + iliyogawanywa ${fmtKg(dbl(r['split_out_kg']))}'),
                trailing: dbl(r['variance_kg']).abs() < 0.001
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : Text('Tofauti\n${fmtKg(dbl(r['variance_kg']))}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.red)),
              ),
            ),
          const SizedBox(height: 8),
          Text('Gharama kwa Batch',
              style: Theme.of(context).textTheme.titleMedium),
          if (_costs.isEmpty)
            const EmptyCard('Hakuna gharama zilizounganishwa na Batch.'),
          for (final r in _costs)
            Card(
              child: ListTile(
                dense: true,
                title: Text('${r['batch_id']}'),
                subtitle: Text('Miamala ${r['txn_count']}'),
                trailing: Text(fmtMoney(dbl(r['total_cost']))),
              ),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// REJISTA YA USHAHIDI
// ===========================================================================
class EvidenceRegisterPage extends StatefulWidget {
  const EvidenceRegisterPage({super.key});

  @override
  State<EvidenceRegisterPage> createState() => _EvidenceRegisterPageState();
}

class _EvidenceRegisterPageState extends State<EvidenceRegisterPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.instance.getAttachments().then((r) {
      if (!mounted) return;
      setState(() {
        _rows = r;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rejista ya Ushahidi • ${AppCtx.company}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: EmptyCard(
                      'Bado hakuna ushahidi. Ongeza kutoka kwenye Mauzo au Usalama (kitufe cha Ushahidi).'))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final a in _rows)
                    Card(
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.attach_file),
                        title: Text('${a['kind']} • ${a['record_entity']}'),
                        subtitle: Text(
                            '${shortDate(a['created_at'])} • ${a['created_by']}\n'
                            'sha256: ${(a['checksum_sha256'] as String).substring(0, 12)}…'),
                        isThreeLine: true,
                        trailing: Text(a['upload_status'] == 'uploaded'
                            ? 'Imepakiwa'
                            : 'Inasubiri'),
                      ),
                    ),
                ]),
    );
  }
}

// ===========================================================================
// MIGONGANO YA SYNC (conflicts) — kuamua bila silent overwrite
// ===========================================================================
class ConflictsPage extends StatefulWidget {
  const ConflictsPage({super.key});

  @override
  State<ConflictsPage> createState() => _ConflictsPageState();
}

class _ConflictsPageState extends State<ConflictsPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await SyncService.listConflicts();
      if (!mounted) return;
      setState(() {
        _rows = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errText(e);
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> c, String decision) async {
    final yes = await confirmDialog(
      context,
      decision == 'accept_conflict'
          ? 'Kubali toleo la kifaa hicho?'
          : 'Baki na toleo la seva?',
      decision == 'accept_conflict'
          ? 'Toleo la seva litabadilishwa na hili. Uamuzi unarekodiwa kwenye audit log.'
          : 'Toleo la kifaa hicho litakataliwa. Uamuzi unarekodiwa kwenye audit log.',
    );
    if (!yes) return;
    try {
      await SyncService.resolveConflict(intv(c['id']), decision);
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Migongano'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
              : _rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: EmptyCard('Hakuna migongano iliyo wazi.'))
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final c in _rows)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c['entity']} • toleo ${c['version']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  Text(
                                      'Rekodi: ${c['record_uuid']}\nKifaa: ${c['device_id']}'),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 8, children: [
                                    FilledButton(
                                        onPressed: () =>
                                            _decide(c, 'accept_conflict'),
                                        child: const Text('Kubali toleo hili')),
                                    OutlinedButton(
                                        onPressed: () =>
                                            _decide(c, 'keep_server'),
                                        child: const Text('Baki na la seva')),
                                  ]),
                                ]),
                          ),
                        ),
                    ]),
    );
  }
}

// ===========================================================================
// WATUMIAJI WA KIFAA (login ya ndani, majukumu, PIN salama)
// ===========================================================================
class LocalUsersPage extends StatefulWidget {
  const LocalUsersPage({super.key});

  @override
  State<LocalUsersPage> createState() => _LocalUsersPageState();
}

class _LocalUsersPageState extends State<LocalUsersPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await LocalAuth.listUsers();
    if (!mounted) return;
    setState(() {
      _rows = r;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final first = _rows.isEmpty;
    final ok = await showSpecSheet(
      context,
      title: first ? 'Mtumiaji wa Kwanza (Mmiliki)' : 'Mtumiaji Mpya',
      note: first
          ? 'Mtumiaji huyu atakuwa Mmiliki wa Kampuni. Baada ya hapo app itaomba kuingia kwa PIN kila inapofunguliwa.'
          : 'PIN ya mtumiaji ihifadhiwe na yeye mwenyewe; inahifadhiwa kwa hash yenye chumvi.',
      fields: [
        const FSpec('username', 'Jina la mtumiaji (herufi ndogo)'),
        const FSpec('name', 'Jina kamili'),
        FSpec('role', 'Jukumu',
            type: FType.dropdown,
            options: [for (final e in kRoleLabels.entries) Opt(e.key, e.value)],
            initial: first ? 'company_owner' : 'production_supervisor'),
        const FSpec('pin', 'PIN (tarakimu 4 hadi 8)', type: FType.integer),
      ],
      onSubmit: (v) => LocalAuth.createUser(
        username: v['username']!,
        fullName: v['name']!,
        role: v['role']!,
        pin: v['pin']!,
      ),
    );
    if (ok) {
      await AppCtx.load();
      await _load();
      if (first && mounted) {
        snack(context, 'Mtumiaji ameundwa. Ingia sasa.');
        appReload.value++;
      }
    }
  }

  Future<void> _reset(Map<String, dynamic> u) async {
    await showSpecSheet(
      context,
      title: 'PIN Mpya: ${u['full_name']}',
      fields: const [
        FSpec('pin', 'PIN mpya (tarakimu 4 hadi 8)', type: FType.integer)
      ],
      onSubmit: (v) => LocalAuth.resetPin(u['uuid'] as String, v['pin']!),
    );
  }

  Future<void> _toggle(Map<String, dynamic> u) async {
    try {
      await LocalAuth.setActive(u['uuid'] as String, intv(u['active']) != 1);
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = _rows.isEmpty || roleIsAdmin(AppCtx.role);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Watumiaji wa Kifaa'))),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add),
              label: const Text('Ongeza'))
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(AppCtx.localAuthActive
                          ? 'Umeingia kama ${AppCtx.sessionName} (${kRoleLabels[AppCtx.role] ?? AppCtx.role}).'
                          : 'Bado hakuna watumiaji wa kifaa. Ukiongeza mtumiaji wa kwanza, app itaanza kuomba kuingia, '
                              'majukumu yataanza kutumika na shahidi atathibitishwa kwa PIN yake.'),
                    ),
                  ),
                  if (AppCtx.localAuthActive)
                    OutlinedButton.icon(
                      onPressed: LocalAuth.logout,
                      icon: const Icon(Icons.logout),
                      label: Text(tr('Toka')),
                    ),
                  for (final u in _rows)
                    Card(
                      child: ListTile(
                        leading: Icon(intv(u['active']) == 1
                            ? Icons.person
                            : Icons.person_off),
                        title: Text('${u['full_name']}'),
                        subtitle: Text(
                            '${u['username']} • ${kRoleLabels[u['role']] ?? u['role']}'),
                        trailing: (roleIsAdmin(AppCtx.role) ||
                                u['uuid'] == AppCtx.userUuid)
                            ? PopupMenuButton<String>(
                                onSelected: (v) =>
                                    v == 'pin' ? _reset(u) : _toggle(u),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'pin',
                                      child: Text('Badilisha PIN')),
                                  if (roleIsAdmin(AppCtx.role))
                                    PopupMenuItem(
                                        value: 'toggle',
                                        child: Text(intv(u['active']) == 1
                                            ? 'Zima akaunti'
                                            : 'Washa akaunti')),
                                ],
                              )
                            : null,
                      ),
                    ),
                ]),
    );
  }
}

// ===========================================================================
// TRACEABILITY: Production -> Batch -> Movement/Split -> Processing -> Gold lot -> Sale -> Evidence
// ===========================================================================
class TraceabilityPage extends StatefulWidget {
  final String batchUuid;
  const TraceabilityPage({super.key, required this.batchUuid});

  @override
  State<TraceabilityPage> createState() => _TraceabilityPageState();
}

class _TraceabilityPageState extends State<TraceabilityPage> {
  Map<String, List<Map<String, Object?>>> _t = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.instance.batchTrace(widget.batchUuid).then((t) {
      if (!mounted) return;
      setState(() {
        _t = t;
        _loading = false;
      });
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errText(e);
      });
    });
  }

  Widget _section(String title, IconData icon, List<Widget> rows,
      {String empty = 'Hakuna.'}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleSmall)
          ]),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Text(empty, style: Theme.of(context).textTheme.bodySmall)
          else
            ...rows,
        ]),
      ),
    );
  }

  Widget _line(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2), child: Text(text));

  @override
  Widget build(BuildContext context) {
    final title = _t['batch']?.isNotEmpty == true
        ? '${_t['batch']!.first['batch_id']}'
        : 'Batch';
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Chanzo na historia')}: $title')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  _section('1. Uzalishaji', Icons.factory_outlined, [
                    for (final p
                        in _t['production'] ?? const <Map<String, Object?>>[])
                      _line(
                          '${p['batch_id']} • ${shortDate(p['shift_date'])} • ${p['shift_type']}\n'
                          '${fmtKg(dbl(p['weight_kg']))} • ${p['shaft_area']} • ${p['recorded_by']}'
                          '${(p['witness'] ?? '').toString().isEmpty ? '' : '\nShahidi: ${p['witness']}${intv(p['witness_verified']) == 1 ? ' (amethibitishwa kwa PIN)' : ''}'}'
                          '${p['original_batch_id'] == null ? '' : '\nID ya asili: ${p['original_batch_id']}'}'),
                  ]),
                  _section('2. Batch', Icons.inventory_2_outlined, [
                    for (final a
                        in (_t['ancestors'] ?? const <Map<String, Object?>>[])
                            .reversed)
                      _line(
                          'Mzazi: ${a['batch_id']} • ${fmtKg(dbl(a['weight_initial_kg']))}'),
                    for (final b
                        in _t['batch'] ?? const <Map<String, Object?>>[])
                      _line(
                          '${b['batch_id']} • ${b['status']} • ${b['current_location']}\n'
                          'Awali ${fmtKg(dbl(b['weight_initial_kg']))} • Sasa ${fmtKg(dbl(b['weight_kg']))}'),
                    for (final source in _t['merged_sources'] ??
                        const <Map<String, Object?>>[])
                      _line('Chanzo cha merge: ${source['batch_id']} • '
                          '${fmtKg(dbl(source['merge_weight_kg']))}'),
                  ]),
                  _section('3. Uhamisho, Mgawanyo na Merge', Icons.swap_horiz, [
                    for (final m
                        in _t['movements'] ?? const <Map<String, Object?>>[])
                      _line(
                          '${shortDate(m['movement_date'])}: ${m['from_location']} → ${m['to_location']} • '
                          '${fmtKg(dbl(m['weight_kg']))} • ${m['moved_by']}'
                          '${(m['child_batch_id'] ?? '').toString().isEmpty ? '' : ' • Batch mpya ${m['child_batch_id']}'}'),
                  ]),
                  _section('4. Usindikaji', Icons.science_outlined, [
                    for (final p
                        in _t['processing'] ?? const <Map<String, Object?>>[])
                      _line(
                          '${shortDate(p['processing_date'])} • ${fmtKg(dbl(p['ore_processed_kg']))} → '
                          '${fmtNum(dbl(p['gold_recovered_g']))} g • mabaki ${fmtKg(dbl(p['tailings_kg']))} • ${p['processed_by']}'),
                  ]),
                  _section('5. Gold lots', Icons.diamond_outlined, [
                    for (final g
                        in _t['lots'] ?? const <Map<String, Object?>>[])
                      _line(
                          'Lot ${(g['uuid'] as String).substring(0, 8)} • ${fmtNum(dbl(g['grams_initial']))} g '
                          '(zimebaki ${fmtNum(dbl(g['grams_available']))} g)'),
                  ]),
                  _section(
                      '6. Mauzo (FIFO allocation)',
                      Icons.sell_outlined,
                      [
                        for (final s
                            in _t['sales'] ?? const <Map<String, Object?>>[])
                          _line(
                              '${shortDate(s['sale_date'])} • ${s['buyer']} • ${fmtNum(dbl(s['grams']))} g '
                              'kutoka lot ${(s['lot_uuid'] as String).substring(0, 8)}'),
                      ],
                      empty: 'Dhahabu ya Batch hii haijauzwa.'),
                  _section(
                      '7. Ushahidi',
                      Icons.attach_file,
                      [
                        for (final e
                            in _t['evidence'] ?? const <Map<String, Object?>>[])
                          _line(
                              '${e['kind']} • ${e['record_entity']} • ${(dbl(e['file_size']) / 1024).round()} KB • ${e['created_by']}'),
                      ],
                      empty: 'Hakuna ushahidi uliohifadhiwa.'),
                ]),
    );
  }
}

/// Chanzo cha dhahabu iliyouzwa: Batch na lots zilizotoa gramu (FIFO).
Future<void> showSaleSources(BuildContext context, String saleUuid) async {
  final rows = await DatabaseHelper.instance.saleSources(saleUuid);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        Text('Chanzo cha dhahabu iliyouzwa',
            style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Text('Hakuna allocation iliyopatikana kwa mauzo haya.'),
        for (final r in rows)
          ListTile(
            leading: const Icon(Icons.diamond_outlined),
            title:
                Text('Batch ${r['batch_id']} • ${fmtNum(dbl(r['grams']))} g'),
            subtitle: Text(
                'Lot ${(r['lot_uuid'] as String).substring(0, 8)} • Bonyeza kuona historia nzima'),
            onTap: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                    builder: (_) => TraceabilityPage(
                        batchUuid: r['batch_uuid'] as String))),
          ),
      ],
    ),
  );
}
