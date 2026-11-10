import 'package:flutter/material.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'utils.dart';

/// Inaonekana mara ya kwanza (au pale kampuni/jina la mtumiaji vinapokosekana).
class SetupScreen extends StatelessWidget {
  final VoidCallback onDone;
  const SetupScreen({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getCompanies(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final needCompany = snap.data!.isEmpty;
        final needUser = AppCtx.user.isEmpty;
        final fields = <FSpec>[
          if (needUser)
            const FSpec('user', 'Jina lako kamili',
                hint: 'Litatumika kama "aliyeingiza rekodi"'),
          if (needCompany) const FSpec('company', 'Jina la kampuni'),
          if (needCompany) const FSpec('mine', 'Jina la mgodi'),
          if (needCompany)
            const FSpec('location', 'Mahali pa mgodi',
                required: false, hint: 'Mfano: Geita, Mwanza'),
        ];

        return Scaffold(
          appBar: AppBar(title: const Text('Karibu Madini Track')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Icon(Icons.diamond_outlined,
                  size: 56, color: Colors.orange),
              const SizedBox(height: 12),
              Text(
                'Tuanze kwa kuweka taarifa za msingi',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Data yote inahifadhiwa ndani ya simu hii. '
                'Unaweza kuongeza kampuni na migodi mingine baadaye.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SpecForm(
                    fields: fields,
                    submitLabel: 'Anza Kutumia',
                    onSubmit: (v) async {
                      final db = DatabaseHelper.instance;
                      if (needUser) {
                        await db.setSetting('user_name', v['user']!);
                      }
                      if (needCompany) {
                        await db.addCompany(
                          name: v['company']!,
                          mineName: v['mine']!,
                          location: (v['location'] ?? '').isEmpty
                              ? null
                              : v['location'],
                        );
                        await db.setSetting('active_company', v['company']!);
                        await db.setSetting('active_mine', v['mine']!);
                      }
                    },
                    onSaved: onDone,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
