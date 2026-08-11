local WidgetMergeA =
{
	Name = "TestWidgetA",
	Type = "ScriptObject",

	Functions =
	{
		{
			Name = "TestMergeSetThing",
			Type = "Function",
			SecretArgumentsAddAspect = { Enum.SecretAspect.Text },
			SecretArguments = "AllowedWhenTainted",
		},
		{
			Name = "TestMergeSetTimer",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "duration", Type = "LuaDurationObject", Nilable = false },
			},
		},
	},
};

APIDocumentation:AddDocumentationTable(WidgetMergeA);

local WidgetMergeB =
{
	Name = "TestWidgetB",
	Type = "ScriptObject",

	Functions =
	{
		{
			Name = "TestMergeSetThing",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",
		},
	},
};

APIDocumentation:AddDocumentationTable(WidgetMergeB);

-- Reviewer fix: an unrecognized future SecretArguments spelling merging into
-- a key whose previous entry carries NO secretArguments at all must still
-- survive (unknown spellings rank most-restrictive, not "no flag").
local WidgetMergeC =
{
	Name = "TestWidgetC",
	Type = "ScriptObject",

	Functions =
	{
		{
			Name = "TestMergeUnknownMode",
			Type = "Function",
			SecretWhenCooldownsRestricted = true,
		},
	},
};

APIDocumentation:AddDocumentationTable(WidgetMergeC);

local WidgetMergeD =
{
	Name = "TestWidgetD",
	Type = "ScriptObject",

	Functions =
	{
		{
			Name = "TestMergeUnknownMode",
			Type = "Function",
			SecretArguments = "SomeFutureMode",
		},
	},
};

APIDocumentation:AddDocumentationTable(WidgetMergeD);

-- Round-22b regression (review): ConditionalSecretContents must survive a
-- cross-system collision where only ONE entry carries the flag. Before
-- conditionalSecretContents joined MERGE_BOOL_KEYS, the unflagged-first /
-- flagged-second direction silently dropped it. E (no flag) is defined
-- BEFORE F (flag) so F merges into an existing unflagged entry — the
-- direction that failed.
local WidgetMergeE =
{
	Name = "TestWidgetE",
	Type = "ScriptObject",

	Functions =
	{
		{
			Name = "TestMergeCondContents",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",
		},
	},
};

APIDocumentation:AddDocumentationTable(WidgetMergeE);

local WidgetMergeF =
{
	Name = "TestWidgetF",
	Type = "ScriptObject",

	Functions =
	{
		{
			Name = "TestMergeCondContents",
			Type = "Function",
			SecretArguments = "AllowedWhenUntainted",

			Returns =
			{
				{ Name = "things", Type = "table", Nilable = false, ConditionalSecretContents = true },
			},
		},
	},
};

APIDocumentation:AddDocumentationTable(WidgetMergeF);
