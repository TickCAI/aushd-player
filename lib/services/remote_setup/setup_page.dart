import 'dart:convert';

import '../../app/app_settings.dart';
import '../../playback/language.dart';

// This page is shown in the phone's browser during QR-code setup. The AusHD
// Player fork ships a Chinese-first UI, so its visible copy is Chinese as
// well. Service / protocol names (Emby, Jellyfin, TMDB, M3U, ...) stay as-is.

const _style = '''
:root{color-scheme:dark;--bg:#0B0B12;--surface:#16161F;--high:#1E1E2A;--outline:#ffffff22;--text:#fff;--muted:#ffffffb3;--faint:#ffffff73;--accent:#6C63FF;--request:#F5B544;--ok:#3DDC97;--bad:#FF5D6C}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(circle at 10% 0%,#221E4A,var(--bg) 60%) fixed;color:var(--text);font:16px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,"Microsoft YaHei",sans-serif}
main{max-width:560px;margin:0 auto;padding:28px 16px 64px}
h1{font-size:28px;margin:8px 0 4px}
p.lead{color:var(--muted);margin:0 0 24px}
section{background:var(--surface);border:1px solid var(--outline);border-radius:18px;padding:20px;margin-bottom:16px}
h2{font-size:18px;margin:0 0 4px}
.hint{color:var(--faint);font-size:14px;margin:0 0 14px}
label{display:block;font-size:14px;color:var(--muted);margin:12px 0 6px}
input,select{width:100%;font:inherit;color:var(--text);background:var(--high);border:1.5px solid var(--outline);border-radius:12px;padding:12px 14px}
input:focus,select:focus{outline:none;border-color:var(--accent)}
button{width:100%;font:600 17px system-ui,sans-serif;color:#fff;background:var(--accent);border:0;border-radius:999px;padding:15px;margin-top:8px;cursor:pointer}
button:disabled{opacity:.6}
.result{margin-top:10px;font-size:14px}
.result.ok{color:var(--ok)}.result.bad{color:var(--bad)}
.code{font-size:28px;letter-spacing:.3em;text-align:center}
.logo{width:44px;height:44px;border-radius:12px;background:var(--accent);display:grid;place-items:center;font-weight:800;font-size:22px}
''';

String _shell(String title, String body) =>
    '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title><style>$_style</style></head>
<body><main><div class="logo">A</div>$body</main></body></html>''';

String setupCodePage({bool wrongCode = false}) => _shell('配置 AusHD Player', '''
<h1>配置 AusHD Player</h1>
<p class="lead">输入电视上显示的 6 位数字码。</p>
<form method="get" action="/"><section>
<input class="code" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" autofocus required>
${wrongCode ? '<p class="result bad">数字码不匹配，请核对电视上的显示后重试。</p>' : ''}
<button type="submit">继续</button>
</section></form>''');

String setupFormPage(Map<String, Object?> values) {
  final json = jsonEncode(values).replaceAll('<', r'\u003c');
  String options(Map<String, String> entries) =>
      [for (final e in entries.entries) '<option value="${_attr(e.key)}">${_text(e.value)}</option>'].join();
  return _shell('配置 AusHD Player', '''
<h1>配置 AusHD Player</h1>
<p class="lead">点「应用到电视」后设置才会生效，所有数据都只在本机网络内传输。</p>
<form id="f" autocomplete="off">
<section id="embySection">
  <h2>媒体服务器</h2>
  <p class="hint" id="embyHint">登录你的 Emby 或 Jellyfin 服务器。</p>
  <div id="serverField">
    <label for="serverKind">服务器类型</label>
    <select id="serverKind" name="serverKind"><option value="emby">Emby</option><option value="jellyfin">Jellyfin</option></select>
    <label for="server">服务器地址</label>
    <input id="server" name="server" placeholder="192.168.1.10:8096" inputmode="url" autocapitalize="off" spellcheck="false">
  </div>
  <label for="username">用户名</label>
  <input id="username" name="username" autocapitalize="off" spellcheck="false" autocomplete="username">
  <label for="password">密码</label>
  <input id="password" name="password" type="password" autocomplete="current-password">
  <p class="result" id="emby"></p>
</section>
<section>
  <h2>语言与字幕</h2>
  <p class="hint">电视上显示的语言，以及片源有对应字幕时优先选择的语言（没有则回退到英文）。</p>
  <label for="uiLanguage">应用语言</label>
  <select id="uiLanguage" name="uiLanguage">${options(uiLanguages)}</select>
  <label for="subtitleLanguage">首选字幕</label>
  <select id="subtitleLanguage" name="subtitleLanguage">${options({'': '跟随文件默认', ...languageNames})}</select>
