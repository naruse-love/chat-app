# Handoff Report — Requirement 3 (Web Search Optimizations)

## 1. Observation

- **`lib/services/search_service.dart`**:
  - `formatSearchResultsForContext` (lines 269–284): Currently formats search results into text formatted as:
    ```
    以下是网络搜索结果:
    1. 标题: Title
       网址: URL
       摘要: Content
    ```
  - `_searchSearxng` (lines 102–170): Currently performs a single GET request with query parameter `{'q': query, 'format': 'json'}` without specifying `pageno`.
- **`lib/services/agent_service.dart`**:
  - Calls `_searchService.formatSearchResultsForContext(results)` on lines 186, 346, 555, and 643 when formatting search results for LLM context.
- **`test/search_service_test.dart`**:
  - Lines 272–284 test `formatSearchResultsForContext` expecting the old text `1. 标题: A` and `网址: https://a.com`.
  - SearXNG tests mock a single request without verifying `pageno`.
- **`test/agent_service_test.dart`**:
  - Mocked `MockSearchService` returns custom search results and tests check `execEvent.toolMessages[0].content, contains('...')`. No direct string dependencies on the old `'标题:'` header format exist in `agent_service_test.dart`.

---

## 2. Logic Chain

### 2.1 Formatting Update in `SearchService` & `AgentService`
- **Requirement R3**: Format search results using:
  ```
  以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题。
  如果需要更详细的信息，请使用 url_fetch 工具读取相关页面全文。
  回答时请引用来源 URL。

  1. [Title](URL)
     摘要: snippet
  ```
- **Analysis**: `AgentService` delegates search result formatting to `SearchService.formatSearchResultsForContext(results)`. Updating `formatSearchResultsForContext` in `SearchService` updates the context string emitted across all agent flows (manual search `@search`, tool calls, multi-turn follow-ups).
- **Implementation Design**:
  ```dart
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) {
      return '未找到相关网络搜索结果。';
    }

    final buffer = StringBuffer();
    buffer.writeln('以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题。');
    buffer.writeln('如果需要更详细的信息，请使用 url_fetch 工具读取相关页面全文。');
    buffer.writeln('回答时请引用来源 URL。');
    buffer.writeln();
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. [${r.title}](${r.url})');
      buffer.writeln('   摘要: ${r.content}');
      if (i < results.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }
  ```

### 2.2 SearXNG Concurrent Multi-Page Search (`pageno: 1` and `pageno: 2`) & URL Deduplication
- **Requirement R3**:
  1. Concurrently request `pageno: 1` and `pageno: 2` using `Future.wait`.
  2. Wrap each page request in individual `try-catch` blocks so if one page fails or times out, the other page's results are still preserved.
  3. Deduplicate combined search results by URL across pages.
- **Implementation Design in `_searchSearxng`**:
  1. Define an inner async helper function `Future<List<SearchResult>> fetchPage(int page) async`.
  2. `fetchPage` issues `_dio.get` with query parameters `{'q': query, 'format': 'json', 'pageno': page}`.
  3. If HTTP 403 or 400 is returned (JSON disabled on SearXNG instance), `SearchException` is rethrown so the user receives the actionable configuration error message.
  4. If a timeout or network exception occurs on a page, `fetchPage` logs the detail to `errorDetails` and returns `[]`.
  5. Execute `Future.wait([fetchPage(1), fetchPage(2)])` to query both pages concurrently.
  6. Combine results from both pages.
  7. Deduplicate using a `Set<String> seenUrls` while preserving order:
     ```dart
     final seenUrls = <String>{};
     final deduplicatedResults = <SearchResult>[];
     for (final result in combinedResults) {
       if (result.url.isNotEmpty) {
         if (seenUrls.add(result.url)) {
           deduplicatedResults.add(result);
         }
       } else {
         deduplicatedResults.add(result);
       }
     }
     ```
  8. If `deduplicatedResults` is empty and `errorDetails` is not empty, throw `SearchException` with aggregated error details. Otherwise, return `deduplicatedResults`.

### 2.3 Impact on Existing Tests & New Test Design
- **Impact on Existing Tests**:
  - `test/search_service_test.dart`:
    - `Formatting context string works correctly (Chinese)` (lines 272–284) needs expectation updates to check the new header lines and Markdown link structure `1. [A](https://a.com)`.
    - Existing `SearXNG search succeeds` mock handler will be called twice (for page 1 and page 2). Deduplication will collapse identical results so it still passes, but updated mock parameters can make it explicit.
  - `test/agent_service_test.dart`: All 127 existing tests pass as `agent_service_test.dart` uses `MockSearchService` which overrides `search()`.
- **New Tests to Add (`test/search_service_test.dart`)**:
  1. **Concurrent Page Fetching & Deduplication**:
     - Mock handler checks requests for `pageno: 1` and `pageno: 2`.
     - Page 1 returns `[Title1 (url1), Title2 (url2)]`.
     - Page 2 returns `[Title2 (url2), Title3 (url3)]`.
     - Verify returned list has length 3: `[Title1, Title2, Title3]` deduplicated by URL.
  2. **Isolated Error Handling (Partial Failure)**:
     - Page 1 succeeds with 2 results.
     - Page 2 throws `DioExceptionType.connectionTimeout`.
     - Verify `search()` completes without throwing an exception and returns Page 1's 2 results.

---

## 3. Caveats

- **Bing Search**: Bing search backend remains single-page HTML scraping as per implementation. R3 specifically targets SearXNG concurrent multi-page search.
- **Empty URLs**: In the rare event a `SearchResult` has an empty URL, it is kept rather than dropped by deduplication.
- **403 Forbidden / JSON format error**: If SearXNG returns 403 or 400 (indicating JSON format is disabled on the SearXNG server), rethrowing `SearchException` ensures the user is prompted to update their SearXNG `settings.yml`.

---

## 4. Conclusion

1. Formatting change is localized to `SearchService.formatSearchResultsForContext` which automatically updates all search contexts in `AgentService`.
2. Multi-page SearXNG execution cleanly uses `Future.wait([fetchPage(1), fetchPage(2)])` with per-page `try-catch` and `Set<String>` deduplication.
3. Existing test `Formatting context string works correctly (Chinese)` in `test/search_service_test.dart` requires updated assertions, and 2 new tests should be added to cover parallel page fetching and deduplication.

---

## 5. Verification Method

1. Run static analysis:
   `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`
   Must output `No issues found!`.
2. Run test suite:
   `D:\work\flutter-sdk\flutter\bin\flutter.bat test test/search_service_test.dart`
   `D:\work\flutter-sdk\flutter\bin\flutter.bat test`
   All unit and integration tests must pass (127 existing + new search tests).
