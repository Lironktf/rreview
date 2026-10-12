import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_scope.dart';
import '../services/import_service.dart';
import '../theme/tokens.dart';

/// Paste a link or PGN, or pick a .pgn file. Returns the created/duplicate
/// review id, or null.
Future<String?> showImportSheet(BuildContext context, {String? initialText}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImportSheet(initialText: initialText),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({this.initialText});
  final String? initialText;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText ?? '');
  final _username = TextEditingController();
  bool _busy = false;
  ImportOutcome? _outcome;

  @override
  void dispose() {
    _text.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ImportOutcome> Function() action) async {
    setState(() {
      _busy = true;
      _outcome = null;
    });
    final out = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = out;
    });
    if (out.ok && out.review != null) {
      Navigator.of(context).pop(out.review!.id);
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final s = AppScope.of(context);
    await _run(() => s.importer.importFile(File(path)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) setState(() => _text.text = data!.text!);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final out = _outcome;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Import a game', style: t.titleLarge),
            const SizedBox(height: Space.xs),
            Text('A Chess.com or Lichess game link, or PGN text. Links need internet; PGN is analysed offline.',
                style: t.bodySmall),
            const SizedBox(height: Space.l),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              autofocus: widget.initialText == null,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'https://www.chess.com/game/live/…  or  1. e4 e5 2. Nf3 …',
                suffixIcon: IconButton(tooltip: 'Paste', onPressed: _paste, icon: const Icon(Icons.content_paste_rounded)),
              ),
            ),
            const SizedBox(height: Space.m),
            if (out != null && !out.ok) ...[
              Container(
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(Radii.medium)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(out.message ?? 'Import failed', style: t.bodyMedium),
                    if (out.kind == ImportKind.needsUsername) ...[
                      const SizedBox(height: Space.s),
                      TextField(
                        controller: _username,
                        decoration: const InputDecoration(hintText: 'Your Chess.com username'),
                        autocorrect: false,
                        onSubmitted: (_) => _addUsernameAndRetry(s),
                      ),
                      const SizedBox(height: Space.s),
                      FilledButton(onPressed: _busy ? null : () => _addUsernameAndRetry(s), child: const Text('Save and retry')),
                    ],
                    if (out.kind == ImportKind.notFound || out.kind == ImportKind.network) ...[
                      const SizedBox(height: Space.xs),
                      Text('You can also paste the PGN from the game page, or share it as a .pgn file.', style: t.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Space.m),
            ],
            FilledButton(
              onPressed: _busy ? null : () => _run(() => s.importer.importText(_text.text)),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Import'),
            ),
            const SizedBox(height: Space.s),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.folder_open_rounded, size: 20),
              label: const Text('Choose a .pgn file'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addUsernameAndRetry(AppServices s) async {
    final u = _username.text.trim();
    if (u.isEmpty) return;
    await s.settings.update((st) {
      if (!st.chesscomUsernames.map((e) => e.toLowerCase()).contains(u.toLowerCase())) st.chesscomUsernames = [...st.chesscomUsernames, u];
    });
    await _run(() => s.importer.importText(_text.text));
  }
}
