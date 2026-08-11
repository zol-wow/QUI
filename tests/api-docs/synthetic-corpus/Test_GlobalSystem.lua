-- Synthetic doc fixture: a namespace-LESS system ("Unit"/"PlayerScript"
-- shape). Its functions are bare GLOBALS at runtime, so the extractor must
-- key them bare — a "TestGlobal.X" key would never match a call site.
local TestGlobal =
{
	Name = "TestGlobal",
	Type = "System",

	Functions =
	{
		{
			Name = "GetGlobalStatValue",
			Type = "Function",
			SecretWhenUnitStatsRestricted = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "unit", Type = "cstring", Nilable = false },
			},

			Returns =
			{
				{ Name = "value", Type = "number", Nilable = false },
			},
		},
		{
			Name = "GetGlobalSecretReturner",
			Type = "Function",
			SecretReturns = true,

			Returns =
			{
				{ Name = "value", Type = "number", Nilable = false },
			},
		},
		{
			Name = "GetGlobalCleanValue",
			Type = "Function",

			Returns =
			{
				{ Name = "value", Type = "number", Nilable = false },
			},
		},
	},
}

APIDocumentation:AddDocumentationTable(TestGlobal)
