-- Comments tools/strip_comments.sh must NOT remove, because something other
-- than a human reader depends on the text being there.
--
-- CURATED, not generated. It was generated once, by harvesting every string
-- literal in the test tree, and that harvest kept 4,495 lines of prose nothing
-- actually needed — an anchor can only ever preserve a comment, so a shotgun
-- harvest fails safe and silently. Discovery still lives in
-- tools/strip_comments_anchors.lua; run it when a new test starts depending on
-- comment text, then add the specific string here with a reason.
--
-- Entries are matched as Lua PATTERNS when they contain a `%`, and as plain
-- text otherwise (a rule of dashes read as a pattern is nested lazy
-- quantifiers — `-` IS the lazy repeat — and backtracks for minutes).
return {
    -- Labels the `do -- Inlined from X.lua ... end` blocks in the merged CDM
    -- chunks, which tests/helpers/load_cdm_consolidated_chunk.lua slices on.
    -- Those files are merged BECAUSE of Lua 5.1's 60-upvalue / 200-local cap,
    -- so a code-side label would spend the exact budget the merge exists to
    -- save.
    "-- Inlined from ",

    -- Explicit `-- <<< NAME` / `-- >>> NAME` extraction seams that let a test
    -- reach a local inside a file too large to load headless. The alternative
    -- is exporting those locals on ns, which is permanent runtime API surface
    -- and is guarded by a "this list may only shrink" assertion.
    "QUI_TEST_EXTRACT",

    -- Taint-analyzer suppressions (tests/taint/annotations.lua). 403 of them.
    -- These are not documentation at all — they are the input language of gate
    -- 2, and deleting one turns a suppressed finding back into a gate failure.
    -- An annotation on its own line binds to the next NON-BLANK line, so
    -- removing a plain comment that sat between the annotation and its code
    -- only ever moves the binding from a comment (where it suppressed nothing)
    -- onto the code it was written for.
    "@secret%-safe:",
    "@secret%-policy:",

    -- Everything below is a comment the suite asserts on DIRECTLY: the
    -- explanation is the artifact under test, so there is no code-side
    -- equivalent to re-anchor to. Deleting one does not relocate the
    -- guardrail, it removes it.

    -- tests/unit/actionbars_extra_button_combat_gate_test.lua. Dropping the
    -- gate on a "both frames are unprotected" premise shipped live taint once.
    "COMBAT GATE (load-bearing)",
    "COMBAT GATE (extra path)",
    "DUAL-MOVER INVARIANT",
    "DELIBERATE SAFETY EXCEPTION",
    "deliberate safety exception",
    "SESSION-LONG OWNERSHIP",
    "NO-OVERRIDE FALLBACK",
    "no secure descendant",
    "We never call ExtraAbilityContainer:RemoveFrame",
    -- The takeover must NOT touch the manager's showingFrames table, so the
    -- only place the name may appear is the comment explaining the omission.
    -- The test asserts both halves: no write, and a reason on record.
    "showingFrames",

    -- tests/unit/skinning_protected_defer_lifecycle_test.lua — the defer
    -- helpers must name the FrameXML lifecycle they are timed against, or the
    -- next reader "simplifies" the delay back into a race.
    "FrameXML DirtiableMixin:MarkDirty uses RunNextFrame",
    "FrameXML OverrideActionBarMixin:UpdateSkin resets skin, size, actionpage, buttons, and status bars",

    -- tests/unit/inspect_pane_lifecycle_regression_test.lua
    "FrameXML InspectFrame_OnEvent calls ShowUIPanel(InspectFrame) before InspectFrame_UpdateTabs()",

    -- tests/unit/instanceframes_lifecycle_test.lua — the comment must describe
    -- what SkinBase composition actually does now, not what it used to.
    "HookScrollBoxAcquired composes callbacks",
    "single qScrollHooked flag makes a second hook a no-op",

    -- tests/unit/safecall_test.lua — the probe-order constraint has to cite the
    -- Blizzard source that imposes it.
    "Blizzard_ScriptErrorsFrame.lua:95-105",

    -- tests/unit/cdm_blizzard_reference_test.lua — maintainer docs must link
    -- the machine-readable reference and name the two decode paths.
    "tests/api-docs/cdm_blizzard_reference.lua",
    "SetCooldownFromDurationObject",
    "C_CurveUtil.EvaluateColorValueFromBoolean",
}
