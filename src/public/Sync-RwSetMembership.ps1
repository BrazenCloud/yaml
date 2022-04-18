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