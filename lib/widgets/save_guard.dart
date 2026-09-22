import 'package:flutter/material.dart';

mixin SaveGuard<T extends StatefulWidget> on State<T> {
  bool saving = false;

  Future<void> runSave(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
