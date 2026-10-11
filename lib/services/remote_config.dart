/// Settings of the shared lesson storage (Supabase, free plan).
///
/// BOTH values below are PUBLIC by design: the project URL and the "anon"
/// (public) key are meant to be shipped inside the app. They give READ access
/// to the lesson list and the lesson files and nothing else. Writing is only
/// possible through the server function `teacher-publish`, which checks the
/// teachers' shared password on the SERVER. NEVER put the service-role key or
/// the teachers' password here or anywhere in this repository.
///
/// While both are empty the app works exactly as before (local lessons, manual
/// export/import) and says plainly that online sync is not enabled yet.
/// See SUPABASE_SETUP_AR.md for the 10-minute setup.
const String kSupabaseUrl = '';
const String kSupabaseAnonKey = '';
