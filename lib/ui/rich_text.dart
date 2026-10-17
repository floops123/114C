import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Mise en forme légère des messages du salon : **gras**, *italique*,
/// ~~barré~~, `code`, liens cliquables et mentions (@pseudo, ou {{pseudo}}
/// tel que le site les enregistre).
final _token = RegExp(
  r'(?<url>https?://[^\s<>"]+[^\s<>".,;:!?)\]])'
  r'|\*\*(?<bold>.+?)\*\*'
  r'|~~(?<strike>.+?)~~'
  r'|`(?<code>[^`\n]+)`'
  r'|(?<![\w*])\*(?<italic>[^\s*](?:[^*\n]*[^\s*])?)\*(?![\w*])'
  r'|(?<![\w@])@(?<mention>[\w.\-]{2,32})'
  r'|\{\{(?<tag>[^{}\s]{1,32})\}\}',
);

String? _mention(RegExpMatch m) =>
    m.namedGroup('mention') ?? m.namedGroup('tag');

/// Le message mentionne-t-il [me] (insensible à la casse) ?
bool mentions(String text, String? me) {
  if (me == null || me.isEmpty) return false;
  final lower = me.toLowerCase();
  return _token.allMatches(text).any(
      (m) => _mention(m)?.toLowerCase() == lower);
}

List<InlineSpan> chatSpans(String text,
    {required AppColors colors, String? me}) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _token.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    last = m.end;

    final url = m.namedGroup('url');
    final mention = _mention(m);
    if (url != null) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _Link(url),
      ));
    } else if (m.namedGroup('bold') != null) {
      spans.add(TextSpan(
          text: m.namedGroup('bold'),
          style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (m.namedGroup('strike') != null) {
      spans.add(TextSpan(
          text: m.namedGroup('strike'),
          style: const TextStyle(decoration: TextDecoration.lineThrough)));
    } else if (m.namedGroup('code') != null) {
      spans.add(TextSpan(
        text: ' ${m.namedGroup('code')} ',
        style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            backgroundColor: colors.surfaceAlt),
      ));
    } else if (m.namedGroup('italic') != null) {
      spans.add(TextSpan(
          text: m.namedGroup('italic'),
          style: const TextStyle(fontStyle: FontStyle.italic)));
    } else if (mention != null) {
      final isMe = me != null && mention.toLowerCase() == me.toLowerCase();
      spans.add(TextSpan(
        text: '@$mention',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colors.accent,
          backgroundColor: isMe ? colors.accent.withValues(alpha: 0.15) : null,
        ),
      ));
    }
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

class _Link extends StatelessWidget {
  const _Link(this.url);
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final uri = Uri.tryParse(url);
    // Affichage raccourci : domaine + début du chemin.
    final label = uri == null
        ? url
        : '${uri.host}${uri.path.length > 28 ? '${uri.path.substring(0, 28)}…' : uri.path}';
    return Tooltip(
      message: url,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: uri == null
              ? null
              : () => launchUrl(uri, mode: LaunchMode.externalApplication),
          child: Text(
            label,
            style: TextStyle(
              color: c.accent,
              decoration: TextDecoration.underline,
              decorationColor: c.accent.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
