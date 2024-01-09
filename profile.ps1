$requiredModules = @{
    'ClassExplorer'              = @{}
    'EditorServicesCommandSuite' = @{
        AllowPrerelease = $true
        RequiredVersion = '1.0.0-beta4'
    }
}

$requiredModules.GetEnumerator() | ForEach-Object {
    if (-not (Get-Module $_.Key -ListAvailable)) {
        $arg = $_.Value
        Install-Module $_.Key @arg -Scope CurrentUser
    }
    Import-Module $_.Key -Force
}

if ($psEditor) {
    Import-CommandSuite
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}

class CultureCompleter : System.Management.Automation.IArgumentCompleter {
    static [System.Collections.Generic.List[System.Management.Automation.CompletionResult]] $Completions
    static [cultureinfo[]] $Cultures

    static CultureCompleter() {
        [CultureCompleter]::Completions = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
        [CultureCompleter]::Cultures = [cultureinfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures)
    }

    [System.Collections.Generic.IEnumerable[System.Management.Automation.CompletionResult]] CompleteArgument(
        [string] $commandName,
        [string] $parameterName,
        [string] $wordToComplete,
        [System.Management.Automation.Language.CommandAst] $commandAst,
        [System.Collections.IDictionary] $fakeBoundParameters) {

        [CultureCompleter]::Completions.Clear()
        $word = [regex]::Escape($WordToComplete)

        foreach ($culture in [CultureCompleter]::Cultures) {
            if ($culture.Name -notmatch $word -and $culture.DisplayName -notmatch $word) {
                continue
            }

            [CultureCompleter]::Completions.Add([System.Management.Automation.CompletionResult]::new(
                $culture.Name,
                [string]::Format('{0}, {1}', $culture.Name, $culture.DisplayName),
                [System.Management.Automation.CompletionResultType]::ParameterValue,
                $culture.DisplayName))
        }

        return [CultureCompleter]::Completions
    }
}

