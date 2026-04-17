/// Data models matching the Python backend's JSON protocol.
library;

// ── Token ────────────────────────────────────────────────────────────────────

class Token {
  final String surface;
  final String reading;
  final String pos;
  final String posDetail;
  final String base;
  final String conjugation;
  final int index;
  final int headIndex;
  final String dep;
  final int charStart;
  final int charEnd;
  final String meaningZh;
  final bool isPunctuation;

  const Token({
    required this.surface,
    this.reading = '',
    this.pos = '',
    this.posDetail = '',
    this.base = '',
    this.conjugation = '',
    this.index = 0,
    this.headIndex = 0,
    this.dep = '',
    this.charStart = 0,
    this.charEnd = 0,
    this.meaningZh = '',
    this.isPunctuation = false,
  });

  static int _toInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  factory Token.fromJson(Map<String, dynamic> j) => Token(
        surface: j['surface'] ?? '',
        reading: j['reading'] ?? '',
        pos: j['pos'] ?? '',
        posDetail: j['pos_detail'] ?? '',
        base: j['base'] ?? '',
        conjugation: j['conjugation'] ?? '',
        index: _toInt(j['index'], 0),
        headIndex: _toInt(j['head_index'], 0),
        dep: j['dep'] ?? '',
        charStart: _toInt(j['char_start'], 0),
        charEnd: _toInt(j['char_end'], 0),
        meaningZh: j['meaning_zh'] ?? '',
        isPunctuation: j['is_punctuation'] == true,
      );

  Map<String, dynamic> toJson() => {
        'surface': surface,
        'reading': reading,
        'pos': pos,
        'pos_detail': posDetail,
        'base': base,
        'conjugation': conjugation,
        'index': index,
        'head_index': headIndex,
        'dep': dep,
        'char_start': charStart,
        'char_end': charEnd,
        'meaning_zh': meaningZh,
        'is_punctuation': isPunctuation,
      };
}

// ── Grammar Match ────────────────────────────────────────────────────────────

class GrammarMatch {
  final String pattern;
  final String level; // N1-N5
  final String meaningZh;
  final String meaningJa;
  final String example;
  final int start;
  final int end;

  const GrammarMatch({
    required this.pattern,
    required this.level,
    this.meaningZh = '',
    this.meaningJa = '',
    this.example = '',
    this.start = 0,
    this.end = 0,
  });

  factory GrammarMatch.fromJson(Map<String, dynamic> j) => GrammarMatch(
        pattern: j['pattern'] ?? '',
        level: j['level'] ?? '',
        meaningZh: j['meaning_zh'] ?? '',
        meaningJa: j['meaning_ja'] ?? '',
        example: j['example'] ?? '',
        start: j['start'] ?? 0,
        end: j['end'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'level': level,
        'meaning_zh': meaningZh,
        'meaning_ja': meaningJa,
        'example': example,
        'start': start,
        'end': end,
      };
}

// ── Basic Result (Phase 1) ──────────────────────────────────────────────────

class BasicResult {
  final String text;
  final List<Token> tokens;
  final List<GrammarMatch> grammarMatches;

  const BasicResult({
    required this.text,
    this.tokens = const [],
    this.grammarMatches = const [],
  });

  factory BasicResult.fromJson(Map<String, dynamic> j) => BasicResult(
        text: j['text'] ?? '',
        tokens:
            (j['tokens'] as List?)?.map((t) => Token.fromJson(t)).toList() ??
                [],
        grammarMatches: (j['grammar_matches'] as List?)
                ?.map((g) => GrammarMatch.fromJson(g))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'type': 'basic_result',
        'text': text,
        'tokens': tokens.map((t) => t.toJson()).toList(),
        'grammar_matches': grammarMatches.map((g) => g.toJson()).toList(),
      };
}

// ── Deep Result components ──────────────────────────────────────────────────

class GrammarPoint {
  final String grammar;
  final String structure;
  final String function;
  final String comparison;
  final String level;

  const GrammarPoint({
    required this.grammar,
    this.structure = '',
    this.function = '',
    this.comparison = '',
    this.level = '',
  });

  factory GrammarPoint.fromJson(Map<String, dynamic> j) => GrammarPoint(
        grammar: j['grammar'] ?? '',
        structure: j['structure'] ?? '',
        function: j['function'] ?? '',
        comparison: j['comparison'] ?? '',
        level: j['level'] ?? '',
      );
}

class WordMeaning {
  final String word;
  final String meaningZh;

  const WordMeaning({
    required this.word,
    this.meaningZh = '',
  });

  factory WordMeaning.fromJson(Map<String, dynamic> j) => WordMeaning(
        word: j['word'] ?? '',
        meaningZh: j['meaning_zh'] ?? '',
      );
}

class SentenceComponent {
  final String fragment;
  final String role;
  final String reading;

  const SentenceComponent({
    required this.fragment,
    required this.role,
    this.reading = '',
  });

  factory SentenceComponent.fromJson(Map<String, dynamic> j) =>
      SentenceComponent(
        fragment: j['fragment'] ?? '',
        role: j['role'] ?? '',
        reading: j['reading'] ?? '',
      );
}

class GrammarTreeNode {
  final String label;
  final String note;
  final List<GrammarTreeNode> children;

  const GrammarTreeNode({
    required this.label,
    this.note = '',
    this.children = const [],
  });

