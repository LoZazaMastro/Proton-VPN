param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('connect','disconnect','status')]
    [string]$Action,

    [string]$CountryCode = 'IT'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Revision = 'R18-structured-recent-connect'
$script:KnownCountryCodes = @(
'AF','AL','DZ','AD','AO','AR','AM','AU','AT','AZ','BH','BD','BY','BE','BT','BO','BA','BR','BN','BG','KH','CM','CA','TD','CL','CO','KM','CD','CR','HR','CU','CY','CZ','CI','DK','DO','EC','EG','SV','ER','EE','ET','FI','FR','GA','GE','DE','GH','GR','GL','GT','GN','HT','HN','HK','HU','IS','IN','ID','IQ','IE','IL','IT','JM','JP','JO','KZ','KE','XK','KW','KG','LA','LV','LB','LY','LI','LT','LU','MO','MY','MT','MR','MU','MX','MD','MC','MN','ME','MA','MZ','MM','NP','NL','NZ','NI','NE','NG','NO','OM','PK','PA','PG','PY','PE','PH','PL','PT','PR','QA','RO','RU','RW','SA','SN','RS','SG','SK','SI','ZA','KR','ES','LK','SD','SE','CH','SY','TW','TZ','TH','TL','TG','TT','TN','TR','TM','UG','UA','AE','GB','US','UY','UZ','VE','VN','YE','ZM','ZW'
)

function Write-Trace([string]$Message) {
    try { [Console]::Error.WriteLine('[HELPER ' + $script:Revision + '] ' + $Message) } catch {}
}

function Write-Result {
    param(
        [bool]$Ok,
        [string]$Message,
        [bool]$Connected = $false,
        [string]$Stage = '',
        [string]$Country = '',
        [object]$Diagnostics = $null,
        [string]$Code = ''
    )
    $payload = [ordered]@{
        ok = $Ok
        message = $Message
        connected = $Connected
        stage = $Stage
        engine = $script:Revision
    }
    if (-not [string]::IsNullOrWhiteSpace($Country)) { $payload.country_code = $Country }
    if (-not [string]::IsNullOrWhiteSpace($Code)) { $payload.code = $Code }
    if ($null -ne $Diagnostics) { $payload.diagnostics = $Diagnostics }
    $payload | ConvertTo-Json -Compress -Depth 10
}

function Get-ProtonProcesses {
    $items = @()
    try {
        # Avoid enumerating every process on the machine. The filtered CIM query is
        # noticeably faster on Windows handheld/Decky setups while still exposing paths.
        $filter = "Name='ProtonVPN.Client.exe' OR Name='ProtonVPNService.exe' OR Name='ProtonVPN.NrptWatchdog.exe' OR Name='ProtonVPN.WireGuardService.exe' OR Name='ProtonVPN.Launcher.exe'"
        $rows = @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction Stop)
        foreach ($row in $rows) {
            $items += [pscustomobject]@{
                name = [string]$row.Name
                process_id = [int]$row.ProcessId
                path = [string]$row.ExecutablePath
            }
        }
    } catch { Write-Trace ('process-query-failed:' + $_.Exception.Message) }
    return @($items)
}

function Get-ProtonServices {
    $items = @()
    try {
        $rows = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
            ($_.Name -match '(?i)Proton.*VPN|ProtonVPN') -or
            ($_.DisplayName -match '(?i)Proton.*VPN|ProtonVPN') -or
            ($_.PathName -match '(?i)Proton.*VPN|ProtonVPN')
        })
        foreach ($row in $rows) {
            $items += [pscustomobject]@{
                name = [string]$row.Name
                display_name = [string]$row.DisplayName
                state = [string]$row.State
            }
        }
    } catch { Write-Trace ('service-query-failed:' + $_.Exception.Message) }
    return @($items)
}

function Get-ProtonAdapters {
    $items = @()
    try {
        if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
            $rows = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
                ($_.Name -match '(?i)Proton|WireGuard|Wintun|TAP') -or
                ($_.InterfaceDescription -match '(?i)Proton|WireGuard|Wintun|TAP')
            })
            foreach ($row in $rows) {
                $vpnRoutes = @()
                try {
                    $vpnRoutes = @(Get-NetRoute -InterfaceIndex $row.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
                        $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1')
                    })
                } catch {}
                $items += [pscustomobject]@{
                    name = [string]$row.Name
                    description = [string]$row.InterfaceDescription
                    status = [string]$row.Status
                    if_index = [int]$row.ifIndex
                    has_vpn_route = [bool]($vpnRoutes.Count -gt 0)
                }
            }
        }
    } catch { Write-Trace ('adapter-query-failed:' + $_.Exception.Message) }
    return @($items)
}

function Get-GrpcPipeInfo {
    $candidates = @(
        'HKLM:\SOFTWARE\Proton AG\Proton VPN\gRPC',
        'HKLM:\SOFTWARE\WOW6432Node\Proton AG\Proton VPN\gRPC',
        'HKCU:\SOFTWARE\Proton AG\Proton VPN\gRPC'
    )
    $found = @()
    foreach ($key in $candidates) {
        try {
            if (Test-Path $key) {
                $item = Get-ItemProperty -Path $key -ErrorAction Stop
                $pipe = ''
                if ($null -ne $item.PipeName) { $pipe = [string]$item.PipeName }
                $found += [pscustomobject]@{ registry_path = $key; pipe_name = $pipe }
            }
        } catch {}
    }
    return @($found)
}

function Get-ClientPath([object[]]$Processes) {
    $running = @($Processes | Where-Object { $_.name -ieq 'ProtonVPN.Client.exe' -and $_.path } | Select-Object -First 1)
    if ($running.Count -gt 0 -and (Test-Path $running[0].path)) { return [string]$running[0].path }

    $patterns = @(
        # Proton 5.x canonical layout (confirmed on the target machine: ...\VPN\v5.1.5\...).
        'C:\Program Files\Proton\VPN\v*\ProtonVPN.Client.exe',
        'C:\Program Files\Proton\VPN\*\ProtonVPN.Client.exe',
        # Legacy/fallback layouts.
        'C:\Program Files\Proton\VPN\ProtonVPN.Client.exe',
        'C:\Program Files\Proton\Proton VPN\ProtonVPN.Client.exe',
        'C:\Program Files\ProtonVPN\ProtonVPN.Client.exe'
    )
    foreach ($pattern in $patterns) {
        try {
            $m = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            if ($m.Count -gt 0) { return [string]$m[0].FullName }
        } catch {}
    }
    return ''
}

