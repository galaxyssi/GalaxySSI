# Local door access on iOS

Import your own Door Access `.gskill` package in the Skill Marketplace and
enable it. No door configuration, account, or example package is bundled.
The package must contain only the manifest and its SHA-256 integrity
record. Integrity checks detect corruption; they do not authenticate the
person who supplied the package. Review the source before enabling it.

Open the panel from the marketplace, or enable automatic invocation on the
Skill and enter one of its exact aliases in the Agent composer. A list
alias only loads doors; an open alias selects the matching door for
confirmation. The local panel never sends the command or account to an
Agent model or paired Desktop. Credentials are held in device-only
Keychain and can be removed from the panel.

An unlock requires one unambiguous configured door, a foreground
confirmation, and an unused confirmation less than 30 seconds old.
The service is contacted directly over HTTPS. Acceptance is not evidence
that the door opened. A lost or interrupted reply is not retried; the
panel remembers the uncertain request until you confirm that you checked
the door.

The XCTest fixtures use a simulated service. They do not open a real
door, use personal configuration, or validate Wear OS behavior.
