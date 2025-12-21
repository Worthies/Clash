import 'package:flutter/material.dart';

/// Helper class to handle emoji and Unicode text rendering
class EmojiTextHelper {
  /// Extract emoji from text using Unicode code point ranges
  static String extractEmoji(String text) {
    final buffer = StringBuffer();
    final runes = text.runes.toList();

    for (int i = 0; i < runes.length; i++) {
      final rune = runes[i];

      // Check if rune is in emoji Unicode ranges
      final isEmoji = _isEmojiCharacter(rune);

      // Also handle emoji followed by variation selector (U+FE0E or U+FE0F)
      if (isEmoji) {
        buffer.writeCharCode(rune);
        // Include variation selector if next character is one
        if (i + 1 < runes.length) {
          final nextRune = runes[i + 1];
          if (nextRune == 0xFE0E || nextRune == 0xFE0F) {
            buffer.writeCharCode(nextRune);
            i++; // Skip the variation selector in next iteration
          }
        }
      }
    }
    return buffer.toString();
  }

  /// Check if a Unicode code point is an emoji
  static bool _isEmojiCharacter(int rune) {
    // Emoji ranges:
    // - Enclosed Alphanumerics: U+2460..U+24FF (includes ① ② ③ Ⓜ️ etc)
    // - Emoticons: U+1F600..U+1F64F
    // - Miscellaneous Symbols: U+2600..U+26FF
    // - Dingbats: U+2700..U+27BF
    // - Box Drawing: U+2500..U+257F (sometimes used as decorative)
    // - Block Elements: U+2580..U+259F
    // - Geometric Shapes: U+25A0..U+25FF
    // - Miscellaneous Symbols and Pictographs: U+1F300..U+1F5FF
    // - Transport and Map: U+1F680..U+1F6FF
    // - Supplemental Symbols and Pictographs: U+1F900..U+1F9FF
    // - Emoticons Extended: U+1F300..U+1F9FF (broader range)

    return (rune >= 0x2460 && rune <= 0x24FF) || // Enclosed alphanumerics (Ⓜ️)
        (rune >= 0x1F300 && rune <= 0x1F9FF) || // Misc symbols, emoticons, transport, etc
        (rune >= 0x2600 && rune <= 0x26FF) || // Misc symbols
        (rune >= 0x2700 && rune <= 0x27BF) || // Dingbats
        (rune >= 0x1F600 && rune <= 0x1F64F) || // Emoticons
        (rune >= 0x1F900 && rune <= 0x1F9FF) || // Supplemental symbols
        (rune >= 0x2500 && rune <= 0x259F); // Box drawing and blocks
  }

  /// Remove emoji from text, leaving only the name
  static String removeEmoji(String text) {
    final buffer = StringBuffer();
    final runes = text.runes.toList();

    for (int i = 0; i < runes.length; i++) {
      final rune = runes[i];

      // Skip emoji and their variation selectors
      if (_isEmojiCharacter(rune)) {
        // Also skip variation selector if next character is one
        if (i + 1 < runes.length) {
          final nextRune = runes[i + 1];
          if (nextRune == 0xFE0E || nextRune == 0xFE0F) {
            i++; // Skip the variation selector
          }
        }
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().trim();
  }

  /// Split proxy name into emoji and text parts
  static Map<String, String> splitProxyName(String name) {
    final emoji = extractEmoji(name);
    final text = removeEmoji(name);
    return {'emoji': emoji, 'text': text.isEmpty ? name : text};
  }
}

/// Widget to display proxy name with proper emoji support
class ProxyNameWithEmoji extends StatelessWidget {
  final String name;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  const ProxyNameWithEmoji(this.name, {this.style, this.maxLines = 1, this.overflow = TextOverflow.ellipsis, super.key});

  @override
  Widget build(BuildContext context) {
    final parts = EmojiTextHelper.splitProxyName(name);
    final emoji = parts['emoji'] ?? '';
    final text = parts['text'] ?? '';

    if (emoji.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Emoji with slightly larger font for visibility
        Text(
          emoji,
          style: (style ?? const TextStyle()).copyWith(fontSize: (style?.fontSize ?? 14) + 2),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 4),
        // Proxy name text
        Expanded(
          child: Text(text, style: style, maxLines: maxLines, overflow: overflow),
        ),
      ],
    );
  }
}