function Get-LauncherPath([string]$ClientPath) {
    $candidates = @('C:\Program Files\Proton\VPN\ProtonVPN.Launcher.exe')
    if ($ClientPath) {
        try {
            $versionDirectory = Split-Path -Parent $ClientPath
            $vpnDirectory = Split-Path -Parent $versionDirectory
            $candidates = @((Join-Path $vpnDirectory 'ProtonVPN.Launcher.exe')) + $candidates
        } catch {}
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return [string]$candidate }
    }
    return ''
}

function Get-ProtonDataRoots {
    $roots = @()
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'ProtonVPN'),
        (Join-Path $env:LOCALAPPDATA 'Proton\VPN'),
        (Join-Path $env:LOCALAPPDATA 'Proton\Proton VPN'),
        (Join-Path $env:APPDATA 'ProtonVPN'),
        (Join-Path $env:APPDATA 'Proton\VPN'),
        (Join-Path $env:PROGRAMDATA 'ProtonVPN'),
        (Join-Path $env:PROGRAMDATA 'Proton\VPN')
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path) -and $roots -notcontains $path) { $roots += $path }
    }
    foreach ($base in @($env:LOCALAPPDATA,$env:APPDATA)) {
        if (-not $base -or -not (Test-Path $base)) { continue }
        try {
            $dirs = @(Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^Proton' })
            foreach ($dir in $dirs) {
                if ($roots -notcontains $dir.FullName) { $roots += $dir.FullName }
            }
        } catch {}
    }
    return @($roots)
}

function Get-UserSettingsFile([object[]]$Roots) {
    $files = @()
    $canonicalStorage = Join-Path $env:LOCALAPPDATA 'Proton\Proton VPN\Storage'
    if ($canonicalStorage -and (Test-Path $canonicalStorage)) {
        try { $files += @(Get-ChildItem -Path $canonicalStorage -Filter 'UserSettings*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 5242880 }) } catch {}
    }
    if ($files.Count -eq 0) {
        foreach ($root in $Roots) {
            try {
                $files += @(Get-ChildItem -Path $root -Filter 'UserSettings*.json' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 5242880 })
            } catch {}
        }
    }
    foreach ($f in @($files | Sort-Object LastWriteTime -Descending -Unique)) {
        try {
            $raw = [IO.File]::ReadAllText($f.FullName)
            $obj = $raw | ConvertFrom-Json -ErrorAction Stop
            $names = @($obj.PSObject.Properties.Name)
            if ($names -contains 'DefaultConnection' -or $names -contains 'IsAutoConnectEnabled') { return $f.FullName }
        } catch {}
    }
    return ''
}

function Get-RecentConnectionsFile([object[]]$Roots) {
    $files = @()
    $canonicalStorage = Join-Path $env:LOCALAPPDATA 'Proton\Proton VPN\Storage'
    if ($canonicalStorage -and (Test-Path $canonicalStorage)) {
        try { $files += @(Get-ChildItem -Path $canonicalStorage -Filter 'RecentConnections*.bin' -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 -and $_.Length -lt 8388608 }) } catch {}
    }
    if ($files.Count -eq 0) {
        foreach ($root in $Roots) {
            try {
                $files += @(Get-ChildItem -Path $root -Filter 'RecentConnections*.bin' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 -and $_.Length -lt 8388608 })
            } catch {}
        }
    }
    $files = @($files | Sort-Object LastWriteTime -Descending -Unique)
    if ($files.Count -gt 0) { return [string]$files[0].FullName }
    return ''
}

