# -*- coding: utf-8 -*-
"""Generate lib/l10n/app_zh.arb from app_en.arb.

Source of truth: zh_full.json (one reviewed Chinese string per l10n key).
Fallback order: zh_full.json -> CORE -> EXACT -> English with brand replaced.

Safety: a translation whose placeholder set differs from the English
template is rejected and the English string is kept, so `flutter gen-l10n`
can never break because of a missing {placeholder}.

To adjust a wording, edit zh_full.json and re-run this script, then run
verify_zh.py to check placeholders, ICU branches and proper nouns.
"""
import json
import os
import re

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ROOT = os.path.join(REPO, 'lib', 'l10n')
EN = os.path.join(ROOT, 'app_en.arb')
ZH = os.path.join(ROOT, 'app_zh.arb')
FULL = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'zh_full.json')

CORE = {
    'notSet': '未设置',
    'save': '保存',
    'cancel': '取消',
    'back': '返回',
    'continueAction': '继续',
    'skip': '跳过',
    'finish': '完成',
    'checking': '正在检查…',
    'stepOf': '第 {current} 步，共 {total} 步',
    'languageFromFile': '跟随文件默认',
    'langEnglish': '英语',
    'langRomanian': '罗马尼亚语',
    'signInWelcome': '欢迎使用 AusHD Player',
    'signInSubtitle': '登录你的 Emby 或 Jellyfin 服务器。',
    'mediaServer': '媒体服务器',
    'serverAddress': '服务器地址',
    'serverAddressHint': '例如 192.168.1.10:8096',
    'signInWithCode': '同步码',
    'signInManually': '手动设置',
    'syncCode': '同步码',
    'syncCodeSubtitle': '输入服务器管理员给你的同步码，再填写你自己的用户名和密码。',
    'hubAddress': '服务端地址',
    'hubAddressHint': '例如 dist.example.com',
    'linkedTo': '由 {name} 配置',
    'unlinkHub': '改用其他同步码',
    'codeEyebrow': 'AusHD Player · {server}',
    'codeHeadline': '你的服务器，每块屏幕。\n一个同步码就够了。',
    'codePitch': '管理 Emby 或 Jellyfin 服务器的人只需配置一次 AusHD Player。输入他给你的同步码，用自己的账号登录，一切就绪。',
    'codeFeatureRequests': '在沙发上就能请求电影和剧集',
    'codeFeatureTogether': '异地同步一起看',
    'codeFeatureProfiles': '多用户配置与「我的片单」',
    'codeFeatureLiveTv': '带完整节目单的直播电视',
    'codeEnterTitle': '输入同步码',
    'codeEnterHint': '12 位字母数字，向服务器管理员索取',
    'codeContinue': '继续',
    'codeChecking': '正在检查…',
    'codeSignInTitle': '现在登录',
    'codeSignInBody': '使用你自己的 {kind} 用户名和密码。',
    'codeNoCode': '没有同步码？可以自己设置，或用手机扫二维码。',
    'codeOwnerHint': '自己搭服务器？到 {site} 打开 AusHD 控制台',
    'codeBack': '使用同步码',
    'groupCollections': '按合集分组',
    'collectionTitle': '合集',
    'groupCollectionsHint': '在「电影」里把每个合集显示为一个条目，而不是逐部影片。',
    'homeClock': '首页显示时钟',
    'requestFolderTitle': '保存到目录',
    'sendLogs': '发送日志',
    'sendLogsSending': '正在发送日志…',
    'sendLogsDoneTitle': '日志已发送',
    'hubLinkedSetting': '同步码',
    'username': '用户名',
    'password': '密码',
    'signIn': '登录',
    'signingIn': '正在登录…',
    'errorWrongCredentials': '用户名或密码错误。',
    'phoneSetupTitle': '用手机设置',
    'phoneWaiting': '等待手机连接…',
    'phoneConnected': '手机已连接',
    'phoneApplying': '正在应用设置…',
    'phoneApplied': '设置已保存',
    'obLanguageTitle': '语言与字幕',
    'appLanguage': '应用语言',
    'preferredSubtitles': '首选字幕',
    'obMetadataTitle': '元数据与海报',
    'metadataSource': '数据来源',
    'metadataSourceEmby': '媒体服务器',
    'metadataSourceEmbyHint': '按服务器上的内容显示。',
    'tmdbApiKey': 'TMDB API 密钥',
    'ratingsHeader': '评分',
    'mdblistApiKey': 'MDBList API 密钥',
    'testMdblistKey': '测试 MDBList 密钥',
    'mdblistKeyFirst': '请先填写 MDBList 密钥',
    'mdblistKeyWorks': 'MDBList 密钥可用',
    'obRequestsTitle': '请求',
    'seerrAddress': '服务器地址',
    'seerrAddressHint': 'https://requests.example.com',
    'seerrApiKey': 'API 密钥',
    'settings': '设置',
    'exitApp': '退出 AusHD Player',
    'exitAppQuestion': '退出 AusHD Player？',
    'exitConfirm': '退出',
    'sectionContent': '内容与预告片',
    'sectionServices': '已连接的服务',
    'settingsGroupDisplay': '显示',
    'settingsGroupDecoding': '画面与解码',
    'advancedVideo': '高级视频设置',
    'sectionPlayback': '播放',
    'audio': '音频',
    'sectionLanguages': '语言与字幕',
    'sectionMetadata': '元数据',
    'sectionRequests': '请求',
    'sectionInterface': '界面',
    'sectionAccount': '账户',
    'streamingQuality': '串流画质',
    'qualityOriginal': '原画（无限制）',
    'playerQuality': '画质',
    'qualityDirect': '原画 / 直连',
    'transcodeByDefault': '默认转码',
    'hdrPassthrough': 'HDR 直通',
    'autoHdr': '自动开启 HDR',
    'autoHdrChecking': '正在检查显示器…',
    'matchRefreshRate': '匹配显示器刷新率',
    'smoothMotion': '动态补偿',
    'autoSkipIntro': '自动跳过片头',
    'seekStep': '快进步长',
    'exclusiveAudio': '独占音频模式',
    'systemLanguage': '跟随系统',
    'preferredAudioLanguage': '首选音频语言',
    'subtitles': '字幕',
    'subtitleForcedOnly': '仅强制字幕',
    'subtitleSmart': '智能',
    'subtitleAlways': '始终开启',
    'subtitleOff': '关闭',
    'preferredSubtitleLanguage': '首选字幕语言',
    'subtitleSize': '字幕大小',
    'subtitlePreviewLine2': '那我们走吧，就现在。',
    'searchSubtitles': '搜索字幕',
    'subtitleSearching': '正在搜索…',
    'subtitleSearchFailed': '字幕搜索失败',
    'subtitleDownloading': '正在下载字幕…',
    'subtitleAdded': '字幕已添加',
    'subtitleExactMatch': '精确匹配',
    'sizeSmall': '小',
    'sizeNormal': '中',
    'sizeLarge': '大',
    'metadataLanguage': '元数据语言',
    'metadataFromServer': '跟随服务器',
    'metadataIntro': '从 TMDB 获取你所用语言的标题、简介、类型和海报（背景图、Logo、剧照），替代服务器上保存的元数据。媒体库本身不会改动。',
    'metadataLanguageNeedsKey': '需要 TMDB API 密钥；未设置前显示服务器上的元数据。',
    'metadataLanguageHint': '缺少翻译时先回退到英文，再回退到服务器。「发现」和「请求」同样适用。',
    'testTmdbKey': '测试 TMDB 密钥',
    'tmdbKeyFirst': '请先填写 TMDB 密钥',
    'tmdbKeyWorks': 'TMDB 密钥可用',
    'restyleAssHint': '把上面的字号与字体同样应用到动漫风格字幕。',
    'appVersionLabel': 'AusHD Player {version}',
    'updateBody': '安装更新时 AusHD Player 会关闭。',
    'updateAllowInstalls': '允许 AusHD Player 安装应用，然后再次选择「立即更新」。',
    'logsIntro': 'AusHD Player 会记录运行日志：错误、服务器请求、播放和卡顿页面。出问题时，把日志目录里最新的文件发给我们。',
    'webhookIntro': 'AusHD Player 可以在播放开始、暂停、继续或停止时通知其他系统，例如向 Home Assistant 的 webhook 发送 JSON 来调暗灯光。请求体包含事件、标题和播放位置。',
    'displayTargetHint': '适用于校色过的显示器和投影机。AusHD Player 会把每段视频转换并色调映射到你设定的色彩空间、传输曲线和亮度。保持「自动」则跟随显示器。',
    'keepRefreshRateHint': '剧集与菜单之间不来回切换刷新率；AusHD Player 关闭时恢复桌面刷新率。',
    'keepHdrHint': '播放 HDR 视频后保持 Windows HDR 开启，而不是自动关闭；AusHD Player 退出时恢复。',
    'settingsGroupContentLanguages': '内容与语言',
    'trailerLanguageOriginal': '原声',
    'calendarDigital': '数字发行',
    'calendarDisc': '光盘发行',
    'calendarTv': '电视播出',
    'metadataSourceTmdb': 'TMDB（{language}）',
}

