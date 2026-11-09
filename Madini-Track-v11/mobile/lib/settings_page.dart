import 'package:flutter/material.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'app_context.dart';
import 'backup_service.dart';
import 'l10n.dart';
import 'v8_pages.dart';
import 'database_helper.dart';
import 'db_reports.dart';
import 'lock_page.dart';
import 'utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _db = DatabaseHelper.instance;

  Future<void> _editProfile() async {
    final ok = await showSpecSheet(
      context,
      title: 'Wasifu',
      fields: [FSpec('name', 'Jina lako kamili', initial: AppCtx.user)],
      onSubmit: (v) async {
        await _db.setSetting('user_name', v['name']!);
        AppCtx.user = v['name']!;
      },
    );
    if (ok) setState(() {});
  }

  Future<void> _editRates() async {
    final ok = await showSpecSheet(
      context,
      title: 'Viwango na Tahadhari',
      note: 'Thibitisha viwango vya mrabaha na ada na Tume ya Madini / TRA '
          'kabla ya kutegemea hesabu hizi.',
      fields: [
        FSpec('royalty', 'Mrabaha (%)',
            type: FType.decimal, initial: AppCtx.royaltyPercent.toString()),
        FSpec('inspection', 'Ada ya ukaguzi (%)',
            type: FType.decimal, initial: AppCtx.inspectionPercent.toString()),
        FSpec('recovery',
            'Tahadhari ikiwa dhahabu halisi iko chini ya (% ya makadirio)',
            type: FType.decimal, initial: AppCtx.minRecoveryPercent.toString()),
      ],
      onSubmit: (v) async {
        final roy = parseNum(v['royalty'])!;
        final ins = parseNum(v['inspection'])!;
        final rec = parseNum(v['recovery'])!;
        if (roy > 100 || ins > 100 || rec > 100) {
          throw AppError('Asilimia haiwezi kuzidi 100.');
        }
        await _db.setSetting('royalty_percent', roy.toString());
        await _db.setSetting('inspection_percent', ins.toString());
        await _db.setSetting('min_recovery_percent', rec.toString());
        AppCtx.royaltyPercent = roy;
        AppCtx.inspectionPercent = ins;
        AppCtx.minRecoveryPercent = rec;
      },
    );
    if (ok) setState(() {});
  }

  Future<void> _setPin() async {
    final ok = await showSpecSheet(
      context,
      title: AppCtx.hasPin ? 'Badilisha PIN' : 'Weka PIN',
      note: 'PIN inafunga app isitumiwe na mtu mwingine. '
          'Ukiisahau, utahitaji Backup ili kuanza upya.',
      fields: const [
        FSpec('pin', 'PIN mpya (tarakimu 4 hadi 8)', type: FType.integer),
        FSpec('pin2', 'Rudia PIN', type: FType.integer),
      ],
      onSubmit: (v) async {
        final p = v['pin']!;
        if (p.length < 4 || p.length > 8) {
          throw AppError('PIN iwe na tarakimu 4 hadi 8.');
        }
        if (p != v['pin2']) throw AppError('PIN hazifanani.');
        await savePin(p);
      },
    );
    if (ok) setState(() {});
  }

  Future<void> _removePin() async {
    final yes =
        await confirmDialog(context, 'Ondoa PIN?', 'App itafunguka bila PIN.');
    if (!yes) return;
    await removePin();
    if (mounted) setState(() {});
  }

  Future<void> _toggle(
      String key, bool value, void Function(bool) apply) async {
    await _db.setSetting(key, value ? '1' : '0');
    apply(value);
    setState(() {});
  }

  Future<void> _backup() async {
    final json = await _db.exportBackupJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    final big = json.length > 800000;
    snack(
      context,
      big
          ? 'Backup imenakiliwa, lakini ni kubwa (${(json.length / 1024).round()} KB). '
              'Simu zingine zinaweza kushindwa kuishikilia; hifadhi kwa vipande ukiona tatizo.'
          : 'Backup imenakiliwa (${(json.length / 1024).round()} KB). '
              'Ibandike kwenye barua pepe au ujumbe wa kujitumia.',
    );
  }

  Future<void> _restore() async {
    final ok = await showSpecSheet(
      context,
      title: 'Rejesha Backup',
      note:
          'ONYO: Data yote ya sasa kwenye simu hii itabadilishwa na ya backup.',
      fields: const [
        FSpec('json', 'Bandika maandishi ya backup hapa',
            type: FType.multiline),
      ],
      submitLabel: 'Rejesha',
      onSubmit: (v) => _db.restoreBackupJson(v['json']!),
    );
    if (ok) {
      if (!mounted) return;
      snack(context, 'Backup imerejeshwa.');
      setState(() {});
    }
  }

  Future<void> _backupFile() async {
    String? password;
    final ok = await showSpecSheet(
      context,
      title: 'Backup ya Faili',
      note:
          'Nywila ni ya hiari. Ukiiweka, faili litasimbwa (AES-256) na LITAHITAJI nywila hiyo kurejesha. '
          'Ukisahau nywila, backup haiwezi kufunguliwa.',
      fields: const [
        FSpec('password', 'Nywila ya backup (si lazima)', required: false)
      ],
      submitLabel: 'Tengeneza',
      onSubmit: (v) async {
        password = v['password'];
      },
    );
    if (!ok) return;
    try {
      final file = await BackupService.createBackupFile(password: password);
      await Share.shareXFiles([XFile(file.path)], text: 'Madini Track backup');
      if (mounted) snack(context, 'Backup imehifadhiwa: ${file.path}');
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _restoreFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.any);
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null) {
        throw AppError('Haikuweza kusoma faili lililochaguliwa.');
      }
      final text = await File(path).readAsString();
      String? password;
      BackupPreview? preview;
      try {
        preview = await BackupService.inspect(text);
      } on AppError catch (e) {
        if (!e.message.contains('nywila')) rethrow;
        if (!mounted) return;
        final ok = await showSpecSheet(
          context,
          title: 'Nywila ya Backup',
          fields: const [FSpec('password', 'Nywila')],
          submitLabel: 'Fungua',
          onSubmit: (v) async {
            password = v['password'];
            preview = await BackupService.inspect(text, password: password);
          },
        );
        if (!ok) return;
      }
      final p = preview!;
      if (!mounted) return;
      final yes = await confirmDialog(
        context,
        'Rejesha backup?',
        'Tarehe: ${p.createdAt.replaceFirst('T', ' ').split('.').first}\n'
            'Toleo la schema: ${p.schemaVersion}\n'
            'Rekodi: ${p.totalRows}\n\n'
            'Data YOTE ya sasa itabadilishwa. Snapshot ya hali ya sasa itahifadhiwa kwanza.',
        yes: 'Rejesha',
      );
      if (!yes) return;
      final snap = await BackupService.restore(p);
      if (!mounted) return;
      snack(context, 'Imerejeshwa. Snapshot ya awali: ${snap?.path ?? '-'}');
      setState(() {});
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _audit() async {
    final rows = await _db.getAuditLog();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _AuditPage(rows: rows)),
    );
  }

  Future<void> _counts() async {
    final c = await _db.tableCounts();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rekodi zilizo kwenye simu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final e in c.entries) KV(e.key, '${e.value}')],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Funga')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mipangilio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(AppCtx.user),
                  subtitle: Text('${AppCtx.company} • ${AppCtx.mine}'),
                  trailing: const Icon(Icons.edit),
                  onTap: _editProfile,
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(AppCtx.hasPin
                      ? 'PIN imewashwa'
                      : 'Weka PIN ya kufunga app'),
                  trailing: AppCtx.hasPin
                      ? TextButton(
                          onPressed: _removePin, child: const Text('Ondoa'))
                      : null,
                  onTap: _setPin,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.verified_user_outlined),
                  title: const Text('Shahidi anahitajika'),
                  subtitle: const Text(
                    'Uzalishaji, uhamisho, uchakataji na mauzo vinahitaji mtu wa pili.',
                  ),
                  value: AppCtx.requireWitness,
                  onChanged: (v) => _toggle(
                    'require_witness',
                    v,
                    (x) => AppCtx.requireWitness = x,
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.fact_check_outlined),
                  title: const Text('Matumizi yahitaji idhini'),
                  subtitle: const Text(
                      'Matumizi yanayoingizwa na watumiaji wasio na mamlaka yanasubiri Mmiliki/Meneja/Mhasibu aidhinishe.'),
                  value: AppCtx.expenseApproval,
                  onChanged: (v) => _toggle(
                      'expense_approval', v, (x) => AppCtx.expenseApproval = x),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.language),
                  title: Text('${tr('Lugha')}: English'),
                  subtitle: const Text(
                      'Kiswahili ni lugha kuu. Skrini ambazo hazijatafsiriwa zinabaki Kiswahili.'),
                  value: L10n.isEn,
                  onChanged: (v) async {
                    await _db.setSetting('lang', v ? 'en' : 'sw');
                    L10n.lang = v ? 'en' : 'sw';
                    appReload.value++;
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(tr('Watumiaji wa Kifaa')),
                  subtitle: const Text(
                      'Ingia kwa PIN, majukumu, shahidi aliyethibitishwa'),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LocalUsersPage())),
                ),
                const SwitchListTile(
                  secondary: Icon(Icons.block),
                  title: Text('Zuia mauzo yanayozidi dhahabu iliyopo'),
                  subtitle: Text(
                      'Ulinzi huu ni wa lazima ili kuzuia kuuza dhahabu isiyopo kwenye stock.'),
                  value: true,
                  onChanged: null,
                ),
                ListTile(
                  leading: const Icon(Icons.percent),
                  title: const Text('Mrabaha, ada na tahadhari'),
                  subtitle: Text(
                    'Mrabaha ${fmtNum(AppCtx.royaltyPercent)}% • '
                    'Ukaguzi ${fmtNum(AppCtx.inspectionPercent)}% • '
                    'Recovery chini ya ${fmtNum(AppCtx.minRecoveryPercent, decimals: 0)}%',
                  ),
                  onTap: _editRates,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: const Text('Backup ya Faili (inapendekezwa)'),
                  subtitle: const Text(
                      'Faili lenye checksum, nywila ya hiari na kushiriki.'),
                  onTap: _backupFile,
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Rejesha kutoka Faili'),
                  subtitle: const Text(
                      'Inaonyesha preview na kuhifadhi snapshot kabla ya kurejesha.'),
                  onTap: _restoreFile,
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Tengeneza Backup'),
                  subtitle:
                      const Text('Inanakili data yote kama maandishi (JSON).'),
                  onTap: _backup,
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Rejesha Backup'),
                  onTap: _restore,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Audit log'),
                  subtitle: const Text('Nani alifanya nini na lini.'),
                  onTap: _audit,
                ),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Takwimu za database'),
                  onTap: _counts,
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Madini Track Tanzania'),
                  subtitle:
                      Text('Toleo 2.0.0 • Database v$kDbVersion • Offline'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditPage extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _AuditPage({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: rows.isEmpty
          ? const Center(child: Text('Bado hakuna rekodi.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text('${r['entity']} • ${r['action']}'),
                    subtitle: Text(
                      '${(r['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first}'
                      ' • ${r['user_name'] ?? ''}'
                      '${(r['detail'] ?? '').toString().isEmpty ? '' : '\n${r['detail']}'}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