function Set-OuterSetting([object]$Object, [string]$Name, [object]$Value) {
    $prop = @($Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1)
    if ($prop.Count -gt 0) { $prop[0].Value = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Set-TemporaryAutoConnectRecent([string]$SettingsFile, [guid]$RecentId) {
    $raw = [IO.File]::ReadAllText($SettingsFile)
    $outer = $raw | ConvertFrom-Json -ErrorAction Stop

    # Proton stores a dictionary<string,string>: values are JSON strings inside the outer JSON file.
    Set-OuterSetting $outer 'IsAutoConnectEnabled' 'true'

    # Proton DefaultConnectionType: Fastest=0, Last=1, Recent=2, Random=3.
    # Point at one exact recent instead of relying on list order or connection timestamps.
    $inner = [pscustomobject]@{
        Type = 2
        RecentId = $RecentId.ToString()
    }
    Set-OuterSetting $outer 'DefaultConnection' ($inner | ConvertTo-Json -Compress)

    $newOuter = $outer | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($SettingsFile, $newOuter, (New-Object Text.UTF8Encoding($false)))
}

function Set-StructuredRecentCountry([string]$ClientPath, [string]$RecentFile, [string]$TargetCode) {
    $clientDirectory = Split-Path -Parent $ClientPath
    $required = @(
        'protobuf-net.Core.dll',
        'protobuf-net.dll',
        'ProtonVPN.Serialization.Contracts.dll',
        'ProtonVPN.Client.Logic.Connection.Contracts.dll',
        'ProtonVPN.Client.Logic.Recents.Contracts.dll',
        'ProtonVPN.Serialization.Protobuf.Entities.dll',
        'ProtonVPN.Serialization.Protobuf.dll'
    )
    foreach ($name in $required) {
        $path = Join-Path $clientDirectory $name
        if (-not (Test-Path $path)) { throw ('Libreria Proton richiesta non trovata: ' + $name) }
        [Reflection.Assembly]::LoadFrom($path) | Out-Null
    }

    $entitiesAssembly = [Reflection.Assembly]::LoadFrom((Join-Path $clientDirectory 'ProtonVPN.Serialization.Protobuf.Entities.dll'))
    $protobufAssembly = [Reflection.Assembly]::LoadFrom((Join-Path $clientDirectory 'ProtonVPN.Serialization.Protobuf.dll'))
    $recentsAssembly = [Reflection.Assembly]::LoadFrom((Join-Path $clientDirectory 'ProtonVPN.Client.Logic.Recents.Contracts.dll'))
    $entitiesType = $entitiesAssembly.GetType('ProtonVPN.Serialization.Protobuf.Entities.ProtobufSerializableEntities', $true)
    $serializerType = $protobufAssembly.GetType('ProtonVPN.Serialization.Protobuf.ProtobufSerializer', $true)
    $recentType = $recentsAssembly.GetType('ProtonVPN.Client.Logic.Recents.Contracts.SerializableEntities.SerializableRecentConnection', $true)
    $entities = [Activator]::CreateInstance($entitiesType)
    $serializer = [Activator]::CreateInstance($serializerType, @($entities))
    $listType = [System.Collections.Generic.List``1].MakeGenericType($recentType)

    $input = [IO.MemoryStream]::new([IO.File]::ReadAllBytes($RecentFile))
    try {
        $deserialize = $serializerType.GetMethod('Deserialize').MakeGenericMethod($listType)
        $recents = $deserialize.Invoke($serializer, @($input))
    } finally {
        $input.Dispose()
    }
    if ($null -eq $recents -or $recents.Count -eq 0) { throw 'Proton non contiene connessioni recenti utilizzabili.' }

    $selected = $null
    foreach ($recent in $recents) {
        $location = $recent.ConnectionIntent.Location
        if ($null -ne $location -and [string]$location.TypeName -eq 'SingleCountryLocationIntent') {
            $selected = $recent
            break
        }
    }
    if ($null -eq $selected) {
        throw 'Proton non contiene un modello recente per la selezione del paese.'
    }
    $selectedId = [guid]$selected.RecentId
    if ($selectedId -eq [guid]::Empty) { throw 'Il modello recente Proton non contiene un identificatore valido.' }

    $sourceCode = [string]$selected.ConnectionIntent.Location.CountryCode
    $selected.ConnectionIntent.Location.CountryCode = $TargetCode
    if ($selected.PSObject.Properties.Name -contains 'LastConnectionTime') {
        $selected.LastConnectionTime = [DateTime]::UtcNow
    }

    $serialize = $serializerType.GetMethod('Serialize').MakeGenericMethod($listType)
    $output = $serialize.Invoke($serializer, [object[]]@(,$recents))
    try {
        [IO.File]::WriteAllBytes($RecentFile, $output.ToArray())
    } finally {
        $output.Dispose()
    }

    return [pscustomobject]@{
        recent_id = $selectedId
        source_code = $sourceCode
        records = [int]$recents.Count
    }
}

function Find-ByteSequenceOffsets([byte[]]$Bytes, [byte[]]$Needle) {
    $hits = @()
    if ($null -eq $Bytes -or $null -eq $Needle -or $Needle.Length -eq 0 -or $Bytes.Length -lt $Needle.Length) { return @() }
    for ($i = 0; $i -le ($Bytes.Length - $Needle.Length); $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) {
            $hits += $i
            $i += ($Needle.Length - 1)
        }
    }
    return @($hits)
}

function Read-ProtoVarintAt([byte[]]$Bytes, [int]$Offset) {
    [uint64]$value = 0
    $shift = 0
    $pos = $Offset
    while ($pos -lt $Bytes.Length -and $shift -lt 64) {
        $b = [int]$Bytes[$pos]
        $value = $value -bor ([uint64]($b -band 0x7F) -shl $shift)
        $pos++
        if (($b -band 0x80) -eq 0) {
            return [pscustomobject]@{ ok = $true; value = $value; next = $pos }
        }
        $shift += 7
    }
    return [pscustomobject]@{ ok = $false; value = [uint64]0; next = $Offset }
}

function Test-ByteSequenceInRange([byte[]]$Bytes, [byte[]]$Needle, [int]$Start, [int]$EndExclusive) {
    if ($null -eq $Bytes -or $null -eq $Needle -or $Needle.Length -eq 0) { return $false }
    if ($Start -lt 0) { $Start = 0 }
    if ($EndExclusive -gt $Bytes.Length) { $EndExclusive = $Bytes.Length }
    if (($EndExclusive - $Start) -lt $Needle.Length) { return $false }
    for ($i = $Start; $i -le ($EndExclusive - $Needle.Length); $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { return $true }
    }
    return $false
}

function Promote-SingleCountryTemplateToFront([string]$RecentFile) {
    [byte[]]$bytes = [IO.File]::ReadAllBytes($RecentFile)
    [byte[]]$needle = [Text.Encoding]::UTF8.GetBytes('SingleCountryLocationIntent')
    $segments = @()
    $pos = 0

    # protobuf-net serializes a root List<T> as repeated field #1 messages. Parse only
    # a fully valid sequence of field-1 length-delimited records; if Proton changes the
    # storage envelope, return a safe no-op rather than corrupting RecentConnections.bin.
    while ($pos -lt $bytes.Length) {
        $segmentStart = $pos
        $keyInfo = Read-ProtoVarintAt $bytes $pos
        if (-not $keyInfo.ok) { return [pscustomobject]@{ ok=$false; records=0; match=-1; moved=$false; reason='invalid-key-varint' } }
        [uint64]$key = $keyInfo.value
        $pos = [int]$keyInfo.next
        $field = [int]($key -shr 3)
        $wire = [int]($key -band 7)
        if ($field -ne 1 -or $wire -ne 2) {
            return [pscustomobject]@{ ok=$false; records=0; match=-1; moved=$false; reason=('unexpected-root-field-' + $field + '-wire-' + $wire) }
        }
        $lenInfo = Read-ProtoVarintAt $bytes $pos
        if (-not $lenInfo.ok) { return [pscustomobject]@{ ok=$false; records=0; match=-1; moved=$false; reason='invalid-length-varint' } }
        [uint64]$payloadLength = $lenInfo.value
        $payloadStart = [int]$lenInfo.next
        if ($payloadLength -gt [uint64]([int]::MaxValue)) { return [pscustomobject]@{ ok=$false; records=0; match=-1; moved=$false; reason='record-too-large' } }
        $payloadEnd = $payloadStart + [int]$payloadLength
        if ($payloadEnd -gt $bytes.Length -or $payloadEnd -lt $payloadStart) {
            return [pscustomobject]@{ ok=$false; records=0; match=-1; moved=$false; reason='record-out-of-range' }
        }
        $segments += [pscustomobject]@{
            start = $segmentStart
            end = $payloadEnd
            contains_country = [bool](Test-ByteSequenceInRange $bytes $needle $payloadStart $payloadEnd)
        }
        $pos = $payloadEnd
    }

    if ($segments.Count -le 1) {
        $matchOne = -1
        if ($segments.Count -eq 1 -and $segments[0].contains_country) { $matchOne = 0 }
        return [pscustomobject]@{ ok=$true; records=$segments.Count; match=$matchOne; moved=$false; reason='single-record' }
    }

    $matchIndex = -1
    for ($i = 0; $i -lt $segments.Count; $i++) {
        if ($segments[$i].contains_country) { $matchIndex = $i; break }
    }
    if ($matchIndex -lt 0) {
        return [pscustomobject]@{ ok=$true; records=$segments.Count; match=-1; moved=$false; reason='no-country-record' }
    }
    if ($matchIndex -eq 0) {
        return [pscustomobject]@{ ok=$true; records=$segments.Count; match=0; moved=$false; reason='already-first' }
    }

    $order = @($matchIndex)
    for ($i = 0; $i -lt $segments.Count; $i++) { if ($i -ne $matchIndex) { $order += $i } }
    $stream = New-Object IO.MemoryStream
    try {
        foreach ($i in $order) {
            $seg = $segments[$i]
            $count = [int]$seg.end - [int]$seg.start
            $stream.Write($bytes, [int]$seg.start, $count)
        }
        [IO.File]::WriteAllBytes($RecentFile, $stream.ToArray())
    } finally {
        $stream.Dispose()
    }
    return [pscustomobject]@{ ok=$true; records=$segments.Count; match=$matchIndex; moved=$true; reason='promoted-country-record' }
}

function Patch-SingleCountryTemplates([string]$RecentFile, [string]$TargetCode) {
    [byte[]]$bytes = [IO.File]::ReadAllBytes($RecentFile)
    [byte[]]$needle = [Text.Encoding]::UTF8.GetBytes('SingleCountryLocationIntent')
    $tokens = @(Find-ByteSequenceOffsets $bytes $needle)
    if ($tokens.Count -eq 0) {
        return [pscustomobject]@{ patched = 0; templates = 0; source_codes = @(); offsets = @() }
    }

    $candidateOffsets = @()
    $sourceCodes = @()
    foreach ($token in $tokens) {
        $from = [Math]::Max(0, $token - 220)
        $to = [Math]::Min($bytes.Length - 3, $token + $needle.Length + 220)
        $bestOffset = -1
        $bestDistance = [int]::MaxValue
        $bestCode = ''
        for ($i = $from; $i -le $to; $i++) {
            # CountryCode is a protobuf length-delimited 2-byte ASCII string. Match the length byte (0x02)
            # plus an ISO-like uppercase pair, then choose the nearest valid code to this intent's TypeName.
            if ($bytes[$i] -ne 2) { continue }
            $a = [int]$bytes[$i + 1]
            $b = [int]$bytes[$i + 2]
            if ($a -lt 65 -or $a -gt 90 -or $b -lt 65 -or $b -gt 90) { continue }
            $code = ([char]$a).ToString() + ([char]$b).ToString()
            if ($script:KnownCountryCodes -notcontains $code) { continue }
            $distance = [Math]::Abs(($i + 1) - $token)
            if ($distance -lt $bestDistance) {
                $bestDistance = $distance
                $bestOffset = $i + 1
                $bestCode = $code
            }
        }
        if ($bestOffset -ge 0 -and $candidateOffsets -notcontains $bestOffset) {
            $candidateOffsets += $bestOffset
            $sourceCodes += $bestCode
        }
    }

    if ($candidateOffsets.Count -eq 0) {
        return [pscustomobject]@{ patched = 0; templates = $tokens.Count; source_codes = @(); offsets = @() }
    }

    [byte[]]$target = [Text.Encoding]::ASCII.GetBytes($TargetCode)
    foreach ($offset in $candidateOffsets) {
        $bytes[$offset] = $target[0]
        $bytes[$offset + 1] = $target[1]
    }
    [IO.File]::WriteAllBytes($RecentFile, $bytes)

    return [pscustomobject]@{
        patched = $candidateOffsets.Count
        templates = $tokens.Count
        source_codes = @($sourceCodes)
        offsets = @($candidateOffsets)
    }
}

function Test-VpnRouteFast {
    try {
        if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) { return $false }
        $rows = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq 'Up' -and (
                ($_.Name -match '(?i)Proton|WireGuard|Wintun|TAP') -or
                ($_.InterfaceDescription -match '(?i)Proton|WireGuard|Wintun|TAP')
            )
        })
        foreach ($row in $rows) {
            try {
                $routes = @(Get-NetRoute -InterfaceIndex $row.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
                    $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1')
                })
                if ($routes.Count -gt 0) { return $true }
            } catch {}
        }
    } catch {}
    return $false
}