  factory GrammarTreeNode.fromJson(Map<String, dynamic> j) => GrammarTreeNode(
        label: j['label'] ?? '',
        note: j['note'] ?? '',
        children: (j['children'] as List?)
                ?.map((c) => GrammarTreeNode.fromJson(c))
                .toList() ??
            [],
      );
}

class ComparisonItem {
  final String expression;
  final String example;
  final String score;
  final String note;

  const ComparisonItem({
    required this.expression,
    this.example = '',
    this.score = '',
    this.note = '',
  });

  factory ComparisonItem.fromJson(Map<String, dynamic> j) => ComparisonItem(
        expression: j['expression'] ?? '',
        example: j['example'] ?? '',
        score: j['score'] ?? '',
        note: j['note'] ?? '',
      );
}

class ComparisonGroup {
  final String category;
  final List<ComparisonItem> items;

  const ComparisonGroup({required this.category, this.items = const []});

  factory ComparisonGroup.fromJson(Map<String, dynamic> j) => ComparisonGroup(
        category: j['category'] ?? '',
        items: (j['items'] as List?)
                ?.map((i) => ComparisonItem.fromJson(i))
                .toList() ??
            [],
      );
}

class CommonMistake {
  final String wrong;
  final String problem;
  final String correct;

  const CommonMistake(
      {required this.wrong, required this.problem, required this.correct});

  factory CommonMistake.fromJson(Map<String, dynamic> j) => CommonMistake(
        wrong: j['wrong'] ?? '',
        problem: j['problem'] ?? '',
        correct: j['correct'] ?? '',
      );
}

class LevelAnnotation {
  final int start;
  final int end;
  final String level;
  final String grammar;

  const LevelAnnotation({
    required this.start,
    required this.end,
    required this.level,
    required this.grammar,
  });

  factory LevelAnnotation.fromJson(Map<String, dynamic> j) => LevelAnnotation(
        start: j['start'] ?? 0,
        end: j['end'] ?? 0,
        level: j['level'] ?? '',
        grammar: j['grammar'] ?? '',
      );
}

// ── Deep Result (Phase 2) ───────────────────────────────────────────────────

class DeepResult {
  final String text;
  final List<GrammarPoint> coreGrammar;
  final List<WordMeaning> wordMeanings;
  final List<SentenceComponent> sentenceBreakdown;
  final List<GrammarTreeNode> grammarTree;
  final List<ComparisonGroup> comparisons;
  final List<CommonMistake> commonMistakes;
  final String culturalContext;
  final String markdownAnalysis;
  final List<String> applications;
  final List<LevelAnnotation> levelAnnotations;

  const DeepResult({
    required this.text,
    this.coreGrammar = const [],
    this.wordMeanings = const [],
    this.sentenceBreakdown = const [],
    this.grammarTree = const [],
    this.comparisons = const [],
    this.commonMistakes = const [],
    this.culturalContext = '',
    this.markdownAnalysis = '',
    this.applications = const [],
    this.levelAnnotations = const [],
  });

  factory DeepResult.fromJson(Map<String, dynamic> j) => DeepResult(
        text: j['text'] ?? '',
        coreGrammar: (j['core_grammar'] as List?)
                ?.map((g) => GrammarPoint.fromJson(g))
                .toList() ??
            [],
        wordMeanings: (j['word_meanings'] as List?)
                ?.map((w) => WordMeaning.fromJson(w))
                .toList() ??
            [],
        sentenceBreakdown: (j['sentence_breakdown'] as List?)
                ?.map((s) => SentenceComponent.fromJson(s))
                .toList() ??
            [],
        grammarTree: (j['grammar_tree'] as List?)
                ?.map((n) => GrammarTreeNode.fromJson(n))
                .toList() ??
            [],
        comparisons: (j['comparisons'] as List?)
                ?.map((c) => ComparisonGroup.fromJson(c))
                .toList() ??
            [],
        commonMistakes: (j['common_mistakes'] as List?)
                ?.map((m) => CommonMistake.fromJson(m))
                .toList() ??
            [],
        culturalContext: j['cultural_context'] ?? '',
        markdownAnalysis: j['markdown_analysis'] ?? '',
        applications:
            (j['applications'] as List?)?.map((a) => a.toString()).toList() ??
                [],
        levelAnnotations: (j['level_annotations'] as List?)
                ?.map((a) => LevelAnnotation.fromJson(a))
                .toList() ??
            [],
      );

  Map<String, String> get wordMeaningMap {
    final map = <String, String>{};
    for (final item in wordMeanings) {
      final key = item.word.trim();
      final value = item.meaningZh.trim();
      if (key.isEmpty || value.isEmpty) continue;
      map.putIfAbsent(key, () => value);
    }
    return map;
  }
}

// ── Combined analysis state ─────────────────────────────────────────────────

class AnalysisState {
  final BasicResult? basic;
  final DeepResult? deep;
  final bool isLoadingDeep;

  const AnalysisState({this.basic, this.deep, this.isLoadingDeep = false});

  AnalysisState copyWith(
          {BasicResult? basic, DeepResult? deep, bool? isLoadingDeep}) =>
      AnalysisState(
        basic: basic ?? this.basic,
        deep: deep ?? this.deep,
        isLoadingDeep: isLoadingDeep ?? this.isLoadingDeep,
      );
}
