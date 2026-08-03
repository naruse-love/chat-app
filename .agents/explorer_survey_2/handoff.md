# Handoff Report — R3 Analysis: Web Scraper (UrlFetchService) & Search Service Enhancements

## 1. Observation

Direct observations from codebase inspection:

### A. `lib/services/url_fetch_service.dart` (163 lines)
- **Line 13-80 (`fetchUrlContent`)**: Requests webpage HTML via Dio.
- **Line 20-24**: Uses User-Agent `'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'`.
- **Line 44-46**: Strips tags: `['script', 'style', 'noscript', 'svg', 'iframe']`.
- **Line 82-161 (`_parseHtmlToStructuredMarkdown`)**: Converts DOM nodes to basic Markdown text.
  - **Line 126-138 (Table handling)**:
    ```dart
    case 'tr':
      buffer.write('\n');
      for (final child in current.nodes) {
        traverse(child);
      }
      break;
    case 'td':
    case 'th':
      buffer.write(' | ');
      for (final child in current.nodes) {
        traverse(child);
      }
      break;
    ```
    Observation: Converts cells to ` | cell ` without generating Markdown header dividers (`| --- | --- |`), resulting in invalid Markdown tables.
  - **Line 140-149 (Link handling)**: Inline replacement ` [$text]($href) `. Does NOT resolve relative URLs (e.g. `/article/123`) to absolute URLs against base URL, and does NOT generate a structured link index ("页面重要链接").
  - **Observation on Metadata**: Entirely misses HTML `<title>` tag and `<meta>` tags (`description`, `author`, `keywords`, `og:*`).
  - **Line 70-76 (Error handling)**:
    ```dart
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '读取网页超时：请检查网络或目标 URL 是否可达';
      }
      return '读取网页失败：${e.message ?? e.toString()}';
    }
    ```
    Observation: HTTP 403 Forbidden / 404 Not Found / 5xx errors are caught under generic `读取网页失败：${e.message}` without explicit WAF/404 diagnostic descriptions.

### B. `lib/services/search_service.dart` (698 lines)
- **Line 81-112 (`search`)**: Main dispatcher for search backends (`searxng`, `bing`, `google`, `google_bing`).
- **Line 178-188 (`_searchSearxng` deduplication)**: Uses `seenUrls` set to deduplicate URLs across pages 1 and 2.
- **Line 425 (`_parseBingResults` deduplication)**: Uses `seenUrls` set inside Bing parsing.
- **Line 96-107 (`google_bing` dual search)**: Concatenates Google and Bing results: `[...results[0], ...results[1]]`.
  Observation: Cross-engine results in `google_bing` mode are NOT deduplicated.
- **Observation on Keyword Cleaning**: There is no static keyword cleaning helper function. Queries passed from `@search` or LLM tool calls may retain noise prefixes like `@search`, `搜索:`, `查询:`, quotes, or extra spaces.

### C. Test Suite Baseline
- Execution of command `D:\work\flutter-sdk\flutter\bin\flutter.bat test`:
  `All 164 tests passed!`
- Execution of command `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`:
  `No issues found!`

---

## 2. Logic Chain

1. **R3 Web Scraper Requirement**:
   - `url_fetch_service.dart` must extract structured metadata (`<title>`, `<meta description/author/keywords/og:*>`), parse `<table>` to Markdown tables, extract links with absolute URL resolution, update User-Agent, and provide friendly Chinese error messages for 403 WAF / Timeout / 404.
   - Step 1.1: Extracting metadata requires inspecting `<title>` tag and `<meta name="..." content="...">` / `<meta property="og:*" content="...">` tags from `html_parser` document.
   - Step 1.2: Markdown table formatting requires parsing `<table>` elements into discrete rows (`<th>`/`<td>`), normalizing cell text (stripping newlines, escaping `|`), constructing a valid header divider line (`| --- | --- |`), and outputting clean Markdown table syntax.
   - Step 1.3: Link extraction requires gathering `<a>` tags, resolving relative `href` paths using `Uri.parse(url).resolve(href)`, deduplicating links, and outputting up to top 15 links under `## 页面重要链接`.
   - Step 1.4: Enhanced User-Agent requires updating `User-Agent` string to a modern Chrome Desktop string. Error handling requires classifying Dio HTTP status codes (403 WAF/Access Denied, 404 Not Found, 5xx Server Error, Timeout) to return clear diagnostic messages.
   - Step 1.5: Structuring output requires placing Title and Metadata at top, Body Markdown in middle, and Important Links at bottom, keeping total character count capped at 8000.

