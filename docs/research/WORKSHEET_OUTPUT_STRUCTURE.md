# Experimental worksheet output structure

`emitExcel(ir, {entrypoint, arguments, includeOutputStructure: true})` adds
`outputStructure` alongside the existing scalar outputs. The default remains
unchanged. This is source metadata, not a delivered workbook or a successor-input
reconstruction API.

## Contract

- `schema` is `gd-output-structure-v1`.
- `availability` is the emitter's global source-availability predicate.
- `root` describes a Dictionary, Array, scalar, conditional choice or absent arm.
- Every node has source `segments` and a Boolean `presence` expression. Segments
  preserve String keys and integer array indices without parsing dotted paths.
- Dictionary `entries` is an ordered list of `{key, node}`. `order` is either
  `source-insertion` or `unproved`. The latter must not be treated as a proved
  round-trip ordering. Branch-merged containers can retain unproved order even
  when every member is present.
- Array `length` is the live length expression. `items` describes finite backing
  slots; an item's presence predicate determines whether it belongs to the live
  array. Capacity is not length. Empty containers remain explicit nodes.
- A choice retains its source condition and both structural alternatives. A
  scalar records its category and numeric-subtype descriptor, not an observed
  cell value. An absent arm is not an empty container or numeric zero.

Predicates use the same helper graph as the scalar outputs. They are liveness
roots and are rewritten during helper compaction. Consumers must retain those
formulas, evaluate availability/presence strictly, and not infer presence from
an output's displayed value. Intentional absent scalar outputs can contain
`#N/A`; those are distinct from unexpected helper errors.

## Limits

This metadata closes the information gap in scalar-only flattening: an empty
Dictionary member, an empty object inside an Array, or uncertain Dictionary order
cannot be recovered from scalar leaf paths alone. It does not discharge that
uncertainty, prove a complete compositional round trip, validate an actual
spreadsheet engine, or qualify a 192-quarter workbook. The maintained game and
production workbook builder do not consume this experimental API.
