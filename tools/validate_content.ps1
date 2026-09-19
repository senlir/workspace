param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$configRoot = Join-Path $ProjectRoot 'data\config'
$assetRoot = Join-Path $ProjectRoot 'assets'
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Read-Config([string]$Name) {
    $path = Join-Path $configRoot $Name
    if (-not (Test-Path -LiteralPath $path)) {
        $errors.Add("Missing config: $Name")
        return @()
    }
    try {
        return @(Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        $errors.Add("Invalid JSON in ${Name}: $($_.Exception.Message)")
        return @()
    }
}

function Test-UniqueKey($Rows, [string]$Name, [string]$Key) {
    $duplicates = $Rows | Group-Object -Property $Key | Where-Object Count -gt 1
    foreach ($duplicate in $duplicates) {
        $errors.Add("Duplicate $Key '$($duplicate.Name)' in $Name")
    }
}

$tools = Read-Config 'cfg_daoju.json'
$monsters = Read-Config 'cfg_guaiwu.json'
$platforms = Read-Config 'cfg_shuzhi.json'
$platformProfiles = Read-Config 'cfg_platform_profiles.json'
$groups = Read-Config 'cfg_zuhe.json'
$tiers = Read-Config 'cfg_score_zuhe.json'
$shops = Read-Config 'cfg_shangcheng.json'

Test-UniqueKey $tools 'cfg_daoju.json' 'id'
Test-UniqueKey $monsters 'cfg_guaiwu.json' 'id'
Test-UniqueKey $platforms 'cfg_shuzhi.json' 'id'
Test-UniqueKey $platformProfiles 'cfg_platform_profiles.json' 'id'
Test-UniqueKey $groups 'cfg_zuhe.json' 'id'
Test-UniqueKey $tiers 'cfg_score_zuhe.json' 'score'
Test-UniqueKey $shops 'cfg_shangcheng.json' 'id'

$toolIds = @{}; $tools | ForEach-Object { $toolIds[[int]$_.id] = $true }
$monsterIds = @{}; $monsters | ForEach-Object { $monsterIds[[int]$_.id] = $true }
$platformIds = @{}; $platforms | ForEach-Object { $platformIds[[int]$_.id] = $true }
$platformProfileIds = @{}; $platformProfiles | ForEach-Object { $platformProfileIds[[int]$_.id] = $true }
$groupIds = @{}; $groups | ForEach-Object { $groupIds[[int]$_.id] = $true }

foreach ($platform in $platforms) {
    $id = [int]$platform.id
    if (-not $platformProfileIds.ContainsKey($id)) {
        $errors.Add("Platform $id has no tuning profile")
    }
}
foreach ($profile in $platformProfiles) {
    $id = [int]$profile.id
    if (-not $platformIds.ContainsKey($id)) {
        $errors.Add("Platform profile $id references a missing platform")
        continue
    }
    $platform = $platforms | Where-Object { [int]$_.id -eq $id } | Select-Object -First 1
    if ([double]$profile.surface_y -lt 0) {
        $errors.Add("Platform profile $id has a negative surface_y")
    }
    if ([double]$profile.collision_height -le 0) {
        $errors.Add("Platform profile $id must have a positive collision_height")
    }
    if ([double]$profile.edge_inset -lt 0 -or ([double]$profile.edge_inset * 2) -ge [double]$platform.lang) {
        $errors.Add("Platform profile $id edge_inset leaves no standable width")
    }
}

foreach ($group in $groups) {
    foreach ($field in 'shuzhi1','shuzhi2') {
        $id = [int]$group.$field
        if ($id -ne 0 -and -not $platformIds.ContainsKey($id)) {
            $errors.Add("Group $($group.id) references missing platform $id via $field")
        }
    }
    foreach ($field in 'guaiwu1','guaiwu2') {
        $id = [int]$group.$field
        if ($id -ne 0 -and -not $monsterIds.ContainsKey($id)) {
            $errors.Add("Group $($group.id) references missing monster $id via $field")
        }
    }
}

foreach ($tier in $tiers) {
    $slots = @([string]$tier.ids -split '#')
    $toolSlots = @([string]$tier.daojuid -split '#')
    if ($slots.Count -ne $toolSlots.Count) {
        $errors.Add("Score tier $($tier.score) has $($slots.Count) group slots but $($toolSlots.Count) tool slots")
    }
    foreach ($slot in $slots) {
        foreach ($rawId in @($slot -split '&')) {
            $id = [int]$rawId
            if (-not $groupIds.ContainsKey($id)) {
                $errors.Add("Score tier $($tier.score) references missing group $id")
            }
        }
    }
    foreach ($slot in $toolSlots) {
        foreach ($rawId in @($slot -split '&')) {
            $id = [int]$rawId
            if ($id -ne 0 -and -not $toolIds.ContainsKey($id)) {
                $errors.Add("Score tier $($tier.score) references missing tool $id")
            }
        }
    }
}

foreach ($shop in $shops) {
    if (-not $toolIds.ContainsKey([int]$shop.toolid)) {
        $errors.Add("Shop $($shop.id) references missing tool $($shop.toolid)")
    }
}

$pairedRoots = @(
    (Join-Path $assetRoot 'animations\player'),
    (Join-Path $assetRoot 'animations\enemies'),
    (Join-Path $assetRoot 'animations\effects')
)
foreach ($root in $pairedRoots) {
    Get-ChildItem -LiteralPath $root -Filter '*.json' | ForEach-Object {
        $png = [System.IO.Path]::ChangeExtension($_.FullName, '.png')
        if (-not (Test-Path -LiteralPath $png)) {
            $errors.Add("Animation atlas has no PNG pair: $($_.FullName)")
        }
    }
    Get-ChildItem -LiteralPath $root -Filter '*.png' | ForEach-Object {
        $json = [System.IO.Path]::ChangeExtension($_.FullName, '.json')
        if (-not (Test-Path -LiteralPath $json)) {
            $errors.Add("Animation PNG has no JSON pair: $($_.FullName)")
        }
    }
}

if (($tiers | Measure-Object -Property score -Maximum).Maximum -eq 99999) {
    $warnings.Add('The 99999 score tier behaves as an unreachable sentinel in normal play.')
}
$shield = $tools | Where-Object id -eq 1
if ($shield -and ([double]$shield.value -le 0 -or [string]::IsNullOrWhiteSpace([string]$shield.mc))) {
    $warnings.Add('Tool 1 (shield) is incomplete and should not enter the drop sequence.')
}

Write-Host "Validated: $($tools.Count) tools, $($monsters.Count) monsters, $($platforms.Count) platforms, $($platformProfiles.Count) platform profiles, $($groups.Count) groups, $($tiers.Count) score tiers, $($shops.Count) shop rows."
foreach ($warning in $warnings) { Write-Warning $warning }
foreach ($errorMessage in $errors) { Write-Error $errorMessage }

if ($errors.Count -gt 0) { exit 1 }
Write-Host "Content validation passed with $($warnings.Count) warning(s)."
