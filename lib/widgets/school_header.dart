import 'package:flutter/material.dart';

class SchoolHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? teacher;

  const SchoolHeader({super.key, required this.title, required this.subtitle, this.teacher});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF183D39), Color(0xFF286F66)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x16000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withOpacity(.16)),
            ),
            child: const Icon(Icons.school_outlined, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Text(
            'GESTCOURS  •  PROF',
            style: TextStyle(
              color: scheme.surface.withOpacity(.78),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ]),
        const SizedBox(height: 17),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            height: 1.08,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        if (subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 14)),
        ],
        if (teacher != null && teacher!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_outline, size: 17, color: Colors.white),
              const SizedBox(width: 7),
              Flexible(child: Text(teacher!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            ]),
          ),
        ],
      ]),
    );
  }
}
