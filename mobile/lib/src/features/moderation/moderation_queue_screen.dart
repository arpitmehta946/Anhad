import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../auth/auth_error.dart';
import '../auth/data/not_authenticated_exception.dart';
import 'data/moderation_models.dart';
import 'data/report_reason.dart';
import 'moderation_audit_log_screen.dart';
import 'moderation_provider.dart';

/// The moderator queue (docs/PRD.md §7.8, §8.4) — open reports, oldest
/// first, each actionable right here as either "dismiss" (reviewed, no
/// violation) or "remove reel" (reviewed, taken down). Reachable only from
/// somewhere that already checked AuthState.isModerator — this screen
/// doesn't re-check it client-side, since the real gate is server-side
/// (api/internal/server/moderation.go's requireModerator on every route
/// this screen calls) and a client-side re-check would only ever be
/// cosmetic.
class ModerationQueueScreen extends ConsumerStatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  ConsumerState<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends ConsumerState<ModerationQueueScreen> {
  List<QueueItem>? _items;
  String? _error;
  final _actioning = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await ref.read(moderationApiClientProvider).listQueue();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      if (e is NotAuthenticatedException) showAuthAwareSnackBar(context, e, '');
      setState(() {
        _error = describeAuthAwareError(e, "Couldn't load the queue. Try again.");
      });
    }
  }

  Future<void> _act(QueueItem item, {required bool removeReel}) async {
    final reason = await _promptReason(
      removeReel: removeReel,
      isPipelineFlagged: item.isPipelineFlagged,
    );
    if (reason == null) return; // cancelled

    setState(() => _actioning.add(item.id));
    try {
      final client = ref.read(moderationApiClientProvider);
      if (removeReel) {
        await client.removeReel(item.id, reason: reason.isEmpty ? null : reason);
      } else {
        await client.dismissReport(item.id, reason: reason.isEmpty ? null : reason);
      }
      if (!mounted) return;
      setState(() {
        _items = _items?.where((i) => i.id != item.id).toList();
        _actioning.remove(item.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _actioning.remove(item.id));
      showAuthAwareSnackBar(context, e, 'Action failed. Try again.');
    }
  }

  Future<String?> _promptReason({
    required bool removeReel,
    required bool isPipelineFlagged,
  }) {
    final controller = TextEditingController();
    final title = removeReel
        ? 'Remove this reel?'
        : (isPipelineFlagged ? 'Approve this reel?' : 'Dismiss this report?');
    final confirmLabel = removeReel ? 'Remove' : (isPipelineFlagged ? 'Approve' : 'Dismiss');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Why (optional, kept in the audit log)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation queue'),
        actions: [
          IconButton(
            tooltip: 'Audit log',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ModerationAuditLogScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final items = _items;
    if (items == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (items!.isEmpty) {
      return const Center(
        child: Text(
          'Nothing waiting for review.',
          style: TextStyle(color: AnhadColors.duskTextSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _QueueItemCard(
          item: items[index],
          busy: _actioning.contains(items[index].id),
          onDismiss: () => _act(items[index], removeReel: false),
          onRemove: () => _act(items[index], removeReel: true),
        ),
      ),
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({
    required this.item,
    required this.busy,
    required this.onDismiss,
    required this.onRemove,
  });

  final QueueItem item;
  final bool busy;
  final VoidCallback onDismiss;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnhadColors.duskBgSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.isPipelineFlagged ? Icons.smart_toy_outlined : Icons.flag_outlined,
                size: 16,
                color: AnhadColors.accentSindoor,
              ),
              const SizedBox(width: 6),
              Text(
                ReportReason.labelFor(item.reason),
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: AnhadColors.accentSindoor),
              ),
              const Spacer(),
              Text(
                item.reelCategory,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
            ],
          ),
          if (item.reelCaption != null) ...[
            const SizedBox(height: 8),
            Text(item.reelCaption!, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 4),
          Text(
            'reel ${item.reelId.substring(0, 8)} · '
            '${item.isPipelineFlagged ? "flagged" : "reported"} ${_relativeTime(item.createdAt)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AnhadColors.duskTextSecondary),
          ),
          // Pipeline-flagged items carry the classifier's own working —
          // a human report has none of this (docs/PRD.md §8.1's pipeline
          // detail only exists on reels the pipeline itself processed).
          if (item.isPipelineFlagged) ...[
            const SizedBox(height: 8),
            if (item.reelModerationLabel != null)
              Text(
                'classifier: ${item.reelModerationLabel}'
                '${item.reelModerationReason != null ? " — ${item.reelModerationReason}" : ""}',
                style: theme.textTheme.bodySmall,
              ),
            if (item.reelModerationFingerprint != null)
              Text(
                'fingerprint match: ${item.reelModerationFingerprint}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.accentSindoor),
              ),
            if (item.reelModerationTranscript != null &&
                item.reelModerationTranscript!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '"${item.reelModerationTranscript}"',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AnhadColors.duskTextSecondary, fontStyle: FontStyle.italic),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDismiss,
                  // Dismissing a pipeline hold is what actually publishes
                  // it (internal/moderation.Service.actOnReport) — "Approve"
                  // says what it does; "Dismiss" only makes sense for an
                  // already-published reel a human reported.
                  child: Text(item.isPipelineFlagged ? 'Approve' : 'Dismiss'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AnhadColors.accentSindoor),
                  onPressed: busy ? null : onRemove,
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Remove reel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().toUtc().difference(time.toUtc());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
