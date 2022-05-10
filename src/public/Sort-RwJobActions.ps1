Function Sort-RwJobActions {
    [cmdletbinding()]
    param (
        [RunwaySdk.PowerShell.Models.ActionInstance[]]$Actions
    )
    $ht = @{}
    foreach ($action in $Actions) {
        $ht[$action.Id] = $action
    }

    for ($x = 0; $x -lt $Actions.Count; $x++) {
        if ($x -eq 0) {
            Tee-Object -InputObject ($Actions | Where-Object { $null -eq $_.PrevActionId }) -Variable prev
        } else {
            if ($prev.NextActionId) {
                Tee-Object -InputObject ($ht[$prev.NextActionId]) -Variable prev
            }
        }
    }
}