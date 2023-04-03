using namespace System.Management.Automation

$requiredModules = @{
    'CompletionPredictor'        = @{}
    'ClassExplorer'              = @{}
    'EditorServicesCommandSuite' = @{
        AllowPrerelease = $true
        RequiredVersion = '1.0.0-beta4'
    }
}

$modules = Get-Module -ListAvailable |
    Group-Object Name -AsHashTable -AsString -NoElement

$requiredModules.GetEnumerator() | ForEach-Object {
    if(-not $modules.ContainsKey($_.Key)) {
        $arg = $_.Value
        Install-Module $_.Key @arg -Scope CurrentUser
    }
    Import-Module $_.Key -Force
}

Import-CommandSuite
Set-PSReadLineOption -PredictionSource HistoryAndPlugin

function QuoteArray {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]] $InputObject,

        [Parameter()]
        [switch] $UseArraySubexpression
    )

    begin {
        $list = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach($item in $InputObject) {
            $list.Add("'{0}'" -f $item)
        }
    }
    end {
        if($UseArraySubexpression.IsPresent) {
            $output = '@('; $indent = ' ' * 4
            foreach($item in 'foo', 'bar', 'baz') {
                $output += "{0}{1}'{2}'" -f [System.Environment]::NewLine, $indent, $item
            }
            $output += '{0})' -f [System.Environment]::NewLine
            return $output
        }

        $list -join ', '
    }
}

function Use-Culture {
    param(
        [Parameter(Mandatory)]
        [ArgumentCompleter({
                param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)

            (Get-Culture -ListAvailable).Name | & {
                    process {
                        if($_ -notlike "*$wordToComplete*") {
                            return
                        }
                        [CompletionResult]::new($_, $_, [CompletionResultType]::ParameterValue, $_)
                    }
                }
            })]
        [cultureinfo] $Culture,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    end {
        $PrevCulture   = [Threading.Thread]::CurrentThread.CurrentCulture
        $PrevCultureUI = [Threading.Thread]::CurrentThread.CurrentUICulture

        try {
            [Threading.Thread]::CurrentThread.CurrentCulture =
            [Threading.Thread]::CurrentThread.CurrentUICulture = $Culture

            & $ScriptBlock
        }
        finally {
            [Threading.Thread]::CurrentThread.CurrentCulture = $PrevCulture
            [Threading.Thread]::CurrentThread.CurrentUICulture = $PrevCultureUI
        }
    }
}

function prompt { "PS ..\$([IO.Path]::GetFileName($executionContext.SessionState.Path.CurrentLocation.ProviderPath))$('>' * ($nestedPromptLevel + 1)) " }

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
            foreach($test in $Tests.GetEnumerator()) {
                $measurement = (Measure-Command { & $test.Value }).TotalMilliseconds
                $totalRound  = [math]::Round($measurement, 2)

                [pscustomobject]@{
                    TestRun           = $_
                    Test              = $test.Key
                    TotalMilliseconds = $totalRound
                }
            }
        } | Sort-Object TotalMilliseconds

        $average = $allTests | Group-Object Test | ForEach-Object {
            $avg = [Linq.Enumerable]::Average([double[]] $_.Group.TotalMilliseconds)

            [pscustomobject]@{
                Test          = $_.Name
                Average       = $avg
                RelativeSpeed = 0
            }
        } | Sort-Object Average

        $average[0].RelativeSpeed = '1x'
        $top = $average[0].Average

        $average | ForEach-Object {
            $_.RelativeSpeed = ($_.Average / $top).ToString('N2') + 'x'
            $_.Average = '{0:0.00} ms' -f $_.Average
        }

        if($OutputAllTests.IsPresent) {
            $allTests | Format-Table -AutoSize
        }

        $average | Format-Table -Property @(
            'Test'
            @{
                Name       = 'Average'
                Expression = { $_.Average }
                Alignment  ='Right'
            }
            'RelativeSpeed'
        )
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
            [PSCmdlet] $Cmdlet

            RandomJunkGenerator([string] $Charmap, [PSCmdlet] $Cmdlet) {
                $this.CharMap = $Charmap
                $this.Cmdlet  = $Cmdlet
            }

            [string] WriteValue([int] $Length) {
                $content = [char[]]::new($Length)

                for($i = 0; $i -lt $Length; $i++) {
                    $content[$i] = $this.CharMap[$this.Randomizer.Next($this.CharMap.Length)]
                }

                return [string]::new($content)
            }

            [void] WriteObject([int] $PropCount, [int] $ValueLength) {
                $object = [ordered]@{}
                foreach($prop in 1..$PropCount) {
                    $object["Prop$prop"] = $this.WriteValue($ValueLength)
                }
                $this.Cmdlet.WriteObject([pscustomobject] $object)
            }
        }

        $junkGenerator = [RandomJunkGenerator]::new($charmap, $PSCmdlet)

        if($PSCmdlet.ParameterSetName -eq 'AsValues') {
            while($NumberOfObjects--) {
                $junkGenerator.WriteValue($ValueLength)
            }
            return
        }

        while($NumberOfObjects--) {
            $junkGenerator.WriteObject($NumberOfProperties, $ValueLength)
        }
    }
}