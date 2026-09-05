import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/colors.dart';
import 'data/creator_profile.dart';
import 'profile_provider.dart';

/// Editing your own profile — display name, bio, and avatar, the three
/// fields docs/PRD.md names as editable. Handle and Verified Artist aren't
/// here: neither has a chooser/grant flow built (see
/// internal/profile.Service.UpdateProfile's own doc).
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
  File? _newAvatar;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

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
