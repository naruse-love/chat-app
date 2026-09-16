import 'dart:io';
import 'package:ankidroid_for_flutter/ankidroid_for_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocabulary_entry.dart';
import 'anki_export_service_interface.dart';
import 'weblio_service.dart';

export 'anki_export_service_interface.dart';

/// AnkiDroid 底层操作抽象网桥（方便在单元测试与桌面环境进行纯内存 Mock）
abstract class AnkidroidBridge {
  bool get isPlatformSupported;
  Future<bool> requestPermission();
  Future<void> init();
  Future<Map<int, String>> getDeckList();
  Future<int> addNewDeck(String name);
  Future<Map<int, String>> getModelList();
  Future<List<String>> getFieldList(int modelId);
  Future<int> addNewCustomModel({
    required String name,
    required List<String> fields,
    required List<String> cards,
    required List<String> qfmt,
    required List<String> afmt,
    String css = '',
    int? did,
    int? sortf,
  });
  Future<List<dynamic>> findDuplicateNotesWithKey(int mid, String key);
  Future<int> addNote({
    required int mid,
    required int did,
    required List<String> fields,
    required List<String> tags,
  });
  Future<void> dispose();
}

/// 基于 ankidroid_for_flutter 的真实原生网桥
class NativeAnkidroidBridge implements AnkidroidBridge {
  Ankidroid? _isolate;

