# Experimental source-output composition

The maintained game and production workbook builder do not import this module.
Its operations consume emitted formulas and source metadata, not observed or
expected economic successor values. They do not run a spreadsheet engine.

## Complete source-shape view

`composeWholeOutputs(graph, options)` consumes:

- `formulas`: the existing upstream formula graph;
- `cellTypes`: declared upstream input cells and their scalar types;
- `descriptors`: source output path/cell/type/presence metadata;
- `structure`: the emitter's opt-in `gd-output-structure-v1` tree.

The result contains an input-binding `value`, fresh Boolean admission `formulas`,
`readyCell`, structural constraints and provenance hashes. The caller must add
the fresh formulas without overwriting upstream cells and **gate every
successor output with `readyCell`**. An unavailable view is not a valid input.

The operation preserves explicit empty containers, source-ordered Dictionary
entries and finite Array slots. Choices and ancestor presence contribute runtime
admission predicates; no large Boolean tautology is assumed. Numeric bindings
retain an exact uniform source subtype. Missing, errored or non-Boolean admission
predicates cannot create a healthy successor.

`prefix` selects a source subtree, such as `state`. Optional `dictionaryKeys`
selects an exact complete Dictionary key-set domain among source alternatives;
it neither supplies values nor determines the Dictionary's source insertion
order. If that source alternative is inactive, the selected view is unavailable.
Keys absent from the source cannot be invented by a selector.

The initial input protocol represents one fixed finite shape. Mixed container
shapes, differing scalar categories/subtypes and unproved Dictionary order
refuse. Complete-capacity Array views require the source's live length to match
their represented slots; shorter arrays cannot be silently padded or truncated.
Numeric-looking Dictionary output paths remain outside the current scalar
descriptor protocol. These are explicit subset limits, not full-domain claims.

All metadata/dependencies are admitted before helper allocation, including
inactive and unselected alternatives. Callbacks/accessors, cycles, source-path
contradictions, unbound dependencies and helper collisions refuse. Plain-data
hashes attribute sources; they do not authenticate a producer or establish
custody. The caller must retain the source-bound emitter artifact.

## Earlier leaf projection and bounded proof

`composeOutputs` remains a leaf-projection API. It cannot recover an empty
container or complete Dictionary order from scalar paths alone. Its `adopted`
projection is usable only under its exact readiness guard and separately proved
whole-object coverage. It is not a replacement for the complete source-tree API.

`BooleanProof` is a bounded over-approximation over declared Boolean formulas.
Only a proved result permits dropping an alternative. Exhaustion means unknown,
not false, and never authorizes clearing source guards. Its small independent
truth-table tests are not a formal proof of the compiler or economic model.

Actual saved-file recalculation, editable-policy restoration, production adoption,
all shipping scenarios and full-horizon qualification remain separate work.
