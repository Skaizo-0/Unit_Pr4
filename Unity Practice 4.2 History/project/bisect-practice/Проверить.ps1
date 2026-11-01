param(
    [string]$Repo = (Join-Path $PSScriptRoot 'work'),
    [string]$Unity,
    [string]$Output,
    [string]$ExecutionRoot,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
$env:GIT_MASTER = '1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$process = $null
$ownedProcess = $false

function Git([string[]]$Arguments) {
    $text = & git.exe -C $Repo @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $Arguments" }
    return $text
}
function Quote([string]$Value) {
    if ($Value.Contains('"') -or $Value.EndsWith('\')) { throw 'Unsupported quote or trailing separator in argument' }
    return '"' + $Value + '"'
}
function Full([string]$Path) { return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') }
function Is-Within([string]$Child, [string]$Parent) {
    $childFull = (Full $Child) + '\'; $parentFull = (Full $Parent) + '\'
    return $childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)
}
function Assert-NotReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point is not allowed: '$Path'" }
}
function Assert-TreeNoReparse([string]$Path) {
    Assert-NotReparse $Path
    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force)) {
        Assert-NotReparse $child.FullName
        if ($child.PSIsContainer) { Assert-TreeNoReparse $child.FullName }
    }
}
function Write-Json([string]$Path, $Value) { [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), $utf8) }
function Read-Json([string]$Path) { return [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
function Hash-Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Text))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Source-Hashes([string]$Project) {
    $result = [ordered]@{}
    foreach ($folder in @('Assets', 'Packages')) {
        $base = Join-Path $Project $folder
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { throw "Source folder missing: $folder" }
        Assert-TreeNoReparse $base
        foreach ($file in @(Get-ChildItem -LiteralPath $base -Filter '*.cs' -File -Recurse | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($Project.Length + 1).Replace('\', '/')
            $result[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $result
}
function Assert-SourceHashes($Expected, [string]$Project, [string]$Label) {
    $actual = Source-Hashes $Project
    if (($actual.Keys -join "`n") -ne ($Expected.Keys -join "`n")) { throw "C# source set changed after ${Label}" }
    foreach ($relative in $Expected.Keys) {
        if ($actual[$relative] -ne $Expected[$relative]) {
            throw "C# source integrity failed after ${Label}: $relative"
        }
    }
}
function Assert-Original([string]$Head, $Hashes) {
    if ((Git @('rev-parse', 'HEAD')) -ne $Head) { throw 'Clone HEAD changed while the check was running' }
    Assert-NotReparse $Repo
    foreach ($folder in @('Assets', 'Packages', 'ProjectSettings')) { Assert-TreeNoReparse (Join-Path $Repo $folder) }
    $files = @(Git @('ls-tree', '-r', '--name-only', 'known-good'))
    if (($files -join "`n") -ne ((Git @('ls-files')) -join "`n")) { throw 'Tracked file set differs from known-good' }
    foreach ($file in $files) {
        $head = Git @('rev-parse', "HEAD:$file")
        $actual = Git @('hash-object', '--no-filters', '--', (Join-Path $Repo $file))
        if ($actual -ne $head) { throw "Worktree bytes differ from Git blob: $file" }
        if ($file -notin @('README.md', 'Assets/Scripts/LookupExercise.cs') -and $head -ne (Git @('rev-parse', "known-good:$file"))) { throw "Protected file changed: $file" }
    }
    $exercisePath = 'Assets/Scripts/LookupExercise.cs'; $baseline = (Git @('show', "known-good:$exercisePath")) -join "`n"; $current = [IO.File]::ReadAllText((Join-Path $Repo $exercisePath)).TrimEnd("`n"); $marker = '    public int ExecuteBatch'
    if ($baseline.IndexOf($marker) -lt 0 -or $current.IndexOf($marker) -lt 0) { throw 'Protected exercise method marker missing' }
    if ($baseline.Substring(0, $baseline.IndexOf($marker)) -ne $current.Substring(0, $current.IndexOf($marker))) { throw 'Protected exercise initialization or instrumentation changed' }
    $changes = @(Git @('status', '--porcelain', '--untracked-files=all') | Where-Object { $_ -cne '?? ProjectSettings/PackageManagerSettings.asset' })
    if ($changes.Count) { throw 'Clone changed or contains untracked files; preserve it and use a fresh clean clone' }
    Assert-SourceHashes $Hashes $Repo 'checking the original clone'
}
function Find-Unity {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    $found = @($roots | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_ 'Unity\Hub\Editor') -Filter Unity.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } } | Sort-Object -Unique)
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -eq 0) { throw 'Unity Editor not found. Choose an installed compatible Editor in Unity Hub and retry with -Unity "D:\Unity\Editor\Unity.exe".' }
    throw "Several Unity Editors are installed. Choose one once with -Unity: $($found -join '; ')"
}
function Test-ProjectCommandLine([string]$CommandLine, [string]$Project) {
    $match = [regex]::Match($CommandLine, '(?i)(?:^|\s)-projectPath\s+(?:"([^"]+)"|([^\s"]+))(?=\s|$)')
    if (-not $match.Success) { return $false }
    $path = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
    return (Full $path) -eq (Full $Project)
}
function Assert-ProjectAvailable([string]$Project) {
    try { $editors = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'" -OperationTimeoutSec 5) }
    catch { throw 'Cannot inspect Unity processes. Check Windows process-query permissions and retry; no lock was removed.' }
    foreach ($editor in $editors) {
        if (-not $editor.CommandLine) { throw "Cannot identify Unity PID $($editor.ProcessId). Check process-query permissions; no lock was removed." }
        if (Test-ProjectCommandLine $editor.CommandLine $Project) { throw "Unity PID $($editor.ProcessId) is using owned execution copy '$Project'. Close that Editor and retry." }
    }
    $lockPath = Join-Path $Project 'Temp\UnityLockfile'
    try { $probe = [IO.File]::Open($lockPath, 'Open', 'Read', 'None') }
    catch [IO.FileNotFoundException] { return }
    catch [IO.DirectoryNotFoundException] { return }
    catch [IO.IOException] { throw "Project lock is held: '$lockPath'. Close this execution copy's Editor or wait; no lock was removed." }
    finally { if ($probe) { $probe.Dispose() } }
    Write-Host "Unheld leftover lock detected; leaving it untouched for Unity: $lockPath"
}
function Read-DiagnosticLog([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $reader = New-Object IO.StreamReader($stream); return $reader.ReadToEnd() }
    finally { if ($reader) { $reader.Dispose() } else { $stream.Dispose() } }
}
function Read-FreshReport([string]$Path, [Diagnostics.Stopwatch]$Clock, [int]$LimitMilliseconds) {
    $deadline = [Math]::Min($Clock.ElapsedMilliseconds + 3000, $LimitMilliseconds)
    while ($true) {
        try { return [IO.File]::ReadAllText($Path) }
        catch [IO.IOException] {
            $remaining = $deadline - $Clock.ElapsedMilliseconds
            if ($remaining -le 0) { throw "Fresh report is still locked or unavailable: '$Path'; no GOOD/BAD result." }
            Start-Sleep -Milliseconds ([Math]::Min(100, $remaining))
        }
    }
}
function Wait-Output($OutTask, $ErrTask, [Diagnostics.Stopwatch]$Clock, [int]$LimitMilliseconds) {
    $remaining = [Math]::Max(0, $LimitMilliseconds - [int]$Clock.ElapsedMilliseconds)
    if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($OutTask, $ErrTask), $remaining)) { throw 'Unity exited but its output streams did not close before the timeout' }
}
function Remove-OwnedChildren([string]$Workspace) {
    Assert-TreeNoReparse $Workspace
    foreach ($child in @(Get-ChildItem -LiteralPath $Workspace -Force)) {
        if ($child.Name -in @('Library', 'owner.json', 'workspace.lock')) { continue }
        Remove-Item -LiteralPath $child.FullName -Recurse -Force
    }
}
function Expand-Commit([string]$Workspace, [string]$Commit) {
    Remove-OwnedChildren $Workspace
    $archive = Join-Path $Workspace ('.capture-' + [Guid]::NewGuid().ToString('N') + '.zip')
    try {
        $null = & git.exe -C $Repo archive --format=zip --output=$archive $Commit 2>&1
        if ($LASTEXITCODE) { throw 'git archive failed' }
        Expand-Archive -LiteralPath $archive -DestinationPath $Workspace -Force
    } finally { if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force } }
    $files = @(Git @('ls-tree', '-r', '--name-only', $Commit))
    $captured = @(Get-ChildItem -LiteralPath $Workspace -Force | Where-Object { $_.Name -notin @('Library', 'owner.json', 'workspace.lock') } | ForEach-Object {
        if ($_.PSIsContainer) { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force } else { $_ }
    } | ForEach-Object { $_.FullName.Substring($Workspace.Length + 1).Replace('\', '/') } | Sort-Object)
    if (($captured -join "`n") -cne (($files | Sort-Object) -join "`n")) { throw 'Captured archive file set differs from Git' }
    foreach ($file in $files) {
        $expected = Git @('rev-parse', "$Commit`:$file")
        $actual = & git.exe hash-object --no-filters -- (Join-Path $Workspace $file)
        if ($LASTEXITCODE -ne 0 -or $actual -ne $expected) { throw "Captured archive bytes differ from Git: $file" }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
try {
    $Repo = Full $Repo
    if (-not (Test-Path (Join-Path $Repo 'Assets\Editor\HistoryRegressionCheck.cs'))) { throw 'Clone unity_fixture/history.bundle first' }
    if ((Git @('rev-parse', '--show-toplevel')).Replace('/', '\') -ne $Repo) { throw 'Repo must be the clone root' }
    $commit = Git @('rev-parse', 'HEAD')
    $originalSources = Source-Hashes $Repo
    Assert-Original $commit $originalSources
    if (-not $Unity) { $Unity = Find-Unity }
    if (-not (Test-Path -LiteralPath $Unity -PathType Leaf)) { throw 'Unity Editor not found. In Unity Hub > Installs > version menu > Show in Explorer, find Editor\Unity.exe and retry with -Unity.' }
    $Unity = Full $Unity
    if (-not $ExecutionRoot) { $ExecutionRoot = Join-Path (Split-Path $Repo -Parent) '.unity-bisect-runs' }
    $ExecutionRoot = Full $ExecutionRoot
    if (Is-Within $ExecutionRoot $Repo -or (Is-Within $Repo $ExecutionRoot)) { throw 'ExecutionRoot must be outside the bisect clone' }
    if (-not (Test-Path -LiteralPath $ExecutionRoot)) { $null = New-Item -ItemType Directory -Path $ExecutionRoot }
    Assert-NotReparse $ExecutionRoot
    $editorVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Unity).ProductVersion
    $key = (Hash-Text (($Repo.ToLowerInvariant()) + '|' + ($Unity.ToLowerInvariant()) + '|' + $editorVersion)).Substring(0, 24)
    $workspace = Join-Path $ExecutionRoot $key
    if (-not (Test-Path -LiteralPath $workspace)) { $null = New-Item -ItemType Directory -Path $workspace }
    Assert-NotReparse $workspace
    $marker = Join-Path $workspace 'owner.json'
    $owner = [ordered]@{ schema = 1; repo = $Repo; unity = $Unity; editor_version = $editorVersion; workspace = $workspace }
    if (Test-Path -LiteralPath $marker) {
        $saved = Read-Json $marker
        if ($saved.schema -ne 1 -or $saved.repo -ne $Repo -or $saved.unity -ne $Unity -or $saved.editor_version -cne $editorVersion -or $saved.workspace -ne $workspace) { throw "Execution workspace ownership collision: '$workspace'. It is not owned by this clone and Editor." }
    } elseif (@(Get-ChildItem -LiteralPath $workspace -Force).Count -ne 0) { throw "Execution workspace is not empty and has no owner marker: '$workspace'" }
    else { Write-Json $marker $owner }
    $workspaceLock = [IO.File]::Open((Join-Path $workspace 'workspace.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $token = [Guid]::NewGuid().ToString('N')
        if (-not $Output) { $Output = Join-Path ([IO.Path]::GetTempPath()) "unity-history-$token.json" }
        $Output = Full $Output
        if (Is-Within $Output $Repo -or Is-Within $Output $ExecutionRoot -or $Output -eq $Repo -or $Output -eq $ExecutionRoot) { throw 'Output must be outside both the clone and ExecutionRoot' }
        $log = "$Output.unity.log"; $stdout = "$Output.stdout.log"; $stderr = "$Output.stderr.log"; $sidecar = "$Output.launcher.json"
        foreach ($path in @($Output, $log, $stdout, $stderr, $sidecar)) { if (Test-Path -LiteralPath $path) { throw "Existing report or log preserved: '$path'. Use a new Output filename; existing results are never reused." } }
        if (-not (Test-Path -LiteralPath (Split-Path $Output -Parent) -PathType Container)) { throw 'Output parent directory must exist' }
        Assert-Original $commit $originalSources
        Assert-ProjectAvailable $workspace
        Expand-Commit $workspace $commit
        $capturedSources = Source-Hashes $workspace
        Assert-SourceHashes $originalSources $workspace 'capturing the commit'
        Assert-TreeNoReparse $workspace
        $library = Join-Path $workspace 'Library'
        if (Test-Path -LiteralPath $library) { Assert-TreeNoReparse $library }
        $arguments = @('-batchmode', '-nographics', '-projectPath', $workspace, '-executeMethod', 'HistoryRegressionCheck.Run', '-logFile', $log, '--history-output', $Output, '--history-token', $token, '--history-commit', $commit)
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $Unity; $start.Arguments = ($arguments | ForEach-Object { Quote $_ }) -join ' '; $start.WorkingDirectory = $workspace
        $start.UseShellExecute = $false; $start.CreateNoWindow = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process; $process.StartInfo = $start
        $clock = [Diagnostics.Stopwatch]::StartNew(); $null = $process.Start(); $ownedProcess = $true
        $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([Math]::Max(0, $TimeoutSeconds * 1000 - [int]$clock.ElapsedMilliseconds))) { $process.Kill(); $null = $process.WaitForExit(5000); throw 'Unity timed out; only the process started by this invocation was killed' }
        Wait-Output $outTask $errTask $clock ($TimeoutSeconds * 1000)
        [IO.File]::WriteAllText($stdout, $outTask.GetAwaiter().GetResult(), $utf8); [IO.File]::WriteAllText($stderr, $errTask.GetAwaiter().GetResult(), $utf8)
        $exit = $process.ExitCode
        Assert-SourceHashes $capturedSources $workspace 'running Unity'; Assert-Original $commit $originalSources
        if (-not (Test-Path -LiteralPath $Output)) {
            $text = ''
            if (Test-Path -LiteralPath $log) { try { $text = Read-DiagnosticLog $log } catch { Write-Host "Diagnostic log is not readable yet; preserve it: $log" } }
            if ($text -match '(?m)\berror CS\d{4}\b') { Write-Host "Compiler errors; skip this revision. Log: $log"; exit 125 }
            throw "Unity exited $exit without a fresh report; no GOOD/BAD result. Inspect '$log' and '$stderr'. Unsupported Editor/package/API startup is 128, not BAD."
        }
        $reportText = Read-FreshReport $Output $clock ($TimeoutSeconds * 1000)
        try { $report = ($reportText | ConvertFrom-Json) } catch { throw "Fresh report is incomplete or invalid JSON: '$Output'; no GOOD/BAD result." }
        if ($report.run_token -ne $token -or $report.commit -ne $commit -or $report.records -ne 4096 -or $report.queries -ne 1024 -or $report.checksum -ne 6168064 -or $report.budget -ne 8192 -or $report.inspections -lt 4096) { throw 'Invalid report identity, workload or checksum' }
        $expected = if ($report.verdict -eq 'good' -and $report.inspections -le 8192) { 0 } elseif ($report.verdict -eq 'bad' -and $report.inspections -gt 8192) { 1 } else { 128 }
        if ($expected -eq 128 -or $exit -ne $expected) { throw "Unity exit $exit disagrees with report verdict" }
        Write-Json $sidecar ([ordered]@{ editor = $Unity; editor_version = $editorVersion; original_repo = $Repo; execution_root = $ExecutionRoot; execution_project = $workspace; commit = $commit; token = $token; outcome = $report.verdict; exit = $exit })
        Write-Host "verdict=$($report.verdict) checksum=$($report.checksum) inspections=$($report.inspections) budget=8192"; Write-Host "Report: $Output"; exit $expected
    } finally { $workspaceLock.Dispose() }
} catch { Write-Host "ERROR (128, not BAD): $($_.Exception.Message)"; exit 128 }
finally { if ($ownedProcess -and -not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }; if ($process) { $process.Dispose() } }