function Wait-VpnRoute([bool]$ExpectedConnected, [int]$TimeoutMs = 12000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    do {
        if ($ExpectedConnected) { Hide-ProtonClientWindows }
        $actual = [bool](Test-VpnRouteFast)
        if ($actual -eq $ExpectedConnected) {
            Write-Trace ('vpn-wait:state=' + $actual + ' elapsed_ms=' + $sw.ElapsedMilliseconds)
            return $true
        }
        Start-Sleep -Milliseconds 250
    } while ($sw.ElapsedMilliseconds -lt $TimeoutMs)
    $actual = [bool](Test-VpnRouteFast)
    Write-Trace ('vpn-wait:timeout expected=' + $ExpectedConnected + ' actual=' + $actual + ' elapsed_ms=' + $sw.ElapsedMilliseconds)
    return ($actual -eq $ExpectedConnected)
}

function Get-ClientLogFile {
    $logDir = Join-Path $env:LOCALAPPDATA 'Proton\Proton VPN\Logs'
    if (-not $logDir -or -not (Test-Path $logDir)) { return '' }
    try {
        $files = @(Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '(?i)client.*\.(txt|log)$'
        } | Sort-Object LastWriteTime -Descending)
        if ($files.Count -gt 0) { return [string]$files[0].FullName }
    } catch {}
    return ''
}

function Get-ActiveCountryFromClientLog {
    $path = Get-ClientLogFile
    if (-not $path -or -not (Test-Path $path)) { return '' }
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        $take = [Math]::Min([int64]524288, [int64]$fi.Length)
        if ($take -le 0) { return '' }
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek(-$take, [IO.SeekOrigin]::End)
            $buf = New-Object byte[] $take
            $read = $fs.Read($buf, 0, [int]$take)
        } finally { $fs.Dispose() }
        if ($read -le 0) { return '' }
        $text = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $lines = @($text -split "`r?`n")
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = [string]$lines[$i]
            if ($line -match '(?i)\[CONNECTION_PROCESS\].*Status updated to Disconnected') { return '' }
            if ($line -match '(?i)\[CONNECTION_PROCESS\].*Status updated to Connected.*Connected to server\s+([A-Z]{2})(?=[#\-\s])') {
                return $matches[1].ToUpperInvariant()
            }
        }
    } catch { Write-Trace ('country-log-read-failed:' + $_.Exception.Message) }
    return ''
}



function Get-ClientConnectionStateFromLog {
    $path = Get-ClientLogFile
    if (-not $path -or -not (Test-Path $path)) {
        return [pscustomobject]@{ known = $false; connected = $false; country = '' }
    }
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        $take = [Math]::Min([int64]262144, [int64]$fi.Length)
        if ($take -le 0) { return [pscustomobject]@{ known = $false; connected = $false; country = '' } }
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek(-$take, [IO.SeekOrigin]::End)
            $buf = New-Object byte[] ([int]$take)
            $read = $fs.Read($buf, 0, [int]$take)
        } finally { $fs.Dispose() }
        if ($read -le 0) { return [pscustomobject]@{ known = $false; connected = $false; country = '' } }
        $text = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $lines = @($text -split "`r?`n")
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = [string]$lines[$i]
            if ($line -match '(?i)\[CONNECTION_PROCESS\].*Status updated to Disconnected') {
                return [pscustomobject]@{ known = $true; connected = $false; country = '' }
            }
            if ($line -match '(?i)\[CONNECTION_PROCESS\].*Status updated to Connected') {
                $country = ''
                if ($line -match '(?i)Connected to server\s+([A-Z]{2})(?=[#\-\s])') { $country = $matches[1].ToUpperInvariant() }
                return [pscustomobject]@{ known = $true; connected = $true; country = $country }
            }
        }
    } catch { Write-Trace ('status-log-read-failed:' + $_.Exception.Message) }
    return [pscustomobject]@{ known = $false; connected = $false; country = '' }
}

