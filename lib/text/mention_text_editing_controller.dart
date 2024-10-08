import 'dart:async';

import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

// ignore_for_file: constant_identifier_names

// Mention object that store the id, display name and avatarurl of the mention
// You can inherit from this to add your own custom data, should you need to

class MentionObject {
  MentionObject(
      {required this.id, required this.displayName, required this.avatarUrl});

  // id of the mention, should match ^([a-zA-Z0-9]){1,}$
  final String id;
  final String displayName;
  final String avatarUrl;
}

// Mention syntax for determining when to start mentioning and parsing to and from markup
// Final markup text would be Prefix -> StartingCharacter -> Id of mention -> Suffix
class MentionSyntax {
  MentionSyntax(
      {required this.startingCharacter,
      required this.missingText,
      this.prefix = '<###',
      this.suffix = '###>',
      this.pattern = "[a-zA-Z0-9]{1,}"}) {
    _mentionRegex = RegExp('($prefix)($startingCharacter)($pattern)($suffix)');
  }

  // The character the regex pattern starts with, used to more performantly find sections in the text, needs to be a single character
  final String startingCharacter;

  // The prefix to add to the final markup text per mention of this type
  final String prefix;

  // The suffix to add to the final markup text per mention of this type
  final String suffix;

  // The display name to show when the mention with the specified id no longer exists
  final String missingText;

  // The inner pattern that will be followed to find a mention
  final String pattern;

  late RegExp _mentionRegex;

  RegExp getRegExp() => _mentionRegex;
}

// Local-only class to store mentions currently stored in the string visible to the user
class TextMention {
  TextMention(
      {required this.id,
      required this.display,
      required this.start,
      required this.end,
      required this.syntax});

  final String id;
  final String display;
  final MentionSyntax syntax;
  int start;
  int end;
}

// Text editing controller that can parse mentions
class MentionTextEditingController extends TextEditingController {
  MentionTextEditingController({
    this.controllerToCopyTo,
    required this.mentionSyntaxes,
    this.onSuggestionChanged,
    required this.mentionBgColor,
    required this.mentionTextColor,
    required this.mentionTextStyle,
    required this.runTextStyle,
    required this.idToMentionObject,
    super.text,
  }) {
    _init();
  }

  // Unique mention syntaxes, all syntaxes should have a different starting character
  final List<MentionSyntax> mentionSyntaxes;

  // Delegate called when suggestion has changed
  Function(MentionSyntax? syntax, String?)? onSuggestionChanged;

  // Function to get a mention from an id, used to deconstruct markup on construct
  final MentionObject? Function(BuildContext, String) idToMentionObject;

  // Background color of the text for the mention
  final Color mentionBgColor;

  // Color of the text for the mention
  final Color mentionTextColor;

  // EditingController to copy our text to, used for things like the Autocorrect widget
  TextEditingController? controllerToCopyTo;

  final List<TextMention> _cachedMentions = [];

  // Text style for the mention
  final TextStyle mentionTextStyle;

  // Text style for normal non-mention text
  final TextStyle runTextStyle;

  String _previousText = '';

  int? _mentionStartingIndex;
  int? _mentionLength;
  MentionSyntax? _mentionSyntax;

  List<TextMention> get mentions => _cachedMentions;

  @override
  void dispose() {
    removeListener(_onTextChanged);

    super.dispose();
  }

