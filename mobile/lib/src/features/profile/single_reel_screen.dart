import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feed/data/reel.dart';
import '../feed/reel_page.dart';
import '../moderation/report_reel_sheet.dart';

/// One reel, opened on its own — reached by tapping a tile in a creator
/// profile's reel grid (docs/PRD.md's Sevak destination), where there's no
/// vertical-swipe feed to embed it in. Wraps the exact same ReelPage the
/// main feed uses so playback and every interaction behave identically;
/// this screen only supplies the single-reel "there's no next page" frame
/// around it.
class SingleReelScreen extends ConsumerStatefulWidget {
  const SingleReelScreen({super.key, required this.reel});

  final Reel reel;

  @override
  ConsumerState<SingleReelScreen> createState() => _SingleReelScreenState();
}

class _SingleReelScreenState extends ConsumerState<SingleReelScreen> {
  late Reel _reel;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _reel = widget.reel;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ReelPage(
            reel: _reel,
            isActive: true,
            muted: _muted,
            onToggleMute: () => setState(() => _muted = !_muted),
            onReport: () => showReportReelSheet(context, ref, _reel.id),
            onReelChanged: (updated) => setState(() => _reel = updated),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
