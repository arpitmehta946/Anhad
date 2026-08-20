/// One category a reel can be tagged with — the mandatory, fixed list from
/// docs/PRD.md §4.1 (resolved August 18 2026). Not user-extensible: the
/// server enforces this exact set too (api/internal/reels/service.go's
/// Categories, backed by the reels_category_check constraint), so a slug
/// added only here would just fail server-side.
class ReelCategory {
  const ReelCategory(this.slug, this.label);

  /// What's sent to/received from the API.
  final String slug;

  /// What's shown in the picker and the feed filter row.
  final String label;
}

const reelCategories = <ReelCategory>[
  ReelCategory('bhajan', 'Bhajan'),
  ReelCategory('mantra', 'Mantra'),
  ReelCategory('stuti', 'Stuti'),
  ReelCategory('chalisa', 'Chalisa'),
  ReelCategory('aarti', 'Aarti'),
  ReelCategory('kirtan', 'Kirtan'),
  ReelCategory('sant_vani', 'Sant Vani'),
  ReelCategory('meditation_naad', 'Meditation & Naad'),
];

String reelCategoryLabel(String slug) {
  for (final category in reelCategories) {
    if (category.slug == slug) return category.label;
  }
  return slug;
}
