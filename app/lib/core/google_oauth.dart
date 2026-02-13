import 'google_oauth_web.dart' if (dart.library.io) 'google_oauth_io.dart';

Future<void> signInWithGoogleUnified() => signInWithGoogleImpl();
