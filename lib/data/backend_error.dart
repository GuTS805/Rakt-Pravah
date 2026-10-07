/// A write the server never confirmed, with a plain-language reason.
///
/// Firestore holds a write until the server acknowledges it, so with no
/// connection (or no database behind the project) the call never finishes and
/// the screen would sit on a spinner. The backend gives up after a few seconds,
/// asks the server what is wrong, and throws this instead.
class BackendUnavailable implements Exception {
  const BackendUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
