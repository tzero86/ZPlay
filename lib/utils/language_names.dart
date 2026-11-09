/// Language code → English display name, shared by every subtitle source.
///
/// ISO 639-1/639-2 codes plus the extras the sources actually emit (`pob`/`pb`
/// for Brazilian Portuguese). Stremio addons report `eng`/`en`, the
/// OpenSubtitles mirrors and Wyzie report either, and CloudStream extensions
/// emit free-form labels. One table keeps the same language on the same label,
/// so the player groups those sources together instead of splitting them into
/// separate language groups.
const Map<String, String> _languageNames = {
  'ara': 'Arabic',
  'ar': 'Arabic',
  'eng': 'English',
  'en': 'English',
  'spa': 'Spanish',
  'es': 'Spanish',
  'fre': 'French',
  'fra': 'French',
  'fr': 'French',
  'ger': 'German',
  'deu': 'German',
  'de': 'German',
  'ita': 'Italian',
  'it': 'Italian',
  'jpn': 'Japanese',
  'ja': 'Japanese',
  'kor': 'Korean',
  'ko': 'Korean',
  'rus': 'Russian',
  'ru': 'Russian',
  'por': 'Portuguese',
  'pt': 'Portuguese',
  'pob': 'Portuguese (BR)',
  'pb': 'Portuguese (BR)',
  'chi': 'Chinese',
  'zho': 'Chinese',
  'zh': 'Chinese',
  'hin': 'Hindi',
  'hi': 'Hindi',
  'tur': 'Turkish',
  'tr': 'Turkish',
  'ind': 'Indonesian',
  'id': 'Indonesian',
  'vie': 'Vietnamese',
  'vi': 'Vietnamese',
  'tha': 'Thai',
  'th': 'Thai',
  'pol': 'Polish',
  'pl': 'Polish',
  'dut': 'Dutch',
  'nld': 'Dutch',
  'nl': 'Dutch',
  'swe': 'Swedish',
  'sv': 'Swedish',
  'nor': 'Norwegian',
  'no': 'Norwegian',
  'dan': 'Danish',
  'da': 'Danish',
  'fin': 'Finnish',
  'fi': 'Finnish',
  'heb': 'Hebrew',
  'he': 'Hebrew',
  'ces': 'Czech',
  'cze': 'Czech',
  'cs': 'Czech',
  'ell': 'Greek',
  'gre': 'Greek',
  'el': 'Greek',
  'hun': 'Hungarian',
  'hu': 'Hungarian',
  'ron': 'Romanian',
  'rum': 'Romanian',
  'ro': 'Romanian',
  'ukr': 'Ukrainian',
  'uk': 'Ukrainian',
  'per': 'Persian',
  'fas': 'Persian',
  'fa': 'Persian',
  'hrv': 'Croatian',
  'scr': 'Croatian',
  'hr': 'Croatian',
  'bul': 'Bulgarian',
  'bg': 'Bulgarian',
  'est': 'Estonian',
  'et': 'Estonian',
  'ms': 'Malay',
  'may': 'Malay',
  'msa': 'Malay',
  'tl': 'Tagalog',
  // 'fil' and 'tgl' are distinct codes; 'fil' (Filipino) keeps the label the
  // CloudStream reader already produced, 'tgl' stays Tagalog.
  'fil': 'Filipino',
  'bn': 'Bengali',
  'ben': 'Bengali',
  'ur': 'Urdu',
  'urd': 'Urdu',
  'ta': 'Tamil',
  'tam': 'Tamil',
  'te': 'Telugu',
  'tel': 'Telugu',
  'mac': 'Macedonian',
  'mkd': 'Macedonian',
  'mk': 'Macedonian',
  'slv': 'Slovenian',
  'sl': 'Slovenian',
  'srp': 'Serbian',
  'scc': 'Serbian',
  'sr': 'Serbian',
  'bos': 'Bosnian',
  'bs': 'Bosnian',
  'alb': 'Albanian',
  'sqi': 'Albanian',
  'sq': 'Albanian',
  'slk': 'Slovak',
  'slo': 'Slovak',
  'sk': 'Slovak',
  'lit': 'Lithuanian',
  'lt': 'Lithuanian',
  'lav': 'Latvian',
  'lv': 'Latvian',
  'ice': 'Icelandic',
  'isl': 'Icelandic',
  'is': 'Icelandic',
  'mal': 'Malayalam',
  'ml': 'Malayalam',
  'tgl': 'Tagalog',
  'cat': 'Catalan',
  'ca': 'Catalan',
};

/// Normalizes a language code/label to a clean human-readable name
/// (e.g. 'en' → 'English', 'pt-br' → 'Portuguese').
///
/// Bracket tags (`[CC]`), parenthesized qualifiers (`(SDH)`) and
/// `-sdh`/`-cc`/`-forced` suffixes are stripped first, so addon labels survive
/// the lookup. A label that matches nothing is returned capitalized, and an
/// empty one becomes 'English', so a picker never shows a blank entry.
String subtitleLanguageName(String raw) {
  var base = raw
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'-\s*(sdh|cc|forced)', caseSensitive: false), '')
      .trim();
  if (base.isEmpty) base = raw.trim();

  final clean = base.toLowerCase();
  final named = _languageNames[clean];
  if (named != null) return named;

  final codeMatch = RegExp(r'^([a-z]{2,3})[-_ ]').firstMatch(clean);
  if (codeMatch != null) {
    final namedByPrefix = _languageNames[codeMatch.group(1)];
    if (namedByPrefix != null) return namedByPrefix;
  }

  for (final name in _languageNames.values) {
    if (name.toLowerCase() == clean) return name;
  }
  for (final name in _languageNames.values) {
    if (name.length > 3 && clean.contains(name.toLowerCase())) return name;
  }

  if (base.isNotEmpty) {
    // An unknown 2-3 letter label is an ISO code, not a word: `xx` reads as
    // `XX`, which is what every catalogue and the old per-provider fallbacks
    // displayed. Only prose gets sentence case.
    if (clean.length <= 3 && !clean.contains(' ')) return clean.toUpperCase();
    return base[0].toUpperCase() + base.substring(1);
  }
  return 'English';
}