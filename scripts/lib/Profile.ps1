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
    }
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

function Get-Profile([string]$RepoRoot, [string]$Name) {
    $dir = Join-Path $RepoRoot ('profiles\' + $Name)
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

function New-ProfileFromTemplate([string]$RepoRoot, [string]$Name, [string]$Language, [string]$ProjectMapTool) {
    $src = Join-Path $RepoRoot 'profiles\_template'
    $dst = Join-Path $RepoRoot ('profiles\' + $Name)
    if (Test-Path $dst) { throw "Profile '$Name' already exists at $dst" }
    Copy-Item -Recurse -Path $src -Destination $dst
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
