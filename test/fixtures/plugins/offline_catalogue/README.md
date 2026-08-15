# Offline Catalogue

A fixture plugin that is honest about needing nothing: `permissions` is empty
because it serves a catalogue bundled inside the plugin and never opens a
connection.

It exists to prove a specific point about the validator. `search` and `catalog`
usually reach an external service, so the validator says so — but only as an
INFO note. A manifest like this one must pass `--strict` cleanly, because
whether a plugin actually opens a socket is not decidable from its manifest and
the runtime already enforces the truth.
