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

    $jobHt = @{}
    $jobHt['jobs'] = @{
        $job.Name = @{
            tags     = @($job.Tags)
            schedule = @{
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
                }
            }
        }
    }
    $jobHt | ConvertTo-Yaml
}