EXACT = {
    'Settings': '设置', 'Search': '搜索', 'Home': '首页', 'Discover': '发现',
    'Library': '媒体库', 'Movies': '电影', 'Shows': '剧集', 'Play': '播放',
    'Pause': '暂停', 'Cancel': '取消', 'Save': '保存', 'Back': '返回',
    'Continue': '继续', 'Skip': '跳过', 'Finish': '完成', 'Off': '关闭',
    'On': '开启', 'Automatic': '自动', 'Enabled': '已启用', 'Disabled': '已禁用',
    'Loading…': '加载中…', 'Retry': '重试', 'Close': '关闭', 'Done': '完成',
    'Apply': '应用', 'Reset': '重置', 'Delete': '删除', 'Remove': '移除',
    'Add': '添加', 'Edit': '编辑', 'Yes': '是', 'No': '否', 'OK': '确定',
    'None': '无', 'Default': '默认', 'Language': '语言', 'Subtitles': '字幕',
    'Audio': '音频', 'Video': '视频', 'Playback': '播放', 'Quality': '画质',
    'Version': '版本', 'Update': '更新', 'Updates': '更新', 'Later': '稍后',
    'Check for updates': '检查更新', 'Update now': '立即更新',
    'Continue watching': '继续观看', 'More like this': '相似推荐',
    'Popular': '热门', 'Coming soon': '即将上映', 'Calendar': '日历',
    'Collections': '合集', 'Requests': '请求', 'Requested': '已请求',
    'Trailers': '预告片', 'Live TV': '直播电视', 'Sign out': '退出登录',
    'Profiles': '用户配置', 'My list': '我的片单', 'Watch together': '一起看',
    'No results': '没有结果', 'Subtitle delay': '字幕延迟',
    'Skip intro': '跳过片头', 'Next episode': '下一集', 'Season': '季',
    'Episode': '集', 'Seasons': '季', 'Episodes': '集', 'Details': '详情',
    'Genres': '类型', 'Cast': '演员', 'Runtime': '片长',
    'Release date': '上映日期', 'Unknown': '未知', 'Error': '错误',
    'Warning': '警告', 'Success': '成功', 'Failed': '失败',
    'Connecting…': '连接中…', 'Not set': '未设置', 'Not available': '不可用',
    'Custom': '自定义', 'Always': '始终', 'Never': '从不', 'Smart': '智能',
    'Original': '原画', 'Normal': '正常', 'Small': '小', 'Large': '大',
    'High': '高', 'Medium': '中', 'Low': '低', 'Searching…': '正在搜索…',
    'Search results': '搜索结果', 'Information': '提示', 'Original (no limit)': '原画（无限制）',
}