  // Set markup text, this is used when you get data that has the mention syntax and you want to initialize the textfield with it.
  void setMarkupText(BuildContext context, String markupText) {
    String deconstructedText = '';

    int lastStartingRunStart = 0;

    _cachedMentions.clear();

    for (int i = 0; i < markupText.length; ++i) {
      final String character = markupText[i];

      for (final MentionSyntax syntax in mentionSyntaxes) {
        if (character == syntax.prefix[0]) {
          final String subStr = markupText.substring(i, markupText.length);
          final RegExpMatch? match = syntax.getRegExp().firstMatch(subStr);
          // Ensure the match starts at the start of our substring
          if (match != null && match.start == 0) {
            deconstructedText += markupText.substring(lastStartingRunStart, i);

            final String matchedMarkup =
                match.input.substring(match.start, match.end);
            final String mentionId = match[3]!;
            final MentionObject? mention =
                idToMentionObject(context, mentionId);

            final String mentionDisplayName =
                mention?.displayName ?? syntax.missingText;

            final String insertText =
                '${syntax.startingCharacter}$mentionDisplayName';

            final int indexToInsertMention = deconstructedText.length;
            final int indexToEndInsertion =
                indexToInsertMention + insertText.length;

            _cachedMentions.add(TextMention(
                id: mentionId,
                display: insertText,
                start: indexToInsertMention,
                end: indexToEndInsertion,
                syntax: syntax));

            deconstructedText += insertText;
            lastStartingRunStart = i + matchedMarkup.length;
          }
        }
      }
    }

    if (lastStartingRunStart != markupText.length) {
      deconstructedText +=
          markupText.substring(lastStartingRunStart, markupText.length);
    }

    _previousText = deconstructedText;
    text = deconstructedText;
  }

  TextSpan _createSpanForNonMatchingRange(
      int start, int end, BuildContext context) {
    return TextSpan(text: text.substring(start, end), style: runTextStyle);
  }

  // Get the current search string for the mention (this is the mention minus the starting character. i.e. @Amber -> Amber)
  String getSearchText() {
    if (isMentioning()) {
      return text.substring(
          _mentionStartingIndex! + 1, _mentionStartingIndex! + _mentionLength!);
    }

    return '';
  }

  // Get the current search syntax for the current mention. This is useful when you have multiple syntaxes
  MentionSyntax? getSearchSyntax() {
    return _mentionSyntax;
  }

  // Get the text in the format that is readable by syntaxes. This will contain all text + syntax mentions (i.e. <###@USERID###>)
  String getMarkupText() {
    String finalString = '';
    int lastStartingRunStart = 0;

    for (int i = 0; i < _cachedMentions.length; ++i) {
      final TextMention mention = _cachedMentions[i];

      final int indexToEndRegular = mention.start;

      if (indexToEndRegular != lastStartingRunStart) {
        finalString += text.substring(lastStartingRunStart, indexToEndRegular);
      }

      final String markupString =
          '${mention.syntax.prefix}${mention.syntax.startingCharacter}${mention.id}${mention.syntax.suffix}';

      finalString += markupString;

      lastStartingRunStart = mention.end;
    }

    if (lastStartingRunStart < text.length) {
      finalString += text.substring(lastStartingRunStart, text.length);
    }

    return finalString;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> inlineSpans = [];
    int lastStartingRunStart = 0;

    for (int i = 0; i < _cachedMentions.length; ++i) {
      final TextMention mention = _cachedMentions[i];

      final int indexToEndRegular = mention.start;

      if (indexToEndRegular != lastStartingRunStart) {
        inlineSpans.add(_createSpanForNonMatchingRange(
            lastStartingRunStart, indexToEndRegular, context));
      }

      inlineSpans.add(TextSpan(
          text: text.substring(mention.start, mention.end),
          style: mentionTextStyle.copyWith(
              backgroundColor: mentionBgColor, color: mentionTextColor)));

      lastStartingRunStart = mention.end;
    }

    if (lastStartingRunStart < text.length) {
      inlineSpans.add(_createSpanForNonMatchingRange(
          lastStartingRunStart, text.length, context));
    }

    return TextSpan(children: inlineSpans);
  }

  void _init() {
    addListener(_onTextChanged);
    if (text.isNotEmpty) {
      _onTextChanged();
    }
  }

