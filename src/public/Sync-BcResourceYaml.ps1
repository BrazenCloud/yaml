Function Sync-BcResourceYaml {
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

    $ogip = $InformationPreference
    $InformationPreference = 'Continue'

    if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
        $Yaml = Get-Content -Raw $PathToYaml
    }

    $currentUser = Get-BcAuthenticationCurrentUser

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
                    $actionId = (Get-BcResourceFromCache -ResourceType Action -Name $resources.connectors[$connector]['action']['name']).Id
                }
            }

            # Leveraging a cache for the Runner names
            if ($resources.connectors[$connector].Keys -contains 'runner') {
                if ($resources.connectors[$connector]['runner'] -contains 'id') {
                    $runnerId = $resources.connectors[$connector]['runner']['id']
                } else {
                    $runnerId = (Get-BcResourceFromCache -ResourceType Runner -Name $resources.connectors[$connector]['runner']['name']).Id
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

            $conn = Get-BcConnectionByName $connector
            if ($null -ne $conn) {
                Write-Information '  - Updating existing Connector'
                if ($Test.IsPresent) {
                    Write-Information "  - Would update existing Connector"
                } else {
                    Set-BcConnection @splat -ConnectionId $conn.Id -ErrorAction Stop
                }
            } else {
                Write-Information '  - Creating new connector'
                if ($Test.IsPresent) {
                    Write-Information "  - Would create new Connector"
                } else {
                    New-BcConnection @splat
                }
            }

            # Assign Tags
            if ($resources.connectors[$connector].Keys -contains 'tags') {
                if ($Test.IsPresent) {
                    Write-Information "  - Would add tags: $($resources.connectors[$connector]['tags'] -join ',')"
                } else {
                    # Build a set
                    $set = New-BcSet
                    # Add the job to the set
                    if ($null -eq $conn) {
                        $conn = Get-BcConnectionByName -ConnectionName $connector
                    }
                    Add-BcSetToSet -TargetSetId $set -ObjectIds $conn.Id
                    # Add the tags to the set
                    Write-Information "  - Adding tags: $($resources.connectors[$connector]['tags'] -join ',')"
                    Add-BcTag -SetId $set -Tags $resources.connectors[$connector]['tags']
                }
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
            $existingJob = Get-BcJobByName $job

            if ($null -ne $existingJob) {
                Write-Verbose '  - Updating existing'
                $existingJob = Get-BcJob -JobId $existingJob.Id
            } else {
                Write-Verbose '  - Creating a new one'
                if ($Test.IsPresent) {
                    Write-Information "  - Would create job"
                } else {
                    $newJob = New-BcJob -Name $job -IsEnabled -IsHidden:$false
                    $existingJob = Get-BcJob -JobId $newJob.JobId
                }
            }

            # Assign Schedule
            if ($resources.jobs[$job].Keys -contains 'schedule') {
                Write-Information "  - Adding Schedule"

                # Create the schedule object
                $sched = $resources.jobs[$job]['schedule']
                $schedule = New-BcJobSchedule @sched

                # Set the schedule
                if ($Test.IsPresent) {
                    Write-Information "  - Would set schedule to $($scheduleSplat | ConvertTo-Json -Compress)"
                } else {
                    Set-BcJobSchedule -JobId $existingJob.Id -Schedule $schedule
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
                        $actionHt['RepositoryActionId'] = (Get-BcResourceFromCache -ResourceType Action -Name $action['name']).Id
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
                            $actionHt['ConnectionId'] = (Get-BcConnectionByName -ConnectionName $action['connector']['name']).Id
                        }
                    }

                    $actionHt
                }
                if ($Test.IsPresent) {
                    Write-Information "    - Would Update Actions"
                } else {
                    Set-BcJobAction -JobId $existingJob.Id -Request $actions
                }
            }

            # Assign Runners
            if ($resources.jobs[$job].Keys -contains 'runners') {
                Write-Information '  - Adding Runners'
                $newMembers = if ($resources.jobs[$job]['runners'].Keys -contains 'names') {
                    Write-Information "    - Adding runners by name"
                    (Get-BcRunnerByName -AssetName $resources.jobs[$job]['runners']['names']).AssetId
                } elseif ($resources.jobs[$job]['runners'].Keys -contains 'tags') {
                    Write-Information "    - Adding Runners by tags: '$($resources.jobs[$job]['runners']['tags'] -join "','")'."
                    (Get-BcEndpointByTag -Tags $resources.jobs[$job]['runners']['tags']).Id
                }

                Write-Information "    - Found $($newMembers.Count) total Runners that should be assigned"

                if ($Test.IsPresent) {
                    Write-Information "    - Would update membership"
                } else {
                    Sync-BcSetMembership -Members $newMembers -SetId $existingJob.EndpointSetId
                }
            }

            # Assign Tags
            if ($resources.jobs[$job].Keys -contains 'tags') {
                if ($Test.IsPresent) {
                    Write-Information "  - Would add tags: $($resources.jobs[$job]['tags'] -join ',')"
                } else {
                    # Build a set
                    $set = New-BcSet
                    # Add the job to the set
                    Add-BcSetToSet -TargetSetId $set -ObjectIds $existingJob.Id
                    # Add the tags to the set
                    Write-Information "  - Adding tags: $($resources.jobs[$job]['tags'] -join ',')"
                    Add-BcTag -SetId $set -Tags $resources.jobs[$job]['tags']
                }
            }
        }
    } else {
        Write-Information "No jobs found."
    }
    $InformationPreference = $ogip
}