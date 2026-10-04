/// Trakt API constants.
library;

import '../config/service_credentials.dart';

/// The Trakt application credentials, through the same ladder every other
/// third-party credential uses: a value the user pasted in Settings, then a
/// build-time `--dart-define`/`.env`, then nothing.
///
/// They used to read [EnvService] directly, which meant a build without a `.env`
/// had an empty `client_id` - and Trakt answers `POST /oauth/device/code` with a
/// 400 for that, so the pairing flow never started and the page could only say
/// the pairing code could not be requested. The build-time rung is the same
/// value it always was: [ServiceCredentials] resolves `TRAKT_CLIENT_ID` and
/// `TRAKT_CLIENT_SECRET` for its build-time step.
String get kTraktClientId => ServiceCredentials.value(ServiceCredential.trakt);

String get kTraktClientSecret =>
    ServiceCredentials.value(ServiceCredential.traktSecret);

/// The optional half of a Trakt OAuth body.
///
/// Trakt's own documentation now calls the client secret deprecated for user
/// sign-in - "should only be used server to server" - while the device flow
/// still accepts one. Sending it only when the user has supplied it means a
/// setup that wants the secret keeps working and a setup that never pastes one
/// is not blocked on finding it. Spread it into the body:
/// `{ 'client_id': kTraktClientId, ...kTraktOptionalClientSecret, ... }`.
Map<String, String> get kTraktOptionalClientSecret => {
  if (kTraktClientSecret.trim().isNotEmpty)
    'client_secret': kTraktClientSecret,
};

/// The Trakt page that issues an application's client id and secret.
///
/// Taken from Trakt's own documentation rather than from memory: the app
/// settings page lives at `app.trakt.tv`, and the older
/// `trakt.tv/oauth/applications` path is not what their docs link to.
const String kTraktAppRegistrationUrl = 'https://app.trakt.tv/settings/apps/api/new';

const String kTraktApiBaseUrl = 'https://api.trakt.tv';
const String kTraktTokenUrl = '$kTraktApiBaseUrl/oauth/token';

const String kTraktDeviceCodeUrl = '$kTraktApiBaseUrl/oauth/device/code';
const String kTraktDeviceTokenUrl = '$kTraktApiBaseUrl/oauth/device/token';

const String kTraktApiVersion = '2';