# ARB placeholder names are always ASCII identifiers. Using \w here would
# wrongly match Chinese ICU branch bodies such as "=0{未选择}".
PLACEHOLDER = re.compile(r'\{([A-Za-z_][A-Za-z0-9_]*)\}')


def brand(text):
    return text.replace('Zerk Play', 'AusHD Player').replace('zerkplay.example.com', 'dist.example.com')


def main():
    with open(EN, encoding='utf-8') as f:
        en = json.load(f)
    with open(FULL, encoding='utf-8') as f:
        full = json.load(f)
    keys = [k for k in en if not k.startswith('@')]
    out = {'@@locale': 'zh'}
    stats = {'full': 0, 'core': 0, 'exact': 0, 'english': 0, 'fallback': 0}
    unknown = sorted(set(full) - set(keys))

    for k in keys:
        original = en[k]
        if not isinstance(original, str):
            out[k] = original
            continue
        wanted = set(PLACEHOLDER.findall(original))
        candidates = [
            ('full', full.get(k)),
            ('core', CORE.get(k)),
            ('exact', EXACT.get(original)),
        ]
        translated = None
        for source, candidate in candidates:
            if not isinstance(candidate, str):
                continue
            if set(PLACEHOLDER.findall(candidate)) != wanted:
                stats['fallback'] += 1
                print(f'WARN placeholder mismatch ({source}), keeping English: {k}')
                continue
            translated = candidate
            stats[source] += 1
            break
        if translated is None:
            translated = brand(original)
            stats['english'] += 1
        out[k] = translated

    with open(ZH, 'w', encoding='utf-8', newline='') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('keys', len(keys), '| full', stats['full'], '| core', stats['core'],
          '| exact', stats['exact'], '| english-remaining', stats['english'],
          '| placeholder-fallback', stats['fallback'])
    if unknown:
        print('WARN keys in zh_full.json not in template:', unknown)
    print('written', ZH)


if __name__ == '__main__':
    main()
