# Dictionary DB Profile

- db_path: cache\jamdict_cn_deduplicated.db
- exists: True

## Meta
- generator: jamdict
- generator_url: https://github.com/neocl/jamdict
- generator_version: 0.1a8
- jmdict.url: http://www.csse.monash.edu.au/~jwb/edict.html
- jmdict.version: 1.08
- jmnedict.date: 2020-05-29
- jmnedict.url: https://www.edrdg.org/enamdict/enamdict_doc.html
- jmnedict.version: 1.08
- kanjidic2.date: April 2008
- kanjidic2.url: https://www.edrdg.org/wiki/index.php/KANJIDIC_Project
- kanjidic2.version: 1.6

## Tables
### Audit
- row_count: 0
- columns:
  - idseq INTEGER pk=False notnull=False
  - upd_date TEXT pk=False notnull=False
  - upd_detl TEXT pk=False notnull=False
### Bib
- row_count: 0
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
  - tag TEXT pk=False notnull=False
  - text TEXT pk=False notnull=False
### Entry
- row_count: 191541
- columns:
  - idseq INTEGER pk=False notnull=True
### Etym
- row_count: 0
- columns:
  - idseq INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### KJI
- row_count: 3691
- columns:
  - kid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### KJP
- row_count: 57348
- columns:
  - kid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### KNI
- row_count: 1679
- columns:
  - kid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### KNP
- row_count: 62607
- columns:
  - kid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### KNR
- row_count: 8864
- columns:
  - kid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### Kana
- row_count: 229297
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
  - nokanji BOOLEAN pk=False notnull=False
### Kanji
- row_count: 194956
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### Link
- row_count: 0
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
  - tag TEXT pk=False notnull=False
  - desc TEXT pk=False notnull=False
  - uri TEXT pk=False notnull=False
### NEEntry
- row_count: 741275
- columns:
  - idseq INTEGER pk=False notnull=True
### NEKana
- row_count: 741796
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
  - nokanji BOOLEAN pk=False notnull=False
### NEKanji
- row_count: 660020
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### NETransGloss
- row_count: 750130
- columns:
  - tid INTEGER pk=False notnull=False
  - lang TEXT pk=False notnull=False
  - gend TEXT pk=False notnull=False
  - text TEXT pk=False notnull=False
### NETransType
- row_count: 765826
- columns:
  - tid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### NETransXRef
- row_count: 8
- columns:
  - tid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### NETranslation
- row_count: 741708
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
### Sense
- row_count: 219434
- columns:
  - ID INTEGER pk=True notnull=False
  - idseq INTEGER pk=False notnull=False
### SenseGloss
- row_count: 740003
- columns:
  - sid INTEGER pk=False notnull=False
  - lang TEXT pk=False notnull=False
  - gend TEXT pk=False notnull=False
  - text TEXT pk=False notnull=False
### SenseInfo
- row_count: 5056
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### SenseSource
- row_count: 5182
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
  - lang TEXT pk=False notnull=False
  - lstype TEXT pk=False notnull=False
  - wasei TEXT pk=False notnull=False
### antonym
- row_count: 893
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### character
- row_count: 13108
- columns:
  - ID INTEGER pk=True notnull=False
  - literal TEXT pk=False notnull=True
  - stroke_count INTEGER pk=False notnull=False
  - grade TEXT pk=False notnull=False
  - freq TEXT pk=False notnull=False
  - jlpt TEXT pk=False notnull=False
### codepoint
- row_count: 28959
- columns:
  - cid INTEGER pk=False notnull=False
  - cp_type TEXT pk=False notnull=False
  - value TEXT pk=False notnull=False
### dialect
- row_count: 451
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### dic_ref
- row_count: 67981
- columns:
  - cid INTEGER pk=False notnull=False
  - dr_type TEXT pk=False notnull=False
  - value TEXT
n pk=False notnull=False
  - m_vol TEXT pk=False notnull=False
  - m_page TEXT pk=False notnull=False
### field
- row_count: 22771
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### meaning
- row_count: 48020
- columns:
  - gid INTEGER pk=False notnull=False
  - value TEXT pk=False notnull=False
  - m_lang TEXT pk=False notnull=False
### meta
- row_count: 11
- columns:
  - key TEXT pk=True notnull=True
  - value TEXT pk=False notnull=True
### misc
- row_count: 32272
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### nanori
- row_count: 3465
- columns:
  - cid INTEGER pk=False notnull=False
  - value TEXT pk=False notnull=False
### pos
- row_count: 269631
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### query_code
- row_count: 29281
- columns:
  - cid INTEGER pk=False notnull=False
  - qc_type TEXT pk=False notnull=False
  - value TEXT pk=False notnull=False
  - skip_misclass TEXT pk=False notnull=False
### rad_name
- row_count: 146
- columns:
  - cid INTEGER pk=False notnull=False
  - value TEXT pk=False notnull=False
### radical
- row_count: 13831
- columns:
  - cid INTEGER pk=False notnull=False
  - rad_type TEXT pk=False notnull=False
  - value TEXT pk=False notnull=False
### reading
- row_count: 86469
- columns:
  - gid INTEGER pk=False notnull=False
  - r_type TEXT pk=False notnull=False
  - value TEXT pk=False notnull=False
  - on_type TEXT pk=False notnull=False
  - r_status TEXT pk=False notnull=False
### rm_group
- row_count: 12788
- columns:
  - ID INTEGER pk=True notnull=False
  - cid INTEGER pk=False notnull=False
### sqlite_sequence
- row_count: 2
- columns:
  - name  pk=False notnull=False
  - seq  pk=False notnull=False
### stagk
- row_count: 771
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### stagr
- row_count: 1402
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False
### stroke_miscount
- row_count: 542
- columns:
  - cid INTEGER pk=False notnull=False
  - value INTEGER pk=False notnull=False
### variant
- row_count: 4624
- columns:
  - cid INTEGER pk=False notnull=False
  - var_type TEXT pk=False notnull=False
  - value TEXT pk=False notnull=False
### xref
- row_count: 29880
- columns:
  - sid INTEGER pk=False notnull=False
  - text TEXT pk=False notnull=False

## Gloss Language Distribution
- eng: 373939
- chn: 366064

## CJK Coverage in Gloss Text
- rows_scanned: 740003
- rows_with_cjk: 363294
- ratio: 0.490936
