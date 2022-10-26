Function New-BcJobSchedule {
    [cmdletbinding()]
    param (
        [int]$RepeatMinutes,
        [string]$Time,
        [string]$Type,
        [string]$WeekDays
    )
    $scheduleSplat = @{
        repeatMinutes = $RepeatMinutes
        Time          = $Time
        scheduletype  = if ($PSBoundParameters.Keys -contains 'Type') {
            $Type
        } else { 'RunNow' }
        weekdays      = $WeekDays
    }
    New-BcJobScheduleObject @scheduleSplat
}