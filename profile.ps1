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

Import-CommandSuite
Set-PSReadLineOption -PredictionSource HistoryAndPlugin

class CultureCompleter : System.Management.Automation.IArgumentCompleter {
    static $Completions = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    [System.Collections.Generic.IEnumerable[System.Management.Automation.CompletionResult]] CompleteArgument(
        [string] $commandName,
        [string] $parameterName,
        [string] $wordToComplete,
        [System.Management.Automation.Language.CommandAst] $commandAst,
        [System.Collections.IDictionary] $fakeBoundParameters) {

        [CultureCompleter]::Completions.Clear()
        $word = [regex]::Escape($WordToComplete)

        foreach ($culture in [cultureinfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures)) {
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
    "PS ..\$([IO.Path]::GetFileName($executionContext.SessionState.Path.CurrentLocation.ProviderPath))$('>' * ($nestedPromptLevel + 1)) "
}

function Measure-Performance {
    [CmdletBinding()]
    [Alias('measureme')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [hashtable] $Tests,

        [Parameter()]
        [int32] $TestCount = 5,

        [Parameter()]
        [switch] $OutputAllTests
    )

    end {
        $allTests = 1..$TestCount | ForEach-Object {
            foreach ($test in $Tests.GetEnumerator()) {
                $totalms = (Measure-Command { & $test.Value }).TotalMilliseconds

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
