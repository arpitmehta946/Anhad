import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../theme/colors.dart';
import '../feed/data/reel_category.dart';
import '../feed/upload/upload_reel_screen.dart';
import 'audio_library_provider.dart';
import 'data/audio_track.dart';

/// The browsable sound library (docs/PRD.md §7.3): every reel's audio that
/// hasn't been excluded (docs/PRD.md §4.5's minor-performer default),
/// filterable by category, showing the original creator and reuse count.
/// Tapping a track previews it in place; "Use this sound" hands off to the
/// same upload flow a fresh reel goes through, just pre-attached to this
/// track (see UploadReelScreen's own doc on presetAudioTrackId).
class AudioLibraryScreen extends ConsumerStatefulWidget {
  const AudioLibraryScreen({super.key});

  @override
  ConsumerState<AudioLibraryScreen> createState() =>
      _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends ConsumerState<AudioLibraryScreen> {
  final List<AudioTrack> _tracks = [];
  String? _category;
  String? _nextCursor;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;

  final _player = AudioPlayer();
  String? _playingTrackId;

  @override
  void initState() {
    super.initState();
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(audioLibraryApiClientProvider);
      final page = await client.listLibrary(
        category: _category,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _tracks.clear();
        _tracks.addAll(page.tracks);
        _nextCursor = page.nextCursor;
        _loading = false;
        _initialLoadDone = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _error = "Couldn't load the sound library. Check your connection and try again.";
      });
    }
  }

  void _selectCategory(String? category) {
    if (category == _category) return;
    setState(() => _category = category);
    unawaited(_loadPage(reset: true));
  }

  Future<void> _togglePreview(AudioTrack track) async {
    if (_playingTrackId == track.id) {
      await _player.stop();
      setState(() => _playingTrackId = null);
      return;
    }
    try {
      await _player.setUrl(track.audioUrl);
      unawaited(_player.play());
      setState(() => _playingTrackId = track.id);
      // Fire-and-forget, same as the client's own doc on recordPlay —
      // counted the moment playback starts, not after some listen-through
      // threshold, matching how simply the reel feed itself counts a view.
      unawaited(
          ref.read(audioLibraryApiClientProvider).recordPlay(track.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't play this track.")),
      );
    }
  }

  void _useSound(AudioTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadReelScreen(
          presetAudioTrackId: track.id,
          presetCategory: track.category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound Library'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _CategoryRow(
            selected: _category,
            onSelected: _selectCategory,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_initialLoadDone) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tracks.isEmpty) {
      return _MessageState(
          message: _error!, onRetry: () => _loadPage(reset: true));
    }
    if (_tracks.isEmpty) {
      return _MessageState(
        message: _category == null
            ? 'No tracks in the library yet.'
            : 'Nothing in ${reelCategoryLabel(_category!)} yet.',
        onRetry: () => _loadPage(reset: true),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300 && _nextCursor != null) {
          unawaited(_loadPage(reset: false));
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _tracks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _TrackTile(
          track: _tracks[index],
          playing: _playingTrackId == _tracks[index].id,
          onTogglePreview: () => _togglePreview(_tracks[index]),
          onUseSound: () => _useSound(_tracks[index]),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in reelCategories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.label),
                selected: selected == category.slug,
                onSelected: (_) => onSelected(category.slug),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.playing,
    required this.onTogglePreview,
    required this.onUseSound,
  });

  final AudioTrack track;
  final bool playing;
  final VoidCallback onTogglePreview;
  final VoidCallback onUseSound;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconButton(
        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
        color: AnhadColors.accentDiya,
        iconSize: 36,
        onPressed: onTogglePreview,
      ),
      title: Text(track.title ?? reelCategoryLabel(track.category)),
      subtitle: Text(
        '${track.creatorDisplayName ?? 'A fellow devotee'} · '
        'used in ${track.reuseCount} reel${track.reuseCount == 1 ? '' : 's'}',
      ),
      trailing: TextButton(
        onPressed: onUseSound,
        child: const Text('Use this sound'),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AnhadColors.duskTextSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
