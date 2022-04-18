param (
    [version]$Version = '0.0.1',
    [string]$NugetApiKey
)
$srcPath = "$PSScriptRoot\src"
$buildPath = "$PSScriptRoot\build"
$docPath = "$PSScriptRoot\docs"
$testPath = "$PSScriptRoot\tests"
$moduleName = ($MyInvocation.MyCommand.Name.Split('.') | Select-Object -SkipLast 2) -join '.'
$modulePath = "$buildPath\$ModuleName"

Write-Host "Version: $($version)"

# Clean out any previous builds
task Clean {
    if (Get-Module $moduleName) {
        Remove-Module $moduleName
    }
    if (Test-Path $modulePath) {
        Remove-Item $modulePath -Recurse -ErrorAction Ignore | Out-Null
    }
}

# Build the docs, depends on PlatyPS
task DocBuild ModuleBuild,{
    if (-not (Test-Path $docPath)) {
        New-Item $docPath -ItemType Directory
    }
    #New-ExternalHelp $docPath -OutputPath "$modulePath\EN-US"
}

# Build the module
task ModuleBuild Clean, {
    $moduleScriptFiles = Get-ChildItem $srcPath -Filter *.ps1 -File -Recurse
    if (-not(Test-Path $modulePath)) {
        New-Item $modulePath -ItemType Directory
    }

    # Add using.ps1 to the .psm1 first
    foreach ($file in $moduleScriptFiles | ?{$_.Name -eq 'using.ps1'}) {
        if ($file.fullname) {
            Write-Host "Adding using file: '$($file.Fullname)'"
            Get-Content $file.fullname | Out-File "$modulePath\$moduleName.psm1" -Append -Encoding utf8
        }
    }

    # Add all .ps1 files to the .psm1, skipping onload.ps1, using.ps1, and any tests
    foreach ($file in $moduleScriptFiles | ?{$_.Name -ne 'onload.ps1' -and $_.Name -ne 'using.ps1' -and $_.FullName -notmatch '(\\|\/)tests(\\|\/)[^\.]+\.tests\.ps1$'}) {
        if ($file.fullname) {
            Write-Host "Adding function file: '$($file.FullName)'"
            Get-Content $file.fullname | Out-File "$modulePath\$moduleName.psm1" -Append -Encoding utf8
        }
    }
    
    # Add the onload.ps1 files last
    foreach ($file in $moduleScriptFiles | ?{$_.Name -eq 'onload.ps1'}) {
        if ($file.fullname) {
            Write-Host "Adding onload file: '$($file.FullName)'"
            Get-Content $file.fullname | Out-File "$modulePath\$moduleName.psm1" -Append -Encoding utf8
        }
    }

    # Copy the manifest
    Copy-Item "$srcPath\$moduleName.psd1" -Destination $modulePath

    # Copy the tests
    foreach($test in ($moduleScriptFiles | Where-Object {$_.FullName -match '(\\|\/)tests(\\|\/)[^\.]+\.tests\.ps1$'})) {
        Write-Host "Copying test file: '$($test.FullName)'"
        Copy-Item $test.FullName -Destination $modulePath
    }

    $moduleManifestData = @{
        Path = "$modulePath\$moduleName.psd1"
        # Only export the public files
        FunctionsToExport = ($moduleScriptFiles | Where-Object {$_.FullName -match "(\\|\/)public(\\|\/)[^\.]+\.ps1$"}).basename
        ModuleVersion = $version
    }
    if ($null -ne $preRelease) {
        $moduleManifestData['Prerelease'] = $preRelease
    }
    Update-ModuleManifest @moduleManifestData
}

Task Test ModuleBuild, {
    Write-Host "Importing module."
    Import-Module $modulePath -RequiredVersion $version
    Write-Host "Invoking tests."
    Invoke-Pester $testPath -Verbose
}

task Publish Test, DocBuild, {
    if ($PSBoundParameters.Keys.Contains('NugetApiKey')) {
        Publish-Module -Name $moduleName -NuGetApiKey $NugetApiKey -RequiredVersion $Version -Repository PsGallery
    }
}

task All ModuleBuild, Publish