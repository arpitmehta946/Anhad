import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/colors.dart';
import '../data/reel.dart';
import '../data/reel_category.dart';
import '../upload/upload_reel_provider.dart';

enum _Stage { initializing, blocked, ready, recording, reviewing, uploading }

/// Jugalbandi (remix/duet, docs/PRD.md §7.2): record a new performance
/// side by side with [sourceReel]'s own playback — an instrumentalist
/// accompanying a vocal track, or call-and-response chanting — camera on
/// one side, the original on the other, both starting together so the
/// result is genuinely synced, not two independently-timed clips.
///
/// The recorded file is uploaded exactly like any other reel (this screen
/// reuses uploadReelProviderClient's own upload-target flow) — only the
/// finalize call differs, going to POST /v1/reels/{sourceReel.id}/jugalbandi
/// instead of POST /v1/reels, which is what attributes both creators and
/// bumps the source's jugalbandi_reuse_count server-side
/// (api/internal/reels.Service.CreateJugalbandi).
///
/// There's no server-side video compositing in this codebase (no muxing
/// pipeline exists — internal/moderation's own ffmpeg use is audio-only
/// extraction) — the uploaded reel is just the performer's own camera
/// recording, and the side-by-side duet view is rendered client-side at
/// playback time by loading both this reel's video and its
/// jugalbandi_source_video_url together (feed_screen.dart's _ReelPage).
class JugalbandiRecordScreen extends ConsumerStatefulWidget {
  const JugalbandiRecordScreen({super.key, required this.sourceReel});

  final Reel sourceReel;

  @override
  ConsumerState<JugalbandiRecordScreen> createState() =>
      _JugalbandiRecordScreenState();
}

class _JugalbandiRecordScreenState
    extends ConsumerState<JugalbandiRecordScreen> {
  CameraController? _cameraController;
  VideoPlayerController? _originalController;
  final _captionController = TextEditingController();
  _Stage _stage = _Stage.initializing;
  String? _error;
  File? _recordedVideo;
  String? _category;

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  @override
  void dispose() {
    _originalController?.removeListener(_onOriginalTick);
    _originalController?.dispose();
    _cameraController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!camStatus.isGranted || !micStatus.isGranted) {
      if (!mounted) return;
      setState(() => _stage = _Stage.blocked);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('no camera available on this device');
      }
      // Front camera by default — seeing yourself while singing/playing
      // alongside the original is the whole point, the same reason
      // Instagram's own duet defaults to the selfie camera.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await cameraController.initialize();

      final originalController = VideoPlayerController.networkUrl(
          Uri.parse(widget.sourceReel.videoUrl));
      await originalController.initialize();
      originalController.addListener(_onOriginalTick);

      if (!mounted) {
        await cameraController.dispose();
        await originalController.dispose();
        return;
      }
      setState(() {
        _cameraController = cameraController;
        _originalController = originalController;
        _stage = _Stage.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.blocked;
        _error = "Couldn't start the camera. Try again.";
      });
    }
  }

  // Stops recording on its own once the original finishes — a Jugalbandi
  // is exactly as long as the thing it's accompanying, not an arbitrary
  // duration the performer has to watch and time themselves.
  void _onOriginalTick() {
    if (_stage != _Stage.recording) return;
    final value = _originalController?.value;
    if (value == null) return;
    if (value.duration > Duration.zero && value.position >= value.duration) {
      unawaited(_stopRecording());
    }
  }

  Future<void> _startRecording() async {
    final camera = _cameraController;
    final original = _originalController;
    if (camera == null || original == null || _stage != _Stage.ready) return;
    try {
      await camera.startVideoRecording();
      await original.seekTo(Duration.zero);
      await original.play();
      if (!mounted) return;
      setState(() => _stage = _Stage.recording);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't start recording. Try again.");
    }
  }

  Future<void> _stopRecording() async {
    final camera = _cameraController;
    if (camera == null || _stage != _Stage.recording) return;
    try {
      final file = await camera.stopVideoRecording();
      await _originalController?.pause();
      if (!mounted) return;
      setState(() {
        _recordedVideo = File(file.path);
        _stage = _Stage.reviewing;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.ready;
        _error = "Couldn't finish recording. Try again.";
      });
    }
  }

  Future<void> _post() async {
    final video = _recordedVideo;
    final category = _category;
    if (video == null || category == null || _stage != _Stage.reviewing) return;

    setState(() {
      _stage = _Stage.uploading;
      _error = null;
    });
    try {
      final client = ref.read(reelApiClientProvider);
      final target = await client.createUploadTarget();
      await client.uploadVideoFile(target, video);

      final caption = _captionController.text.trim();
      await client.createJugalbandi(
        sourceReelId: widget.sourceReel.id,
        videoId: target.videoId,
        category: category,
        caption: caption.isEmpty ? null : caption,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.reviewing;
        _error = e is HttpException ? e.message : "Couldn't post. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Jugalbandi'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.initializing:
        return const Center(
          child: CircularProgressIndicator(color: AnhadColors.accentDiya),
        );
      case _Stage.blocked:
        return _BlockedMessage(
            error: _error,
            onRetry: () {
              setState(() => _stage = _Stage.initializing);
              unawaited(_setup());
            });
      case _Stage.ready:
      case _Stage.recording:
        return _RecordingView(
          sourceReel: widget.sourceReel,
          originalController: _originalController!,
          cameraController: _cameraController!,
          recording: _stage == _Stage.recording,
          onStart: _startRecording,
          onStop: _stopRecording,
          error: _error,
        );
      case _Stage.reviewing:
        return _ReviewForm(
          video: _recordedVideo!,
          category: _category,
          onCategorySelected: (c) => setState(() => _category = c),
          captionController: _captionController,
          error: _error,
          onPost: _post,
        );
      case _Stage.uploading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AnhadColors.accentDiya),
              SizedBox(height: 16),
              Text('Posting your Jugalbandi…',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        );
    }
  }
}

