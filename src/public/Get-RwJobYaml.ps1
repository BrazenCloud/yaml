Function Get-RwJobYaml {
    [cmdletbinding(
        DefaultParameterSetName = 'ById'
    )]
    param (
        [Parameter(
            Mandatory,
            ParameterSetName = 'ById'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'ById-Id'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'ById-Name'
        )]
        [string[]]$JobId,
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName-Id'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName-Name'
        )]
        [string[]]$JobName,
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName-Id'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'ById-Id'
        )]
        [switch]$IncludeAssignedRunnersById,
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName-Name'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'ById-Name'
        )]
        [switch]$IncludeAssignedRunnersByName
    )
    $jobs = if ($PSCmdlet.ParameterSetName -like 'ByName*') {
        foreach ($name in $jobName) {
            Get-RwJobByName -JobName $name
        }
    } elseif ($PSCmdlet.ParameterSetName -like 'ById*') {
        foreach ($id in $JobId) {
            Get-RwJob -JobId $id
        }
    }

    # Build basic job
    $jobHt = @{}
    $jobHt['jobs'] = @{}
    foreach ($job in $jobs ) {
        $jobHt['jobs'][$job.Name] = [ordered]@{
            tags     = @($job.Tags)
            schedule = [ordered]@{
                type          = $job.Schedule.ScheduleType
                weekdays      = $job.Schedule.Weekdays
                time          = $job.Schedule.Time
                repeatMinutes = $job.Schedule.RepeatMinutes
            }
            runners  = @{
                tags = @( 'setme' )
            }
            actions  = foreach ($action in (Sort-RwJobActions -Actions $job.Actions)) {
                [ordered]@{
                    name       = $action.ActionName
                    parameters = & {
                        $ht = @{}
                        foreach ($param in $action.Settings) {
                            $ht[$param.Name] = $param.Value
                        }
                        $ht
                    }
                    connector  = @{
                        id = $action.ConnectionId
                    }
                }
            }
        }
        switch ($PSCmdlet.ParameterSetName) {
            { ($_ -like 'ByName*') } {
                $job = Get-RwJob -JobId $job.Id
            }
            { ($_ -like '*-Id') } {
                $jobHt['jobs'][$job.Name]['runners'] = @{
                    Ids = (Get-RwSetMember -SetId $job.EndpointSetId).Id
                }
            }
            { ($_ -like '*-Name') } {
                $jobHt['jobs'][$job.Name]['runners'] = @{
                    Names = (Get-RwSetMember -SetId $job.EndpointSetId).Name
                }
            }
        }
    }

    # Clean up null connectors and parameters
    $connectorCache = @{}
    foreach ($job in $jobHt['jobs'].Keys) {
        foreach ($action in $jobHt['jobs'][$job]['actions']) {
            if ($null -eq $action['connector']['id']) {
                $action.Remove('connector')
            } else {
                if ($connectorCache.Keys -notcontains $action['connector']['id']) {
                    $connectorCache[$action['connector']['id']] = Get-RwConnection -ConnectionId $action['connector']['id']
                }
                $action['connector']['name'] = $connectorCache[$action['connector']['id']].Name
                $action['connector'].Remove('id')
            }
            $toRemove = foreach ($key in $action.parameters.Keys) {
                if ($null -eq $action.parameters[$key]) {
                    $key
                }
            }
            foreach ($key in $toRemove) {
                $action.parameters.Remove($key)
            }
            if ($action.parameters.Count -eq 0) {
                $action.Remove('parameters')
            }
        }
    }

    if ($connectorCache.Keys.Count -gt 0) {
        $jobHt['connectors'] = foreach ($connector in $connectorCache.Keys) {
            $conn = Get-RwConnection -ConnectionId $connector
            [ordered]@{
                $conn.Name = [ordered]@{
                    action     = @{
                        name = $conn.ActionName
                    }
                    runner     = @{
                        name = $conn.AssignedEndpointName
                    }
                    parameters = & {
                        $ht = @{}
                        foreach ($param in $conn.Settings) {
                            $ht[$param.Name] = $param.Value
                        }
                        $ht
                    }
                }
            }
        }
    }
    
    $jobHt | ConvertTo-Yaml
}