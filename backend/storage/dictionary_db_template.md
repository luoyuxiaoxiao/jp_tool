# Dictionary DB Template (JA->ZH Rebuild Plan)

## Current Status in This Project

- The runtime setting `RESOURCE_DICT_DB_PATH` is currently persisted and exposed in API only.
- There is no active dictionary lookup path in the analyzer pipeline right now.
- Replacing `cache/jmdict.sqlite` does not break grammar/deep analysis flow today.

## Current DB Snapshot (cache/jmdict.sqlite)

The current file can be profiled by:

```bash
python backend/tools/inspect_dictionary_sqlite.py \
  --db cache/jmdict.sqlite \
  --out-json cache/jmdict_profile.json \
  --out-md cache/jmdict_profile.md
```

Known facts (2026-04-16):

- `meta.language = en`
- `senses.glosses` has no CJK rows
- Effective direction: JA->EN (not JA->ZH)

## Target DB Contract (for New JA->ZH Source)

Use the same high-level shape so migration and future query code stay simple.

### Table: entries

```sql
CREATE TABLE IF NOT EXISTS entries (
  ent_seq INTEGER PRIMARY KEY,
  kanji TEXT,
  kana TEXT
);
```

### Table: senses

```sql
CREATE TABLE IF NOT EXISTS senses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ent_seq INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  lang TEXT NOT NULL DEFAULT 'chi',
  note TEXT,
  glosses TEXT NOT NULL,    -- JSON array string, e.g. ["考虑了很久", "最终决定"]
  pos TEXT,                 -- JSON array string
  fields TEXT,              -- JSON array string
  tags TEXT,                -- JSON array string
  refs TEXT                 -- JSON array string
);
CREATE INDEX IF NOT EXISTS idx_senses_ent_seq_lang
ON senses(ent_seq, lang);
```

### Table: meta

```sql
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

Recommended meta values:

- `language = zh`
- `version = <source_version_or_date>`
- `license = <source_license>`

## Mapping Rules for Rebuild

1. Keep `ent_seq` stable if source provides it.
2. If source has no `ent_seq`, generate deterministic IDs by normalized `(kanji, kana)` hash.
3. Store Chinese meanings in `senses.glosses` as JSON array string.
4. Use `lang='chi'` for Chinese rows.
5. Drop English-only rows (since this build is JA->ZH only).
6. Keep optional POS/field/tag/ref as JSON arrays when available.

## Validation Checklist

1. `SELECT value FROM meta WHERE key='language'` returns `zh`.
2. `SELECT COUNT(*) FROM senses WHERE lang='chi'` is close to total sense count.
3. `SELECT COUNT(*) FROM senses WHERE glosses LIKE '%\\u4e00%'` is not used for validation.
4. Instead, run Python CJK regex over decoded gloss text and check non-zero coverage.
5. Randomly sample 50 entries and verify kana/kanji -> Chinese gloss quality.

## Handoff Requirement for Next Step

When a new JA->ZH source arrives, provide:

- source file path(s)
- source schema or sample rows
- license constraints

Then the remap script can be implemented with deterministic field mapping.
