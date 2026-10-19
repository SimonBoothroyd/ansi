import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/ask/data/ask_voice.dart';
import 'package:ansi/features/ask/domain/ask_proposal.dart';
import 'package:ansi/features/ask/domain/ask_repository.dart';
import 'package:ansi/features/ask/domain/ask_tool_runner.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';

/// One scripted model turn: it reads what was sent and answers.
typedef AskScript = AskReplyData Function(List<Map<String, Object?>> sent);

/// The `ask` relay, answering from [script] in order and recording every
/// conversation it was sent.
class ScriptedAskRepository implements AskRepository {
  ScriptedAskRepository(this.script);

  final List<AskScript> script;
  final List<List<Map<String, Object?>>> sent = [];

  @override
  Future<AskReplyData> turn(List<Map<String, Object?>> messages) async {
    sent.add(messages);
    if (sent.length > script.length) {
      throw const AskException('the script ran out');
    }
    return script[sent.length - 1](messages);
  }
}

/// A model turn that calls one tool.
AskReplyData askToolCall(
  String name,
  Map<String, Object?> input, {
  String id = 'toolu_1',
}) => (
  content: [
    {'type': 'thinking', 'thinking': '', 'signature': 'sig-$id'},
    {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
  ],
  stopReason: 'tool_use',
);

/// A model turn that answers in words.
AskReplyData askSays(String text) => (
  content: [
    {'type': 'text', 'text': text},
  ],
  stopReason: 'end_turn',
);

/// The last tool result's content in a conversation.
String lastToolResult(List<Map<String, Object?>> sent) {
  final blocks = sent.last['content']! as List;
  final result = blocks.last as Map;
  return result['content']! as String;
}

/// The mic and speaker: each [listen] hands back the next of [heard] as a
/// finished question, or silence once they are spent (or refuses when
/// [available] is false), and [speak] records what was read.
class FakeAskVoice implements AskVoice {
  FakeAskVoice({this.available = true});

  final List<String> heard = [];
  bool available;
  int listens = 0;
  final List<String> spoken = [];

  @override
  Future<bool> listen({
    required void Function(String words, {required bool done}) onWords,
  }) async {
    if (!available) return false;
    listens++;
    final words = heard.isEmpty ? '' : heard.removeAt(0);
    onWords(words, done: false);
    onWords(words, done: true);
    return true;
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}
}

/// A household for the runner: [weeks] by first day, [members], the
/// [ingredients] vocabulary, and a card answered by [decide] (Cancel by
/// default), each card recorded in [cards].
class FakeAskHousehold {
  FakeAskHousehold({
    this.weeks = const {},
    this.members = const [],
    this.ingredients = const [],
    this.me,
    this.cookPlan = const CookPlan(),
    this.shoppingList = const ShoppingList(),
    this.previous,
    DateTime? today,
    this.decide,
  }) : today = today ?? DateTime.utc(2026, 10, 21);

  final Map<DateTime, WeekPlan> weeks;
  final List<Member> members;
  final List<Ingredient> ingredients;
  final String? me;
  final CookPlan cookPlan;
  final ShoppingList shoppingList;
  final WeekPlan? previous;
  final DateTime today;
  final AskDecision Function(AskProposal proposal)? decide;
  final List<AskProposal> cards = [];

  AskHousehold get household => AskHousehold(
    today: () => today,
    shape: () => WeekShape.monday,
    loadWeek: (weekStart) async => weeks[weekStart],
    previousWeek: (_) async => previous,
    members: () async => members,
    me: (_) => me,
    cookPlan: (_) async => cookPlan,
    shoppingList: (_) async => shoppingList,
    shopTotal: (item) => item.totals.isEmpty ? '—' : 'some',
    searchIngredients: (query) async => (
      rows: [
        for (final i in ingredients)
          if (i.canonicalName.toLowerCase().contains(query.toLowerCase())) i,
      ],
      guessed: false,
    ),
    ingredientFacts: (ids, {required forMeal}) async => {
      for (final i in ingredients)
        if (ids.contains(i.id))
          i.id: (ingredient: i, measures: const <Measure>[], usual: null),
    },
    propose: (proposal) async {
      cards.add(proposal);
      return decide?.call(proposal) ?? AskDecision.cancelled;
    },
  );
}
