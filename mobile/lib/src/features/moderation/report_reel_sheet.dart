import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../auth/auth_error.dart';
import '../auth/data/not_authenticated_exception.dart';
import 'data/report_reason.dart';
import 'moderation_provider.dart';

/// The report action on a reel (docs/PRD.md §7.8's in-app reporting
/// requirement) — a plain reason picker, not a form, since the whole
/// point of a fixed reason list (docs/PRD.md §8.0.1) is that a report is
/// immediately actionable by a moderator without needing interpretation.
Future<void> showReportReelSheet(BuildContext context, WidgetRef ref, String reelId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AnhadColors.duskBgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _ReportReelSheet(reelId: reelId),
  );
}

class _ReportReelSheet extends ConsumerStatefulWidget {
  const _ReportReelSheet({required this.reelId});

  final String reelId;

  @override
  ConsumerState<_ReportReelSheet> createState() => _ReportReelSheetState();
}

class _ReportReelSheetState extends ConsumerState<_ReportReelSheet> {
  ReportReason? _selected;
  bool _submitting = false;
  String? _error;
  bool _submitted = false;

  Future<void> _submit() async {
    final reason = _selected;
    if (reason == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(moderationApiClientProvider)
          .reportReel(widget.reelId, reason: reason.slug);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
      unawaited(Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      }));
    } catch (e) {
      if (!mounted) return;
      if (e is NotAuthenticatedException) showAuthAwareSnackBar(context, e, '');
      setState(() {
        _submitting = false;
        // Plain, person-facing copy (docs/FRONTEND_GUIDELINES.md §9) — the
        // two cases worth calling out specifically rather than a generic
        // failure message: already reported, and reporting too fast.
        _error = describeAuthAwareError(e, "Couldn't submit the report. Try again.");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_submitted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: AnhadColors.accentTulsi, size: 32),
            const SizedBox(height: 12),
            Text(
              "Thanks — we'll take a look.",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        // viewInsets.bottom covers the keyboard; viewPadding.bottom covers
        // the system nav bar itself (gesture pill or 3-button bar) — a
        // sheet that only accounts for the former has its bottom button
        // rendered half-covered by the nav bar on any device using
        // 3-button navigation.
        bottom: 24 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report this reel', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'What made you report it?',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AnhadColors.duskTextSecondary),
          ),
          const SizedBox(height: 16),
          for (final reason in ReportReason.all)
            RadioListTile<ReportReason>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(reason.label),
              value: reason,
              groupValue: _selected,
              onChanged: _submitting ? null : (v) => setState(() => _selected = v),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AnhadColors.accentSindoor),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_selected == null || _submitting) ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit report'),
          ),
        ],
      ),
    );
  }
}