function Get-ClientLogMarker {
    $path = Get-ClientLogFile
    if (-not $path -or -not (Test-Path $path)) {
        return [pscustomobject]@{ path = ''; length = [int64]0 }
    }
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        return [pscustomobject]@{ path = [string]$fi.FullName; length = [int64]$fi.Length }
    } catch {
        return [pscustomobject]@{ path = [string]$path; length = [int64]0 }
    }
}

function Get-NewConnectedCountryFromClientLog([object]$Marker) {
    $path = Get-ClientLogFile
    if (-not $path -or -not (Test-Path $path)) { return '' }
    try {
        $fi = Get-Item -LiteralPath $path -ErrorAction Stop
        $start = [int64]0
        if ($null -ne $Marker -and [string]$Marker.path -and ([string]$Marker.path -ieq [string]$fi.FullName) -and [int64]$Marker.length -le [int64]$fi.Length) {
            $start = [int64]$Marker.length
        } else {
            $start = [Math]::Max([int64]0, [int64]$fi.Length - [int64]131072)
        }
        $available = [int64]$fi.Length - $start
        if ($available -le 0) { return '' }
        if ($available -gt 262144) { $start = [int64]$fi.Length - [int64]262144; $available = [int64]262144 }
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ([int]$available)
            $read = $fs.Read($buf, 0, [int]$available)
        } finally { $fs.Dispose() }
        if ($read -le 0) { return '' }
        $text = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $lines = @($text -split "`r?`n")
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = [string]$lines[$i]
            if ($line -match '(?i)\[CONNECTION_PROCESS\].*Status updated to Connected.*Connected to server\s+([A-Z]{2})(?=[#\-\s])') {
                return $matches[1].ToUpperInvariant()
            }
        }
    } catch { Write-Trace ('fresh-country-log-read-failed:' + $_.Exception.Message) }
    return ''
}

function Wait-VpnConnectedFast([string]$ExpectedCountry, [object]$LogMarker, [int]$TimeoutMs = 25000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $nextRouteCheck = [int64]1200
    do {
        Hide-ProtonClientWindows
        $freshCountry = Get-NewConnectedCountryFromClientLog $LogMarker
        if ($freshCountry) {
            Write-Trace ('vpn-fast:source=client-log country=' + $freshCountry + ' elapsed_ms=' + $sw.ElapsedMilliseconds)
            return [pscustomobject]@{ ok = $true; country = $freshCountry; source = 'client-log'; elapsed_ms = [int64]$sw.ElapsedMilliseconds }
        }
        if ($sw.ElapsedMilliseconds -ge $nextRouteCheck) {
            if (Test-VpnRouteFast) {
                Write-Trace ('vpn-fast:route-up-awaiting-client-confirmation elapsed_ms=' + $sw.ElapsedMilliseconds)
            }
            $nextRouteCheck = $sw.ElapsedMilliseconds + 500
        }
        Start-Sleep -Milliseconds 100
    } while ($sw.ElapsedMilliseconds -lt $TimeoutMs)

    # One last check prevents a false timeout on the exact polling boundary.
    $freshCountry = Get-NewConnectedCountryFromClientLog $LogMarker
    if ($freshCountry) {
        Write-Trace ('vpn-fast:source=client-log-final country=' + $freshCountry + ' elapsed_ms=' + $sw.ElapsedMilliseconds)
        return [pscustomobject]@{ ok = $true; country = $freshCountry; source = 'client-log-final'; elapsed_ms = [int64]$sw.ElapsedMilliseconds }
    }
    $routeUp = [bool](Test-VpnRouteFast)
    Write-Trace ('vpn-fast:timeout expected=' + $ExpectedCountry + ' route_up=' + $routeUp + ' elapsed_ms=' + $sw.ElapsedMilliseconds)
    return [pscustomobject]@{ ok = $false; country = ''; source = $(if ($routeUp) { 'route-unconfirmed' } else { 'timeout' }); elapsed_ms = [int64]$sw.ElapsedMilliseconds }
}

function Stop-ProtonClient {
    try {
        $rows = @(Get-CimInstance Win32_Process -Filter "Name='ProtonVPN.Client.exe'" -ErrorAction SilentlyContinue)
        foreach ($row in $rows) {
            try { Stop-Process -Id $row.ProcessId -Force -ErrorAction Stop } catch {}
        }
        if ($rows.Count -gt 0) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            do {
                $still = @(Get-Process -Name 'ProtonVPN.Client' -ErrorAction SilentlyContinue)
                if ($still.Count -eq 0) { break }
                Start-Sleep -Milliseconds 100
            } while ($sw.ElapsedMilliseconds -lt 900)
        }
    } catch {}
}

