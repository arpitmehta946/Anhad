import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/anhad_icons.dart';
import '../../theme/colors.dart';
import 'data/reel.dart';
import 'data/social_api_client.dart';
import 'social_provider.dart';

/// The Satsang sheet (docs/PRD.md §6/§7.2): a flat, oldest-first stream of
/// reflections, not a most-recent debate thread (internal/social.Service.
/// ListSatsang's own doc explains why the ordering is deliberate). Returns
/// the reel's fresh comment count so the caller can update its own Reel
/// copy without a second feed fetch.
Future<int?> showSatsangSheet(BuildContext context, WidgetRef ref, Reel reel) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AnhadColors.duskBgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _SatsangSheet(reel: reel),
  );
}

class _SatsangSheet extends ConsumerStatefulWidget {
  const _SatsangSheet({required this.reel});

  final Reel reel;

  @override
  ConsumerState<_SatsangSheet> createState() => _SatsangSheetState();
}

class _SatsangSheetState extends ConsumerState<_SatsangSheet> {
  final _controller = TextEditingController();
  List<SatsangComment>? _comments;
  String? _loadError;
  bool _posting = false;
  String? _postError;
  int _count = 0;

  int get _maxLength => widget.reel.reflectionOnly ? 280 : 500;

  @override
  void initState() {
    super.initState();
    _count = widget.reel.satsangCount;
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments =
          await ref.read(socialApiClientProvider).listSatsang(widget.reel.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError =
          "Couldn't load reflections. Check your connection and try again.");
    }
  }

  Future<void> _submit() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() {
      _posting = true;
      _postError = null;
    });
    try {
      final comment = await ref
          .read(socialApiClientProvider)
          .postSatsang(widget.reel.id, body);
      if (!mounted) return;
      setState(() {
        _comments = [...?_comments, comment];
        _count += 1;
        _controller.clear();
        _posting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _postError =
            e is HttpException ? e.message : "Couldn't post. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comments = _comments;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) Navigator.of(context).pop(_count);
      },
      child: Padding(
        padding: EdgeInsets.only(
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const SatsangIcon(
                      filled: true, color: AnhadColors.accentDiya, size: 20),
                  const SizedBox(width: 8),
                  Text('Satsang', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    widget.reel.reflectionOnly
                        ? 'Reflections only'
                        : 'Open discussion',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AnhadColors.duskTextSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: comments == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: _loadError != null
                          ? Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: AnhadColors.duskTextSecondary),
                            )
                          : const CircularProgressIndicator(),
                    )
                  : comments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 32, horizontal: 24),
                          child: Text(
                            'No reflections yet — be the first to share one.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AnhadColors.duskTextSecondary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: comments.length,
                          itemBuilder: (context, index) {
                            final c = comments[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.userDisplayName ?? 'A fellow devotee',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color: AnhadColors.accentDiya),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(c.body,
                                      style: theme.textTheme.bodyMedium),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_postError != null) ...[
                    Text(
                      _postError!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AnhadColors.accentSindoor),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLength: _maxLength,
                          maxLines: 4,
                          minLines: 1,
                          enabled: !_posting,
                          decoration: InputDecoration(
                            hintText: widget.reel.reflectionOnly
                                ? 'Share a reflection…'
                                : 'Add to the discussion…',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _controller.text.trim().isEmpty || _posting
                            ? null
                            : _submit,
                        icon: _posting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send,
                                color: AnhadColors.accentDiya),
                        tooltip: 'Post reflection',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
