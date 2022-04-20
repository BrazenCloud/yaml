Function Get-RwResourceFromCache {
    [cmdletbinding()]
    param (
        [Parameter(
            Mandatory
        )]
        [ValidateSet('Action','Runner')]
        [string]$ResourceType,
        [Parameter(
            Mandatory
        )]
        [string]$Name
    )
    if ($null -eq (Get-Variable -Scope Script -Name 'rwCache' -ErrorAction SilentlyContinue)) {
        $rwCache = @{}
        $rwCache['Action'] = @{}
        $rwCache['Runner'] = @{}
    }
    if ($rwCache[$ResourceType].Keys -notcontains $Name) {
        $rwCache[$ResourceType][$Name] = switch ($ResourceType) {
            'Action' { Get-RwRepository -Name $Name }
            'Runner' { Get-RwRunnerByName -AssetName $Name }
        }
    }
    $rwCache[$ResourceType][$Name]
}