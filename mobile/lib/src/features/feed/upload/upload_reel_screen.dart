import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/colors.dart';
import '../data/reel_category.dart';
import 'upload_reel_provider.dart';

enum _UploadStage { idle, uploading, finalizing }

/// Upload screen for the first feed slice (docs/PRD.md §4.1, §7.1): pick or
/// record a video, choose a mandatory category, upload. Only ever reachable
/// from a creator-only entry point (feed_screen.dart) — the *real*
/// enforcement is server-side (api/internal/server/reels.go's
/// requireRole), this screen existing at all isn't what makes upload
/// creator-only.
class UploadReelScreen extends ConsumerStatefulWidget {
  const UploadReelScreen({super.key});

  @override
  ConsumerState<UploadReelScreen> createState() => _UploadReelScreenState();
}

class _UploadReelScreenState extends ConsumerState<UploadReelScreen> {
  final _captionController = TextEditingController();
  File? _video;
  String? _category;
  _UploadStage _stage = _UploadStage.idle;
  String? _error;

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
    if (video == null || category == null || _stage != _UploadStage.idle) return;

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
      await client.createReel(
        videoId: target.videoId,
        category: category,
        caption: caption.isEmpty ? null : caption,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UploadStage.idle;
        // Plain, person-facing copy (docs/FRONTEND_GUIDELINES.md §9) — the
        // technical detail (a dropped connection, a malformed response)
        // has nothing a person watching an upload bar can act on.
        _error = "Couldn't upload — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _stage != _UploadStage.idle;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload')),
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
                      onSelected:
                          busy ? null : () => setState(() => _category = cat.slug),
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
              const SizedBox(height: 28),
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
