/// The fixed report-reason list (api/internal/moderation.Reasons,
/// docs/PRD.md §8.0.1) — a person reporting a reel picks one of these
/// rather than writing free text, so every report is immediately
/// actionable by a moderator instead of needing interpretation first.
class ReportReason {
  const ReportReason(this.slug, this.label);

  final String slug;
  final String label;

  static const notDevotional = ReportReason('not_devotional', 'Not devotional content');
  static const filmiCommercial = ReportReason('filmi_commercial', 'Filmi or commercial track');
  static const financialSolicitation =
      ReportReason('financial_solicitation', 'Financial solicitation (donations, UPI, links)');
  static const medicalMiracleClaim =
      ReportReason('medical_miracle_claim', 'Medical or miracle claim');
  static const hateSpeech = ReportReason('hate_speech', 'Hate speech');
  static const other = ReportReason('other', 'Other');

  static const all = [
    notDevotional,
    filmiCommercial,
    financialSolicitation,
    medicalMiracleClaim,
    hateSpeech,
    other,
  ];

  static String labelFor(String slug) {
    for (final reason in all) {
      if (reason.slug == slug) return reason.label;
    }
    return slug;
  }
}
