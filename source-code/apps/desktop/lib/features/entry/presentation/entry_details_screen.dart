import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/models/entry_field.dart';
import '../../../presentation/shared/widgets/section_surface.dart';
import '../application/entry_providers.dart';

/// Read-only entry details screen for the currently selected vault item.
class EntryDetailsScreen extends ConsumerStatefulWidget {
  const EntryDetailsScreen({
    required this.entryUuid,
    super.key,
  });

  final String entryUuid;

  @override
  ConsumerState<EntryDetailsScreen> createState() => _EntryDetailsScreenState();
}

class _EntryDetailsScreenState extends ConsumerState<EntryDetailsScreen> {
  bool _revealSecrets = false;

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(selectedEntryProvider(widget.entryUuid));
    final totp = ref.watch(entryTotpProvider(widget.entryUuid));

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.title ?? 'Entry'),
        actions: <Widget>[
          IconButton(
            tooltip: _revealSecrets ? 'Hide protected fields' : 'Reveal protected fields',
            onPressed: () => setState(() => _revealSecrets = !_revealSecrets),
            icon: Icon(
              _revealSecrets
                  ? TablerIcons.eye_off
                  : TablerIcons.eye,
            ),
          ),
        ],
      ),
      body: entry == null
          ? const Center(child: Text('Entry not found.'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                if (totp != null) ...<Widget>[
                  SectionSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Authenticator',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          totp.code,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Refreshes in ${totp.secondsRemaining}s',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SectionSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Fields',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      for (final field in entry.fields) ...<Widget>[
                        _FieldRow(
                          field: field,
                          revealSecrets: _revealSecrets,
                        ),
                        if (field != entry.fields.last) const Divider(height: 24),
                      ],
                    ],
                  ),
                ),
                if ((entry.notes ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  SectionSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(entry.notes!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.revealSecrets,
  });

  final EntryField field;
  final bool revealSecrets;

  @override
  Widget build(BuildContext context) {
    final obscured = field.isProtected && !revealSecrets;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            field.key,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: SelectableText(
            obscured ? '••••••••••' : field.value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
