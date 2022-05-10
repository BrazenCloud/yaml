Function Get-RwJobYaml {
    [cmdletbinding(
        DefaultParameterSetName = 'ById'
    )]
    param (
        [Parameter(
            Mandatory,
            ParameterSetName = 'ById'
        )]
        [string]$JobId,
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName'
        )]
        [string]$JobName
    )
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $job = Get-RwJobByName -JobName $JobName
    } elseif ($PSCmdlet.ParameterSetName -eq 'ById') {
        $job = Get-RwJob -JobId $JobId
    }

    $actionsSorted = Sort-RwJobActions -Actions $job.Actions

    # Build basic job
    $jobHt = @{}
    $jobHt['jobs'] = @{
        $job.Name = [ordered]@{
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
            actions  = foreach ($action in $actionsSorted) {
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