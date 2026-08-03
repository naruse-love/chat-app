# DISPATCH — explorer_survey_2

## Objective
Investigate codebase for R3:
- `lib/services/url_fetch_service.dart`: Structured metadata extraction (parse HTML `<title>`, `<meta description/author/keywords/og:*>`), parse `<table>` into Markdown tables, extract links, format structured Markdown output, enhanced User-Agent header and friendly error messages for 403 WAF / timeout / 404.
- `lib/services/search_service.dart`: Keyword cleaning & deduplication logic optimization.

## Working Directory
`D:\work\chat\.agents\explorer_survey_2`

## Mandatory Input Files
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`

## Output Requirements
Write `handoff.md` in your working directory `D:\work\chat\.agents\explorer_survey_2` detailing:
1. Current implementation of `url_fetch_service.dart` and exact changes needed for HTML `<title>`, `<meta>`, `<table>` to Markdown table parsing, link extraction, User-Agent, and error handling.
2. Current implementation of `search_service.dart` and exact changes needed for keyword cleaning and URL/result deduplication.
3. Affected test files in `test/` (e.g. `test/url_fetch_service_test.dart`, `test/search_service_test.dart`) and recommended test cases to verify R3.