2. **R3 Search Optimizations Requirement**:
   - `search_service.dart` must implement keyword cleaning and URL/result deduplication logic optimization.
   - Step 2.1: Implement `SearchService.cleanSearchQuery(String rawQuery)` to strip `@search`, `@web_search`, `@google`, `@bing`, `search:`, `query:`, `搜索:`, `查询:`, `查找:`, leading/trailing quotes, and redundant whitespace.
   - Step 2.2: Implement `SearchService.deduplicateResults(List<SearchResult> rawResults)` to normalize URLs (strip trailing slash, lowercase scheme/host, trim) and eliminate duplicates by normalized URL or identical title/content across all backends (`searxng`, `bing`, `google`, `google_bing`).

3. **Test Safety & Compatibility**:
   - Updates must maintain 100% test compatibility with existing tests in `test/url_fetch_service_test.dart` and `test/search_service_test.dart`.
   - Adding unit tests for new metadata extraction, table parsing, link extraction, error handling, keyword cleaning, and deduplication will guarantee non-regression.

---

## 3. Caveats

- **No Caveats**: All target files, test files, and caller dependencies (`agent_service.dart`) have been thoroughly examined.

---

## 4. Conclusion & Recommended Code Changes

### Proposed Changes to `lib/services/url_fetch_service.dart`

```dart
// 1. Enhanced User-Agent in fetchUrlContent:
'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',

// 2. Structured Metadata Extraction:
Map<String, String> _extractMetadata(html_dom.Document document) {
  final meta = <String, String>{};
  final title = document.querySelector('title')?.text.trim() ??
      document.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
      '';
  if (title.isNotEmpty) meta['标题'] = title;

  final desc = document.querySelector('meta[name="description"]')?.attributes['content']?.trim() ??
      document.querySelector('meta[property="og:description"]')?.attributes['content']?.trim() ??
      '';
  if (desc.isNotEmpty) meta['描述'] = desc;

  final author = document.querySelector('meta[name="author"]')?.attributes['content']?.trim() ??
      document.querySelector('meta[property="article:author"]')?.attributes['content']?.trim() ??
      '';
  if (author.isNotEmpty) meta['作者'] = author;

  final keywords = document.querySelector('meta[name="keywords"]')?.attributes['content']?.trim() ?? '';
  if (keywords.isNotEmpty) meta['关键词'] = keywords;

  final siteName = document.querySelector('meta[property="og:site_name"]')?.attributes['content']?.trim() ?? '';
  if (siteName.isNotEmpty) meta['站点名称'] = siteName;

  return meta;
}

// 3. Table Parsing to Markdown:
String _parseTableToMarkdown(html_dom.Element table) {
  final rows = table.querySelectorAll('tr');
  if (rows.isEmpty) return '';

  final tableData = <List<String>>[];
  for (final row in rows) {
    final cells = row.querySelectorAll('th, td');
    final rowText = cells.map((cell) {
      return cell.text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').replaceAll('|', '\\|').trim();
    }).toList();
    if (rowText.any((cell) => cell.isNotEmpty)) {
      tableData.add(rowText);
    }
  }

  if (tableData.isEmpty) return '';
  final colCount = tableData.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  if (colCount == 0) return '';

  final buffer = StringBuffer();
  buffer.writeln();
  
  // Header row
  final header = tableData.first;
  final headerRow = List.generate(colCount, (i) => i < header.length ? header[i] : '');
  buffer.writeln('| ${headerRow.join(' | ')} |');
  
  // Divider row
  buffer.writeln('| ${List.filled(colCount, '---').join(' | ')} |');

  // Data rows
  for (int i = 1; i < tableData.length; i++) {
    final row = tableData[i];
    final paddedRow = List.generate(colCount, (j) => j < row.length ? row[j] : '');
    buffer.writeln('| ${paddedRow.join(' | ')} |');
  }
  buffer.writeln();

  return buffer.toString();
}

// 4. Link Extraction & Resolution:
List<String> _extractImportantLinks(html_dom.Element body, String baseUrl) {
  final links = <String>[];
  final seen = <String>{};
  final anchors = body.querySelectorAll('a');

  for (final a in anchors) {
    final text = a.text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    final href = a.attributes['href']?.trim() ?? '';
    if (text.isEmpty || href.isEmpty || href.startsWith('javascript:') || href == '#') continue;

    try {
      final absoluteUri = Uri.parse(baseUrl).resolve(href);
      if (absoluteUri.scheme == 'http' || absoluteUri.scheme == 'https') {
        final urlStr = absoluteUri.toString();
        if (seen.add(urlStr)) {
          links.add('- [$text]($urlStr)');
          if (links.length >= 15) break;
        }
      }
    } catch (_) {}
  }
  return links;
}

// 5. Friendly Error Classification in DioException:
if (e.type == DioExceptionType.connectionTimeout ||
    e.type == DioExceptionType.receiveTimeout ||
    e.type == DioExceptionType.sendTimeout) {
  return '读取网页超时：请检查网络或目标 URL 是否可达';
}
final statusCode = e.response?.statusCode;
if (statusCode == 403 || statusCode == 401) {
  return '读取网页失败：目标网站开启了反爬拦截或拒绝访问 (HTTP $statusCode Forbidden)';
}
if (statusCode == 404) {
  return '读取网页失败：页面不存在 (HTTP 404 Not Found)';
}
if (statusCode != null && statusCode >= 500) {
  return '读取网页失败：服务器响应错误 (HTTP $statusCode)';
}
return '读取网页失败：${e.message ?? e.toString()}';
```

