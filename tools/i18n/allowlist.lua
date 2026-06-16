-- Shared allowlist for QUI i18n string extraction/wrapping.
-- WRAP the value of these table keys:
return {
    wrapKeys = {
        "label", "description", "desc", "title", "message", "warningText",
        "acceptText", "cancelText", "text", "question", "answer", "header",
        "tooltip", "name",   -- NOTE: "name" is ambiguous; reviewer must confirm it is display text, not a dbKey
    },
    -- WRAP the string literal at these (function, 1-based arg index) sites:
    wrapArgs = {
        { fn = "BuildSettingRow",        arg = 2 },  -- (parent, LABEL, widget, desc)
        { fn = "BuildSettingRow",        arg = 4 },  -- (..., DESC)
        { fn = "CreateAccentDotLabel",   arg = 2 },  -- (content, HEADER, y)
        { fn = "headerAt",               arg = 1 },
        { fn = "CreateQA",               arg = 2 },  -- (content, QUESTION, ANSWER, y, w)
        { fn = "CreateQA",               arg = 3 },
    },
    -- NEVER wrap the value of these keys (non-user data):
    denyKeys = {
        "dbKey", "key", "id", "value", "url", "iconTexture", "atlas",
        "texture", "moverKey", "event", "command", "navType", "tileId",
    },
}
