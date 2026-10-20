import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// The app's strings, with English as the fallback when a widget is pumped
/// without the app's localization delegates.
///
/// Production always has the delegates from `main.dart`. A widget test that
/// pumps a page in a plain `MaterialApp` does not, and a generated
/// `AppLocalizations.of(context)` would throw there; the English bundle keeps
/// those tests meaningful without making every test host carry the delegates.
AppLocalizations l10nOf(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    lookupAppLocalizations(const Locale('en'));