  Future<void> _onTextChanged() async {
    if (_previousText == text) {
      return;
    }

    // remove any mentions are have been altered
    final removedMention = _processTextChangeMentionRemove();

    if (!removedMention) {
      /// if no changes to the mentions, process the text
      _processTextChange();
    }

    _previousText = text;

    if (controllerToCopyTo != null) {
      controllerToCopyTo!.text = text;
    }
  }

  bool bGuardDeletion = false;

  // Insert a mention in the currently mentioning position
  void insertMention(MentionObject mention) {
    assert(isMentioning());

    final int mentionVisibleTextEnd =
        _mentionStartingIndex! + mention.displayName.length + 1;

    _cachedMentions.add(TextMention(
        id: mention.id,
        display: mention.displayName,
        start: _mentionStartingIndex!,
        end: mentionVisibleTextEnd,
        syntax: _mentionSyntax!));

    final int mentionStart = _mentionStartingIndex!;
    final int mentionEnd = _mentionStartingIndex! + _mentionLength!;
    final String startChar = _mentionSyntax!.startingCharacter;

    cancelMentioning();

    bGuardDeletion = true;
    text = text.replaceRange(
        mentionStart, mentionEnd, '$startChar${mention.displayName}');
    bGuardDeletion = false;

    selection = TextSelection.collapsed(
        offset: mentionVisibleTextEnd, affinity: TextAffinity.upstream);

    _sortMentions();
  }

  // Check if we are currently mentioning
  bool isMentioning() =>
      _mentionStartingIndex != null &&
      _mentionLength != null &&
      _mentionSyntax != null;

  void _sortMentions() {
    _cachedMentions.sort((TextMention a, TextMention b) {
      return a.start - b.start;
    });
  }

  // Cancel mentioning
  void cancelMentioning() {
    _mentionStartingIndex = null;
    _mentionLength = null;
    _mentionSyntax = null;

    if (onSuggestionChanged != null) {
      onSuggestionChanged!(null, null);
    }
  }

  List<Diff> diffTextChange() {
    return diff(_previousText, text);
  }

  bool _processTextChangeMentionRemove() {
    List<Diff> differences = diffTextChange();

    int currentTextIndex = 0;

    bool mentionTextRemoved = false;

    for (int i = 0; i < differences.length; ++i) {
      Diff difference = differences[i];

      int rangeStart = currentTextIndex;
      int rangeEnd = currentTextIndex + difference.text.length;

      // If we insert a character in a position then it should end the range on the last character, not after the last character
      if (difference.operation != DIFF_DELETE) {
        rangeEnd -= 1;
      }

      for (int x = _cachedMentions.length - 1; x >= 0; --x) {
        // if the key has gone skip it
        if (!_cachedMentions.asMap().containsKey(x)) continue;
        final TextMention mention = _cachedMentions[x];

        if (!bGuardDeletion) {
          if (difference.operation != DIFF_EQUAL) {
            if (rangeStart < mention.end && rangeEnd > mention.start) {
              // remove mention ref
              _cachedMentions.removeAt(x);
              // if change is within mention text, remove the text
              if (rangeStart >= mention.start && rangeEnd <= mention.end) {
                var replaceText = "";
                var cursorPosition = mention.start;
                if (difference.operation == DIFF_INSERT) {
                  replaceText = difference.text;
                }

                text = _previousText.replaceRange(
                    mention.start, mention.end, replaceText);
                selection = TextSelection.collapsed(
                    offset: cursorPosition, affinity: TextAffinity.upstream);
              }
              mentionTextRemoved = true;
              continue;
            }
          }
        }
      }
      if (difference.operation == DIFF_EQUAL) {
        currentTextIndex += difference.text.length;
      }

      if (difference.operation == DIFF_INSERT) {
        currentTextIndex += difference.text.length;
      }

      if (difference.operation == DIFF_DELETE) {
        currentTextIndex -= difference.text.length;
      }
    }
    return mentionTextRemoved;
  }