function Use-Culture {
    param(
        [Parameter(Mandatory)]
        [ArgumentCompleter([CultureCompleter])]
        [cultureinfo] $Culture,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    end {
        $PrevCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        $PrevCultureUI = [Threading.Thread]::CurrentThread.CurrentUICulture

        try {
            [Threading.Thread]::CurrentThread.CurrentCulture =
            [Threading.Thread]::CurrentThread.CurrentUICulture = $Culture

            $ScriptBlock.Invoke()
        }
        finally {
            [Threading.Thread]::CurrentThread.CurrentCulture = $PrevCulture
            [Threading.Thread]::CurrentThread.CurrentUICulture = $PrevCultureUI
        }
    }
}

function prompt {
    "PS $($PWD.Path -replace '.+(?=\\)', '..')$('>' * ($nestedPromptLevel + 1)) "
}

function Measure-Expression {
    [CmdletBinding()]
    [Alias('measureme')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [hashtable] $Tests,

        [Parameter()]
        [int32] $TestCount = 5,

        [Parameter()]
        [switch] $OutputAllTests,

        [Parameter()]
        [object[]] $ArgumentList
    )

    end {
        $allTests = 1..$TestCount | ForEach-Object {
            foreach ($test in $Tests.GetEnumerator()) {
                $sb = if ($ArgumentList) {
                    { & $test.Value $ArgumentList }
                }
                else {
                    { & $test.Value }
                }

                $totalms = (Measure-Command $sb).TotalMilliseconds

                [pscustomobject]@{
                    TestRun           = $_
                    Test              = $test.Key
                    TotalMilliseconds = [math]::Round($totalms, 2)
                }

                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        } | Sort-Object TotalMilliseconds

        $average = $allTests | Group-Object Test | ForEach-Object {
            $avg = [Linq.Enumerable]::Average([double[]] $_.Group.TotalMilliseconds)

            [pscustomobject]@{
                Test    = $_.Name
                Average = $avg
            }
        } | Sort-Object Average

        $average | Select-Object @(
            'Test'
            @{
                Name       = 'Average'
                Expression = { '{0:0.00} ms' -f $_.Average }
            }
            @{
                Name       = 'RelativeSpeed'
                Expression = {
                    $relativespeed = $_.Average / $average[0].Average
                    [math]::Round($relativespeed, 2).ToString() + 'x'
                }
            }
        ) | Format-Table -Property @(
            'Test'
            @{
                Name       = 'Average'
                Expression = { $_.Average }
                Alignment  = 'Right'
            }
            'RelativeSpeed'
        )

        if ($OutputAllTests.IsPresent) {
            $allTests | Format-Table -AutoSize
        }
    }
}

function New-DataSet {
    [CmdletBinding(DefaultParameterSetName = 'AsObjects')]
    [Alias('dataset')]
    param(
        [Parameter(ParameterSetName = 'AsObjects')]
        [int] $NumberOfObjects = 10000,

        [Parameter(ParameterSetName = 'AsValues')]
        [int] $NumberOfValues = 10000,

        [Parameter(ParameterSetName = 'AsObjects')]
        [int] $NumberOfProperties = 10,

        [Parameter(ParameterSetName = 'AsValues')]
        [Parameter(ParameterSetName = 'AsObjects')]
        [int] $ValueLength = 10
    )

    end {
        $charmap = -join @(
            [char]'A'..[char]'Z'
            [char]'a'..[char]'z'
            0..10
        )

        class RandomJunkGenerator {
            [string] $CharMap
            [random] $Randomizer = [random]::new()
            [System.Management.Automation.PSCmdlet] $Cmdlet

            RandomJunkGenerator([string] $Charmap, [System.Management.Automation.PSCmdlet] $Cmdlet) {
                $this.CharMap = $Charmap
                $this.Cmdlet = $Cmdlet
            }

            [string] WriteValue([int] $Length) {
                $content = [char[]]::new($Length)

                for ($i = 0; $i -lt $Length; $i++) {
                    $content[$i] = $this.CharMap[$this.Randomizer.Next($this.CharMap.Length)]
                }

                return [string]::new($content)
            }

            [void] WriteObject([int] $PropCount, [int] $ValueLength) {
                $object = [ordered]@{}
                foreach ($prop in 1..$PropCount) {
                    $object["Prop$prop"] = $this.WriteValue($ValueLength)
                }
                $this.Cmdlet.WriteObject([pscustomobject] $object)
            }
        }

        $junkGenerator = [RandomJunkGenerator]::new($charmap, $PSCmdlet)

        if ($PSCmdlet.ParameterSetName -eq 'AsValues') {
            while ($NumberOfObjects--) {
                $junkGenerator.WriteValue($ValueLength)
            }
            return
        }

        while ($NumberOfObjects--) {
            $junkGenerator.WriteObject($NumberOfProperties, $ValueLength)
        }
    }
}

function Expand-MemberInfo {
    [Alias('emi')]
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [Alias('Member')]
        [psobject] $InputObject,

        [Parameter()]
        [ValidateSet('IL', 'CSharp', 'VisualBasic')]
        [string] $Language = 'CSharp',

        [switch] $NoAnonymousMethods,
        [switch] $NoExpressionTrees,
        [switch] $NoYield,
        [switch] $NoAsync,
        [switch] $NoAutomaticProperties,
        [switch] $NoAutomaticEvents,
        [switch] $NoUsingStatements,
        [switch] $NoForEachStatements,
        [switch] $NoLockStatements,
        [switch] $NoSwitchOnString,
        [switch] $NoUsingDeclarations,
        [switch] $NoQueryExpressions,
        [switch] $DontClarifySameNameTypes,
        [switch] $UseFullnamespace,
        [switch] $DontUseVariableNamesFromSymbols,
        [switch] $NoObjectOrCollectionInitializers,
        [switch] $NoInlineXmlDocumentation,
        [switch] $DontRemoveEmptyDefaultConstructors,
        [switch] $DontUseIncrementOperators,
        [switch] $DontUseAssignmentExpressions,
        [switch] $AlwaysCreateExceptionVariables,
        [switch] $SortMembers,
        [switch] $ShowTokens,
        [switch] $ShowBytes,
        [switch] $ShowPdbInfo
    )
    begin {
        $dnSpy = Get-Command -CommandType Application -Name dnSpy.Console.exe -ErrorAction Stop

        $argumentList = & {
            if ($NoAnonymousMethods.IsPresent) {
                '--no-anon-methods'
            }

            if ($NoExpressionTrees.IsPresent) {
                '--no-expr-trees'
            }

            if ($NoYield.IsPresent) {
                '--no-yield'
            }

            if ($NoAsync.IsPresent) {
                '--no-async'
            }

            if ($NoAutomaticProperties.IsPresent) {
                '--no-auto-props'
            }

            if ($NoAutomaticEvents.IsPresent) {
                '--no-auto-events'
            }

            if ($NoUsingStatements.IsPresent) {
                '--no-using-stmt'
            }

            if ($NoForEachStatements.IsPresent) {
                '--no-foreach-stmt'
            }

            if ($NoLockStatements.IsPresent) {
                '--no-lock-stmt'
            }

            if ($NoSwitchOnString.IsPresent) {
                '--no-switch-string'
            }

            if ($NoUsingDeclarations.IsPresent) {
                '--no-using-decl'
            }

            if ($NoQueryExpressions.IsPresent) {
                '--no-query-expr'
            }

            if ($DontClarifySameNameTypes.IsPresent) {
                '--no-ambig-full-names'
            }

            if ($UseFullnamespace.IsPresent) {
                '--full-names'
            }

            if ($DontUseVariableNamesFromSymbols.IsPresent) {
                '--use-debug-syms'
            }

            if ($NoObjectOrCollectionInitializers.IsPresent) {
                '--no-obj-inits'
            }

            if ($NoInlineXmlDocumentation.IsPresent) {
                '--no-xml-doc'
            }

            if ($DontRemoveEmptyDefaultConstructors.IsPresent) {
                '--dont-remove-empty-ctors'
            }

            if ($DontUseIncrementOperators.IsPresent) {
                '--no-inc-dec'
            }

            if ($DontUseAssignmentExpressions.IsPresent) {
                '--dont-make-assign-expr'
            }

            if ($AlwaysCreateExceptionVariables.IsPresent) {
                '--always-create-ex-var'
            }

            if ($SortMembers.IsPresent) {
                '--sort-members'
            }

            if ($ShowBytes.IsPresent) {
                '--bytes'
            }

            if ($ShowPdbInfo.IsPresent) {
                '--pdb-info'
            }

            if ($Language -ne 'CSharp') {
                $languageGuid = switch ($Language) {
                    IL {
                        '{a4f35508-691f-4bd0-b74d-d5d5d1d0e8e6}'
                    }
                    CSharp {
                        '{bba40092-76b2-4184-8e81-0f1e3ed14e72}'
                    }
                    VisualBasic {
                        '{a4f35508-691f-4bd0-b74d-d5d5d1d0e8e6}'
                    }
                }

                "-l ""$languageGuid"""
            }

            '--spaces 4'
        }

        if ($argumentList.Count -gt 1) {
            $arguments = $argumentList -join ' '
            return
        }

        $arguments = [string] $argumentList
    }
    process {
        if ($InputObject -is [System.Management.Automation.PSMethod]) {
            $null = $PSBoundParameters.Remove('InputObject')
            return $InputObject.ReflectionInfo | & $MyInvocation.MyCommand @PSBoundParameters
        }

        if ($InputObject -is [type]) {
            $assembly = $InputObject.Assembly
        }
        else {
            $assembly = $InputObject.DeclaringType.Assembly
        }

        $sb = [System.Text.StringBuilder]::new([string] $arguments)
        if ($sb.Length -gt 0) {
            $null = $sb.Append(' ')
        }

        if (-not $ShowTokens.IsPresent) {
            $null = $sb.Append('--no-tokens ')
        }

        try {
            # Use the special name accessor as PowerShell ignores property exceptions.
            $metadataToken = $InputObject.get_MetadataToken()
        }
        catch [System.InvalidOperationException] {
            $exception = [PSArgumentException]::new(
                ('Unable to get the metadata token of member "{0}". Ensure ' -f $InputObject) +
                'the target is not dynamically generated and then try the command again.',
                $PSItem)

            $PSCmdlet.WriteError(
                [ErrorRecord]::new(
                    <# exception:     #> $exception,
                    <# errorId:       #> 'CannotGetMetadataToken',
                    <# errorCategory: #> [ErrorCategory]::InvalidArgument,
                    <# targetObject:  #> $InputObject))

            return
        }


        $null = $sb.
        AppendFormat('--md {0} ', $metadataToken).
        AppendFormat('"{0}"', $assembly.Location)

        & ([scriptblock]::Create(('& "{0}" {1}' -f $dnSpy.Source, $sb.ToString())))
    }
}

function ConvertTo-ArrayExpression {
    [Alias('ToArrayEx')]
    param(
        [Parameter(ValueFromPipeline)]
        [string[]] $InputObject = (Get-Clipboard),

        [Parameter()]
        [string] $Indentation = ' ' * 4
    )

    begin {
        '@('
    }
    process {
        foreach ($item in $InputObject.Trim()) {
            $Indentation + "'{0}'" -f $item.Replace("'", "''")
        }
    }
    end {
        ')'
    }
}

function Update-DotNet {
    [CmdletBinding()]
    param()
    end {
        $globalFile = Join-Path $global:PWD.ProviderPath global.json
        if (-not (Test-Path -LiteralPath $globalFile)) {
            return
        }

        $version = (Get-Content -LiteralPath $globalFile -Raw -ErrorAction Stop | ConvertFrom-Json).sdk.version
        $installPath = Join-Path C:\dotnet $version
        if (-not (Test-Path -LiteralPath $installPath\dotnet.exe)) {
            dotnet-install.ps1 -Version $version -InstallDir $installPath
        }

        $vscodeSettingsPath = Join-Path $global:PWD .vscode/settings.json
        $vscodeSettings = Get-Content -LiteralPath $vscodeSettingsPath -Raw | ConvertFrom-Json
        if ($vscodeSettings.'omnisharp.dotnetPath' -ne $installPath) {
            if (-not $vscodeSettings.'omnisharp.dotnetPath') {
                $vscodeSettings.psobject.Properties.Add(
                    [psnoteproperty]::new(
                        'omnisharp.dotnetPath',
                        $installPath))
            }
            else {
                $vscodeSettings.'omnisharp.dotnetPath' = $installPath
            }

            $vscodeSettings |
                ConvertTo-Json |
                Set-Content -Encoding ([System.Text.UTF8Encoding]::new()) -LiteralPath $vscodeSettingsPath
        }

        if ($env:PATH.Contains($installPath)) {
            return
        }

        $env:PATH = $installPath + [System.IO.Path]::PathSeparator + $env:PATH
    }
}
