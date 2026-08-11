local TestEnumRefs =
{
    Name = "TestEnumRefs",
    Namespace = "C_TestEnumRefs",
    Type = "System",

    Functions =
    {
        {
            Name = "GetAspectValue",
            Type = "Function",
            SecretReturnsForAspect = { Enum.SecretAspect.Alpha },
            SecretWhenCooldownsRestricted = true,
            Returns = { { Name = "value", Type = "number", Nilable = false } },
        },
        {
            Name = "SetAspectValue",
            Type = "Function",
            SecretArgumentsAddAspect = { Enum.SecretAspect.Alpha },
            SecretArguments = "AllowedWhenUntainted",
            Arguments = { { Name = "value", Type = "number", Nilable = false } },
        },
        {
            Name = "GetConstantsValue",
            Type = "Function",
            MaxResults = Constants.TestConsts.MAX_RESULTS,
            SecretArguments = "NotAllowed",
            Returns = { { Name = "value", Type = "number", Nilable = false } },
        },
    },
}

APIDocumentation:AddDocumentationTable(TestEnumRefs)