function Hide-ProtonClientWindows {
    try {
        if (-not ('DeckyProtonNativeWindow' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DeckyProtonNativeWindow {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        }
        $rows = @(Get-Process -Name 'ProtonVPN.Client' -ErrorAction SilentlyContinue)
        foreach ($row in $rows) {
            try {
                $row.Refresh()
                if ($row.MainWindowHandle -ne [IntPtr]::Zero) {
                    [DeckyProtonNativeWindow]::ShowWindow($row.MainWindowHandle, 0) | Out-Null
                }
            } catch {}
        }
    } catch {}
}

function Start-ProtonClient([string]$ClientPath, [bool]$Background = $true) {
    if (-not $ClientPath -or -not (Test-Path $ClientPath)) { throw 'ProtonVPN.Client.exe non trovato.' }
    $existing = @(Get-Process -Name 'ProtonVPN.Client' -ErrorAction SilentlyContinue)
    if ($existing.Count -eq 0) {
        $launcherPath = Get-LauncherPath $ClientPath
        $startPath = if ($launcherPath) { $launcherPath } else { $ClientPath }
        $workingDirectory = Split-Path -Parent $startPath
        $windowStyle = if ($Background) { 'Hidden' } else { 'Normal' }
        Start-Process -FilePath $startPath -WorkingDirectory $workingDirectory -WindowStyle $windowStyle | Out-Null
        Write-Trace ('client-start:detached-hidden=' + $Background + ' path=' + $startPath + ' official-launcher=' + [bool]$launcherPath)
    } else {
        Write-Trace ('client-start:already-running count=' + $existing.Count)
    }
    if ($Background) {
        for ($i = 0; $i -lt 2; $i++) {
            Start-Sleep -Milliseconds 120
            Hide-ProtonClientWindows
        }
    }
}

function Get-Diagnostics {
    param([bool]$Deep = $true)

    $processes = @(Get-ProtonProcesses)
    $services = @(Get-ProtonServices)
    $adapters = @(Get-ProtonAdapters)
    $pipes = @(Get-GrpcPipeInfo)
    $roots = @()
    $settingsFile = ''
    $recentFile = ''
    $clientPath = Get-ClientPath $processes

    if ($Deep) {
        $roots = @(Get-ProtonDataRoots)
        $settingsFile = Get-UserSettingsFile $roots
        $recentFile = Get-RecentConnectionsFile $roots
        if (-not $clientPath) { $clientPath = Get-ClientPath $processes }
    }

    Write-Trace ('processes:' + ($(if ($processes.Count) { ($processes | ForEach-Object { $_.name + ':' + $_.process_id }) -join ',' } else { 'none' })))
    Write-Trace ('services:' + ($(if ($services.Count) { ($services | ForEach-Object { $_.name + ':' + $_.state }) -join ',' } else { 'none' })))
    Write-Trace ('adapters:' + ($(if ($adapters.Count) { ($adapters | ForEach-Object { $_.name + ':' + $_.status + ':route=' + $_.has_vpn_route }) -join ',' } else { 'none' })))
    Write-Trace ('grpc-pipes:' + ($(if ($pipes.Count) { ($pipes | ForEach-Object { $_.pipe_name }) -join ',' } else { 'none' })))
    if ($Deep) {
        Write-Trace ('settings-file:' + ($(if ($settingsFile) { $settingsFile } else { 'none' })))
        Write-Trace ('recents-file:' + ($(if ($recentFile) { $recentFile } else { 'none' })))
        Write-Trace ('client-path:' + ($(if ($clientPath) { $clientPath } else { 'none' })))
    }

    return [pscustomobject]@{
        revision = $script:Revision
        processes = $processes
        services = $services
        adapters = $adapters
        grpc = $pipes
        data_roots = $roots
        settings_file = $settingsFile
        recents_file = $recentFile
        client_path = $clientPath
    }
}

function Get-ConnectionState([object]$Diagnostics) {
    $active = @($Diagnostics.adapters | Where-Object { $_.status -eq 'Up' -and $_.has_vpn_route })
    if ($active.Count -gt 0) { return [pscustomobject]@{ connected = $true; state = 'connected'; source = 'vpn-route' } }
    $runningServices = @($Diagnostics.services | Where-Object { $_.state -eq 'Running' })
    if ($Diagnostics.processes.Count -gt 0 -or $runningServices.Count -gt 0) {
        return [pscustomobject]@{ connected = $false; state = 'disconnected'; source = 'process-service' }
    }
    return [pscustomobject]@{ connected = $false; state = 'not_running'; source = 'process-service' }
}

function Restore-ConnectionFiles([string]$SettingsFile, [string]$SettingsBackup, [string]$RecentFile, [string]$RecentBackup, [string]$ClientPath, [bool]$RestartClient = $false) {
    if ($SettingsBackup -and (Test-Path $SettingsBackup)) {
        Copy-Item -LiteralPath $SettingsBackup -Destination $SettingsFile -Force
        Remove-Item -LiteralPath $SettingsBackup -Force -ErrorAction SilentlyContinue
    }
    if ($RecentBackup -and (Test-Path $RecentBackup)) {
        Copy-Item -LiteralPath $RecentBackup -Destination $RecentFile -Force
        Remove-Item -LiteralPath $RecentBackup -Force -ErrorAction SilentlyContinue
    }
    if ($RestartClient -and $ClientPath) {
        try {
            Stop-ProtonClient
            Start-ProtonClient $ClientPath $true
        } catch { Write-Trace ('restore-client-start-failed:' + $_.Exception.Message) }
    }
}

function Recover-StaleR11Backups([object]$Diag) {
    if (-not $Diag.settings_file) { return }
    $settingsBackup = $Diag.settings_file + '.decky-r11.bak'
    $recentBackup = ''
    if ($Diag.recents_file) { $recentBackup = $Diag.recents_file + '.decky-r11.bak' }
    $hasSettings = Test-Path $settingsBackup
    $hasRecent = ($recentBackup -and (Test-Path $recentBackup))
    if (-not $hasSettings -and -not $hasRecent) { return }

    Write-Trace 'stale-r11-backup-recovery'
    try {
        Stop-ProtonClient
        if ($hasSettings) {
            Copy-Item -LiteralPath $settingsBackup -Destination $Diag.settings_file -Force
            Remove-Item -LiteralPath $settingsBackup -Force -ErrorAction SilentlyContinue
        }
        if ($hasRecent) {
            Copy-Item -LiteralPath $recentBackup -Destination $Diag.recents_file -Force
            Remove-Item -LiteralPath $recentBackup -Force -ErrorAction SilentlyContinue
        }
        if ($Diag.client_path) { Start-ProtonClient $Diag.client_path $true }
    } catch { Write-Trace ('stale-r11-recovery-failed:' + $_.Exception.Message) }
}

try {
    $CountryCode = ([string]$CountryCode).Trim().ToUpperInvariant()
    if ($CountryCode -notmatch '^[A-Z]{2}$') { $CountryCode = 'IT' }
    Write-Trace ('start action=' + $Action + ' country=' + $CountryCode)

    if ($Action -eq 'status') {
        # Match the state Proton itself is already showing first. Windows route
        # enumeration can lag behind the client by several seconds on this machine.
        $logState = Get-ClientConnectionStateFromLog
        if ($logState.known) {
            $fastConnected = [bool]$logState.connected
            $activeCountry = [string]$logState.country
            Write-Trace ('status-fast-log connected=' + $fastConnected + ' country=' + ($(if ($activeCountry) { $activeCountry } else { 'unknown' })))
            $message = if ($fastConnected -and $activeCountry) { 'Proton VPN risulta connessa a ' + $activeCountry + '.' } elseif ($fastConnected) { 'Proton VPN risulta connessa.' } else { 'Proton VPN risulta disconnessa.' }
            Write-Result -Ok $true -Message $message -Connected $fastConnected -Stage 'status-fast-client-log' -Country $activeCountry
            exit 0
        }

        $fastConnected = [bool](Test-VpnRouteFast)
        $activeCountry = if ($fastConnected) { Get-ActiveCountryFromClientLog } else { '' }
        Write-Trace ('status-fallback-route connected=' + $fastConnected + ' country=' + ($(if ($activeCountry) { $activeCountry } else { 'unknown' })))
        $message = if ($fastConnected -and $activeCountry) { 'Proton VPN risulta connessa a ' + $activeCountry + '.' } elseif ($fastConnected) { 'Proton VPN risulta connessa.' } else { 'Proton VPN risulta disconnessa.' }
        Write-Result -Ok $true -Message $message -Connected $fastConnected -Stage 'status-fallback-route' -Country $activeCountry
        exit 0
    }

    $diag = Get-Diagnostics -Deep ($Action -eq 'connect')
    if ($Action -eq 'connect') {
        $hadStaleBackup = $false
        if ($diag.settings_file -and (Test-Path ($diag.settings_file + '.decky-r11.bak'))) { $hadStaleBackup = $true }
        if ($diag.recents_file -and (Test-Path ($diag.recents_file + '.decky-r11.bak'))) { $hadStaleBackup = $true }
        Recover-StaleR11Backups $diag
        if ($hadStaleBackup) {
            Write-Trace 'connect:refresh-diagnostics-after-stale-recovery'
            $diag = Get-Diagnostics -Deep $true
        }
    }
    $state = Get-ConnectionState $diag
    $clientWasRunning = (@($diag.processes | Where-Object { $_.name -ieq 'ProtonVPN.Client.exe' }).Count -gt 0)
    Write-Trace ('client-was-running:' + $clientWasRunning)

    if ($Action -eq 'disconnect') {
        if (-not $state.connected) {
            Write-Result -Ok $true -Message 'Proton VPN risulta gia disconnessa.' -Connected $false -Stage 'already-disconnected' -Diagnostics $diag
            exit 0
        }

        # ProtonVPN Service owns the connection state and recreates WireGuard when only
        # the worker is stopped. Use the proven deterministic reset directly instead of
        # wasting several seconds on a worker-only stop that gets undone.
        $svc = @($diag.services | Where-Object {
            $_.state -eq 'Running' -and
            (($_.display_name -ieq 'ProtonVPN Service') -or ($_.name -ieq 'ProtonVPN Service') -or ($_.name -ieq 'ProtonVPNService'))
        } | Select-Object -First 1)
        if ($svc.Count -eq 0) {
            $svc = @($diag.services | Where-Object { $_.state -eq 'Running' -and $_.name -notmatch '(?i)WireGuard|Nrpt' } | Select-Object -First 1)
        }
        if ($svc.Count -eq 0) {
            Write-Result -Ok $false -Message 'Servizio Proton VPN non trovato: disconnessione non eseguita.' -Connected $true -Stage 'disconnect-no-service' -Diagnostics $diag -Code 'SERVICE_NOT_FOUND'
            exit 0
        }

        Write-Trace ('disconnect:restart-main-service ' + $svc[0].name)
        try { Restart-Service -Name $svc[0].name -Force -ErrorAction Stop } catch {
            Write-Result -Ok $false -Message ('Impossibile disconnettere Proton VPN: ' + $_.Exception.Message) -Connected $true -Stage 'disconnect-service-restart-failed' -Diagnostics $diag -Code 'SERVICE_RESTART_FAILED'
            exit 0
        }

        $down = Wait-VpnRoute $false 4500
        $after = Get-Diagnostics -Deep $false
        $afterState = Get-ConnectionState $after
        if ($down -and -not $afterState.connected) {
            Write-Result -Ok $true -Message 'Proton VPN disconnessa.' -Connected $false -Stage 'disconnect-service-reset' -Diagnostics $after
        } else {
            $actualCountry = if ($afterState.connected) { Get-ActiveCountryFromClientLog } else { '' }
            Write-Result -Ok $false -Message 'Proton VPN risulta ancora connessa dopo il tentativo di disconnessione.' -Connected $afterState.connected -Stage 'disconnect-still-connected' -Country $actualCountry -Diagnostics $after -Code 'STILL_CONNECTED'
        }
        exit 0
    }

    # A connect request is also a country-selection request. If the currently
    # verified country already matches the target, do nothing at all.
    if ($state.connected) {
        $activeBefore = Get-ActiveCountryFromClientLog
        Write-Trace ('country-switch:active-before=' + ($(if ($activeBefore) { $activeBefore } else { 'unknown' })) + ' target=' + $CountryCode)
        if ($activeBefore -and $activeBefore -eq $CountryCode) {
            Write-Trace ('country-switch:already-on-target target=' + $CountryCode)
            Write-Result -Ok $true -Message ('Proton VPN e gia connessa a ' + $CountryCode + '.') -Connected $true -Stage 'already-connected-same-country' -Country $activeBefore -Diagnostics $diag
            exit 0
        }

        Write-Trace ('country-switch:stable-reset target=' + $CountryCode)
        $switchClientPath = $diag.client_path
        try {
            # The current non-UI technique needs the Proton client to reload its
            # RecentConnections/UserSettings at startup. Stop it only for a genuine
            # country change, never for status refreshes or same-country selections.
            Stop-ProtonClient

            # R15 first stopped only ProtonVPN WireGuard, but ProtonVPN Service recreated
            # the worker and the route stayed up. Go straight to the deterministic reset
            # instead of spending ~4 seconds on a failed fast path.
            $mainSvc = @($diag.services | Where-Object {
                $_.state -eq 'Running' -and
                (($_.display_name -ieq 'ProtonVPN Service') -or ($_.name -ieq 'ProtonVPN Service') -or ($_.name -ieq 'ProtonVPNService'))
            } | Select-Object -First 1)
            if ($mainSvc.Count -eq 0) {
                $mainSvc = @($diag.services | Where-Object {
                    $_.state -eq 'Running' -and $_.name -notmatch '(?i)WireGuard|Nrpt'
                } | Select-Object -First 1)
            }
            if ($mainSvc.Count -eq 0) { throw 'Servizio principale Proton VPN non trovato per il cambio paese.' }

            Write-Trace ('country-switch:restart-main-service ' + $mainSvc[0].name)
            Restart-Service -Name $mainSvc[0].name -Force -ErrorAction Stop
            if (-not (Wait-VpnRoute $false 4500)) {
                throw 'Il tunnel Proton precedente e ancora attivo dopo il reset.'
            }

            Write-Trace ('country-switch:tunnel-down target=' + $CountryCode)
            $switchDiag = Get-Diagnostics -Deep $true
            if (-not $switchDiag.client_path -and $switchClientPath) { $switchDiag.client_path = $switchClientPath }
            $diag = $switchDiag
            $state = Get-ConnectionState $diag
        } catch {
            $switchReason = $_.Exception.Message
            Write-Trace ('country-switch:failed ' + $switchReason)
            if ($switchClientPath) {
                try { Start-ProtonClient $switchClientPath $true } catch { Write-Trace ('country-switch:client-restore-failed ' + $_.Exception.Message) }
            }
            $switchFailDiag = Get-Diagnostics -Deep $false
            $switchFailState = Get-ConnectionState $switchFailDiag
            $actualAfterFailure = if ($switchFailState.connected) { Get-ActiveCountryFromClientLog } else { '' }
            Write-Result -Ok $false -Message ('Cambio paese non riuscito: ' + $switchReason) -Connected $switchFailState.connected -Stage 'country-switch-reset-failed' -Country $actualAfterFailure -Diagnostics $switchFailDiag -Code 'COUNTRY_SWITCH_RESET_FAILED'
            exit 0
        }
    }

    if (-not $diag.client_path) {
        Write-Result -Ok $false -Message 'ProtonVPN.Client.exe non trovato.' -Connected $false -Stage 'connect-client-not-found' -Country $CountryCode -Diagnostics $diag -Code 'CLIENT_NOT_FOUND'
        exit 0
    }
    if (-not $diag.settings_file) {
        Write-Result -Ok $false -Message 'UserSettings di Proton VPN non trovato.' -Connected $false -Stage 'connect-settings-not-found' -Country $CountryCode -Diagnostics $diag -Code 'SETTINGS_NOT_FOUND'
        exit 0
    }
    if (-not $diag.recents_file) {
        Write-Result -Ok $false -Message 'RecentConnections.bin di Proton VPN non trovato.' -Connected $false -Stage 'connect-recents-not-found' -Country $CountryCode -Diagnostics $diag -Code 'RECENTS_NOT_FOUND'
        exit 0
    }

    $settingsBackup = $diag.settings_file + '.decky-r11.bak'
    $recentBackup = $diag.recents_file + '.decky-r11.bak'
    $restored = $false

    try {
        # Let Proton flush its in-memory recents first, then snapshot exactly what is on disk.
        Stop-ProtonClient
        Copy-Item -LiteralPath $diag.settings_file -Destination $settingsBackup -Force
        Copy-Item -LiteralPath $diag.recents_file -Destination $recentBackup -Force

        $recent = Set-StructuredRecentCountry $diag.client_path $diag.recents_file $CountryCode
        Write-Trace ('recent-structured:records=' + $recent.records + ' id=' + $recent.recent_id + ' source=' + $recent.source_code + ' target=' + $CountryCode)
        Set-TemporaryAutoConnectRecent $diag.settings_file $recent.recent_id
        Write-Trace ('temporary-default:Recent id=' + $recent.recent_id + ' target=' + $CountryCode)
        $connectLogMarker = Get-ClientLogMarker
        Write-Trace ('connect-log-marker:path=' + ($(if ($connectLogMarker.path) { $connectLogMarker.path } else { 'none' })) + ' length=' + $connectLogMarker.length)
        Start-ProtonClient $diag.client_path $true

        # Proton writes its own Connected event before Windows route enumeration can
        # become visible to our helper. Trust that fresh post-command event first, and
        # keep the route check as fallback/verification instead of making it the gate.
        $fastConnect = Wait-VpnConnectedFast $CountryCode $connectLogMarker 25000
        if (-not $fastConnect.ok) {
            throw 'Proton non ha confermato la connessione entro il tempo previsto.'
        }
        if ($fastConnect.country -and $fastConnect.country -ne $CountryCode) {
            throw ('Proton ha confermato la connessione a ' + $fastConnect.country + ' invece del paese richiesto ' + $CountryCode + '.')
        }

        Write-Trace ('connected-before-restore:true source=' + $fastConnect.source + ' elapsed_ms=' + $fastConnect.elapsed_ms)
        # Restore only the user's normal Proton settings. Keep RecentConnections.bin as the
        # actual recent connection Proton just used; restoring that file while the client is
        # alive caused R15 races on subsequent country changes.
        if ($settingsBackup -and (Test-Path $settingsBackup)) {
            Copy-Item -LiteralPath $settingsBackup -Destination $diag.settings_file -Force
            Remove-Item -LiteralPath $settingsBackup -Force -ErrorAction SilentlyContinue
        }
        if ($recentBackup -and (Test-Path $recentBackup)) {
            Remove-Item -LiteralPath $recentBackup -Force -ErrorAction SilentlyContinue
        }
        $restored = $true

        # Return as soon as Proton itself has confirmed Connected. Do not add a full
        # CIM/service/route diagnostic pass after success: that was a large part of the
        # visible delay even though the Proton app was already connected.
        $actualCountry = if ($fastConnect.country) { [string]$fastConnect.country } else { '' }
        if (-not $actualCountry) {
            $verifySw = [Diagnostics.Stopwatch]::StartNew()
            do {
                $actualCountry = Get-ActiveCountryFromClientLog
                if ($actualCountry) { break }
                Start-Sleep -Milliseconds 100
            } while ($verifySw.ElapsedMilliseconds -lt 500)
        }
        Write-Trace ('connect-active-country:' + ($(if ($actualCountry) { $actualCountry } else { 'unknown' })) + ' target=' + $CountryCode)
        if ($actualCountry -and $actualCountry -ne $CountryCode) {
            throw ('Proton ha stabilito il tunnel su ' + $actualCountry + ' invece del paese richiesto ' + $CountryCode + '.')
        }
        $reportedCountry = if ($actualCountry) { $actualCountry } else { $CountryCode }
        Write-Result -Ok $true -Message ('Proton VPN connessa a ' + $reportedCountry + '.') -Connected $true -Stage ('connect-fast-' + $fastConnect.source) -Country $reportedCountry
        exit 0
    } catch {
        $reason = $_.Exception.Message
        Write-Trace ('connect-attempt-failed:' + $reason)
        if (-not $restored) {
            try { Restore-ConnectionFiles $diag.settings_file $settingsBackup $diag.recents_file $recentBackup $diag.client_path $true } catch { Write-Trace ('restore-after-failure:' + $_.Exception.Message) }
            $restored = $true
        }
        $failDiag = Get-Diagnostics -Deep $false
        $failState = Get-ConnectionState $failDiag
        Write-Result -Ok $false -Message ('Connessione non riuscita: ' + $reason) -Connected $failState.connected -Stage 'connect-recents-template-failed' -Country $CountryCode -Diagnostics $failDiag -Code 'RECENTS_TEMPLATE_FAILED'
        exit 0
    } finally {
        if (-not $restored) {
            try { Restore-ConnectionFiles $diag.settings_file $settingsBackup $diag.recents_file $recentBackup $diag.client_path $true } catch {}
        }
    }
}
catch {
    Write-Trace ('fatal:' + $_.Exception.Message)
    Write-Result -Ok $false -Message $_.Exception.Message -Connected $false -Stage 'fatal' -Code 'HELPER_FATAL'
    exit 0
}
