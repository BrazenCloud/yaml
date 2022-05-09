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
        [string]$PathToYaml,
        [switch]$Test
    )

    if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
        $Yaml = Get-Content -Raw $PathToYaml
    }

    $currentUser = Get-RwAuthenticationCurrentUser

    Write-Verbose "Context:`n- Name: $($currentUser.name)`n- Email: $($currentUser.emailAddress)`n- Home Group: $($currentUser.homeContainerId)"

    $resources = ConvertFrom-Yaml $yaml

    # If there are any connectors
    if ($resources.connectors) {
        Write-Information "Found $($resources.connectors.count) connectors"
        Write-Information "Connectors:"

        foreach ($connector in $resources.connectors.Keys) {
            Write-Information "- $connector"

            # Leveraging a cache for the Action names
            if ($resources.connectors[$connector].Keys -contains 'action') {
                if ($resources.connectors[$connector]['action'] -contains 'id') {
                    $actionId = $resources.connectors[$connector]['action']['id']
                } else {
                    $actionId = (Get-RwResourceFromCache -ResourceType Action -Name $resources.connectors[$connector]['action']['name']).Id
                }
            }

            # Leveraging a cache for the Runner names
            if ($resources.connectors[$connector].Keys -contains 'runner') {
                if ($resources.connectors[$connector]['runner'] -contains 'id') {
                    $runnerId = $resources.connectors[$connector]['runner']['id']
                } else {
                    $runnerId = (Get-RwResourceFromCache -ResourceType Runner -Name $resources.connectors[$connector]['runner']['name']).Id
                }
            }

            $splat = @{
                Name     = $connector
                ActionId = $actionId
                RunnerId = $runnerId
                IsHidden = $false
                GroupId  = $currentUser.HomeContainerId
            }

            if ($resources.connectors[$connector].Keys -contains 'parameters') {
                $splat['settings'] = $resources.connectors[$connector]['parameters']
            }

            $conn = Get-RwConnectionByName $connector
            if ($null -ne $conn) {
                Write-Information '  - Updating existing Connector'
                if ($Test.IsPresent) {
                    Write-Information "  - Would update existing Connector"
                } else {
                    Set-RwConnection @splat -ConnectionId $conn.Id -ErrorAction Stop
                }
            } else {
                Write-Information '  - Creating new connector'
                if ($Test.IsPresent) {
                    Write-Information "  - Would create new Connector"
                } else {
                    New-RwConnection @splat
                }
            }

            # Assign Tags
            if ($resources.connectors[$connector].Keys -contains 'tags') {
                # Build a set
                $set = New-RwSet
                # Add the job to the set
                if ($null -eq $conn) {
                    $conn = Get-RwConnectionByName -ConnectionName $connector
                }
                Add-RwSetToSet -TargetSetId $set -ObjectIds $conn.Id
                # Add the tags to the set
                Add-RwTag -SetId $set -Tags $resources.connectors[$connector]['tags']
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
                if ($Test.IsPresent) {
                    Write-Information "  - Would create job"
                } else {
                    $newJob = New-RwJob -Name $job -IsEnabled -IsHidden:$false
                    $existingJob = Get-RwJob -JobId $newJob.JobId
                }
            }

            # Assign Schedule
            if ($resources.jobs[$job].Keys -contains 'schedule') {
                Write-Information "  - Adding Schedule"
                
                # Create the schedule object
                $sched = $resources.jobs[$job]['schedule']
                $schedule = New-RwJobSchedule @sched

                # Set the schedule
                if ($Test.IsPresent) {
                    Write-Information "  - Would set schedule to $($scheduleSplat | ConvertTo-Json -Compress)"
                } else {
                    Set-RwJobSchedule -JobId $existingJob.Id -Schedule $schedule
                }
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
                        $actionHt['RepositoryActionId'] = (Get-RwResourceFromCache -ResourceType Action -Name $action['name']).Id
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
                if ($Test.IsPresent) {
                    Write-Information "    - Would Update Actions"
                } else {
                    Set-RwJobAction -JobId $existingJob.Id -Request $actions
                }
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

                if ($Test.IsPresent) {
                    Write-Information "    - Would update membership"
                } else {
                    Sync-RwSetMembership -Members $newMembers -SetId $existingJob.EndpointSetId
                }
            }

            # Assign Tags
            if ($resources.jobs[$job].Keys -contains 'tags') {
                # Build a set
                $set = New-RwSet
                # Add the job to the set
                Add-RwSetToSet -TargetSetId $set -ObjectIds $existingJob.Id
                # Add the tags to the set
                Add-RwTag -SetId $set -Tags $resources.jobs[$job]['tags']
            }
        }
    } else {
        Write-Information "No jobs found."
    }
}