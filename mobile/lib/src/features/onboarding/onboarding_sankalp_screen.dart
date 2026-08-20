import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../japa/background/background_japa_controller.dart';
import '../japa/data/isar_provider.dart';
import '../japa/data/japa_preferences_store.dart';
import '../japa/reminder/sankalp_reminder_provider.dart';
import 'save_practice_screen.dart';

enum _Step { choose, configure }

/// Screen 3 of the first-run flow (docs/ONBOARDING.md §3, §2): the first
/// real choice, offered right after the emotional peak of the first
/// completed mala. "Not now" is a real option, not a dark pattern — either
/// way the user keeps everything they just did and moves on to save it.
///
/// Choosing a length moves to a second step (docs/PRD.md §10.3): the daily
/// target is set here, once, and locked for the vow's duration — and the
/// reminder time, never preset, is asked here too (docs/PRD.md §7.7). Both
/// are still skippable ("Skip reminder"), matching the same non-coercive
/// pattern as "Not now" itself.
class OnboardingSankalpScreen extends ConsumerStatefulWidget {
  const OnboardingSankalpScreen({super.key});

  @override
  ConsumerState<OnboardingSankalpScreen> createState() =>
      _OnboardingSankalpScreenState();
}

class _OnboardingSankalpScreenState
    extends ConsumerState<OnboardingSankalpScreen> {
  final _intentionController = TextEditingController();
  final _malasPerDayController = TextEditingController();
  bool _submitting = false;
  _Step _step = _Step.choose;
  int? _selectedLength;
  String? _targetError;
  TimeOfDay? _reminderTime;

  @override
  void dispose() {
    _intentionController.dispose();
    _malasPerDayController.dispose();
    super.dispose();
  }

  /// The locked daily target in chants, or null if what's typed isn't a
  /// valid positive count of malas yet — a traditional mala is 108
  /// chants regardless of what ring length someone prefers to look at
  /// while tapping (japa_session_controller.dart's malaSize), so this
  /// always multiplies by 108, not the user's own malaLength preference.
  int? get _dailyTarget {
    final malas = int.tryParse(_malasPerDayController.text.trim());
    if (malas == null || malas < 1) return null;
    return malas * 108;
  }

  Future<void> _skip() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await setSankalpChoice(
      ref.read(isarProvider),
      lengthDays: null,
      intention: null,
      dailyTarget: null,
      reminderHour: null,
      reminderMinute: null,
    );
    await ref.read(sankalpReminderSchedulerProvider).cancel();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavePracticeScreen()),
    );
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _reminderTime = picked);
  }

  /// Requests notification permission and, if a reminder time was actually
  /// chosen, the battery-optimization exemption too — the same two checks
  /// and the same explanation-before-asking pattern already used for
  /// screen-off japa (japa_screen.dart's _toggleScreenOffSession), since a
  /// missed reminder from a killed background process is the same failure
  /// mode either way.
  Future<bool> _ensureReminderCanFire() async {
    if (_reminderTime == null) return false;
    final controller = ref.read(backgroundJapaControllerProvider.notifier);
    if (!await controller.hasNotificationPermission()) {
      final granted = await controller.requestNotificationPermission();
      if (!granted) return false;
    }
    if (await controller.needsBatteryExemption()) {
      if (!mounted) return true;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep the reminder reliable'),
          content: const Text(
            'Android may otherwise delay or drop a daily reminder a few '
            'hours after the app was last open. The next screen lets you '
            'exempt Anhad from battery optimization so it arrives on time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed ?? false) {
        await controller.requestBatteryExemption();
      }
    }
    return true;
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    final dailyTarget = _dailyTarget;
    if (dailyTarget == null) {
      setState(() => _targetError = 'How many malas a day? (e.g. 2)');
      return;
    }
    setState(() {
      _targetError = null;
      _submitting = true;
    });

    final canRemind = await _ensureReminderCanFire();
    final reminderTime = canRemind ? _reminderTime : null;

    final intention = _intentionController.text.trim();
    await setSankalpChoice(
      ref.read(isarProvider),
      lengthDays: _selectedLength,
      intention: intention.isEmpty ? null : intention,
      dailyTarget: dailyTarget,
      reminderHour: reminderTime?.hour,
      reminderMinute: reminderTime?.minute,
    );

    if (reminderTime != null) {
      await ref
          .read(sankalpReminderSchedulerProvider)
          .scheduleForTime(reminderTime);
    } else {
      await ref.read(sankalpReminderSchedulerProvider).cancel();
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavePracticeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: switch (_step) {
                _Step.choose => _buildChoose(theme),
                _Step.configure => _buildConfigure(theme),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoose(ThemeData theme) {
    return Column(
      key: const ValueKey(_Step.choose),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "You've completed one mala.",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Would you like to take a sankalp?',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: AnhadColors.duskTextSecondary),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _intentionController,
          enabled: !_submitting,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'What is this practice for?',
            hintText: 'Optional — always private, just for you',
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final days in sankalpLengthOptions)
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _selectedLength = days;
                          _step = _Step.configure;
                        }),
                child: Text('$days days'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _submitting ? null : _skip,
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Widget _buildConfigure(ThemeData theme) {
    return Column(
      key: const ValueKey(_Step.configure),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A $_selectedLength-day sankalp',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          "Set a daily target — it's locked for the whole sankalp, so a "
          "day either meets it or it doesn't.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AnhadColors.duskTextSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _malasPerDayController,
          enabled: !_submitting,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _targetError = null),
          decoration: InputDecoration(
            labelText: 'Malas per day',
            hintText: 'e.g. 2  (216 chants)',
            errorText: _targetError,
            suffixText: _dailyTarget == null ? null : '${_dailyTarget!} chants',
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Want a daily reminder?',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Brahma muhurta (roughly 4–6am) is traditionally considered '
          'most auspicious for japa — but any time that actually works '
          'for you is the right one.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AnhadColors.duskTextSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _submitting ? null : _pickReminderTime,
          child: Text(
            _reminderTime == null
                ? 'Choose a time'
                : _reminderTime!.format(context),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _confirm,
          child: const Text('Start sankalp'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _submitting
              ? null
              : () {
                  setState(() => _reminderTime = null);
                  _confirm();
                },
          child: const Text('Skip reminder'),
        ),
      ],
    );
  }
}
