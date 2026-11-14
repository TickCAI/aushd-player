import '../playback/language.dart' show normalizeLanguage;

/// Chinese adaptation for **content**, not chrome.
///
/// The UI strings themselves are localized through the ARB files, but Emby,
/// Jellyfin and TMDB also return user-visible English data: genres, track
/// languages, cast roles, collection names. Since the product is aimed almost
/// exclusively at domestic users, those values are translated at the display
/// boundary when the UI language is Chinese. The original values are kept for
/// filtering/querying, so a genre chip still sends the server's own string.
abstract final class ContentZh {
  /// Synchronized by the app root from `AppSettings.resolvedUiLanguage`.
  /// Defaults to Chinese because that is the product's primary audience.
  static String uiLanguage = 'zh';

  static bool get enabled => uiLanguage.startsWith('zh');

  /// Translate a genre/type label. Unknown labels pass through untouched so a
  /// server-specific category is never lost.
  static String genre(String raw) {
    if (!enabled || raw.isEmpty) return raw;
    final key = raw.trim().toLowerCase().replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
    return _genres[key] ?? raw;
  }

  static String genres(Iterable<String> values, {String separator = ', '}) =>
      values.map(genre).join(separator);

  /// Turn "English", "Chinese (Simplified)", "eng", "zh-CN" into 英语 / 简体中文.
  static String language(String raw) {
    if (!enabled || raw.isEmpty) return raw;
    final text = raw.trim();
    final bare = text.toLowerCase().replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();
    final region = text.toLowerCase();
    if (region.contains('zh-tw') || region.contains('traditional') || region.contains('繁')) return '繁體中文';
    if (region.contains('zh-cn') || region.contains('zh-hans') || region.contains('simplified') || region.contains('简')) {
      return '简体中文';
    }
    if (region.contains('yue') || region.contains('cantonese') || region.contains('粤')) return '粤语';
    final direct = _englishLanguageCodes[bare];
    final code = direct ?? normalizeLanguage(bare);
    final name = _languageNames[code];
    return name ?? raw;
  }

  /// Cast/crew job titles and common placeholder role names.
  static String personRole(String raw) {
    if (!enabled || raw.isEmpty) return raw;
    final key = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return _roles[key] ?? raw;
  }

