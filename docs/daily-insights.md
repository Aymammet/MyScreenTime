# Daily insights content structure

The Daily Insights section appears at the bottom of all four Analysis destinations. It currently has no external feed and ships without sample news or statistics. An empty catalog is intentional; no claims are fabricated.

## Reviewed catalog

The loader accepts an optional `daily-insights.json` bundled resource containing an array of entries. Dates use ISO 8601. Each entry requires:

- `id`: stable unique identifier
- `kind`: `statistic`, `news`, or `guidance`
- `title` and `summary`: short editorial text, not full copied articles
- `sourceName`: original publisher
- `publishedAt`: original publication date
- `reviewedAt`: date the source and summary were checked
- `region`: scope of the claim, not the family's inferred location
- `sourceURL`: HTTPS link to the supporting original source

Entries with missing text, insecure links, or future dates are withheld. Content last reviewed more than 30 days ago is visibly marked as older content. Historical publication dates are never relabeled as today's news.

## Next integration step

Choose a reviewed publisher/feed or an editorially managed endpoint, add its content resource or provider, and test refresh, offline caching, duplicate IDs, stale content, and failure recovery. The current loader does not fetch news or perform daily network refreshes. Children's names, photos, and usage records must not be sent to content providers.
