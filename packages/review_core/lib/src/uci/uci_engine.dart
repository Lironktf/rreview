/// The minimal engine transport the review core needs: UCI text in, lines out.
abstract class UciEngine {
  Stream<String> get lines;
  void send(String command);
  Future<void> dispose();
}
