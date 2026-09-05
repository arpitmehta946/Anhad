import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/colors.dart';
import 'data/creator_profile.dart';
import 'profile_provider.dart';

/// Editing your own profile — display name, bio, and avatar (docs/PRD.md's
/// own instruction on what's editable), plus the optional identity fields
/// (tradition/sampradaya, lineage, languages, instruments) that
/// distinguish this profile from a generic social one. Handle and
/// Verified Artist aren't here: neither has a chooser/grant flow built
/// (see internal/profile.ProfileEdits's own doc).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final CreatorProfile profile;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _displayNameController =
      TextEditingController(text: widget.profile.displayName ?? '');
  late final _bioController = TextEditingController(text: widget.profile.bio ?? '');
  late final _traditionController =
      TextEditingController(text: widget.profile.tradition ?? '');
  late final _lineageController =
      TextEditingController(text: widget.profile.lineage ?? '');
  late final _languagesController =
      TextEditingController(text: widget.profile.languages.join(', '));
  late final _instrumentsController =
      TextEditingController(text: widget.profile.instruments.join(', '));
  File? _newAvatar;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _traditionController.dispose();
    _lineageController.dispose();
    _languagesController.dispose();
    _instrumentsController.dispose();
    super.dispose();
  }

  /// Splits a comma-separated field into a trimmed, non-empty list — the
  /// simplest input this screen can offer for a repeatable field without
  /// building chip-entry UI for what's still an optional, low-traffic set
  /// of values.
  List<String> _splitList(String text) => text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _pickAvatar() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _newAvatar = File(picked.path));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = ref.read(profileApiClientProvider);
      var profile = await client.updateProfile(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        tradition: _traditionController.text.trim(),
        lineage: _lineageController.text.trim(),
        languages: _splitList(_languagesController.text),
        instruments: _splitList(_instrumentsController.text),
      );
      final avatar = _newAvatar;
      if (avatar != null) {
        profile = await client.uploadAvatar(avatar);
      }
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't save your profile. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingAvatarUrl = widget.profile.avatarUrl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _saving ? null : _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AnhadColors.duskBgSurface,
                        backgroundImage: _newAvatar != null
                            ? FileImage(_newAvatar!)
                            : (existingAvatarUrl != null
                                ? NetworkImage(existingAvatarUrl)
                                : null) as ImageProvider?,
                        child: _newAvatar == null && existingAvatarUrl == null
                            ? const Icon(Icons.person, size: 48)
                            : null,
                      ),
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: AnhadColors.accentDiya,
                        child: Icon(Icons.edit, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('Display name', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _displayNameController,
                enabled: !_saving,
                maxLength: 40,
                decoration: const InputDecoration(hintText: 'Your name'),
              ),
              const SizedBox(height: 16),
              Text('Bio', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _bioController,
                enabled: !_saving,
                maxLines: 3,
                maxLength: 160,
                decoration: const InputDecoration(
                  hintText: 'A short line about you',
                ),
              ),
              const SizedBox(height: 16),
              Text('Tradition / sampradaya', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Optional — e.g. Gaudiya Vaishnav, Nirmala, Nath.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _traditionController,
                enabled: !_saving,
                maxLength: 80,
                decoration: const InputDecoration(hintText: 'Optional'),
              ),
              const SizedBox(height: 16),
              Text('Lineage', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Optional — your guru or parampara, if you\'d like to name it.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lineageController,
                enabled: !_saving,
                maxLength: 120,
                decoration: const InputDecoration(hintText: 'Optional'),
              ),
              const SizedBox(height: 16),
              Text('Languages', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Optional — separate with commas.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _languagesController,
                enabled: !_saving,
                decoration: const InputDecoration(hintText: 'Hindi, Braj Bhasha'),
              ),
              const SizedBox(height: 16),
              Text('Instruments', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Optional — separate with commas.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instrumentsController,
                enabled: !_saving,
                decoration:
                    const InputDecoration(hintText: 'Harmonium, Tabla'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AnhadColors.accentSindoor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