  @override
  bool get isPlatformSupported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!isPlatformSupported) return false;
    try {
      return await Ankidroid.askForPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> init() async {
    if (!isPlatformSupported) {
      throw UnsupportedError('AnkiDroid 仅支持 Android 平台');
    }
    _isolate ??= await Ankidroid.createAnkiIsolate();
  }

  @override
  Future<Map<int, String>> getDeckList() async {
    await init();
    final result = await _isolate!.deckList();
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    final map = result.asValue?.value;
    if (map == null) return {};
    final res = <int, String>{};
    map.forEach((k, v) {
      final id = k is int ? k : int.tryParse(k.toString());
      if (id != null) {
        res[id] = v.toString();
      }
    });
    return res;
  }

  @override
  Future<int> addNewDeck(String name) async {
    await init();
    final result = await _isolate!.addNewDeck(name);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<Map<int, String>> getModelList() async {
    await init();
    final result = await _isolate!.modelList();
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    final map = result.asValue?.value;
    if (map == null) return {};
    final res = <int, String>{};
    map.forEach((k, v) {
      final id = k is int ? k : int.tryParse(k.toString());
      if (id != null) {
        res[id] = v.toString();
      }
    });
    return res;
  }

  @override
  Future<List<String>> getFieldList(int modelId) async {
    await init();
    final result = await _isolate!.getFieldList(modelId);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    final list = result.asValue?.value;
    if (list == null) return [];
    return list.map((e) => e.toString()).toList();
  }

  @override
  Future<int> addNewCustomModel({
    required String name,
    required List<String> fields,
    required List<String> cards,
    required List<String> qfmt,
    required List<String> afmt,
    String css = '',
    int? did,
    int? sortf,
  }) async {
    await init();
    final result = await _isolate!.addNewCustomModel(
      name,
      fields,
      cards,
      qfmt,
      afmt,
      css,
      did,
      sortf,
    );
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<List<dynamic>> findDuplicateNotesWithKey(int mid, String key) async {
    await init();
    final result = await _isolate!.findDuplicateNotesWithKey(mid, key);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<int> addNote({
    required int mid,
    required int did,
    required List<String> fields,
    required List<String> tags,
  }) async {
    await init();
    final result = await _isolate!.addNote(mid, did, fields, tags);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<void> dispose() async {
    try {
      _isolate?.killIsolate();
      _isolate = null;
    } catch (_) {}
  }
}

/// Anki 模型解析与自愈结果
class AnkiModelResolution {
  final int modelId;
  final String modelName;
  final bool isUpgraded;
  final String? upgradedFrom;

  const AnkiModelResolution({
    required this.modelId,
    required this.modelName,
    this.isUpgraded = false,
    this.upgradedFrom,
  });
}

/// AnkiDroid 导出生词服务核心实现类
class AnkiExportService implements AnkiExportServiceInterface {
  static const String defaultDeckName = 'gal';
  static const String legacyDefaultModelName = '日语生词本-AI';
  static const String defaultModelName = '日语生词本-AI-v2';

  /// 13 个标准 Anki 卡片字段（首字段为唯一主键 VocabKanji，确保 AnkiDroid 重复检测与卡片标题精准匹配）
  static const List<String> ankiFields = [
    'VocabKanji',
    'VocabFurigana',
    'VocabPoS',
    'VocabDefSC',
    'VocabDefJa',
    'SentKanji1',
    'SentFurigana1',
    'SentDefSC1',
    'SentKanji2',
    'SentFurigana2',
    'SentDefSC2',
    'SourceDict',
    'NoteID',
  ];

  /// 默认模板实际引用的完整字段集合。
  /// 保留 [ankiFields] 作为旧模型与纯数据映射的兼容字段列表。
  /// 包含 'Alt1' 占位防御字段，彻底杜绝任何残存模板校验异常。
  static const List<String> defaultModelFields = [
    ...ankiFields,
    'Alt1',
    'VocabPitch',
    'VocabDefTC',
    'VocabPlus',
    'VocabAudio',
    'SentKanji3',
    'SentFurigana3',
    'SentDefSC3',
    'SentDefTC3',
    'SentType3',
    'SentAudio3',
    'SentKanji4',
    'SentFurigana4',
    'SentDefSC4',
    'SentDefTC4',
    'SentType4',
    'SentAudio4',
    'SentDefTC1',
    'SentDefTC2',
    'SentType1',
    'SentType2',
    'SentAudio1',
    'SentAudio2',
  ];

  static const String defaultQfmt = r'''
<!-- Card1 [日-中] 正面 -->

<main id="FrontSide" class="CardSide">
  <div class="Top">
    <span class="Level">{{Tags}}</span>
    <a target="_blank" class="Feedback">反馈</a>
  </div>

  <header class="Question">
  <a target="_blank" class="Search">🔍</a>
  <h1 class="VocabKanji">
    <span lang="ja">{{furigana:VocabKanji}}</span>
    <span class="VocabPitch">{{VocabPitch}}</span>
  </h1>
  <div class="VocabAudio"></div>
</header>

  <ul class="SentenceList">
    {{#SentKanji1}}
    <li class="Sentence">
      <h3 class="SentKanji LabelIndent" lang="ja">
        {{#SentFurigana1}}{{kanji:SentFurigana1}}{{/SentFurigana1}}
        {{^SentFurigana1}}{{kanji:SentKanji1}}{{/SentFurigana1}}
      </h3>
    </li>
    {{/SentKanji1}}

    {{#SentKanji2}}
    <li class="Sentence">
      <h3 class="SentKanji LabelIndent" lang="ja">
        {{#SentFurigana2}}{{kanji:SentFurigana2}}{{/SentFurigana2}}
        {{^SentFurigana2}}{{kanji:SentKanji2}}{{/SentFurigana2}}
      </h3>
    </li>
    {{/SentKanji2}}

    {{#SentKanji3}}
    <li class="Sentence">
      <h3 class="SentKanji LabelIndent" lang="ja">
        {{#SentFurigana3}}{{kanji:SentFurigana3}}{{/SentFurigana3}}
        {{^SentFurigana3}}{{kanji:SentKanji3}}{{/SentFurigana3}}
      </h3>
    </li>
    {{/SentKanji3}}

    {{#SentKanji4}}
    <li class="Sentence">
      <h3 class="SentKanji LabelIndent" lang="ja">
        {{#SentFurigana4}}{{kanji:SentFurigana4}}{{/SentFurigana4}}
        {{^SentFurigana4}}{{kanji:SentKanji4}}{{/SentFurigana4}}
      </h3>
    </li>
    {{/SentKanji4}}
  </ul>
</main>

<script>
  function CONFIG() {
    // --- 以下为设置里的预设项，根据个人需求调整 --- //
    const settings = {
      lang: 'zh-Hans',      // 显示语言: 'zh-Hans' 简体中文 | 'zh-Hant' 繁体中文
      dict: {
        ios: 'moji',        // 在 iOS 使用 MOji 辞書
        android: 'moji',    // 在 Android 使用 MOji 辞書
        mac: 'dict',        // 在 macOS 使用系统自带的词典
        win: 'goldendict',  // 在 Windows 使用 GoldenDict-ng 词典
        other: 'weblio',    // 在其他平台使用 Weblio 国語辞典
      },
      display: 'default',   // 正面单词显示: 'default' 显示汉字和注音假名 | 'kana' 只显示假名 | 'kanji' 只显示汉字
      playback: 'force',    // 背面播放设置: 'default' 跟随牌组的系统设置 | 'force' 强制只播放单词音频
      autoCopy: {           // 背面自动复制: true 开启 | false 关闭
        ipad: true,
        iphone: false,
        ankiweb: false,
      },
      tts: {
        enable: 'fallback', // 在线 TTS 开关: 'always' 始终开启 | 'fallback' 无本地音频时启用 | 'never' 始终关闭
        hotkey: 'G',        // 播放快捷键，仅支持桌面端
        domain: [
          // 可以添加更多域名，按顺序依次尝试播放
          'https://anki.0w0.live/',
          'https://ms-ra-forwarder-for-ifreetime-pbbu.vercel.app/',
        ],
        params: {
          voiceName: 'ja-JP-KeitaNeural,ja-JP-NanamiNeural', // 语音为多个时随机选择一个
          speed: -4, // 语速范围 -50 到 100，0 为正常语速
        }
      }
    }
    // --- 以下为词典预设项，新增词典参考格式添加 --- //
    const dictOptions = {
      'moji': 'mojisho://?search={query}',                          // MOJi 辞書 [ios|android]
      'mojidict': 'https://www.mojidict.com/searchText/{query}',    // MOJi 辞書网页版 [web]
      'dict': 'dict://{query}',                                     // macOS 词典 [mac]
      'eudic': 'eudic://dict/{query}',                              // Eudic 欧路词典 [win|mac|ios|android]
      'goldendict': 'goldendict://{query}',                         // GoldenDict-ng 词典 [win]
      'dicttango': 'dttp://app.dicttango/WordLookup?word={query}',  // DictTango [android]
      'monokakido': 'mkdictionaries:///?text={query}',              // Monokakido 物書堂 [mac|ios]
      'google': 'https://www.google.com/search?q={query}',          // Google Search [web]
      'weblio': 'https://www.weblio.jp/content/{query}',            // Weblio 国語辞典 [web]
      'weblioCJJC': 'https://cjjc.weblio.jp/content/{query}',       // Weblio 日中中日 [web]
      'takoboto': 'https://takoboto.jp/?q={query}',                 // Takoboto [web]
      'mazii': 'https://mazii.net/zh-TW/search/word/jatw/{query}',  // Mazii [web]
      'jisho': 'https://jisho.org/search/{query}',                  // Jisho [web]
      'kotobank': 'https://kotobank.jp/search?q={query}',           // Kotobank [web]
      'goo': 'https://dictionary.goo.ne.jp/srch/all/{query}/m0u/',  // Goo 辞書 [web]
    }

    return { settings, dictOptions }
  }

  function getTranslation(key) {
    const translations = {
      feedback: {
        'zh-Hans': '反馈',
        'zh-Hant': '反饋',
      },
      dictionaryTip: {
        'zh-Hans': '未配置适用于此平台的词典',
        'zh-Hant': '未配置適用於此平台的詞典',
      },
      updateReminder: {
        'zh-Hans': '请更新至最新版后再提交反馈',
        'zh-Hant': '請更新至最新版後再提交反饋',
      },
      versionCurrent: {
        'zh-Hans': '当前版本',
        'zh-Hant': '當前版本',
      },
      versionLatest: {
        'zh-Hans': '最新版本',
        'zh-Hant': '最新版本',
      },
      updateDetails: {
        'zh-Hans': '更新说明',
        'zh-Hant': '更新說明',
      },
      cardFeedback: {
        'zh-Hans': '卡片反馈',
        'zh-Hant': '卡片反饋',
      },
      cardInfo: {
        'zh-Hans': '卡片信息',
        'zh-Hant': '卡片資訊',
      },
      cardVersion: {
        'zh-Hans': '卡片版本',
        'zh-Hant': '卡片版本',
      },
      feedbackContent: {
        'zh-Hans': '反馈内容',
        'zh-Hant': '反饋內容',
      }
    }
    const lang = CONFIG().settings.lang
    return translations[key]?.[lang] || ''
  }

  function getToday() {
    return new Date().toLocaleDateString('sv-SE')
  }

  function setStorage(value) {
    Object.keys(localStorage)
      .filter(key => key.startsWith('JLPT_'))
      .forEach(key => localStorage.removeItem(key))
    const key = `JLPT_${getToday()}`
    localStorage.setItem(key, JSON.stringify(value))
  }

  function getStorage() {
    const key = `JLPT_${getToday()}`
    return JSON.parse(localStorage.getItem(key)) || {}
  }

  function getCurrentVersion(tags = '{{Tags}}') {
    return tags.split(/\s+|::/).find(part => part.startsWith('v')) || ''
  }

  async function getLatestReleaseInfo() {
    let latest, info
    try {
      const response = await fetch('https://api.github.com/repos/5mdld/anki-jlpt-decks/releases/latest')
      if (!response.ok) throw new Error(response.status)

      const data = await response.json()
      latest = `v${data.tag_name?.split('_')[0].replace(/^v/, '')}`
      info = data.body
        ?.replace(/`([^`]+)`/g, (m, p1) => `<code>${p1}</code>`)
        .replace(/\r?\n/g, '<br>')
        .replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
        .replace(/(!)?\[([^\]]+)\]\(((?:https?:\/\/[^\s()]+|\([^()]*\))+)\)/g, (m, bang, text, url) =>
          bang ? m : `<a target="_blank" rel="noopener noreferrer" href="${url}">${text}</a>`
        )
        .replace(/(^|<br>)[ \t]*-[ \t]+/g, '$1◦ ')
      info = info.replace(/(^|<br>)[ \t]*#{3}[ \t]*(.+?)(?=(?:<br>|$))/g, '$1<b>$2</b>')
    } catch (err) {
      console.error(err)
    }
    return { latest, info }
  }

  function createDialog(config = {}) {
    if (document.getElementById('DynamicDialog')) {
      closeDialog()
    }
    const modal = document.createElement('div')
    modal.id = 'DynamicDialog'
    modal.className = 'DialogOverlay'
    modal.innerHTML = `
    <div class="DialogContent">
      <h2 class="DialogTitle">${config.title || '提示'}</h2>
      <div class="DialogBody">${config.content || ''}</div>
      <div class="DialogFooter">
        ${config.cancelText ? `<a target="_blank" class="DialogButton CancelButton">${config.cancelText}</a>` : ''}
        <a target="_blank" class="DialogButton ConfirmButton">${config.confirmText || '确定'}</a>
      </div>
    </div>
    `
    modal.querySelector('.DialogContent').addEventListener('click', e => e.stopPropagation())
    modal.querySelector('.CancelButton')?.addEventListener('click', config.onCancel || closeDialog)
    modal.querySelector('.ConfirmButton').addEventListener('click', config.onConfirm || closeDialog)
    modal.addEventListener('click', closeDialog)
    document.getElementById('qa').appendChild(modal)
    document.body.style.overflow = 'hidden'
  }

  function closeDialog() {
    document.getElementById('DynamicDialog')?.remove()
    document.body.style.overflow = ''
  }

  async function checkVersion(force = false) {
    const current = getCurrentVersion()
    const storage = getStorage()
    const el = document.querySelector('.Feedback')

    const shouldFetch = force || (current && !storage.latest?.startsWith?.('v'))
    const { latest, info } = shouldFetch ? await getLatestReleaseInfo().then(res => (setStorage(res), res)) : storage

    const icon = el.querySelector('i')
    if (!getTags().isDeleted && current && latest && current < latest) {
      if (!icon) el.insertAdjacentHTML('afterbegin', '<i>🎉 </i>')
    } else {
      icon?.remove()
    }
    return { current, latest, info }
  }

  function feedback(e) {
    const feedbackBtn = document.querySelector('.Feedback')
    feedbackBtn.addEventListener('click', async e => {
      const current = getCurrentVersion()
      const { latest, info } = await checkVersion(!current)

      if (!current || current < latest) {
        createDialog({
          title: `
          <p>🎉 可用更新</p>
          <span>${getTranslation('updateReminder')}</span>
          `,
          content: `
          <p>📌 ${getTranslation('versionCurrent')}: ${current || 'Unknown'}</p>
          <p>🌟 ${getTranslation('versionLatest')}: ${latest || 'Unknown'}</p>
          <p>🚀 ${getTranslation('updateDetails')}: </p>
          <ul>${info || '- No details available'}</ul>
          `,
          cancelText: '取消',
          confirmText: '更新',
          onConfirm: () => {
            document.querySelector('a.ConfirmButton').href = 'https://github.com/5mdld/anki-jlpt-decks/releases/latest'
            closeDialog()
          }
        })
      } else {
        feedbackBtn.href = getFeedbackLink()
      }
    })
  }

  function getFeedbackLink(platform = 'github', VocabKanji = '{{text:kanji:VocabKanji}}', NoteID = '{{text:NoteID}}') {
    const current = getCurrentVersion()
    const urls = {
      github: `https://github.com/5mdld/anki-jlpt-decks/issues/new?${Object.entries({
        title: `[${getTranslation('cardFeedback')}] ${getToday()} 「${VocabKanji}」`,
        body: `### ${getTranslation('cardInfo')}\n- ${getTranslation('cardVersion')}: ${current}\n- VocabKanji: ${VocabKanji}\n- NoteID: ${NoteID}\n\n### ${getTranslation('feedbackContent')}\n`
      }).map(([key, value]) => `${key}=${encodeURIComponent(value)}`).join('&')}`,
      feishu: `https://ncn8ci2h7v0y.feishu.cn/share/base/form/shrcnTh5DRxtrGWtiWTkdBlSWze?${new URLSearchParams({
        NoteID,
        Version: current
      })}`,
    }
    return urls[platform]
  }

  function getPlatform() {
    return ['ios', 'android', 'mac', 'win'].find(p => document.documentElement.className.includes(p)) || 'other'
  }

  function getDevice() {
    if (isAnkiWeb()) return 'ankiweb'
    return ['iphone', 'ipad'].find(p => document.documentElement.className.includes(p)) || 'other'
  }

  function isAndroid() {
    return !!document.documentElement.className.includes('android')
  }

  function isAnkiWeb() {
    return !!document.getElementById('quiz')
  }

  function isBackSide() {
    return !!document.getElementById('BackSide')
  }

  function cleanWord(word = '{{text:kanji:VocabKanji}}') {
    return word.replace(/\[[^\]]*\]|\([^)]*\)|[0-9!@#$%^&*()_+\-='":\\|,.<>/?~～〜\s]+/g, '')
  }

  function lookUp(word = '{{text:kanji:VocabKanji}}') {
    const searchBtn = document.querySelector('.Search')
    searchBtn.addEventListener('click', e => {
      const cleaned = cleanWord()
      const dict = CONFIG().settings.dict[getPlatform()]
      const scheme = CONFIG().dictOptions[dict]
      if (!scheme) {
        createDialog({
          content: `<p class="text-center">${getTranslation('dictionaryTip')}</p>`,
          cancelText: '取消',
          confirmText: '查看文档',
          onConfirm: () => {
            document.querySelector('a.ConfirmButton').href = 'https://github.com/5mdld/anki-jlpt-decks/blob/main/README.md'
            closeDialog()
          }
        })
      }
      searchBtn.href = scheme.replace('{query}', encodeURIComponent(cleaned))
    })
  }

  function forcePlayback() {
    if (CONFIG().settings.playback !== 'force') return
    const el = document.querySelector('.VocabAudio .replay-button')
    if (el) el.click()
  }

  function hideFrontElements() {
    document.querySelector('#FrontSide ul').style.display = 'none'
  }

  function hideFurigana() {
    if (CONFIG().settings.display === 'kanji') {
      document.querySelectorAll('.VocabKanji rt').forEach(rt => {
        rt.style.display = isBackSide() ? 'ruby-text' : 'none'
      })
    }
  }

  function hideKanji() {
    if (CONFIG().settings.display === 'kana') {
      if (isBackSide()) {
        if (isAndroid()) {
          updateText('.VocabKanji span[lang="ja"]', '{{furigana:VocabKanji}}')
        }
        return
      }
      const isKatakana = getTags().isLoanword || /^[ァ-ヴー]+$/.test('{{VocabKanji}}')
      updateText('.VocabKanji span[lang="ja"]', isKatakana ? '{{kanji:VocabKanji}}' : '{{VocabFurigana}}')
    }
  }

  function audioStylePatch() {
    const target = document.querySelector('#FrontSide .VocabAudio')
    const source = document.querySelector('#qa > .VocabAudio')
    if (source && target && !target.innerHTML.trim()) {
      source.classList.remove('!hidden')
      target.replaceWith(source)
    }
  }

  function updateText(selector, text) {
    if (!text) return
    const el = document.querySelector(selector)
    if (el) {
      const hasRuby = el.innerHTML.includes('<ruby>')
      const hasHTMLTags = /<[^>]+>/i.test(text)
      ;(isAndroid() || hasRuby || hasHTMLTags)
        ? el.innerHTML = text
        : el.textContent = text
    }
  }

  function getTags(tags = '{{Tags}}') {
    const ignoreTags = ['$', '^', 'v']
    const deleteTags = ['del', 'delete', 'remove', 'outdated']

    const rawTags = tags.split(/\s+/)
      .map(tag => tag.split(/::|-/).pop())
      .filter(tag => tag && !ignoreTags.some(prefix => tag.startsWith(prefix)))

    const deleted = rawTags.filter(tag => deleteTags.includes(tag))
    const normal = rawTags.filter(tag => !deleteTags.includes(tag))

    const compareTags = (a, b) => {
      const getPriority = s => s.startsWith('N') ? 0 : /^[a-zA-Z]/.test(s) ? 1 : 2
      const pa = getPriority(a)
      const pb = getPriority(b)
      if (pa !== pb) return pa - pb
      return a.localeCompare(b)
    }
    const sorted = [...normal].sort(compareTags)

    return {
      all: [...sorted, ...deleted],
      formatted: [...sorted, ...deleted].join('・'),
      isDeleted: deleted.length > 0,
      isLoanword: sorted.includes?.('外'),
    }
  }

  function setLang() {
    updateText('.Level', getTags().formatted)
    updateText('.Feedback', getCurrentVersion() ? `${getCurrentVersion()}・${getTranslation('feedback')}` : getTranslation('feedback'))
    const lang = CONFIG().settings.lang
    if (lang === 'zh-Hant') {
      document.documentElement.lang = lang
      updateText('.VocabDef', '{{VocabDefTC}}')
      const defs = ['{{SentDefTC1}}', '{{SentDefTC2}}', '{{SentDefTC3}}', '{{SentDefTC4}}']
      defs.forEach((def, index) => updateText(`li:nth-child(${index + 1}) .SentDef`, def))
    }
  }

  function removeSpaces() {
    document.querySelectorAll('.VocabPlus, .VocabPoS, .SentKanji, .SentFurigana, .SentDef').forEach(el => {
      el.innerHTML = el.innerHTML
        .replace(/\s*\n\s*/g, '')
        .replace(/>\s+</g, '><')
        .replace(/(<[^>]+>)|\s+/g, (m, tag) => tag || '')
    })
  }

  function toggleBlur() {
    document.querySelectorAll('.VocabKanji, .VocabFurigana, .VocabPlus, .SentKanji').forEach(el =>
      el.classList.toggle('blur')
    )
  }

  function getType(index) {
    return ['{{SentType1}}', '{{SentType2}}', '{{SentType3}}', '{{SentType4}}'][index] || '例'
  }

  function setType() {
    ['.SentKanji', '.SentFurigana', '.SentDef', '.VocabPlus', '.VocabPoS'].forEach(selector => {
      document.querySelectorAll(selector).forEach((el, i) => {
        if (!el.textContent.trim() || el.querySelector('em')) return
        const typeMap = {
          'SentDef': '［訳］',
          'VocabPlus': '［補］',
          'SentKanji': `［${getType(i)}］`,
          'SentFurigana': `［${getType(i)}］`,
          'VocabPoS': '{{VocabPoS}}' ? '［{{VocabPoS}}］' : '［名］',
        }
        const type = typeMap[Object.keys(typeMap).find(key => el.className.includes(key))]
        el.insertAdjacentHTML('afterbegin', `<em lang='ja'>${type}</em>`)
      })
    })
  }

  function markWords(word = '{{text:kanji:VocabKanji}}') {
    const wordRegex = /[一-龠々ヵヶ]+|[ぁ-んァ-ヴー]+/g
    const kanjiRegex = /[一-龠々ヵヶ]/
    const parts = cleanWord().match(wordRegex) ?? []
    const regexParts = parts.map(part => {
      return kanjiRegex.test(part)
        ? `(?:<ruby><rb>${part}</rb><rt>[^<]+</rt></ruby>|${part})`
        : `(?:<ruby><rb>[^<]+</rb><rt>${part}</rt></ruby>|${part})`
    })
    const regex = new RegExp(regexParts.join('(?:\\s*?)'), 'g');

    ['.SentKanji', '.SentFurigana'].forEach(selector => {
      document.querySelectorAll(selector).forEach((el, i) => {
        const type = getType(i)
        if (el.querySelector('b, i, u, span, strong') || type !== '例') return
        el.innerHTML = el.innerHTML
          .replace(regex, match => `<strong>${match}</strong>`)
          .replace(/[～〜]/g, `<strong>${cleanWord()}</strong>`)
      })
    })
  }

  function highlightWords() {
    document.querySelectorAll('.SentFurigana').forEach((el, i) => {
      if (el.querySelector('b, i, u, span')) return
      const type = getType(i)
      const prefix = type.match(/^(関|対)/)
      if (!prefix) return
      const tag = prefix[1] === '関' ? 'synonym' : 'antonym'
      const content = el.innerHTML
        .replace(/^<em[^>]*>［[^]*?］<\/em>/, '')
        .trim()
        .replace(/^［[^]*?］/, '')
      el.innerHTML = el.querySelector('em') ? `<em lang='ja'>［${type}］</em><span class='${tag}'>${content}</span>` : `<span class='${tag}'>${content}</span>`
    })
  }

  function showHint() {
    if (isBackSide()) {
      document.querySelectorAll('a.hint').forEach(hint => hint.style.display = 'none')
    }
  }

  function setAnkiWebAudio() {
    if (!isAnkiWeb()) return

    document.querySelectorAll('.VocabAudio, .SentAudio').forEach(el => {
      const audio = el.querySelector('audio')
      if (!audio) return
      audio.removeAttribute('controls')
      el.insertAdjacentHTML('beforeend', '<a class="replay-button soundLink"><svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="29"/><path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z"/></svg></a>')
      el.querySelector('.replay-button').addEventListener('click', e => {
        e.preventDefault()
        document.querySelectorAll('audio').forEach(a => a !== audio && !a.paused && a.pause())
        audio.currentTime = 0
        audio.play()
      })
    })
  }

  function setEdgeTTS() {
    const { enable, hotkey, domain, params } = CONFIG().settings.tts
    if (enable === 'never') return

    const getVoice = () => {
      const voices = params.voiceName.split(',').map(v => v.trim())
      return voices.length === 1 ? voices[0] : voices[Math.floor(Math.random() * voices.length)]
    }

    // --- 单词在线发音 (VocabAudio) ---
    document.querySelectorAll('.VocabAudio').forEach(el => {
      if (enable === 'fallback' && (el.childNodes.length > 0 || el.querySelector('audio, .soundLink, a'))) return
      const text = cleanWord('{{text:kanji:VocabKanji}}') || '{{text:VocabFurigana}}'.trim()
      if (!text) return
      const queryString = new URLSearchParams({ ...params, text, voiceName: getVoice() })
      const audio = document.createElement('audio')
      audio.preload = 'none'
      domain.forEach(url => {
        const source = document.createElement('source')
        source.src = `${url}api/aiyue?${queryString}`
        source.type = 'audio/mpeg'
        audio.appendChild(source)
      })
      el.appendChild(audio)
      el.insertAdjacentHTML(
        'beforeend',
        '<a class="tts replay-button soundLink"><svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="29"/><path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z"/></svg></a>',
      )
      el.querySelector('.tts.replay-button')?.addEventListener('click', e => {
        e.preventDefault()
        document.querySelectorAll('audio').forEach(a => a !== audio && !a.paused && a.pause())
        audio.currentTime = 0
        audio.play()
      })
    })

    const getSentKanji = (index) => {
      const SentKanji = [
        '{{text:kanji:SentKanji1}}',
        '{{text:kanji:SentKanji2}}',
        '{{text:kanji:SentKanji3}}',
        '{{text:kanji:SentKanji4}}'
      ][index] || ''
      return SentKanji.replace(/・/g, '、')
    }
    document.querySelectorAll('.SentAudio').forEach((el, i) => {
      if (enable === 'fallback' && el.childNodes.length) return
      const text = getSentKanji(i)
      if (!text) return
      const queryString = new URLSearchParams({ ...params, text, voiceName: getVoice() })
      const audio = document.createElement('audio')
      audio.preload = 'none'
      domain.forEach(url => {
        const source = document.createElement('source')
        source.src = `${url}api/aiyue?${queryString}`
        source.type = 'audio/mpeg'
        audio.appendChild(source)
      })
      el.appendChild(audio)
      el.insertAdjacentHTML(
        'beforeend',
        '<a class="tts replay-button soundLink"><svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="29"/><path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z"/></svg></a>',
      )
      el.querySelector('.tts.replay-button').addEventListener('click', e => {
        e.preventDefault()
        document.querySelectorAll('audio').forEach(a => a !== audio && !a.paused && a.pause())
        audio.currentTime = 0
        audio.play()
      })
    })
    triggerAudioPlayback(hotkey)
  }

  function triggerAudioPlayback(hotkey) {
    if (!hotkey) return

    let currentAudioIndex = 0
    let isError = false
    document.addEventListener('keydown', e => {
      if (e.key.toLowerCase() === hotkey.toLowerCase()) {
        const audios = document.querySelectorAll('.CardSide audio')
        audios.forEach((audio) => {
          audio.pause()
          audio.currentTime = 0
        })
        if (!isError) currentAudioIndex = 0
        playNext(audios)
      }
    })
    function playNext(audios) {
      if (currentAudioIndex >= audios.length) return
      const audio = audios[currentAudioIndex]
      audio.play().then(() => {
        audio.onended = () => {
          currentAudioIndex++
          playNext(audios)
        }
        isError = false
      }).catch(() => (isError = true))
    }
  }

  function autoCopyWord() {
    if (!CONFIG().settings.autoCopy[getDevice()]) return
    setTimeout(async () => {
      try {
        await navigator.clipboard.writeText(cleanWord())
      } catch (err) {
        console.error(err)
      }
    }, 0)
  }

  function setupCard() {
    lookUp()
    feedback()
    setLang()
    setType()
    markWords()
    hideKanji()
    removeSpaces()
    checkVersion()
  }
</script>

<script>
  setupCard()
  setEdgeTTS()
  hideFurigana()
  setAnkiWebAudio()
</script>
''';

  static const String defaultAfmt = r'''
<!-- Card1 [日-中] 背面 -->

{{FrontSide}}

<div class="VocabAudio !hidden">{{VocabAudio}}</div>

<main id="BackSide" class="CardSide">
  <section class="Answer">
    <h2 class="VocabFurigana">
      <span lang="ja">{{kana:VocabFurigana}}</span>
      <span class="VocabPitch">{{VocabPitch}}</span>
    </h2>

    <h3 class="VocabPoS LabelIndent2">
      <div class="VocabDefWrap">
        <span class="VocabDef" id="VocabDefDisplay" lang="ja">{{#VocabDefJa}}{{VocabDefJa}}{{/VocabDefJa}}{{^VocabDefJa}}{{#VocabPlus}}{{VocabPlus}}{{/VocabPlus}}{{^VocabPlus}}{{VocabDefSC}}{{/VocabPlus}}{{/VocabDefJa}}</span>
        {{#VocabDefJa}}
        <a class="DefSwitchBtn" id="DefSwitchBtn" href="javascript:void(0);" title="切换为中文翻译">译</a>
        {{/VocabDefJa}}
        {{^VocabDefJa}}
        {{#VocabPlus}}
        <a class="DefSwitchBtn" id="DefSwitchBtn" href="javascript:void(0);" title="切换为中文翻译">译</a>
        {{/VocabPlus}}
        {{/VocabDefJa}}
      </div>
      <div id="DefStoreSc" style="display:none;">{{VocabDefSC}}</div>
      <div id="DefStoreJa" style="display:none;">{{#VocabDefJa}}{{VocabDefJa}}{{/VocabDefJa}}{{^VocabDefJa}}{{#VocabPlus}}{{VocabPlus}}{{/VocabPlus}}{{/VocabDefJa}}</div>
    </h3>
  </section>

  <ul class="SentenceList">
    {{#SentKanji1}}
    <li class="Sentence">
      <div class="SentGroup">
        <h3 class="SentFurigana LabelIndent" lang="ja">
          {{#SentFurigana1}}{{furigana:SentFurigana1}}{{/SentFurigana1}}
          {{^SentFurigana1}}{{furigana:SentKanji1}}{{/SentFurigana1}}
        </h3>
        <h3 class="SentDef LabelIndent">{{SentDefSC1}}</h3>
      </div>
      <div class="SentAudio">{{SentAudio1}}</div>
    </li>
    {{/SentKanji1}}

    {{#SentKanji2}}
    <li class="Sentence">
      <div class="SentGroup">
        <h3 class="SentFurigana LabelIndent" lang="ja">
          {{#SentFurigana2}}{{furigana:SentFurigana2}}{{/SentFurigana2}}
          {{^SentFurigana2}}{{furigana:SentKanji2}}{{/SentFurigana2}}
        </h3>
        <h3 class="SentDef LabelIndent">{{SentDefSC2}}</h3>
      </div>
      <div class="SentAudio">{{SentAudio2}}</div>
    </li>
    {{/SentKanji2}}

    {{#SentKanji3}}
    <li class="Sentence">
      <div class="SentGroup">
        <h3 class="SentFurigana LabelIndent" lang="ja">
          {{#SentFurigana3}}{{furigana:SentFurigana3}}{{/SentFurigana3}}
          {{^SentFurigana3}}{{furigana:SentKanji3}}{{/SentFurigana3}}
        </h3>
        <h3 class="SentDef LabelIndent">{{SentDefSC3}}</h3>
      </div>
      <div class="SentAudio">{{SentAudio3}}</div>
    </li>
    {{/SentKanji3}}

    {{#SentKanji4}}
    <li class="Sentence">
      <div class="SentGroup">
        <h3 class="SentFurigana LabelIndent" lang="ja">
          {{#SentFurigana4}}{{furigana:SentFurigana4}}{{/SentFurigana4}}
          {{^SentFurigana4}}{{furigana:SentKanji4}}{{/SentFurigana4}}
        </h3>
        <h3 class="SentDef LabelIndent">{{SentDefSC4}}</h3>
      </div>
      <div class="SentAudio">{{SentAudio4}}</div>
    </li>
    {{/SentKanji4}}

  </ul>
</main>

<style>
  .VocabDefWrap {
    display: inline-flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 6px;
    text-indent: 0;
  }
  .DefSwitchBtn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    text-indent: 0 !important;
    font-size: 11px;
    font-weight: 600;
    line-height: 1;
    color: #0284c7;
    background: #f0f9ff;
    border: 1px solid #bae6fd;
    border-radius: 10px;
    padding: 2px 7px;
    cursor: pointer;
    user-select: none;
    text-decoration: none !important;
    vertical-align: middle;
    box-sizing: border-box;
    white-space: nowrap;
  }
  .DefSwitchBtn:active {
    background: #0284c7;
    color: #ffffff;
  }
</style>

<script>
  function setupDefSwitch() {
    const btn = document.getElementById('DefSwitchBtn')
    const display = document.getElementById('VocabDefDisplay')
    const storeSc = document.getElementById('DefStoreSc')
    const storeJa = document.getElementById('DefStoreJa')
    if (!btn || !display || !storeSc || !storeJa) return
    if (!storeSc.textContent.trim() || !storeJa.textContent.trim()) {
      btn.style.display = 'none'
      return
    }

    let isJa = true
    btn.addEventListener('click', e => {
      e.preventDefault()
      e.stopPropagation()
      isJa = !isJa
      if (isJa) {
        display.innerHTML = storeJa.innerHTML
        display.setAttribute('lang', 'ja')
        btn.textContent = '译'
        btn.setAttribute('title', '切换为中文翻译')
      } else {
        display.innerHTML = storeSc.innerHTML
        display.setAttribute('lang', 'zh-Hans')
        btn.textContent = '原'
        btn.setAttribute('title', '切换为日文原文')
      }
    })
  }

  setupDefSwitch()
  showHint()
  setEdgeTTS()
  autoCopyWord()
  highlightWords()
  audioStylePatch()
  hideFrontElements()
  typeof onShownHook !== 'undefined' ? onShownHook.push(forcePlayback) : forcePlayback()

  // 安卓平台需要重复正面调用的方法
  if (isAndroid()) setupCard()
</script>
''';

  static const String defaultCss = r'''
@charset "UTF-8";
.\!hidden {
  display: none !important;
}

.text-center {
  text-align: center;
}

*,
::after,
::before {
  box-sizing: border-box;
  border-width: 0;
  border-style: solid;
}

:host,
html {
  line-height: 1.5;
  -webkit-text-size-adjust: 100%;
  font-feature-settings: normal;
  font-variation-settings: normal;
  -webkit-tap-highlight-color: transparent;
}

body {
  margin: 0;
  line-height: inherit;
}

h1,
h2,
h3,
a,
p {
  font-size: inherit;
  font-weight: inherit;
  color: inherit;
  text-decoration: inherit;
  margin: 0;
}

ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

@font-face {
  font-family: 'Source Han Serif CN';
  src: url('_SourceHanSerifCN-Medium.otf') format('opentype');
  font-weight: 500;
  font-display: swap;
}

@font-face {
  font-family: 'Source Han Serif TW';
  src: url('_SourceHanSerifTW-Medium.otf') format('opentype');
  font-weight: 500;
  font-display: swap;
}

@font-face {
  font-family: 'Source Han Serif JP';
  src: url('_SourceHanSerifJP-Medium.otf') format('opentype');
  font-weight: 500;
  font-display: swap;
}

body,
:lang(zh-Hans) {
  font-family: 'Source Han Serif CN', 'Source Han Serif JP', serif;
}

:lang(zh-Hant) {
  font-family: 'Source Han Serif TW', 'Source Han Serif JP', 'Source Han Serif CN', serif;
}

:lang(ja) {
  font-family: 'Source Han Serif JP', 'Source Han Serif CN', serif;
}

.VocabKanji :lang(ja) {
  font-family: 'YuKyokasho Yoko', 'UD Digi Kyokasho NK-R', 'Source Han Serif JP', serif;
}

:root {
  --fg: #1f2937;
  --fg-subtle: #737373;
  --canvas: #fffaf0;
  --canvas-elevated: white;
  --canvas-inset: #f9fafb;
  --border: #d1d5db;
  --border-subtle: #e4e4e4;
  --border-radius: 7px;
  --button-bg: #f3f3f3;
  --button-gradient-start: #f7f7f7;
  --button-primary-bg: #306bec;
  --button-primary-gradient-start: #3b82f6;
  --svg-path: #555;
  --fg-highlight-red: #ef4444;
  --fg-highlight-orange: #f97316;
  --fg-highlight-lime: #84cc16;
  --fg-highlight-teal: #14b8a6;
  --fg-highlight-blue: #3b82f6;
  --fg-highlight-indigo: #6366f1;
  --fg-highlight-purple: #a855f7;
  --font-size: 16px;
  --text-xs: 12px;
  --text-sm: 14px;
  --text-lg: 18px;
  --text-xl: 20px;
  --text-2xl: 24px;
  --text-4xl: 36px;
  --label-indent-padding: calc(52 / 18 * 1em);
  --label-indent-text: calc(-54 / 18 * 1em);
  --label-indent2-padding: calc(11 / 18 * 1em);
  --label-indent2-text: calc(-13 / 18 * 1em);
  --audio-button-size: calc(32 / 18 * 1em);
  --modal-padding-top: 12vh;
  --modal-max-width: 80%;
}

:root.night-mode,
:root .night_mode,
:root .nightMode,
[data-bs-theme='dark'] {
  --fg: #e5e7eb;
  --canvas: #2c2c2c;
  --canvas-elevated: #363636;
  --canvas-inset: #2c2c2c;
  --border: #494949;
  --border-subtle: #252525;
  --border-radius: 7px;
  --button-bg: #404040;
  --button-gradient-start: #4a4a4a;
  --button-primary-bg: #2652cf;
  --button-primary-gradient-start: #2f67e1;
  --svg-path: #e5e7eb;
  --fg-highlight-red: #fca5a5;
  --fg-highlight-orange: #fdba74;
  --fg-highlight-lime: #bef264;
  --fg-highlight-teal: #5eead4;
  --fg-highlight-blue: #93c5fd;
  --fg-highlight-indigo: #a5b4fc;
  --fg-highlight-purple: #d8b4fe;
  --font-size: 16px;
}

@media (min-width: 475px) {
  :root {
    --text-xs: 14px;
    --text-sm: 16px;
    --text-lg: 22px;
    --text-xl: 24px;
    --text-2xl: 28px;
    --text-4xl: 40px;
    --label-indent-padding: calc(64 / 22 * 1em);
    --label-indent-text: calc(-66 / 22 * 1em);
    --label-indent2-padding: calc(14 / 22 * 1em);
    --label-indent2-text: calc(-16 / 22 * 1em);
    --modal-padding-top: 15vh;
    --modal-max-width: 28em;
  }
}

.card {
  text-align: left;
  color: var(--fg);
  background-color: var(--canvas);
  font-size: var(--text-lg);
}

.card.nightMode {
  background-color: var(--canvas);
}

.card a.hint {
  cursor: pointer;
  color: inherit;
}

.card a.hint[style*='display: none']+div.hint {
  display: inline !important;
}

.card .blur:has(a.hint) {
  filter: none;
}

.card em,
.card ruby rt,
.card .blur b,
.card .blur span,
.card .Top,
.card .Search,
.card .Feedback,
.card .VocabPitch,
.card .DialogContent {
  -webkit-touch-callout: none;
  -webkit-user-select: none;
  user-select: none;
}

.card u,
.card i,
.card em,
.card b,
.card strong {
  font-style: normal;
  font-weight: inherit;
  text-decoration: none;
}

.replay-button {
  margin: 0;
  cursor: pointer;
  align-items: center;
  justify-content: center;
}

.replay-button svg {
  width: var(--audio-button-size);
  height: var(--audio-button-size);
}

.replay-button svg circle {
  fill: var(--canvas);
  stroke: var(--svg-path);
  stroke-width: 2.5px;
}

.replay-button svg path {
  fill: var(--svg-path);
}

.tts.replay-button svg circle {
  stroke: var(--fg-highlight-purple);
}

.tts.replay-button svg path {
  fill: var(--fg-highlight-purple);
}

.CardSide {
  width: 100%;
  margin: 0 auto;
  padding: 0 12px;
}

.LabelIndent {
  padding-left: var(--label-indent-padding);
  text-indent: var(--label-indent-text);
}

.LabelIndent2 {
  padding-left: var(--label-indent2-padding);
  text-indent: var(--label-indent2-text);
}

.Top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 4px 0;
  color: var(--fg-subtle);
  font-size: 14px;
}

a.Feedback {
  color: var(--fg-subtle);
}

.Question {
  min-height: calc(var(--text-4xl) * 2.5);
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border);
  border-radius: var(--border-radius) var(--border-radius) 0 0;
  padding: 0 0.5em;
}

.VocabAudio {
  width: var(--audio-button-size);
}

.VocabAudio,
.SentAudio {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  gap: 0.2em;
}

.SentDef:empty,
.SentAudio:empty {
  display: none;
}

.VocabKanji {
  flex: 1 1 0%;
  text-align: center;
  font-size: var(--text-4xl);
}

.VocabPitch {
  vertical-align: text-top;
  font-size: 16px;
  margin-left: -0.3em;
}

.VocabKanji .VocabPitch {
  margin-left: -0.6em;
}

.Search {
  display: flex;
  flex-direction: column;
  font-size: var(--text-xl);
}

.SentenceList {
  min-height: 310px;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  row-gap: 12px;
  border: 1px solid var(--border);
  border-top-width: 0;
  border-radius: 0 0 var(--border-radius) var(--border-radius);
  padding: 12px 8px 12px 0;
}

.Sentence {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  column-gap: 2px;
}

.SentKanji {
  flex: 1 1 0%;
  color: var(--fg-subtle);
  line-height: 1.625;
  padding-top: 0.26em;
}

.SentKanji span {
  color: inherit !important;
  background-color: inherit !important;
  font-weight: inherit !important;
  font-style: inherit !important;
}

.VocabPlus.blur,
.VocabKanji.blur,
.VocabFurigana.blur {
  filter: blur(10px);
}

.SentKanji.blur b,
.SentKanji.blur strong {
  color: var(--canvas);
  border-bottom: 1px solid var(--border);
}

.Answer {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  row-gap: 6px;
  border: 1px solid var(--border);
  border-top-width: 0;
  padding: 8px 8px 8px 0;
}

.VocabFurigana {
  width: 100%;
  padding-left: 0.4em;
  font-size: var(--text-2xl);
}

.VocabPlus {
  width: 100%;
  color: var(--fg-subtle);
}

.SentGroup {
  display: grid;
  flex: 1 1 0%;
  row-gap: 2px;
  min-width: 0;
  overflow: hidden;
}

.SentFurigana {
  overflow-wrap: break-word;
  word-break: break-all;
  line-height: 1.625;
  line-break: anywhere;
  -webkit-line-break: anywhere;
  min-width: 0;
  max-width: 100%;
}

.SentFurigana b,
.SentFurigana strong {
  color: var(--fg-highlight-orange);
  /* text-decoration-line: underline; */
  /* text-underline-offset: 5px; */
}

.SentFurigana i {
  /* color: var(--fg-highlight-lime); */
  font-style: italic;
}

.SentFurigana u {
  /* color: var(--fg-highlight-orange); */
  /* text-decoration-color: var(--fg-highlight-orange); */
  text-decoration-line: underline;
  text-underline-offset: 5px;
}

.SentFurigana .antonym {
  color: var(--fg-highlight-blue);
}

.SentFurigana .synonym {
  color: var(--fg-highlight-teal);
}

.SentDef {
  color: var(--fg-subtle);
}

/* --- 针对屏幕尺寸特殊样式 --- */
@media (min-width: 475px) {
  .CardSide {
    padding: 0 24px;
    max-width: 720px;
  }

  .SentenceList {
    min-height: 364px;
  }

  .VocabAudio,
  .SentAudio {
    flex-direction: row;
  }
}

@media (min-width: 1024px) {
  .CardSide {
    max-width: 1024px;
  }
}

/* --- 若需不限制宽度开启以下样式 --- */
/* .CardSide {
  max-width: none !important;
} */

/* --- AnkiWeb 样式 --- */
#quiz {
  --canvas: #fff;
}

#quiz #qa {
  margin-top: 0;
}

#quiz .CardSide {
  padding: 0;
}

#quiz .DialogOverlay {
  display: flex;
  position: absolute;
  inset: 0;
  height: 100%;
  padding-top: 0;
  overflow: hidden;
}

#quiz .DialogContent {
  display: flex;
  flex-direction: column;
  margin-top: var(--modal-padding-top);
  max-height: calc(100% - var(--modal-padding-top));
  overflow: hidden;
}

#quiz .DialogBody {
  overflow: auto;
  min-height: 0;
}

#quiz .DialogFooter {
  position: sticky;
  bottom: 0;
  background: var(--canvas-inset);
}

/* --- iOS 思源宋体振假名高度修复 --- */
.ios rt,
.safari rt {
  transform: translateY(0.6em);
}

/* --- iOS 若安装教科书字体开启以下样式 --- */
.ios .VocabKanji rt,
.safari .VocabKanji rt {
  /* transform: 0; */
}

/* --- 安卓平台使用系统默认字体 --- */
.android body,
.android :lang(zh),
.android :lang(ja),
.android .VocabKanji :lang(ja) {
  font-family: ui-sans-serif, system-ui, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, 'Noto Sans', sans-serif;
}

/* --- 移动端不显示左右边框和底部边框 --- */
.ios *,
.android * {
  border-left-width: 0;
  border-right-width: 0;
  border-radius: 0;
}

.ios .SentenceList,
.android .SentenceList {
  border-bottom-width: 0;
  min-height: 0;
}

/* --- 弹出模态框样式 --- */
.DialogOverlay {
  /* display: none; */
  display: flex;
  position: fixed;
  inset: 0;
  z-index: 10;
  height: 100vh;
  align-items: flex-start;
  justify-content: center;
  overflow: hidden;
  padding-top: var(--modal-padding-top);
  background-color: rgb(0 0 0 / 0.5);
  backdrop-filter: blur(1px);

}

.DialogTitle {
  text-align: center;
  font-size: var(--text-xl);
  letter-spacing: 2px;
  border-bottom: 1px solid var(--border);
  padding-bottom: 12px;
}

.DialogTitle span {
  display: block;
  font-size: var(--text-sm);
  letter-spacing: 0;
  padding-top: 2px;
}

.DialogContent {
  margin-left: auto;
  margin-right: auto;
  max-width: var(--modal-max-width);
  width: 100%;
  border-radius: var(--border-radius);
  background-color: var(--canvas-inset);
  padding: 22px 16px;
  font-size: var(--text-sm);
  display: flex;
  flex-direction: column;
  max-height: calc(100vh - var(--modal-padding-top));
  overflow: hidden;
}

@supports (height: 100dvh) {
  .DialogOverlay  { height: 100dvh; }
  .DialogContent  { max-height: calc(100dvh - var(--modal-padding-top)); }
}

.DialogBody {
  margin: 0 auto;
  max-width: 26em;
  display: flex;
  flex-direction: column;
  row-gap: 6px;
  padding: 10px 0 20px;
  overflow: auto;
  min-height: 0; 
}

.DialogBody ul {
  font-size: var(--text-xs);
  padding-left: 1.2em;
  white-space: pre-wrap;
}

.DialogBody ul code {
  background-color: var(--button-bg);
  border-radius: 4px;
  border: 1px solid var(--border-subtle);
  color: var(--fg);
  vertical-align: text-bottom;
  padding: .2em .4em;
  font-size: 85%;
  white-space: break-spaces;
}

.DialogBody ul b {
  font-weight: 600;
}

.DialogFooter {
  margin: 0 10px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  column-gap: 20px;
}

.DialogButton {
  width: 100%;
  cursor: pointer;
  border: 1px solid var(--border-subtle);
  border-radius: var(--border-radius);
  background-color: var(--button-bg);
  padding: 6px 0;
  text-align: center;
  color: var(--fg);
  letter-spacing: 2px;
}

.DialogButton:hover {
  background-color: var(--button-gradient-start);
}

.DialogButton.CancelButton {
  color: var(--fg);
  background-color: var(--button-bg);
}

.DialogButton.ConfirmButton {
  color: #fff;
  background-color: var(--button-primary-bg);
}

.DialogButton.ConfirmButton:hover {
  background-color: var(--button-primary-gradient-start);
}

/* --- 切换按钮样式 --- */
.VocabDefWrap {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  text-indent: 0;
}
.DefSwitchBtn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  text-align: center;
  text-indent: 0 !important;
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  color: #0284c7;
  background: #f0f9ff;
  border: 1px solid #bae6fd;
  border-radius: 10px;
  padding: 2px 7px;
  cursor: pointer;
  user-select: none;
  text-decoration: none !important;
  vertical-align: middle;
  box-sizing: border-box;
  white-space: nowrap;
}
.DefSwitchBtn:active {
  background: #0284c7;
  color: #ffffff;
}
''';

    final AnkidroidBridge _bridge;

  AnkiExportService({AnkidroidBridge? bridge})
      : _bridge = bridge ?? NativeAnkidroidBridge();

  @override
  Future<bool> isAnkiDroidAvailable() async {
    if (!_bridge.isPlatformSupported) return false;
    try {
      return await _bridge.requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_bridge.isPlatformSupported) return false;
    try {
      return await _bridge.requestPermission();
    } catch (_) {
      return false;
    }
  }

  static const Set<String> _vocabKanjiAliases = {
    'vocabkanji',
    'vocabularykanji',
    'kanji',
    'word',
    'front',
    'front1',
    'frontside',
    'cardfront',
    'cardfront1',
    'card1front',
    'expression',
    'headword',
    'term',
    'vocab',
    'vocabulary',
    'question',
    'q',
    'japanese',
    'targetword',
    'target',
    '单词',
    '词',
    '表记',
    '词汇',
    '正面',
    '问题',
    '単語',
    '表記',
    '見出し語',
    '見出し',
    '語',
  };

  static const Set<String> _vocabFuriganaAliases = {
    'vocabfurigana',
    'vocabularyfurigana',
    'furigana',
    'reading',
    'kana',
    'hiragana',
    'pronunciation',
    'yomi',
    'vocabreading',
    'vocabularyreading',
    '读音',
    '假名',
    '读法',
    '发音',
    '平假名',
    '平仮名',
    'ひらがな',
    'ふりがな',
    '読み',
    'よみ',
    '振仮名',
    '振り仮名',
  };

  static const Set<String> _vocabPoSAliases = {
    'vocabpos',
    'vocabularypos',
    'pos',
    'partofspeech',
    '词性',
    '品詞',
  };

  static const Set<String> _vocabDefScAliases = {
    'vocabdef',
    'vocabularydef',
    'vocabdefsc',
    'vocabularydefsc',
    'defsc',
    'meaning',
    'meaningsc',
    'scmeaning',
    'definitionsc',
    'scdef',
    'defchinese',
    'meaningchinese',
    'translationchinese',
    'glossary',
    'back',
    'back1',
    'backside',
    'cardback',
    'cardback1',
    'card1back',
    'definition',
    'def',
    'translation',
    'answer',
    'a',
    'meaningcn',
    'defcn',
    'translationcn',
    '释义',
    '中文释义',
    '中文',
    '背面',
    '答案',
    '意味',
    '和訳',
    '中訳',
    '翻訳',
  };

  static const Set<String> _vocabDefJaAliases = {
    'vocabdefja',
    'vocabularydefja',
    'defja',
    'definitionja',
    'meaningja',
    'jameaning',
    'jadef',
    'defjapanese',
    'meaningjapanese',
    'translationjapanese',
    '日日释义',
    '日文释义',
    '日语释义',
    '日日',
    '国語',
    '国語释义',
  };

  static const Set<String> _sentKanji1Aliases = {
    'sentkanji1',
    'sentkanji',
    'sent1kanji',
    'sentence1kanji',
    'sentence1',
    'sentence',
    'example1',
    'example',
    'examplesentence1',
    'examplesentence',
    'sent1',
    'sent',
    '例句1',
    '例句',
    '例文1',
    '例文',
  };

  static const Set<String> _sentFurigana1Aliases = {
    'sentfurigana1',
    'sentfurigana',
    'sent1furigana',
    'sentence1furigana',
    'sentreading1',
    'sentreading',
    'sent1reading',
    'sentencefurigana1',
    'sentencefurigana',
    'sentencereading1',
    'sentencereading',
    'sentence1reading',
    'examplereading1',
    'examplereading',
    '例句假名1',
    '例句假名',
    '例句读音1',
    '例句读音',
    '例文假名1',
    '例文假名',
    '例文読み1',
    '例文読み',
  };

  static const Set<String> _sentDefSc1Aliases = {
    'sentdefsc1',
    'sentdefsc',
    'sent1defsc',
    'sentence1defsc',
    'sentdef1',
    'sentdef',
    'sent1def',
    'senttrans1',
    'senttrans',
    'sent1trans',
    'sentence1trans',
    'sentmeaning1',
    'sentmeaning',
    'sent1meaning',
    'sentence1meaning',
    'examplesentencedef1',
    'examplesentencedef',
    'sentencetranslation1',
    'sentencetranslation',
    'sentence1translation',
    'sentencemeaning',
    'sentencemeaning1',
    'examplemeaning1',
    'examplemeaning',
    'exampletrans1',
    'exampletrans',
    '例句翻译1',
    '例句释义1',
    '例句翻译',
    '例句释义',
    '例文訳1',
    '例文訳',
  };

  static const Set<String> _sentKanji2Aliases = {
    'sentkanji2',
    'sent2kanji',
    'sentence2kanji',
    'sentence2',
    'example2',
    'examplesentence2',
    'sent2',
    '例句2',
    '例文2',
  };

  static const Set<String> _sentFurigana2Aliases = {
    'sentfurigana2',
    'sent2furigana',
    'sentence2furigana',
    'sentreading2',
    'sent2reading',
    'sentencefurigana2',
    'sentencereading2',
    'sentence2reading',
    'examplereading2',
    '例句假名2',
    '例句读音2',
    '例文假名2',
    '例文読み2',
  };

  static const Set<String> _sentDefSc2Aliases = {
    'sentdefsc2',
    'sent2defsc',
    'sentence2defsc',
    'sentdef2',
    'sent2def',
    'senttrans2',
    'sent2trans',
    'sentence2trans',
    'sentmeaning2',
    'sent2meaning',
    'sentence2meaning',
    'examplesentencedef2',
    'sentencetranslation2',
    'sentence2translation',
    'sentencemeaning2',
    'examplemeaning2',
    'exampletrans2',
    '例句翻译2',
    '例句释义2',
    '例文訳2',
  };

  static const Set<String> _sourceDictAliases = {
    'sourcedict',
    'source',
    'dict',
    'dictionary',
    '来源',
    '词典',
    '词典来源',
    '辞書',
    '出典',
  };

  static const Set<String> _noteIdAliases = {
    'noteid',
    'id',
    'uid',
    '编号',
    '卡片编号',
  };

  static const Set<String> _tagsAliases = {
    'tags',
    'tag',
    'level',
    '标签',
    '分类',
    'タグ',
  };

  static const Set<String> _sourceUrlAliases = {
    'sourceurl',
    'url',
    'link',
    '来源链接',
    '链接',
  };

  static const Set<String> _alt1Aliases = {
    'alt1',
    'alt',
    'alternative1',
  };

  static const Set<String> _vocabPitchAliases = {
    'vocabpitch',
    'vocabularypitch',
    'pitch',
    'pitchaccent',
    'accent',
    'vocabaccent',
    '声调',
    '音调',
    '音调核',
    '音調',
    'アクセント',
    'アクセント核',
  };

  static const Set<String> _vocabDefTcAliases = {
    'vocabdeftc',
    'vocabularydeftc',
    'deftc',
    'meaningtc',
    'tcmeaning',
    'definitiontc',
    'tcdef',
    'glossarytc',
    'traditionalchinese',
    '繁体',
    '繁体释义',
    '繁体中文',
    '繁體',
    '繁體釋義',
    '繁體中文',
  };

  static const Set<String> _vocabPlusAliases = {
    'vocabplus',
    'vocabularyplus',
    'plus',
    'supplement',
    'addition',
    '补充',
    '补充说明',
    '追記',
  };

  static const Set<String> _vocabAudioAliases = {
    'vocabaudio',
    'vocabularyaudio',
    'audio',
    'sound',
    'sound1',
    'vocabsound',
    'pronunciationsound',
    'wordaudio',
    'wordsound',
    '音频',
    '单词音频',
    '发音音频',
    '音声',
    '発音',
  };

  static const Set<String> _sentType1Aliases = {
    'senttype1',
    'senttype',
    'sentencetype1',
    'sentencetype',
    'type1',
    '例句类型1',
    '例句类型',
  };

  static const Set<String> _sentType2Aliases = {
    'senttype2',
    'sentencetype2',
    'type2',
    '例句类型2',
  };

  static const Set<String> _sentAudio1Aliases = {
    'sentaudio1',
    'sentaudio',
    'sentenceaudio1',
    'sentenceaudio',
    'sentsound1',
    'sentsound',
    'sentencesound1',
    'sentencesound',
    '例句音频1',
    '例句音频',
  };

  static const Set<String> _sentAudio2Aliases = {
    'sentaudio2',
    'sentenceaudio2',
    'sentsound2',
    'sentencesound2',
    '例句音频2',
  };

  static const Set<String> _sentDefTc1Aliases = {
    'sentdeftc1',
    'sent1deftc',
    'sentdeftc',
    'sentencedeftc1',
    'sentence1deftc',
    'senttranstc1',
    'sent1transtc',
    'sentencetranstc1',
    'sentence1transtc',
    '例句繁体1',
    '例句繁体翻译1',
    '例句繁体',
    '例句繁体翻译',
  };

  static const Set<String> _sentDefTc2Aliases = {
    'sentdeftc2',
    'sent2deftc',
    'sentencedeftc2',
    'sentence2deftc',
    'senttranstc2',
    'sent2transtc',
    'sentencetranstc2',
    'sentence2transtc',
    '例句繁体2',
    '例句繁体翻译2',
  };

  /// 根据字段名将 VocabularyEntry 属性精准映射为对应字段值
  /// 彻底废除索引盲目回退，未识别的扩展字段统一安全填充空字符串，防止错位
  static String mapFieldValue(
    String fieldName,
    VocabularyEntry entry, [
    int? fallbackIndex,
    bool hasExplicitDefJa = false,
  ]) {
    final norm = fieldName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5\u3040-\u30ff\u3400-\u4dbf]'), '');

    if (_vocabPitchAliases.contains(norm)) {
      return entry.vocabPitch;
    }
    if (_vocabKanjiAliases.contains(norm)) {
      return entry.vocabKanji.trim();
    }
    if (_vocabFuriganaAliases.contains(norm)) {
      return entry.vocabFurigana;
    }
    if (_vocabPoSAliases.contains(norm)) {
      return entry.vocabPoS;
    }
    if (_vocabDefScAliases.contains(norm)) {
      return entry.vocabDefSc;
    }
    if (_vocabDefTcAliases.contains(norm)) {
      return '';
    }
    if (_vocabPlusAliases.contains(norm)) {
      // 若目标模型已包含独立的 VocabDefJa 字段，VocabPlus 保留为空，防止与 VocabDefJa 重复；
      // 仅当目标模型缺少 VocabDefJa（如原版 JLPT 牌组）时，才降级承载 entry.vocabDefJa
      return hasExplicitDefJa ? '' : entry.vocabDefJa;
    }
    if (_vocabAudioAliases.contains(norm)) {
      return '';
    }
    if (_vocabDefJaAliases.contains(norm)) {
      return entry.vocabDefJa;
    }
    if (_sentType1Aliases.contains(norm) || _sentType2Aliases.contains(norm)) {
      return '';
    }
    if (_sentAudio1Aliases.contains(norm) || _sentAudio2Aliases.contains(norm)) {
      return '';
    }
    if (_sentDefTc1Aliases.contains(norm) || _sentDefTc2Aliases.contains(norm)) {
      return '';
    }
    if (_sentKanji1Aliases.contains(norm)) {
      return entry.sentKanji1 ?? '';
    }
    if (_sentFurigana1Aliases.contains(norm)) {
      return WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana1 ?? '',
        entry.vocabKanji,
      );
    }
    if (_sentDefSc1Aliases.contains(norm)) {
      return entry.sentDefSc1 ?? '';
    }
    if (_sentKanji2Aliases.contains(norm)) {
      return entry.sentKanji2 ?? '';
    }
    if (_sentFurigana2Aliases.contains(norm)) {
      return WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana2 ?? '',
        entry.vocabKanji,
      );
    }
    if (_sentDefSc2Aliases.contains(norm)) {
      return entry.sentDefSc2 ?? '';
    }
    if (_sourceDictAliases.contains(norm)) {
      return entry.sourceDict;
    }
    if (_noteIdAliases.contains(norm)) {
      return entry.id?.toString() ?? '';
    }
    if (_sourceUrlAliases.contains(norm)) {
      return entry.sourceUrl;
    }
    if (_tagsAliases.contains(norm)) {
      return entry.sourceDict.isNotEmpty ? entry.sourceDict : 'AI生词本';
    }
    if (_alt1Aliases.contains(norm)) {
      return '';
    }

    // 彻底废除 fallbackIndex 盲目回退！未识别字段一律安全返回空字符串，杜绝错位污染
    return '';
  }

  /// 将单词实体转换为 13 个标准字段列表
  static List<String> entryToFields(VocabularyEntry entry) {
    return [
      entry.vocabKanji.trim(),
      entry.vocabFurigana,
      entry.vocabPoS,
      entry.vocabDefSc,
      entry.vocabDefJa,
      entry.sentKanji1 ?? '',
      WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana1 ?? '',
        entry.vocabKanji,
      ),
      entry.sentDefSc1 ?? '',
      entry.sentKanji2 ?? '',
      WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana2 ?? '',
        entry.vocabKanji,
      ),
      entry.sentDefSc2 ?? '',
      entry.sourceDict,
      entry.id?.toString() ?? '',
    ];
  }

  /// 将单词实体按目标模型实际字段列表动态自适应映射为字段值列表
  static List<String> entryToModelFields(
    VocabularyEntry entry,
    List<String> modelFields,
  ) {
    if (modelFields.isEmpty) {
      return entryToFields(entry);
    }
    final hasExplicitDefJa = modelFields.any((f) {
      final norm = f
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5\u3040-\u30ff\u3400-\u4dbf]'), '');
      return _vocabDefJaAliases.contains(norm);
    });
    return List<String>.generate(
      modelFields.length,
      (index) => mapFieldValue(
        modelFields[index],
        entry,
        index,
        hasExplicitDefJa,
      ),
    );
  }

  /// 查找或创建目标牌组，返回 deckId
  Future<int> getOrCreateDeck(String deckName) async {
    final decks = await _bridge.getDeckList();
    for (final entry in decks.entries) {
      if (entry.value.trim() == deckName.trim()) {
        return entry.key;
      }
    }
    return await _bridge.addNewDeck(deckName.trim());
  }

  /// 计算自适应升级的模型名称（如 naruse -> naruse-v2, naruse-v2 -> naruse-v3）
  static String computeUpgradedModelName(String modelName) {
    final clean = modelName.trim();
    final match = RegExp(r'^(.*?)-v(\d+)$').firstMatch(clean);
    if (match != null) {
      final base = match.group(1)!;
      final version = int.tryParse(match.group(2)!) ?? 1;
      return '$base-v${version + 1}';
    }
    return '$clean-v2';
  }

  /// 查找或创建卡片模型，并校验字段完整性。
  /// 若目标模型已存在但缺少关键字段（如残存旧模板导致的 Alt1/Pitch 缺失），
  /// 自动创建平滑升级的独立新模型（如 <name>-v2），确保既有卡片与新卡片均安全可用。
  Future<AnkiModelResolution> resolveOrCreateModel(String modelName) async {
    final cleanName = modelName.trim();
    final models = await _bridge.getModelList();

    // 查找同名模型
    MapEntry<int, String>? matchedEntry;
    for (final entry in models.entries) {
      if (entry.value.trim() == cleanName) {
        matchedEntry = entry;
        break;
      }
    }

    if (matchedEntry != null) {
      // 检查字段完整性与是否属于需自愈升级的软件旧模型
      bool isComplete = true;
      try {
        final existingFields = await _bridge.getFieldList(matchedEntry.key);
        if (existingFields.isEmpty) {
          isComplete = false;
        } else {
          final existingSet =
              existingFields.map((f) => f.trim().toLowerCase()).toSet();
          
          final isDefaultModel = cleanName == defaultModelName ||
              cleanName == legacyDefaultModelName;
          
          // 仅当是默认模型，或者属于软件生成的生词本模型（包含 VocabKanji、VocabFurigana 但缺失 Alt1 且非带有 Tags 的特殊模型）
          // 才判定为需要自愈升级的受影响旧模型，绝对不误改用户第三方的自定义基础卡片或句子卡片
          final isCandidateForUpgrade = isDefaultModel ||
              (existingSet.contains('vocabkanji') &&
                  existingSet.contains('vocabfurigana') &&
                  !existingSet.contains('alt1') &&
                  !existingSet.contains('tags'));

          if (isCandidateForUpgrade) {
            for (final f in defaultModelFields) {
              if (!existingSet.contains(f.trim().toLowerCase())) {
                isComplete = false;
                break;
              }
            }
          }
        }
      } catch (_) {
        isComplete = true;
      }

      if (isComplete) {
        return AnkiModelResolution(
          modelId: matchedEntry.key,
          modelName: cleanName,
        );
      }

      // 字段不完整，平滑升级到新模型
      String candidateName = computeUpgradedModelName(cleanName);
      while (true) {
        MapEntry<int, String>? existingCandidate;
        for (final entry in models.entries) {
          if (entry.value.trim() == candidateName) {
            existingCandidate = entry;
            break;
          }
        }

        if (existingCandidate == null) {
          final newId = await _bridge.addNewCustomModel(
            name: candidateName,
            fields: defaultModelFields,
            cards: const ['Card 1'],
            qfmt: const [defaultQfmt],
            afmt: const [defaultAfmt],
            css: defaultCss,
            sortf: 0,
          );
          return AnkiModelResolution(
            modelId: newId,
            modelName: candidateName,
            isUpgraded: true,
            upgradedFrom: cleanName,
          );
        }

        // 候选模型已存在，校验其字段是否完整
        bool candidateComplete = true;
        try {
          final fields = await _bridge.getFieldList(existingCandidate.key);
          final set = fields.map((f) => f.trim().toLowerCase()).toSet();
          for (final f in defaultModelFields) {
            if (!set.contains(f.trim().toLowerCase())) {
              candidateComplete = false;
              break;
            }
          }
        } catch (_) {
          candidateComplete = true;
        }

        if (candidateComplete) {
          return AnkiModelResolution(
            modelId: existingCandidate.key,
            modelName: candidateName,
            isUpgraded: true,
            upgradedFrom: cleanName,
          );
        }

        candidateName = computeUpgradedModelName(candidateName);
      }
    }

    // 全新创建
    final newId = await _bridge.addNewCustomModel(
      name: cleanName,
      fields: defaultModelFields,
      cards: const ['Card 1'],
      qfmt: const [defaultQfmt],
      afmt: const [defaultAfmt],
      css: defaultCss,
      sortf: 0,
    );
    return AnkiModelResolution(
      modelId: newId,
      modelName: cleanName,
    );
  }

  /// 查找或创建卡片模型，返回 modelId（兼容既有接口）
  Future<int> getOrCreateModel(String modelName) async {
    final res = await resolveOrCreateModel(modelName);
    return res.modelId;
  }

  @override
  Future<AnkiExportResult> exportEntries(
    List<VocabularyEntry> entries, {
    String? deckName,
    String? modelName,
  }) async {
    if (entries.isEmpty) {
      return const AnkiExportResult();
    }

    if (!_bridge.isPlatformSupported) {
      return AnkiExportResult(
        failedEntries: entries,
        errors: const ['当前平台不支持 AnkiDroid 导出（仅支持 Android）'],
      );
    }

    final hasPermission = await _bridge.requestPermission();
    if (!hasPermission) {
      return AnkiExportResult(
        failedEntries: entries,
        errors: const ['未获得 AnkiDroid 授权，无法导出'],
      );
    }

    try {
      String targetDeck = (deckName != null && deckName.trim().isNotEmpty)
          ? deckName.trim()
          : '';
      String targetModel = (modelName != null && modelName.trim().isNotEmpty)
          ? modelName.trim()
          : '';

      if (targetDeck.isEmpty || targetModel.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (targetDeck.isEmpty) {
            targetDeck = prefs.getString('anki_deck_name') ?? defaultDeckName;
          }
          if (targetModel.isEmpty) {
            final savedModelName = prefs.getString('anki_model_name');
            targetModel = savedModelName == null ||
                    savedModelName.trim() == legacyDefaultModelName
                ? defaultModelName
                : savedModelName;
          }
        } catch (_) {
          if (targetDeck.isEmpty) targetDeck = defaultDeckName;
          if (targetModel.isEmpty) targetModel = defaultModelName;
        }
      }

      final deckId = await getOrCreateDeck(targetDeck);
      final modelResolution = await resolveOrCreateModel(targetModel);
      final modelId = modelResolution.modelId;

      if (modelResolution.isUpgraded) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('anki_model_name', modelResolution.modelName);
        } catch (_) {}
      }

      List<String> modelFields;
      try {
        modelFields = await _bridge.getFieldList(modelId);
        if (modelFields.isEmpty) {
          modelFields = ankiFields;
        }
      } catch (_) {
        modelFields = ankiFields;
      }

      int successCount = 0;
      int skipCount = 0;
      final failedEntries = <VocabularyEntry>[];
      final errors = <String>[];
      final seenWordsInBatch = <String>{};

      for (final entry in entries) {
        final cleanKanji = entry.vocabKanji.trim();
        if (cleanKanji.isEmpty) continue;

        try {
          // 批次内去重（避免单次导出列表中含有同名词）
          if (seenWordsInBatch.contains(cleanKanji)) {
            skipCount++;
            continue;
          }

          // 查重键自适应：优先取目标模型首字段对应的值，回退为 cleanKanji
          final duplicateKey = (modelFields.isNotEmpty
                  ? mapFieldValue(modelFields.first, entry, 0)
                  : cleanKanji)
              .trim();
          final keyToCheck =
              duplicateKey.isNotEmpty ? duplicateKey : cleanKanji;

          // AnkiDroid 原生去重检测（以首字段为键，查询 AnkiDroid 是否已有同名卡片）
          bool isDuplicate = false;
          try {
            final dupes = await _bridge.findDuplicateNotesWithKey(
              modelId,
              keyToCheck,
            );
            if (dupes.isNotEmpty) {
              isDuplicate = true;
            }
          } catch (_) {
            // 重复检测异常不阻断正常创建流程
          }

          if (isDuplicate) {
            seenWordsInBatch.add(cleanKanji);
            skipCount++;
            continue;
          }

          final fields = entryToModelFields(entry, modelFields);
          final tags = [
            'AI生词本',
            if (entry.sourceDict.isNotEmpty) entry.sourceDict,
          ];

          await _bridge.addNote(
            mid: modelId,
            did: deckId,
            fields: fields,
            tags: tags,
          );
          seenWordsInBatch.add(cleanKanji);
          successCount++;
        } catch (e) {
          failedEntries.add(entry);
          final errorMsg = '「${entry.vocabKanji}」导出失败: $e';
          if (!errors.contains(errorMsg)) {
            errors.add(errorMsg);
          }
        }
      }

      return AnkiExportResult(
        successCount: successCount,
        skipCount: skipCount,
        failedEntries: failedEntries,
        errors: errors,
        modelUpgradedFrom:
            modelResolution.isUpgraded ? modelResolution.upgradedFrom : null,
        modelUpgradedTo:
            modelResolution.isUpgraded ? modelResolution.modelName : null,
      );
    } catch (e) {
      return AnkiExportResult(
        failedEntries: entries,
        errors: ['AnkiDroid 导出异常: $e'],
      );
    } finally {
      await _bridge.dispose();
    }
  }
}
