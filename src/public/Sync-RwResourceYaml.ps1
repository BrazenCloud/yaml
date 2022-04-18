Function Sync-RwResourceYaml {
    [cmdletbinding(
        DefaultParameterSetName = 'FromString'
    )]
    param (
        [Parameter(
            ParameterSetName = 'FromString'
        )]
        [string]$Yaml,
        [Parameter(
            ParameterSetName = 'FromFile'
        )]
        [string]$PathToYaml
    )

    if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
        $Yaml = Get-Content -Raw $PathToYaml
    }

    $currentUser = Get-RwAuthenticationCurrentUser

    Write-Verbose "Context:`n- Name: $($currentUser.name)`n- Email: $($currentUser.emailAddress)`n- Home Group: $($currentUser.homeContainerId)"

    $actionCache = @{}
    $runnerCache = @{}

    $resources = ConvertFrom-Yaml $yaml

    # If there are any connectors
    if ($resources.connectors) {
        Write-Information "Found $($resources.connectors.count) connectors"
        Write-Information "Connectors:"

        foreach ($connector in $resources.connectors.Keys) {
            Write-Information "- $connector"

            if ($resources.connectors[$connector].Keys -contains 'action') {
                if ($resources.connectors[$connector]['action'] -contains 'id') {
                    $actionId = $resources.connectors[$connector]['action']['id']
                } else {
                    if ($actionCache.Keys -notcontains $resources.connectors[$connector]['action']['name']) {
                        $actionCache[$resources.connectors[$connector]['action']['name']] = Get-RwRepository -Name $resources.connectors[$connector]['action']['name']
                    }
                    $actionId = $actionCache[$resources.connectors[$connector]['action']['name']].Id
                }
            }

            if ($resources.connectors[$connector].Keys -contains 'runner') {
                if ($resources.connectors[$connector]['runner'] -contains 'id') {
                    $runnerId = $resources.connectors[$connector]['runner']['id']
                } else {
                    if ($runnerCache.Keys -notcontains $resources.connectors[$connector]['runner']['name']) {
                        $runnerCache[$resources.connectors[$connector]['runner']['name']] = Get-RwRunnerByName -Name $resources.connectors[$connector]['runner']['name']
                    }
                    $runnerId = $runnerCache[$resources.connectors[$connector]['runner']['name']].Id
                }
            }

            $splat = @{
                Name = $connector
                ActionId = $actionId
                RunnerId = $runnerId
                IsHidden = $false
                GroupId = $currentUser.HomeContainerId
            }

            if ($resources.connectors[$connector].Keys -contains 'parameters') {
                $splat['settings'] = $resources.connectors[$connector]['parameters']
            }

            $conn = Get-RwConnectionByName $connector
            if ($null -ne $conn) {
                Write-Information '  - Updating existing connector'
                Set-RwConnection @splat -ConnectionId $conn.Id
            } else {
                Write-Information '  - Creating new connector'
                New-RwConnection @splat
            }
        }
    } else {
        Write-Information "No connectors found."
    }

    # If there are any jobs
    if ($resources.jobs) {
        Write-Information "Found $($resources.jobs.count) jobs"
        Write-Information 'Jobs:'

        foreach ($job in $resources.jobs.Keys) {
            Write-Information "- $job"

            # Create job if it doesn't already exist
            $existingJob = Get-RwJobByName $job

            if ($null -ne $existingJob) {
                Write-Verbose '  - Updating existing'
                $existingJob = Get-RwJob -JobId $existingJob.Id
            } else {
                Write-Verbose '  - Creating a new one'
                $newJob = New-RwJob -Name $job -IsEnabled -IsHidden:$false
                $existingJob = Get-RwJob -JobId $newJob.JobId
            }

            # Assign Schedule
            if ($resources.jobs[$job].Keys -contains 'schedule') {
                Write-Information "  - Adding Schedule"
                # Create the schedule object
                $scheduleSplat = @{
                    repeatMinutes = if ($resources.jobs[$job]['schedule'].Keys -contains 'repeatMinutes') {
                            $resources.jobs[$job]['schedule']['repeatMinutes']
                        } else { $null }
                    Time = if ($resources.jobs[$job]['schedule'].Keys -contains 'time') {
                            $resources.jobs[$job]['schedule']['time']
                        } else { $null }
                    scheduletype = if ($resources.jobs[$job]['schedule'].Keys -contains 'type') {
                            $resources.jobs[$job]['schedule']['type']
                        } else { 'RunNow' }
                    weekdays = if ($resources.jobs[$job]['schedule'].Keys -contains 'weekdays') {
                            $resources.jobs[$job]['schedule']['weekdays']
                        } else { $null }
                }
                $schedule = New-RwJobScheduleObject @scheduleSplat

                # Set the schedule
                Set-RwJobSchedule -JobId $existingJob.Id -Schedule $schedule
            }

            # Assign Actions
            if ($resources.jobs[$job].Keys -contains 'actions') {
                Write-Information '  - Adding Actions'
                $x = 0
                $actions = foreach ($action in $resources.jobs[$job]['actions']) {
                    $x++
                    $actionHt = @{}
                    if ($action.Keys -contains 'id') {
                        $actionHt['RepositoryActionId'] = $action['id']
                    } else {
                        if ($actionCache.Keys -notcontains $action['name']) {
                            $actionCache[$action['name']] = Get-RwRepository -Name $action['name']
                            $actionCache[$actionCache[$action['name']].Id] = $actionCache[$action['name']]
                        }
                        $actionHt['RepositoryActionId'] = $actionCache[$action['name']].Id
                    }
                    Write-Information "    - $x`: '$($action['name'])'"
                    Write-Verbose "Associating '$($action['name'])' to '$($actionHt['RepositoryActionId'])'"
                    if ($action.Keys -contains 'parameters') {
                        Write-Information "      - Adding parameters"
                        $actionHt['Settings'] = $action['parameters']
                    }

                    if ($action.Keys -contains 'connector') {
                        Write-Information "      - Adding connector"
                        if ($action['connector'].Keys -contains 'id') {
                            $actionHt['ConnectionId'] = $action['connector']['id']
                        } elseif ($action['connector'].Keys -contains 'name') {
                            $actionHt['ConnectionId'] = (Get-RwConnectionByName -ConnectionName $action['connector']['name']).Id
                        }
                    }

                    $actionHt
                }
                Set-RwJobAction -JobId $existingJob.Id -Request $actions
            }

            # Assign Runners
            if ($resources.jobs[$job].Keys -contains 'runners') {
                Write-Information '  - Adding Runners'
                $newMembers = if ($resources.jobs[$job]['runners'].Keys -contains 'names') {
                    Write-Information "    - Adding runners by name"
                    (Get-RwRunnerByName -AssetName $resources.jobs[$job]['runners']['names']).AssetId
                } elseif ($resources.jobs[$job]['runners'].Keys -contains 'tags') {
                    Write-Information "    - Adding Runners by tags: '$($resources.jobs[$job]['runners']['tags'] -join "','")'."
                    (Get-RwEndpointByTag -Tags $resources.jobs[$job]['runners']['tags']).Id
                }

                Write-Information "    - Found $($newMembers.Count) total Runners that should be assigned"

                Sync-RwSetMembership -Members $newMembers -SetId $existingJob.EndpointSetId
            }
        }
    } else {
        Write-Information "No jobs found."
    }
}