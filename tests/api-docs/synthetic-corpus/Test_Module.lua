local TestSpell =
{
    Name = "Test",
    Namespace = "C_Test",
    Type = "System",

    Functions =
    {
        {
            Name = "GetSecretValue",
            Type = "Function",
            SecretWhenCooldownsRestricted = true,
            Returns = { { Name = "value", Type = "number", Nilable = false } },
        },
        {
            Name = "GetCleanValue",
            Type = "Function",
            Returns = { { Name = "value", Type = "number", Nilable = false } },
        },
        {
            Name = "RestrictedReturn",
            Type = "Function",
            SecretArguments = "Restricted",
            Returns = { { Name = "value", Type = "number", IsSecret = true } },
        },
        {
            Name = "GuardedGetter",
            Type = "Function",
            RequiresUnitAuraAccess = true,
            SecretArguments = "AllowedWhenTainted",
            Returns = { { Name = "value", Type = "number", Nilable = false } },
        },
    },

    Events =
    {
        {
            Name = "TestSecretEvent",
            Type = "Event",
            LiteralName = "TEST_SECRET_EVENT",
            SecretInActivePvPMatch = true,
            Payload =
            {
                { Name = "unit", Type = "cstring", Nilable = false },
            },
        },
        {
            Name = "TestSecretPayloadEvent",
            Type = "Event",
            LiteralName = "TEST_SECRET_PAYLOAD_EVENT",
            Payload =
            {
                { Name = "spellID", Type = "number", Nilable = false, SecretWhenUnitSpellCastRestricted = true },
            },
        },
        {
            Name = "TestCleanEvent",
            Type = "Event",
            LiteralName = "TEST_CLEAN_EVENT",
            Payload =
            {
                { Name = "value", Type = "number", Nilable = false },
            },
        },
    },
}

APIDocumentation:AddDocumentationTable(TestSpell)
