# Schema provenance

`opc-contentTypes.xsd` and `opc-relationships.xsd` are unmodified byte extracts
from `OpenPackagingConventions-XMLSchema.zip` in the official ECMA-376 Part 2
fifth-edition (December 2021) archive:
https://ecma-international.org/wp-content/uploads/ECMA-376-2_5th_edition_december_2021.zip

Archive SHA-256: `1d489dc491168ea1f9e9a59063acc8dd5f02b4ad1d21aa7ec19ba9a58d020c70`.
They are standard schema data, not an installed dependency or Graphink-authored
schemas. See the [official publication](https://ecma-international.org/publications-and-standards/standards/ecma-376/)
for the standard and applicable publication notices.

`graphink-document-v1.xsd` is an original profile schema. Its native-color slot
is intentionally delegated: the independent checker restricts current compact
native attributes/structure, and native product tests must establish actual
NSColor archive/pattern/catalog decoding fidelity. XSD success alone is not that
proof. Versions/required features are semantically checked separately so unknown
versions/features produce unsupported-profile errors, not false schema promises.