  /// TMDB collection names are localized when the API is queried with
  /// `language=zh-CN`, but cached/legacy documents may still carry the English
  /// name. Trim the redundant English suffix in that case.
  static String collectionName(String raw) {
    if (!enabled || raw.isEmpty) return raw;
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)) return raw;
    var name = raw.trim();
    for (final suffix in const [' Collection', ' (Film Series)', ' Film Series', ' Series']) {
      if (name.toLowerCase().endsWith(suffix.toLowerCase())) {
        name = name.substring(0, name.length - suffix.length).trim();
        break;
      }
    }
    return '$name 系列';
  }

  static const _genres = <String, String>{
    // TMDB movie genres
    'action': '动作', 'adventure': '冒险', 'animation': '动画', 'comedy': '喜剧',
    'crime': '犯罪', 'documentary': '纪录片', 'drama': '剧情', 'family': '家庭',
    'fantasy': '奇幻', 'history': '历史', 'horror': '恐怖', 'music': '音乐',
    'mystery': '悬疑', 'romance': '爱情', 'science fiction': '科幻',
    'tv movie': '电视电影', 'thriller': '惊悚', 'war': '战争', 'western': '西部',
    // TMDB TV genres
    'action & adventure': '动作冒险', 'action/adventure': '动作冒险',
    'action and adventure': '动作冒险', 'kids': '儿童', 'news': '新闻',
    'reality': '真人秀', 'sci-fi & fantasy': '科幻奇幻', 'science fiction & fantasy': '科幻奇幻',
    'soap': '肥皂剧', 'talk': '脱口秀', 'war & politics': '战争政治',
    'war and politics': '战争政治', 'sci-fi': '科幻',
    // Common scraper / Emby variants
    'anime': '动漫', 'wuxia': '武侠', 'martial arts': '武侠', 'costume drama': '古装',
    'historical': '历史', 'biography': '传记', 'biographical': '传记', 'sport': '运动',
    'sports': '体育', 'short': '短片', 'musical': '歌舞', 'game show': '综艺',
    'variety': '综艺', 'sitcom': '情景喜剧', 'film noir': '黑色电影',
    'independent': '独立', 'foreign': '外语', 'adult': '成人', 'suspense': '悬疑',
    'disaster': '灾难', 'mini-series': '迷你剧', 'miniseries': '迷你剧',
    'crime drama': '犯罪', 'comedy drama': '喜剧', 'romance drama': '爱情',
    'kids & family': '儿童家庭', 'special interest': '专题', 'educational': '教育',
    'home and garden': '家居园艺', 'eastern': '东方', 'urban': '都市',
    'thriller & suspense': '惊悚悬疑', 'science-fiction': '科幻', 'scifi': '科幻',
    'action/adventure/comedy': '动作冒险喜剧', 'drama, crime': '剧情 / 犯罪',
    'unwatched': '未观看', 'favorites': '收藏',
  };

  static const _englishLanguageCodes = <String, String>{
    'english': 'en', 'chinese': 'zh', 'mandarin': 'zh', 'japanese': 'ja',
    'korean': 'ko', 'french': 'fr', 'german': 'de', 'spanish': 'es',
    'italian': 'it', 'portuguese': 'pt', 'russian': 'ru', 'thai': 'th',
    'vietnamese': 'vi', 'indonesian': 'id', 'hindi': 'hi', 'arabic': 'ar',
    'dutch': 'nl', 'polish': 'pl', 'turkish': 'tr', 'swedish': 'sv',
    'danish': 'da', 'norwegian': 'no', 'finnish': 'fi', 'czech': 'cs',
    'hungarian': 'hu', 'greek': 'el', 'hebrew': 'he', 'ukrainian': 'uk',
    'romanian': 'ro', 'bulgarian': 'bg', 'croatian': 'hr', 'serbian': 'sr',
    'slovak': 'sk', 'slovenian': 'sl', 'persian': 'fa', 'malay': 'ms',
    'filipino': 'tl', 'catalan': 'ca', 'basque': 'eu', 'galician': 'gl',
    'estonian': 'et', 'latvian': 'lv', 'lithuanian': 'lt', 'icelandic': 'is',
    'albanian': 'sq', 'macedonian': 'mk', 'bosnian': 'bs', 'bengali': 'bn',
    'tamil': 'ta', 'telugu': 'te', 'urdu': 'ur', 'welsh': 'cy',
    'irish': 'ga', 'georgian': 'ka', 'armenian': 'hy', 'azerbaijani': 'az',
    'kazakh': 'kk', 'cantonese': 'yue', 'unknown': '', 'undetermined': '',
  };

  static const _languageNames = <String, String>{
    '': '未知语言', 'en': '英语', 'zh': '中文', 'ja': '日语', 'ko': '韩语',
    'fr': '法语', 'de': '德语', 'es': '西班牙语', 'it': '意大利语', 'pt': '葡萄牙语',
    'ru': '俄语', 'th': '泰语', 'vi': '越南语', 'id': '印尼语', 'hi': '印地语',
    'ar': '阿拉伯语', 'nl': '荷兰语', 'pl': '波兰语', 'tr': '土耳其语',
    'sv': '瑞典语', 'da': '丹麦语', 'no': '挪威语', 'nb': '挪威语',
    'fi': '芬兰语', 'cs': '捷克语', 'hu': '匈牙利语', 'el': '希腊语',
    'he': '希伯来语', 'uk': '乌克兰语', 'ro': '罗马尼亚语', 'bg': '保加利亚语',
    'hr': '克罗地亚语', 'sr': '塞尔维亚语', 'sk': '斯洛伐克语', 'sl': '斯洛文尼亚语',
    'fa': '波斯语', 'ms': '马来语', 'tl': '菲律宾语', 'ca': '加泰罗尼亚语',
    'eu': '巴斯克语', 'gl': '加利西亚语', 'et': '爱沙尼亚语', 'lv': '拉脱维亚语',
    'lt': '立陶宛语', 'is': '冰岛语', 'sq': '阿尔巴尼亚语', 'mk': '马其顿语',
    'bs': '波斯尼亚语', 'bn': '孟加拉语', 'ta': '泰米尔语', 'te': '泰卢固语',
    'ur': '乌尔都语', 'cy': '威尔士语', 'ga': '爱尔兰语', 'ka': '格鲁吉亚语',
    'hy': '亚美尼亚语', 'az': '阿塞拜疆语', 'kk': '哈萨克语', 'yue': '粤语',
  };

  static const _roles = <String, String>{
    'director': '导演', 'actor': '演员', 'actress': '演员', 'writer': '编剧',
    'screenplay': '编剧', 'producer': '制片人', 'executive producer': '监制',
    'composer': '配乐', 'original music composer': '配乐', 'creator': '主创',
    'cinematography': '摄影', 'editor': '剪辑', 'guest star': '客串',
    'narrator': '旁白', 'self': '本人出演', 'himself': '本人出演', 'herself': '本人出演',
    'themselves': '本人出演', 'voice': '配音', 'host': '主持人', 'presenter': '主持人',
  };
}
