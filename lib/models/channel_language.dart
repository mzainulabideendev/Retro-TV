/// Languages a channel's uploaded cartoons/videos can be watched in.
///
/// The [ChannelLanguage.code] is what gets stored in
/// `channels.language` (see migration 012). Keep this list in sync with the
/// languages offered by the admin Channel editor and the public Channel
/// Guide filter — both read from here so they never drift apart.
class ChannelLanguage {
  final String code;
  final String label;

  const ChannelLanguage(this.code, this.label);
}

const List<ChannelLanguage> channelLanguages = [
  ChannelLanguage('en', 'English'),
  ChannelLanguage('hi', 'Hindi'),
  ChannelLanguage('ur', 'Urdu'),
  ChannelLanguage('ar', 'Arabic'),
  ChannelLanguage('es', 'Spanish'),
  ChannelLanguage('fr', 'French'),
  ChannelLanguage('pt', 'Portuguese'),
  ChannelLanguage('bn', 'Bengali'),
  ChannelLanguage('ta', 'Tamil'),
  ChannelLanguage('te', 'Telugu'),
  ChannelLanguage('id', 'Indonesian'),
  ChannelLanguage('ms', 'Malay'),
  ChannelLanguage('ru', 'Russian'),
  ChannelLanguage('de', 'German'),
  ChannelLanguage('it', 'Italian'),
  ChannelLanguage('tr', 'Turkish'),
  ChannelLanguage('fa', 'Persian'),
  ChannelLanguage('ja', 'Japanese'),
  ChannelLanguage('ko', 'Korean'),
  ChannelLanguage('zh', 'Chinese'),
  ChannelLanguage('th', 'Thai'),
  ChannelLanguage('vi', 'Vietnamese'),
  ChannelLanguage('sw', 'Swahili'),
  ChannelLanguage('other', 'Other'),
];

/// Display label for a stored language code. Unknown/absent codes return
/// "Unspecified" so older channels (created before language support) render
/// sensibly instead of showing a raw two-letter code.
String channelLanguageLabel(String? code) {
  final normalized = code?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return 'Unspecified';
  for (final language in channelLanguages) {
    if (language.code == normalized) return language.label;
  }
  return code!.trim();
}

/// True when [code] is one of the known [channelLanguages] codes.
bool isKnownChannelLanguage(String? code) {
  final normalized = code?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return false;
  return channelLanguages.any((language) => language.code == normalized);
}
