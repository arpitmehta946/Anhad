import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/colors.dart';
import '../../auth/auth_error.dart';
import '../../auth/data/not_authenticated_exception.dart';
import '../data/reel_category.dart';
import 'upload_reel_provider.dart';

enum _UploadStage { idle, uploading, finalizing }

/// Upload screen for the first feed slice (docs/PRD.md §4.1, §7.1): pick or
/// record a video, choose a mandatory category, upload. Only ever reachable
/// from a creator-only entry point (feed_screen.dart) — the *real*
/// enforcement is server-side (api/internal/server/reels.go's
/// requireRole), this screen existing at all isn't what makes upload
/// creator-only.
///
/// [presetAudioTrackId] is set when this screen was reached via "use this
/// sound" (docs/PRD.md §7.3, audio_library_screen.dart/interaction_rail.dart)
/// — the new reel is then finalized through
/// ReelApiClient.createReelFromAudioTrack instead of createReel, and the
/// Jugalbandi/library-opt-out switches don't apply to it (a reel already
/// built from someone else's track isn't itself offering its video up for
/// either kind of reuse in this first slice). [presetCategory] just saves
/// a tap by pre-selecting the source track's own category; still changeable.
class UploadReelScreen extends ConsumerStatefulWidget {
  const UploadReelScreen({
    super.key,
    this.presetAudioTrackId,
    this.presetCategory,
  });

  final String? presetAudioTrackId;
  final String? presetCategory;

  @override
  ConsumerState<UploadReelScreen> createState() => _UploadReelScreenState();
}

class _UploadReelScreenState extends ConsumerState<UploadReelScreen> {
  final _captionController = TextEditingController();
  File? _video;
  String? _category;
  // Jugalbandi (remix/duet, docs/PRD.md §4.5/§7.2) — an ordinary adult
  // creator defaults to allowed, matching the server's own default
  // (api/internal/reels.Service.CreateReel); this switch is how they turn
  // it off for a given reel, not how a Family Account's parent would (that
  // account's own default is already off server-side, before this screen
  // ever renders — see migration 000011's own doc).
  bool _jugalbandiEnabled = true;
  // Sound library inclusion (docs/PRD.md §4.5/§7.3) — same shape and same
  // server-side default resolution as _jugalbandiEnabled above.
  bool _audioLibraryEnabled = true;
  _UploadStage _stage = _UploadStage.idle;
  String? _error;

  bool get _isUseThisSound => widget.presetAudioTrackId != null;

  @override
  void initState() {
    super.initState();
    _category = widget.presetCategory;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(source: source);
    if (picked == null) return;
    setState(() {
      _video = File(picked.path);
      _error = null;
    });
  }

  Future<void> _upload() async {
    final video = _video;
    final category = _category;
    if (video == null || category == null || _stage != _UploadStage.idle) {
      return;
    }

    setState(() {
      _stage = _UploadStage.uploading;
      _error = null;
    });

    try {
      final client = ref.read(reelApiClientProvider);
      final target = await client.createUploadTarget();
      await client.uploadVideoFile(target, video);

      if (!mounted) return;
      setState(() => _stage = _UploadStage.finalizing);

      final caption = _captionController.text.trim();
      final trackId = widget.presetAudioTrackId;
      if (trackId != null) {
        await client.createReelFromAudioTrack(
          trackId: trackId,
          videoId: target.videoId,
          category: category,
          caption: caption.isEmpty ? null : caption,
        );
      } else {
        await client.createReel(
          videoId: target.videoId,
          category: category,
          caption: caption.isEmpty ? null : caption,
          jugalbandiEnabled: _jugalbandiEnabled,
          audioLibraryEnabled: _audioLibraryEnabled,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      if (e is NotAuthenticatedException) showAuthAwareSnackBar(context, e, '');
      setState(() {
        _stage = _UploadStage.idle;
        // Plain, person-facing copy (docs/FRONTEND_GUIDELINES.md §9) — the
        // technical detail (a dropped connection, a malformed response)
        // has nothing a person watching an upload bar can act on, unlike
        // being signed out, which describeAuthAwareError calls out
        // specifically instead of folding it into this same fallback.
        _error = describeAuthAwareError(
            e, "Couldn't upload — check your connection and try again.");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _stage != _UploadStage.idle;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isUseThisSound ? 'Use this sound' : 'Upload'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VideoPicker(
                video: _video,
                busy: busy,
                onRecord: () => _pickVideo(ImageSource.camera),
                onChoose: () => _pickVideo(ImageSource.gallery),
              ),
              const SizedBox(height: 24),
              Text('Category', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Required — pick the one that fits best.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final cat in reelCategories)
                    _CategoryChip(
                      label: cat.label,
                      selected: _category == cat.slug,
                      onSelected: busy
                          ? null
                          : () => setState(() => _category = cat.slug),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _captionController,
                enabled: !busy,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Caption',
                  hintText: 'Optional',
                ),
              ),
              // A reel built via "use this sound" isn't itself offering its
              // own video up for either kind of reuse in this first slice —
              // see this widget's own doc for why these two don't apply.
              if (!_isUseThisSound) ...[
                const SizedBox(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _jugalbandiEnabled,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _jugalbandiEnabled = v),
                  title: const Text('Allow Jugalbandi'),
                  subtitle: const Text(
                    'Let other people record a duet alongside this reel.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _audioLibraryEnabled,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _audioLibraryEnabled = v),
                  title: const Text('Add to sound library'),
                  subtitle: const Text(
                    'Let other people start a new reel with this audio.',
                  ),
                ),
              ],
              const SizedBox(height: 4),
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AnhadColors.accentSindoor),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: (_video != null && _category != null && !busy)
                    ? _upload
                    : null,
                child: busy
                    ? Text(_stage == _UploadStage.uploading
                        ? 'Uploading…'
                        : 'Almost done…')
                    : const Text('Upload'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPicker extends StatelessWidget {
  const _VideoPicker({
    required this.video,
    required this.busy,
    required this.onRecord,
    required this.onChoose,
  });

  final File? video;
  final bool busy;
  final VoidCallback onRecord;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AnhadColors.duskBgSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            video == null ? Icons.videocam_outlined : Icons.check_circle,
            size: 40,
            color: video == null
                ? AnhadColors.duskTextSecondary
                : AnhadColors.accentTulsi,
          ),
          const SizedBox(height: 8),
          Text(
            video == null
                ? 'No video selected yet'
                : video!.path.split(Platform.pathSeparator).last,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onRecord,
                  child: const Text('Record'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onChoose,
                  child: const Text('Choose from gallery'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);
    return selected
        ? FilledButton(onPressed: onSelected, child: text)
        : OutlinedButton(onPressed: onSelected, child: text);
  }
}