class _BlockedMessage extends StatelessWidget {
  const _BlockedMessage({required this.error, required this.onRetry});

  final String? error;
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
              error ??
                  'Jugalbandi needs camera and microphone access to record alongside this reel.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            const TextButton(
              onPressed: openAppSettings,
              child: Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.sourceReel,
    required this.originalController,
    required this.cameraController,
    required this.recording,
    required this.onStart,
    required this.onStop,
    required this.error,
  });

  final Reel sourceReel;
  final VideoPlayerController originalController;
  final CameraController cameraController;
  final bool recording;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            sourceReel.creatorDisplayName != null
                ? 'Duetting with ${sourceReel.creatorDisplayName}'
                : 'Duetting with a fellow devotee',
            style: const TextStyle(
                color: AnhadColors.accentDiya, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          // Side by side, left/right — the layout docs/PRD.md §7.2 and the
          // user's own instruction both call "Instagram's duet."
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: originalController.value.aspectRatio,
                    child: VideoPlayer(originalController),
                  ),
                ),
              ),
              Container(width: 1, color: Colors.white24),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: cameraController.value.aspectRatio,
                    child: CameraPreview(cameraController),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(error!,
                style: const TextStyle(color: AnhadColors.accentSindoor)),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: GestureDetector(
            onTap: recording ? onStop : onStart,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              padding: const EdgeInsets.all(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: AnhadColors.accentSindoor,
                  borderRadius: BorderRadius.circular(recording ? 6 : 32),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewForm extends StatelessWidget {
  const _ReviewForm({
    required this.video,
    required this.category,
    required this.onCategorySelected,
    required this.captionController,
    required this.error,
    required this.onPost,
  });

  final File video;
  final String? category;
  final ValueChanged<String> onCategorySelected;
  final TextEditingController captionController;
  final String? error;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AnhadColors.duskBgSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AnhadColors.accentTulsi),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recording saved: ${video.path.split(Platform.pathSeparator).last}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Category', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final cat in reelCategories)
                category == cat.slug
                    ? FilledButton(
                        onPressed: () => onCategorySelected(cat.slug),
                        child: Text(cat.label),
                      )
                    : OutlinedButton(
                        onPressed: () => onCategorySelected(cat.slug),
                        child: Text(cat.label),
                      ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: captionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Caption',
              hintText: 'Optional',
            ),
          ),
          const SizedBox(height: 24),
          if (error != null) ...[
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AnhadColors.accentSindoor),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: category == null ? null : onPost,
            child: const Text('Post Jugalbandi'),
          ),
        ],
      ),
    );
  }
}