  void _processTextChange() {
    List<Diff> differences = diffTextChange();

    int currentTextIndex = 0;

    for (int i = 0; i < differences.length; ++i) {
      Diff difference = differences[i];

      if (difference.operation == DIFF_INSERT) {
        if (isMentioning()) {
          // Spaces are considered breakers for mentioning
          if (difference.text == " ") {
            cancelMentioning();
          } else {
            if (currentTextIndex <= _mentionStartingIndex! + _mentionLength! &&
                currentTextIndex >= _mentionStartingIndex! + _mentionLength!) {
              _mentionLength = _mentionLength! + difference.text.length;
              if (onSuggestionChanged != null) {
                onSuggestionChanged!(
                    _mentionSyntax!,
                    text.substring(_mentionStartingIndex!,
                        _mentionStartingIndex! + _mentionLength!));
              }
            } else {
              cancelMentioning();
            }
          }
        } else {
          for (int i = 0; i < mentionSyntaxes.length; ++i) {
            final MentionSyntax syntax = mentionSyntaxes[i];
            if (difference.text == syntax.startingCharacter) {
              _mentionStartingIndex = currentTextIndex;
              _mentionLength = 1;
              _mentionSyntax = syntax;
              if (onSuggestionChanged != null) {
                onSuggestionChanged!(_mentionSyntax!, syntax.startingCharacter);
              }
              break;
            }
          }
        }
      }

      if (difference.operation == DIFF_DELETE) {
        if (isMentioning()) {
          // If we removed our startingCharacter, chancel mentioning
          // TODO: This detects if *ANY* character contains our mention character, which isn't ideal..
          // But I have not yet figured out how to get whether we are currently deleting our starting character..
          // We can, however, find out if we are deleting our starting character AFTER our mention start so that names with the starting character don't cancel mentioning when backspacing
          if (difference.text.contains(_mentionSyntax!.startingCharacter) &&
              currentTextIndex <= _mentionStartingIndex!) {
            cancelMentioning();
          } else {
            if (currentTextIndex < _mentionStartingIndex!) {
              continue;
            }

            if (currentTextIndex > _mentionStartingIndex! + _mentionLength!) {
              continue;
            }

            _mentionLength = _mentionLength! - difference.text.length;
            assert(_mentionLength! >= 0);

            if (onSuggestionChanged != null) {
              onSuggestionChanged!(
                  _mentionSyntax!,
                  text.substring(_mentionStartingIndex!,
                      _mentionStartingIndex! + _mentionLength!));
            }
          }
        }
      }

      for (int x = _cachedMentions.length - 1; x >= 0; --x) {
        final TextMention mention = _cachedMentions[x];

        // keep mention position if it matches position.
        if (!hasMentionShifted(mention)) continue;

        // Not overlapping but we inserted text in front of metions so we need to shift them
        if (mention.start >= currentTextIndex &&
            difference.operation == DIFF_INSERT) {
          mention.start += difference.text.length;
          mention.end += difference.text.length;
        }

        // Not overlapping but we removed text in front of metions so we need to shift them
        if (mention.start >= currentTextIndex &&
            difference.operation == DIFF_DELETE) {
          mention.start -= difference.text.length;
          mention.end -= difference.text.length;
        }
      }

      if (difference.operation == DIFF_EQUAL) {
        currentTextIndex += difference.text.length;
      }

      if (difference.operation == DIFF_INSERT) {
        currentTextIndex += difference.text.length;
      }

      if (difference.operation == DIFF_DELETE) {
        currentTextIndex -= difference.text.length;
      }
    }
  }

  bool hasMentionShifted(TextMention mention) {
    if (mention.end > text.length) return true;
    final maybeMention = text.substring(mention.start, mention.end);
    final mentionName = "${mention.syntax.startingCharacter}${mention.display}";
    if (maybeMention != mentionName) return true;

    // mention matches text in position
    return false;
  }
}
