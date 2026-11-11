# Profiles: per-person settings under profiles/<name>/. ASCII-only file.

function Get-ProfileDefaults {
    @{
        language   = 'auto'
        sync       = @{ debounceMinutes = 10 }
        update     = @{ day = 'Sunday' }
        projectMap = @{ tool = 'graphify' }
        ownSkills  = @()
        ownPlugins = @()
        ignored    = @()
        upstream   = @{ follow = $true }
    }
}

function Test-Following($Prof) {
    # False once the user stopped following the shared repository (scripts/follow.ps1 -Stop).
    return -not ($Prof -and $Prof.upstream -is [hashtable] -and $Prof.upstream.follow -eq $false)
}

function Get-SharedFile([string]$RepoRoot, $Prof, [string]$Name) {
    # A shared file (GEMINI.core.md, permissions.json, sources.json, sources.lock.json): from core/ while
    # following the shared repository, from the profile's own copy in shared/ after the user stopped.
    if ($Prof -and $Prof.Path -and -not (Test-Following $Prof)) {
        $own = Join-Path $Prof.Path ('shared\' + $Name)
        if (Test-Path $own) { return $own }
    }
    return Join-Path $RepoRoot ('core\' + $Name)
}

function Get-I18nText([string]$RepoRoot, [string]$Language = 'en') {
    # All user-facing script text is English (scripts/i18n/en.json); other files are optional.
    $dir = Join-Path $RepoRoot 'scripts\i18n'
    $file = Join-Path $dir ($Language + '.json')
    if (-not $Language -or -not (Test-Path $file)) { $file = Join-Path $dir 'en.json' }
    Read-JsonFile $file @{}
}

function Get-LanguageName([string]$Code) {
    # English name of a language code, e.g. vi -> Vietnamese; unknown codes are returned as given.
    try {
        $c = [Globalization.CultureInfo]::GetCultureInfo($Code)
        if ($c -and $c.EnglishName -and $c.EnglishName -notmatch '^Unknown') { return ($c.EnglishName -replace '\s*\(.*\)$', '') }
    } catch { }
    return $Code
}

function Get-ProfileLocation([string]$RepoRoot, $Machine) {
    # Where this machine's profile lives and which repository sync commits it to.
    # Personal: the root of the user's own backup clone (machine.json profileRoot), every file managed.
    # Otherwise: profiles/<name>/ in the shared clone (plus the core files on an owner).
    if ($Machine.profileRoot) {
        return @{ Dir = [string]$Machine.profileRoot; GitRoot = [string]$Machine.profileRoot; Personal = $true; Managed = @('*') }
    }
    $managed = @('profiles/' + $Machine.profile + '/')
    if ($Machine.role -eq 'owner') { $managed += @('core/GEMINI.core.md', 'core/permissions.json', 'core/sources.json', 'core/sources.lock.json', 'THIRD_PARTY.md') }
    return @{ Dir = (Join-Path $RepoRoot ('profiles\' + $Machine.profile)); GitRoot = $RepoRoot; Personal = $false; Managed = $managed }
}

function Get-Profile([string]$RepoRoot, [string]$Name, [string]$Dir) {
    # $Dir overrides the default profiles/<name>/ folder (a personal backup clone).
    $dir = if ($Dir) { $Dir } else { Join-Path $RepoRoot ('profiles\' + $Name) }
    $data = Read-JsonFile (Join-Path $dir 'profile.json') $null
    if ($null -eq $data) { throw "Profile '$Name' not found in $dir" }
    $p = Get-ProfileDefaults
    foreach ($k in $data.Keys) {
        if ($p[$k] -is [hashtable] -and $data[$k] -is [hashtable]) {
            foreach ($k2 in $data[$k].Keys) { $p[$k][$k2] = $data[$k][$k2] }
        } else {
            $p[$k] = $data[$k]
        }
    }
    $p.name = $Name
    $p.Path = $dir
    $gm = Join-Path $dir 'GEMINI.profile.md'
    $p.GeminiProfileText = if (Test-Path $gm) { (Read-TextFile $gm).TrimEnd("`r", "`n") } else { '' }
    $p.Sources = @(Read-JsonFile (Join-Path $dir 'sources.json') @())
    $p.Lock = Read-JsonFile (Join-Path $dir 'sources.lock.json') @{}
    $p.Permissions = @(Read-JsonFile (Join-Path $dir 'permissions.json') @())
    return $p
}

function New-ProfileFromTemplate([string]$RepoRoot, [string]$Name, [string]$Language, [string]$ProjectMapTool, [string]$Destination) {
    # $Destination: an existing folder to fill (a personal backup clone); default profiles/<name>/.
    $src = Join-Path $RepoRoot 'profiles\_template'
    if ($Destination) {
        $dst = $Destination
        if (Test-Path (Join-Path $dst 'profile.json')) { throw "A profile already exists at $dst" }
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Get-ChildItem -LiteralPath $src -Force | ForEach-Object { Copy-Item -Recurse -Force -LiteralPath $_.FullName -Destination $dst }
    } else {
        $dst = Join-Path $RepoRoot ('profiles\' + $Name)
        if (Test-Path $dst) { throw "Profile '$Name' already exists at $dst" }
        Copy-Item -Recurse -Path $src -Destination $dst
    }
    $json = Join-Path $dst 'profile.json'
    $data = Read-JsonFile $json @{}
    $data.name = $Name
    $data.language = $Language
    $data.projectMap = @{ tool = $ProjectMapTool }
    Write-JsonFile $json $data
    $texts = Get-I18nText $RepoRoot 'en'
    # 'auto' (the default) mirrors the user's language; a code such as 'vi' pins one language.
    $rule = if (-not $Language -or $Language -eq 'auto') { $texts.languageRuleAuto } else { $texts.languageRule -f (Get-LanguageName $Language) }
    $gm = Join-Path $dst 'GEMINI.profile.md'
    Write-TextFile $gm (((Read-TextFile $gm) -replace '\{\{LANGUAGE_RULE\}\}', $rule.Replace('$', '$$')))
    return $dst
}
