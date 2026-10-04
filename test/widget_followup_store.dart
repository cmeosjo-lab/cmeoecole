import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';

// Widget tests use deterministic completed futures. Real SQLite and reset
// durability are covered separately by unit and Android integration tests.
class WidgetFollowUpStore extends LocalStore {
  final List<TeacherEvent> pendingItems;
  final List<TeacherEvent> historyItems;
  WidgetFollowUpStore(this.pendingItems, this.historyItems)
      : super(legacyValues: const {});
  @override
  Future<List<TeacherEvent>> loadQueue() async => pendingItems;
  @override
  Future<List<TeacherEvent>> loadFollowUpHistory({bool archived = false}) async =>
      archived ? [] : historyItems;
}