</section>
<section id="metadataSection">
  <h2>元数据与海报</h2>
  <p class="hint">片名、简介、海报和 Logo 可以按应用语言从 TMDB 获取（缺少翻译时用英文），也可以保持服务器上的原样。</p>
  <label for="metadataSource">数据来源</label>
  <select id="metadataSource" name="metadataSource"><option value="tmdb">TMDB</option><option value="emby">媒体服务器</option></select>
  <label for="tmdbApiKey">TMDB API 密钥</label>
  <p class="hint">无论选哪个数据来源，预告片、合集和「发现」都会用到它；使用 TMDB 元数据时必填。</p>
  <input id="tmdbApiKey" name="tmdbApiKey" autocomplete="off" autocorrect="off" placeholder="API 密钥或只读访问令牌" autocapitalize="off" spellcheck="false">
  <p class="result" id="tmdb"></p>
</section>
<section>
  <h2>评分</h2>
  <p class="hint">来自 MDBList 的烂番茄评分。可在 mdblist.com → 偏好设置 → API 免费获取密钥，选填。</p>
  <label for="mdblistApiKey">MDBList API 密钥</label>
  <input id="mdblistApiKey" name="mdblistApiKey" autocomplete="off" autocorrect="off" placeholder="API 密钥" autocapitalize="off" spellcheck="false">
  <p class="result" id="mdblist"></p>
</section>
<section id="seerrSection">
  <h2>求片</h2>
  <p class="hint">接入 Jellyseerr 或 Overseerr，用来求片媒体库里还没有的内容，选填。</p>
  <label for="seerrUrl">服务器地址</label>
  <input id="seerrUrl" name="seerrUrl" placeholder="http://192.168.1.10:5055" inputmode="url" autocapitalize="off" spellcheck="false">
  <label for="seerrApiKey">API 密钥</label>
  <input id="seerrApiKey" name="seerrApiKey" autocomplete="off" autocorrect="off" placeholder="设置 → 常规 → API Key" autocapitalize="off" spellcheck="false">
  <p class="result" id="seerr"></p>
</section>
<section>
  <h2>电视直播播放列表</h2>
  <p class="hint">带 XMLTV 节目单的 M3U 播放列表，例如 Tunarr 或 NostalgiaTV，选填。</p>
  <label for="playlistUrl">播放列表地址（M3U）</label>
  <input id="playlistUrl" name="playlistUrl" placeholder="http://192.168.1.10:8000/api/channels.m3u" inputmode="url" autocapitalize="off" spellcheck="false">
  <label for="playlistGuideUrl">节目单地址（XMLTV，可选）</label>
  <input id="playlistGuideUrl" name="playlistGuideUrl" placeholder="http://192.168.1.10:8000/api/xmltv.xml" inputmode="url" autocapitalize="off" spellcheck="false">
</section>
<button id="save" type="submit">应用到电视</button>
<p class="result" id="overall"></p>
</form>
<script>
const v = $json;
const f = document.getElementById('f');
const byId = (id) => document.getElementById(id);
f.server.value = v.server || '';
f.serverKind.value = v.serverKind || 'emby';
f.uiLanguage.value = v.uiLanguage || 'zh';
f.subtitleLanguage.value = v.subtitleLanguage || '';
f.metadataSource.value = v.metadataSource || 'tmdb';
f.seerrUrl.value = v.seerrUrl || '';
f.playlistUrl.value = v.playlistUrl || '';
f.playlistGuideUrl.value = v.playlistGuideUrl || '';
if (v.signedIn) byId('embyHint').textContent = '电视已登录。只在需要切换账号时填写用户名。';
if (v.hasSeerrKey) f.seerrApiKey.placeholder = '已保存在电视上，留空即保持不变。';
if (v.hasTmdbKey) f.tmdbApiKey.placeholder = '已保存在电视上，留空即保持不变。';
if (v.hasMdblistKey) f.mdblistApiKey.placeholder = '已保存在电视上，留空即保持不变。';
function show(id, r) {
  const el = byId(id);
  if (!el) return;
  el.textContent = r ? r.message : '';
  el.className = 'result' + (r ? (r.ok ? ' ok' : ' bad') : '');
}
f.addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn = byId('save');
  btn.disabled = true; btn.textContent = '正在保存…';
  ['emby', 'seerr', 'tmdb', 'mdblist', 'overall'].forEach((id) => show(id, null));
  try {
    const res = await fetch(location.pathname.replace(/\\/\$/, '') + '/apply', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(Object.fromEntries(new FormData(f))),
    });
    if (!res.ok) throw new Error(await res.text());
    const r = await res.json();
    show('emby', r.emby); show('seerr', r.seerr); show('tmdb', r.tmdb); show('mdblist', r.mdblist);
    const failed = Object.values(r).some((x) => !x.ok);
    show('overall', {ok: !failed, message: failed ? '已保存，但有部分设置需要检查。' : '已保存，可以放下手机了。'});
    if (r.emby && r.emby.ok) f.password.value = '';
    if (!failed) { if (f.seerrApiKey) f.seerrApiKey.value = ''; if (f.tmdbApiKey) f.tmdbApiKey.value = ''; f.mdblistApiKey.value = ''; }
  } catch (err) {
    show('overall', {ok: false, message: '无法连接电视，配置页面还开着吗？' + (err.message || '')});
  } finally {
    btn.disabled = false; btn.textContent = '应用到电视';
  }
});
</script>''');
}

String _text(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
String _attr(String s) => _text(s).replaceAll('"', '&quot;');
