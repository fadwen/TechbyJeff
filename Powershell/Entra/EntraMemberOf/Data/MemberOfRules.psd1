@{
    <#
        What this module knows about the memberOf rule operator and its retirement, in one
        place. No other file names a date, a limit, a Review reason or a remediation sentence.

        Source, read on VerifiedOn:
            https://learn.microsoft.com/entra/identity/users/groups-dynamic-rule-member-of
        Raw Markdown, which the opt-in Tests/Integration/LearnPage.Tests.ps1 diffs against:
            MicrosoftDocs/entra-docs, docs/identity/users/groups-dynamic-rule-member-of.md
        Message Center item: MC1448379.

        The Learn page's own examples write the property in lower case:
            user.memberof -any (group.objectId -in ['groupId'])
            device.memberof -any (group.objectId -in ['groupId'])
        and its property tables write it as memberOf. Property names in rules are documented as
        case sensitive, but both spellings come from Microsoft, so the scanner matches the name
        case-insensitively and never reads anything into the casing.

        This is a data file: Import-PowerShellDataFile allows literals only, so the long
        sentences are here-strings wrapped for reading. Get-MemberOfRuleCatalog collapses the
        line breaks to single spaces when it loads them.
    #>

    SourceUrl       = 'https://learn.microsoft.com/entra/identity/users/groups-dynamic-rule-member-of'
    SourceDate      = '2026-08-04'
    VerifiedOn      = '2026-10-27'
    MessageCenterId = 'MC1448379'
    RetirementDate  = '2026-11-03'

    # What Learn says happens on that date, quoted so the module never says more than the page.
    RetirementEffect = @'
After November 3, 2026, dynamic membership groups, dynamic administrative units, and entitlement
management auto-assignment policies that use the memberOf operator stop updating and remain in
their last known state.
'@

    # The documented form. A rule is Retired when it uses one of the Properties as an
    # identifier outside a quoted string. Quantifier and Operator are what Learn shows; a rule
    # that uses something else is still Retired, with a note saying what it used.
    Retired = @{
        Properties     = @('user.memberOf', 'device.memberOf')
        SourceProperty = 'group.objectId'
        Quantifier     = 'any'
        Operator       = 'in'
    }

    # Preview limitations, from the Learn page. RuleMaxLength is from the dynamic membership
    # rules page (groups-dynamic-membership), which applies to every rule.
    Limits = @{
        MemberOfGroupsPerTenant = 500
        SourceGroupsPerGroup    = 50
        DynamicGroupsPerTenant  = 15000
        RuleMaxLength           = 3072
    }

    <#
        Review entries are never reported as Retired. Each is a rule that mentions memberOf in a
        way the documented operator form does not, or a rule the tokenizer could not read to
        the end, so a person has to look. The list is short on purpose: an entry here is a
        reason to read a rule, not a guess about what Microsoft will retire next.
    #>
    Review = @(
        @{
            Code   = 'StringLiteral'
            Reason = 'memberOf appears only inside a quoted string, where it is a value and not the operator.'
        }
        @{
            Code   = 'UnparsedRule'
            Reason = 'The rule could not be tokenized to the end, so the scanner cannot say what it uses.'
        }
        @{
            Code   = 'UnqualifiedMemberOf'
            Reason = @'
An identifier contains memberOf but is not user.memberOf or device.memberOf, the only documented
forms.
'@
        }
        @{
            Code   = 'MemberOfAsOperator'
            Reason = 'memberOf is written as an operator (-memberOf), which the documentation does not define.'
        }
    )

    # The migration guidance per object kind, from "Migrate before the preview ends". One
    # sentence each, kept to what the page says.
    Remediation = @{
        Group = @'
Replace memberOf with supported rule operators, or convert the group to assigned membership, then
validate the membership. If the group is no longer needed, pause or delete it.
'@
        AdministrativeUnit = @'
Replace the memberOf rule with supported logic, or convert the administrative unit to assigned
membership, then validate both membership and administrative scope. Delete the unit if it is no
longer needed.
'@
        AutoAssignmentPolicy = @'
Replace memberOf with supported attribute-based operators where possible. If no equivalent rule
is available, plan an alternative assignment method before retirement. Validate access package
assignments after the change.
'@
        Rule = @'
Replace memberOf with a supported rule operator, or convert the object to assigned membership,
then validate the result.
'@
    }
}