### Proposed Changes to `lib/services/search_service.dart`

```dart
// 1. Public static Keyword Cleaning Helper:
static String cleanSearchQuery(String rawQuery) {
  var cleaned = rawQuery.trim();
  // Strip trigger prefixes
  cleaned = cleaned.replaceAll(RegExp(r'^(@(search|web_search|google|bing)|(search|query|搜索|查询|查找|帮我搜索|请搜索)[:：])\s*', caseSensitive: false), '');
  // Strip leading/trailing quotes
  if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
      (cleaned.startsWith('\'') && cleaned.endsWith('\''))) {
    cleaned = cleaned.substring(1, cleaned.length - 1).trim();
  }
  // Normalize whitespace
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? rawQuery.trim() : cleaned;
}

// 2. Public static Deduplication Helper:
static List<SearchResult> deduplicateResults(List<SearchResult> rawResults) {
  final seenUrls = <String>{};
  final seenTitleContent = <String>{};
  final deduplicated = <SearchResult>[];

  for (final item in rawResults) {
    var url = item.url.trim();
    if (url.endsWith('/') && url.length > 8) {
      url = url.substring(0, url.length - 1);
    }
    // Normalize scheme and host to lowercase
    try {
      final uri = Uri.parse(url);
      if (uri.hasAuthority) {
        url = uri.replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase()).toString();
      }
    } catch (_) {}

    final titleContentKey = '${item.title.trim().toLowerCase()}_${item.content.trim().toLowerCase()}';

    if (url.isNotEmpty) {
      if (seenUrls.add(url)) {
        seenTitleContent.add(titleContentKey);
        deduplicated.add(item);
      }
    } else {
      if (seenTitleContent.add(titleContentKey)) {
        deduplicated.add(item);
      }
    }
  }

  return deduplicated;
}
```

---

## 5. Verification Method

To verify the implementation of R3:

1. **Static Analysis**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat analyze
   ```
   Must output `No issues found!`.

2. **Unit Tests Execution**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat test
   ```
   Must execute all tests with 100% pass rate (0 failures).

3. **Target Test Files**:
   - `test/url_fetch_service_test.dart`:
     - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test test/url_fetch_service_test.dart`
     - Verify metadata extraction, Markdown table conversion, link resolution, and 403/404/timeout error messages.
   - `test/search_service_test.dart`:
     - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test test/search_service_test.dart`
     - Verify `cleanSearchQuery` and `deduplicateResults` functions.
