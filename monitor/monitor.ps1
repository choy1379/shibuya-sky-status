# Shibuya Sky (Klook) evening-slot monitor.
# Read-only: polls Klook's public schedule API, never logs in, books or pays.
param(
    [string[]]$Dates = @('2026-10-09', '2026-10-10', '2026-10-11'),
    [string]$MinTime = '16:00',
    [string]$Topic = 'shibuya-sky-xfym6e25t7',
    [int]$MinDelay = 120,
    [int]$MaxDelay = 180,
    [datetime]$StopAtJst = '2026-10-11 21:30',
    [switch]$Once,
    [int]$PushEveryMin = 15,         # publish status.json to the repo's data branch at least this often
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $Dir 'monitor.log'
$StatusFile = Join-Path $Dir 'status.json'
$PageUrl = 'https://www.klook.com/ko/activity/70672-shibuya-sky-tokyo/'
$ApiUrl = 'https://www.klook.com/v1/experiencesrv/product/spu_service/get_spu_schedule?spu_id=507136&activity_id=70672&k_lang=ko_KR&k_currency=KRW'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0'
$Jst = [TimeZoneInfo]::FindSystemTimeZoneById('Tokyo Standard Time')

function NowJst { [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $Jst) }

function Log($msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Send-Toast($title, $body) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $esc = { param($s) [Security.SecurityElement]::Escape($s) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast scenario='reminder' activationType='protocol' launch='$PageUrl'><visual><binding template='ToastGeneric'><text>$(& $esc $title)</text><text>$(& $esc $body)</text></binding></visual><audio src='ms-winsoundevent:Notification.Looping.Alarm' loop='false'/><actions><action content='Klook 열기' activationType='protocol' arguments='$PageUrl'/></actions></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { Log "toast failed: $($_.Exception.Message)" }
}

function Send-Ntfy($title, $body, [int]$priority = 5, $tags = @('rotating_light')) {
    try {
        $json = @{ topic = $Topic; title = $title; message = $body; priority = $priority; tags = $tags; click = $PageUrl } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post -Uri 'https://ntfy.sh/' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 20 | Out-Null
    } catch { Log "ntfy failed: $($_.Exception.Message)" }
}

function Alert($title, $body, [int]$priority = 5, $tags = @('rotating_light')) {
    Log "ALERT: $title | $body"
    Send-Toast $title $body
    Send-Ntfy $title $body $priority $tags
}

function Write-Status($state, $slots) {
    $obj = [ordered]@{
        checkedAt      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        state          = $state
        minTime        = $MinTime
        slots          = @($slots | Where-Object { $_ })
        highlightDates = $Dates
        url            = $PageUrl
    }
    [IO.File]::WriteAllText($StatusFile, ($obj | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
}

# Publishes status.json to the data branch of choy1379/shibuya-sky-status (read by index.html).
# Pushes only when the slots/state change or every $PushEveryMin minutes (dashboard flags data older than 30 min).
$RepoUrl = 'https://github.com/choy1379/shibuya-sky-status.git'
$DataDir = Join-Path $Dir 'data-branch'
$Git = @('C:\Program Files\Git\cmd\git.exe', 'git') | Where-Object { $_ -eq 'git' -or (Test-Path $_) } | Select-Object -First 1
$script:lastPush = [datetime]::MinValue
$script:lastPushedKey = $null

function Invoke-Git { & $Git -C $DataDir @args 2>&1 | Out-String }

function Push-Status($key) {
    if ($NoPush) { return }
    $due = ((Get-Date) - $script:lastPush).TotalMinutes -ge $PushEveryMin
    if (-not $due -and $key -eq $script:lastPushedKey) { return }
    $ErrorActionPreference = 'Continue'   # git writes progress to stderr
    try {
        if (-not (Test-Path (Join-Path $DataDir '.git'))) {
            & $Git clone -q --single-branch -b data $RepoUrl $DataDir 2>&1 | Out-Null
        }
        $out = Invoke-Git pull -q --rebase origin data
        if ($LASTEXITCODE -ne 0) { throw "pull: $out" }
        Copy-Item $StatusFile (Join-Path $DataDir 'status.json') -Force
        Invoke-Git add status.json | Out-Null
        Invoke-Git -c user.name=shibuya-sky-monitor -c user.email=choy1379@users.noreply.github.com commit -q -m 'status update' | Out-Null
        $out = Invoke-Git push -q origin HEAD:data
        if ($LASTEXITCODE -ne 0) { throw "push: $out" }
        $script:lastPush = Get-Date
        $script:lastPushedKey = $key
    } catch { Log "push failed: $($_.Exception.Message)" }
}

# Returns @{ state = ok|blocked|captcha|error; slots = [...] }
function Check-Once {
    try {
        $r = Invoke-WebRequest -Uri $ApiUrl -UseBasicParsing -UserAgent $UA -TimeoutSec 30 -Headers @{
            'Accept' = 'application/json, text/plain, */*'; 'Accept-Language' = 'ko-KR,ko;q=0.9'; 'Referer' = $PageUrl }
    } catch {
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code -eq 403 -or $code -eq 429) { return @{ state = 'blocked'; detail = "HTTP $code" } }
        return @{ state = 'error'; detail = $_.Exception.Message }
    }
    $text = $r.Content
    if ($text -match 'captcha|datadome|geo\.captcha-delivery') { return @{ state = 'captcha'; detail = 'captcha page returned' } }
    try { $j = $text | ConvertFrom-Json } catch { return @{ state = 'error'; detail = 'non-JSON response' } }
    if (-not $j.success) { return @{ state = 'error'; detail = "API error: $($j.error.message)" } }

    $slots = @()
    foreach ($s in $j.result.schedules) {
        if ($Dates -notcontains $s.date) { continue }
        foreach ($t in $s.time_slots) {
            $start = $t.title
            if ($start -lt $MinTime) { continue }
            $soldOut = @($t.stock_info | Where-Object { $_.sold_out }).Count -gt 0
            if ($t.stock -le 0 -or $soldOut) { continue }
            $end = ([datetime]::ParseExact($start, 'HH:mm', $null)).AddMinutes(20).ToString('HH:mm')
            $slots += [pscustomobject]@{ date = $s.date; start = $start; end = $end; stock = [int]$t.stock }
        }
    }
    return @{ state = 'ok'; slots = $slots; dayCounts = ($j.result.schedules | Where-Object { $Dates -contains $_.date } | ForEach-Object { "$($_.date):$(@($_.time_slots).Count)" }) -join ' ' }
}

$seen = @{}         # "date start" -> first-seen UTC string
$lastBadState = $null
Log "monitor start: dates=$($Dates -join ',') min=$MinTime topic=$Topic"
if (-not $Once) { Send-Ntfy '시부야 스카이 모니터 시작' "$($Dates -join ', ') / $MinTime 이후 슬롯 감시 중" 2 @('eyes') }

while ($true) {
    if ((NowJst) -gt $StopAtJst) { Log 'stop time reached, exiting'; Send-Ntfy '시부야 스카이 모니터 종료' '감시 기간이 끝났습니다.' 2 @('stop_sign'); break }

    $res = Check-Once
    if ($res.state -eq 'ok') {
        if ($lastBadState) { Log "recovered from $lastBadState"; Send-Ntfy '모니터 복구' '정상 조회 재개' 2 @('white_check_mark'); $lastBadState = $null }
        $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $current = @{}
        $new = @()
        foreach ($sl in $res.slots) {
            $k = "$($sl.date) $($sl.start)"
            $current[$k] = $true
            if (-not $seen.ContainsKey($k)) { $seen[$k] = $now; $new += $sl }
        }
        foreach ($k in @($seen.Keys)) { if (-not $current.ContainsKey($k)) { $seen.Remove($k); Log "gone: $k" } }

        $out = $res.slots | ForEach-Object {
            [ordered]@{ date = $_.date; start = $_.start; end = $_.end; status = $(if ($_.stock -le 5) { 'low' } else { 'ok' }); since = $seen["$($_.date) $($_.start)"] }
        }
        Write-Status 'ok' $out
        Push-Status ('ok|' + (($res.slots | ForEach-Object { "$($_.date) $($_.start) $($_.stock -le 5)" }) -join ','))
        $summary = if ($res.slots.Count) { ($res.slots | ForEach-Object { "$($_.date) $($_.start)($($_.stock))" }) -join ', ' } else { 'none' }
        Log "ok  slots>=$MinTime : $summary   [available slots per day: $($res.dayCounts)]"

        if ($new.Count -gt 0) {
            $body = ($new | ForEach-Object { "$($_.date.Substring(5)) $($_.start) (잔여 $($_.stock))" }) -join "`n"
            Alert '시부야 스카이 저녁 슬롯 열림!' "$body`n지금 Klook에서 예약하세요." 5
        }
    } else {
        Write-Status $res.state @()
        Push-Status $res.state
        Log "$($res.state): $($res.detail)"
        if ($res.state -ne $lastBadState -and $res.state -ne 'error') {
            Alert "모니터 $($res.state)" "Klook 조회가 막혔습니다 ($($res.detail)). PC에서 확인이 필요합니다." 4 @('warning')
        }
        $lastBadState = $res.state
    }

    if ($Once) { break }
    $delay = Get-Random -Minimum $MinDelay -Maximum ($MaxDelay + 1)
    if ($res.state -eq 'blocked' -or $res.state -eq 'captcha') { $delay = 900 }
    Start-Sleep -Seconds $delay
}
