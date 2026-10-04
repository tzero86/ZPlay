import 'service_credentials.dart';

/// Credentials inherited from the upstream PlayTorrio fork. Every one of them
/// ships blank: ZPlay ships no upstream keys and no upstream identities, so
/// each integration below is off on a fresh install until the owner supplies a
/// value at build time or a user supplies their own in Settings.
///
/// A blank entry is the deliberate end state, not a placeholder waiting to be
/// filled in. The map still exists because it is the bottom rung of the
/// value ladder in [ServiceCredentials], and because the reason each value is
/// gone is recorded inline so nobody restores one by accident.
const Map<ServiceCredential, String> legacyUpstreamCredentialValues = {
  // Blank: a key issued to the upstream developer's Wyzie account. Wyzie hands
  // out a free key of your own, so anyone who wants subtitles claims one.
  ServiceCredential.wyzie: '',
  // Blank: an upstream Google API key for Audionest search. It is the
  // developer's key, and a replacement has to come from their own Google
  // project.
  ServiceCredential.audiobookSearch: '',
  // Blank: the Audionest service bearer authenticates against a private
  // upstream backend that never issued it to ZPlay.
  ServiceCredential.audiobookService: '',
  // Blank: an upstream Paper2Audio key for an account with no public signup.
  ServiceCredential.paper2audio: '',
  // Blank: the cache cluster behind this token is upstream infrastructure, the
  // same operator as the two hosts in tmdb_helper and videasy. Supply your own
  // or leave this scraper switched off.
  ServiceCredential.vidgod: '',
  // Blank: the Films365 downloader bearer is a private upstream token, and the
  // host behind it is a machine the upstream developer runs.
  ServiceCredential.xdownloader: '',
  // Blank, and blank for a different reason from the five above: these two are
  // not upstream leftovers at all. Trakt issues an application id per app and
  // none can be shared or committed, so a fresh install always starts here and
  // this rung is never anything but empty. It is an entry rather than an
  // omission because the map has to name every credential the enum names, and
  // because the ladder's bottom rung is what `sourceFor` reports while the user
  // has not supplied their own app yet.
  ServiceCredential.trakt: '',
  ServiceCredential.traktSecret: '',
};
