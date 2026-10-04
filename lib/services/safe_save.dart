import 'user_message.dart';
import 'package:flutter/material.dart';

mixin SafeSave<T extends StatefulWidget> on State<T> {
  bool saving = false;
  Future<void> saveGuarded(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              userMessage(
                e,
                fallback:
                    'L’enregistrement n’a pas abouti. Vérifiez les champs puis réessayez. Le formulaire reste ouvert.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
