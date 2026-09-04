import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../auth/auth_error.dart';
import '../auth/data/not_authenticated_exception.dart';
import 'data/moderation_models.dart';
import 'moderation_provider.dart';

/// Read-only view of moderation_audit_log (docs/GAPS.md's 🟡 audit-log
/// gap, also an IT Rules 2021 requirement) — who acted on what, when, why.
/// Moderator-gated the same way the queue itself is
/// (api/internal/server/moderation.go's requireModerator on
/// GET /v1/moderation/audit-log).
class ModerationAuditLogScreen extends ConsumerStatefulWidget {
  const ModerationAuditLogScreen({super.key});

  @override
  ConsumerState<ModerationAuditLogScreen> createState() => _ModerationAuditLogScreenState();
}

class _ModerationAuditLogScreenState extends ConsumerState<ModerationAuditLogScreen> {
  List<AuditLogEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final entries = await ref.read(moderationApiClientProvider).listAuditLog();
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      if (e is NotAuthenticatedException) showAuthAwareSnackBar(context, e, '');
      setState(() {
        _error = describeAuthAwareError(e, "Couldn't load the audit log. Try again.");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final entries = _entries;
    if (entries == null && _error == null) {
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
    if (entries!.isEmpty) {
      return const Center(
        child: Text(
          'No moderator actions yet.',
          style: TextStyle(color: AnhadColors.duskTextSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _actionLabel(entry.action),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'reel ${entry.reelId.substring(0, 8)} · '
                'moderator ${entry.moderatorId.substring(0, 8)} · '
                '${entry.createdAt.toLocal()}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
              if (entry.reason != null && entry.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('"${entry.reason}"'),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _actionLabel(String action) {
  switch (action) {
    case 'reel_removed':
      return 'Removed reel';
    case 'report_dismissed':
      return 'Dismissed report';
    default:
      return action;
  }
}
