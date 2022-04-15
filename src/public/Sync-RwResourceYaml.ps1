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

    Function Sync-RwSetMembership {
        [CmdletBinding()]
        param (
            [string[]]$Members,
            [string]$SetId
        )
        $existingMembers = Get-RwSetMember -SetId $SetId

        Write-Verbose "Current set membership count: $($existingMembers.Count)"

        # Finding any existing members that don't meet the filter
        $toRemove = [System.Collections.Generic.List[string]]::new()
        $toAdd = [System.Collections.Generic.List[string]]::new()
        foreach ($existingMember in $existingMembers.Items) {
            if ($newMembers.Items.Id -notcontains $existingMember.Id) {
                #Write-Verbose "Will remove $($existingMember.Id)"
                $toRemove.Add($existingMember.Id)
            }
        }

        # Find any matching members that need to be added
        foreach ($newMember in $Members) {
            if ($existingMembers.Items.Id -notcontains $newMember) {
                #Write-Verbose "Will add $($newMember)"
                $toAdd.Add($newMember)       
            }
        }

        # Remove unneeded runners
        if ($toRemove.Count -gt 0) {
            Write-Verbose "Removing $($toRemove.Count) Runners from the set"
            Remove-RwSetFromSet -TargetSetId $SetId -ObjectIds $toRemove | Out-Null
        }

        # Add those runners to the job set
        if ($toAdd.Count -gt 0) {
            Write-Verbose "Adding $($toRemove.Count) Runners to the set"
            Add-RwSetToSet -TargetSetId $SetId -ObjectIds $toAdd | Out-Null
        }
    }

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
        Write-Host "Found $($resources.connectors.count) connectors"

        foreach ($connector in $resources.connectors.Keys) {
            Write-Host "Creating connector: '$connector'"

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
                Set-RwConnection @splat -ConnectionId $conn.Id
            } else {
                New-RwConnection @splat
            }
        }
    } else {
        Write-Host "No connectors found."
    }

    # If there are any jobs
    if ($resources.jobs) {
        Write-Host "Found $($resources.jobs.count) jobs"

        foreach ($job in $resources.jobs.Keys) {
            Write-Host "Working on Job: '$job'"
            
            # Create job if not already exist
            $existingJob = Get-RwJobByName $job

            if ($null -ne $existingJob) {
                Write-Verbose 'Job already exists, will update it.'
                $existingJob = Get-RwJob -JobId $existingJob.Id
            } else {
                Write-Verbose 'Job does not exist, will create it.'
                $newJob = New-RwJob -Name $job -IsEnabled -IsHidden:$false
                $existingJob = Get-RwJob -JobId $newJob.JobId
            }

            # Assign Schedule
            if ($resources.jobs[$job].Keys -contains 'schedule') {
                Write-Host "Adding Schedule."
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
                Write-Host 'Adding Actions to the Job.'
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
                    Write-Verbose "$x - '$($action['name'])'"
                    Write-Verbose "Associating '$($action['name'])' to '$($actionHt['RepositoryActionId'])'"
                    if ($action.Keys -contains 'parameters') {
                        Write-Verbose "Adding parameters."
                        $actionHt['Settings'] = $action['parameters']
                    }

                    if ($action.Keys -contains 'connector') {
                        Write-Verbose "Adding connector."
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
                Write-Host 'Adding Runners to the Job.'
                $newMembers = if ($resources.jobs[$job]['runners'].Keys -contains 'names') {
                    Write-Verbose "Adding runners by name."
                    (Get-RwRunnerByName -AssetName $resources.jobs[$job]['runners']['names']).AssetId
                } elseif ($resources.jobs[$job]['runners'].Keys -contains 'tags') {
                    Write-Verbose "Adding Runners by tags: '$($resources.jobs[$job]['runners']['tags'] -join "','")'."
                    (Get-RwEndpointByTag -Tags $resources.jobs[$job]['runners']['tags']).Id
                }

                Write-Verbose "Found $($newMembers.Count) total Runners that should be assigned."

                Sync-RwSetMembership -Members $newMembers -SetId $existingJob.EndpointSetId
            }
        }
    } else {
        Write-Host "No jobs found."
    }
}