## Challenge Summary

**Overall risk assessment**: MEDIUM

While `AgentService` is structurally robust and does not crash under malformed JSON inputs or parallel stream execution, there are important resource and correctness implications under cancellation and invalid tool calls.

---

## Challenges

### [Medium] Challenge 1: In-Flight Search Requests are Not Aborted on Cancellation
- **Assumption challenged**: Cancelling the stream during search aborts the network request.
- **Attack scenario**: The user triggers a search request. The user immediately cancels the request. 
- **Blast radius**: The search HTTP requests (both to 9Router and SearXNG fallback) continue to run to completion in the background, consuming network bandwidth, server resources, and API quotas. The stream only throws the cancellation error *after* the search completes.
- **Mitigation**: Update `SearchService.search` to accept an optional `CancelToken` and pass it to the `_dio.post` and `_dio.get` calls:
  ```dart
  Future<List<SearchResult>> search({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
    CancelToken? cancelToken, // Add this
  })
  ```
  And update `AgentService` to pass `cancelToken` to `_searchService.search(...)`.

### [Low] Challenge 2: TypeErrors during Tool Call Arguments parsing fall back to JSON strings
- **Assumption challenged**: Tool call arguments are always string-to-string maps.
- **Attack scenario**: The model returns `{"query": 123}` or `{"query": ["flutter"]}`.
- **Blast radius**: The cast `parsedArgs['query'] as String?` fails with a `TypeError`. This is caught by `catch (_)`, which falls back to setting `query = firstAcc.argumentsBuffer.toString()`. Consequently, the search query is literally executed as the raw JSON buffer `{"query": 123}` instead of falling back to a clean string or throwing a validation error.
- **Mitigation**: Instead of casting using `as String?`, parse values safely, or stringify any non-string type when fallback occurs. For example:
  ```dart
  final queryVal = parsedArgs['query'];
  query = queryVal?.toString() ?? '';
  ```

---

## Stress Test Results

We implemented and executed a comprehensive suite of edge-case tests in `test/agent_service_test.dart`.

| Test Scenario | Tested Behavior | Actual Behavior | Status |
|---|---|---|---|
| **Malformed Arguments - Incomplete JSON** | Incomplete JSON buffer (e.g. `{"query": "flutter`) is parsed. | `json.decode` fails with `FormatException`, caught safely, and query falls back to raw buffer. | **PASS** |
| **Malformed Arguments - TypeError** | Query property contains invalid type (e.g. `{"query": 123}`). | Cast throws `TypeError`, caught safely, and query falls back to raw buffer. | **PASS** |
| **Malformed Arguments - Missing Property** | Query property is missing (e.g. `{}`). | `query` becomes empty string `''` safely. | **PASS** |
| **Immediate Cancellation** | Stream is cancelled before listing starts. | Throws `DioException` of type `cancel` immediately, yielding no events. | **PASS** |
| **Cancellation During Search** | Stream is cancelled while `searchService.search()` is running. | Search completes in background, and `_checkCancellation` throws `DioException` right after, emitting no more events. | **PASS** |
| **Empty Messages List** | Called with `messages: []`. | Stream completes immediately with no events. | **PASS** |
| **Last Message Empty Content** | Last message is empty string `""`. | Standard stream completions execute normally without throwing. | **PASS** |
| **Concurrency** | 10 streams executed in parallel with random latencies. | Streams run in parallel without cross-talk or race conditions. | **PASS** |

---

## Unchallenged Areas
- **SearXNG API / 9Router API integration**: We mocked `SearchService` and did not perform live HTTP tests against a real SearXNG instance as it is out of scope and requires network connectivity which is blocked under `CODE_ONLY` restrictions.
