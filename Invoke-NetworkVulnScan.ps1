<#!
.SYNOPSIS
    Scanner de vulnérabilités réseau basé sur Nmap, piloté depuis PowerShell.

.DESCRIPTION
    - Découvre les hôtes actifs sur un segment réseau via Nmap (-sn)
    - Exécute des scans de services et vulnérabilités (scripts NSE: vuln, vulners)
    - Agrège les résultats en JSON/CSV et génère un rapport HTML optionnel
    - Exécution parallèle par hôte pour de bonnes performances

.PREREQUIS
    - Nmap installé et accessible dans le PATH (https://nmap.org)
      Sous Debian/Ubuntu: sudo apt-get install -y nmap
      Sous RHEL/CentOS/Fedora: sudo dnf install -y nmap
      Sous Windows: installer Nmap, puis ajouter nmap.exe au PATH

    - PowerShell 7+ recommandé (compatibilité Windows PowerShell 5.1 assurée
      avec Start-Job, mais la parallélisation est plus efficace en PS7).

.EXEMPLES
    # Scanner un réseau donné (CIDR)
    pwsh ./Invoke-NetworkVulnScan.ps1 -Target 192.168.1.0/24

    # Scanner en "rapide" (moins de ports, timing plus agressif) et sans HTML
    pwsh ./Invoke-NetworkVulnScan.ps1 -Target 10.0.0.0/24 -Quick -NoHTML

    # Forcer 20 scans en parallèle et sortie vers un dossier custom
    pwsh ./Invoke-NetworkVulnScan.ps1 -Target 172.16.1.0/24 -MaxParallel 20 -OutputDir ./out

.NOTES
    - Les scripts NSE 'vulners' et 'vuln' s'exécutent localement. 'vulners'
      peut nécessiter l'accès Internet pour une meilleure couverture CPE->CVE.
    - Ce script n'offre pas une garantie d'exhaustivité. Utilisez-le comme point
      de départ et complétez par des outils dédiés (OpenVAS, Nessus, etc.).
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, HelpMessage = "CIDR/Plage à scanner ex: 192.168.1.0/24 ou 10.0.0.1-254")]
    [string]$Target,

    [Parameter(HelpMessage = "Mode rapide: ports limités, timing agressif")]
    [switch]$Quick,

    [Parameter(HelpMessage = "Nombre de ports les plus courants à scanner en mode Quick")]
    [ValidateRange(10,65535)]
    [int]$TopPorts = 1000,

    [Parameter(HelpMessage = "Nombre maximum d'hôtes scannés en parallèle")]
    [ValidateRange(1,128)]
    [int]$MaxParallel = 10,

    [Parameter(HelpMessage = "Répertoire de sortie (sera suffixé d'un horodatage)")]
    [string]$OutputDir = "./scan-output",

    [Parameter(HelpMessage = "Sauter la découverte (considérer la cible comme la liste d'hôtes)")]
    [switch]$SkipDiscovery,

    [Parameter(HelpMessage = "Chemin vers l'exécutable Nmap")]
    [string]$NmapPath = "nmap",

    [Parameter(HelpMessage = "Ne pas générer de rapport HTML")]
    [switch]$NoHTML,

    [Parameter(HelpMessage = "Générer uniquement JSON (pas de CSV)")]
    [switch]$JSONOnly
)

begin {
    function Write-Info {
        param([string]$Message)
        Write-Host "[+] $Message" -ForegroundColor Cyan
    }
    function Write-Warn {
        param([string]$Message)
        Write-Warning $Message
    }
    function Write-Err {
        param([string]$Message)
        Write-Error $Message
    }

    function Test-CommandAvailable {
        param([Parameter(Mandatory)][string]$Name)
        $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
        return [bool]$cmd
    }

    function Get-LocalCidrsLinux {
        try {
            $lines = (& ip -o -f inet addr show 2>$null)
            if (-not $lines) { return @() }
            $cidrs = @()
            foreach ($l in $lines) {
                # format: 2: eth0    inet 192.168.1.10/24 brd 192.168.1.255 scope global ...
                $parts = $l -split '\s+'
                if ($parts.Length -ge 4 -and $parts[2] -eq 'inet') {
                    $cidr = $parts[3]
                    if ($cidr -and -not ($cidr.StartsWith('127.'))) {
                        $cidrs += $cidr
                    }
                }
            }
            return $cidrs | Sort-Object -Unique
        } catch {
            return @()
        }
    }

    function Get-LocalCidrsWindows {
        try {
            $cidrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixLength -ge 8 -and $_.PrefixLength -le 30 } |
                ForEach-Object { "{0}/{1}" -f $_.IPAddress, $_.PrefixLength }
            return $cidrs | Sort-Object -Unique
        } catch {
            return @()
        }
    }

    function Resolve-TargetCidrs {
        param([string]$Target)
        if ([string]::IsNullOrWhiteSpace($Target)) {
            Write-Info "Aucune cible fournie. Tentative de détection automatique des CIDR locaux..."
            if ($IsWindows) {
                $cidrs = Get-LocalCidrsWindows
            } else {
                $cidrs = Get-LocalCidrsLinux
            }
            if (-not $cidrs -or $cidrs.Count -eq 0) {
                Write-Err "Impossible de déterminer automatiquement le réseau local. Spécifiez -Target."
                throw "TargetRequired"
            }
            return $cidrs
        }
        return @($Target)
    }

    function Ensure-OutputPaths {
        param([string]$BaseOut)
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $root = Join-Path -Path $BaseOut -ChildPath $timestamp
        $null = New-Item -ItemType Directory -Path $root -Force
        $discovery = Join-Path -Path $root -ChildPath 'discovery'
        $vuln = Join-Path -Path $root -ChildPath 'vuln'
        $reports = Join-Path -Path $root -ChildPath 'reports'
        $null = New-Item -ItemType Directory -Path $discovery -Force
        $null = New-Item -ItemType Directory -Path $vuln -Force
        $null = New-Item -ItemType Directory -Path $reports -Force
        return [pscustomobject]@{
            Root = $root
            Discovery = $discovery
            Vuln = $vuln
            Reports = $reports
        }
    }

    function Invoke-Nmap {
        param(
            [Parameter(Mandatory)][string[]]$Arguments,
            [Parameter(Mandatory)][string]$XmlOutputPath
        )
        $argsList = @()
        $argsList += $Arguments
        $argsList += @('-oX', $XmlOutputPath)
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $NmapPath
        $startInfo.ArgumentList.AddRange($argsList)
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.UseShellExecute = $false

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $startInfo

        Write-Info ("Exécution: {0} {1}" -f $NmapPath, ($argsList -join ' '))
        $null = $proc.Start()
        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($proc.ExitCode -ne 0 -and -not (Test-Path $XmlOutputPath)) {
            Write-Warn "Nmap a retourné le code $($proc.ExitCode). STDERR: $stdErr"
        }
        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut = $stdOut
            StdErr = $stdErr
            Xml = $XmlOutputPath
        }
    }

    function Invoke-Discovery {
        param([string]$Target, [string]$OutDir)
        $xmlPath = Join-Path -Path $OutDir -ChildPath ("discovery_{0}.xml" -f ($Target -replace '[^a-zA-Z0-9_-]', '_'))
        $args = @('-sn', '-PE', '-T4', $Target)
        $res = Invoke-Nmap -Arguments $args -XmlOutputPath $xmlPath
        if (-not (Test-Path $xmlPath)) {
            Write-Err "Échec découverte Nmap pour $Target"
            return @()
        }
        $doc = [xml](Get-Content -Path $xmlPath -Raw)
        $hosts = @()
        foreach ($h in $doc.nmaprun.host) {
            if ($h.status.state -eq 'up') {
                $addr = ($h.address | Where-Object { $_.addrtype -eq 'ipv4' }).addr
                if ($addr) { $hosts += $addr }
            }
        }
        return $hosts | Sort-Object -Unique
    }

    function Invoke-VulnScanHost {
        param(
            [string]$Host,
            [string]$OutDir,
            [switch]$Quick,
            [int]$TopPorts
        )
        $xmlPath = Join-Path -Path $OutDir -ChildPath ("vuln_{0}.xml" -f ($Host -replace '[^a-zA-Z0-9_-]', '_'))
        $args = @()
        if ($Quick) {
            $args += @('-sV', '-Pn', ("--top-ports {0}" -f $TopPorts), '--script', 'vuln,vulners', '-T4', $Host)
        } else {
            $args += @('-sV', '-Pn', '-p', '1-65535', '--script', 'vuln,vulners', '-T3', $Host)
        }
        $args += @('--script-args', 'mincvss=5.0')
        $res = Invoke-Nmap -Arguments $args -XmlOutputPath $xmlPath
        return $xmlPath
    }

    function Parse-NmapVulnXml {
        param([string]$XmlFile)
        if (-not (Test-Path $XmlFile)) { return @() }
        $doc = [xml](Get-Content -Path $XmlFile -Raw)
        $rows = @()
        $hostNode = $doc.nmaprun.host
        if (-not $hostNode) { return @() }
        $hostAddr = ($hostNode.address | Where-Object { $_.addrtype -eq 'ipv4' }).addr
        $hostname = $hostNode.hostnames.hostname.name
        foreach ($port in $hostNode.ports.port) {
            $portId = $port.portid
            $proto = $port.protocol
            $service = $port.service.name
            foreach ($script in $port.script) {
                $scriptId = $script.id
                $scriptOut = $script.output

                # Essayer d'extraire CVE + score si présent (vulners)
                $cves = @()
                if ($scriptOut) {
                    foreach ($line in ($scriptOut -split "`n")) {
                        $m = [regex]::Match($line, 'CVE-\d{4}-\d{4,7}.*?(score\s*[:=]\s*(?<score>\d+(?:\.\d+)?))?', 'IgnoreCase')
                        if ($m.Success) {
                            $score = $null
                            if ($m.Groups['score'] -and $m.Groups['score'].Value) {
                                $score = [double]$m.Groups['score'].Value
                            }
                            $cveId = [regex]::Match($line, 'CVE-\d{4}-\d{4,7}', 'IgnoreCase').Value
                            if ($cveId) {
                                $cves += [pscustomobject]@{ Id = $cveId; Score = $score }
                            }
                        }
                    }
                }

                if ($cves.Count -gt 0) {
                    foreach ($c in $cves) {
                        $rows += [pscustomobject]@{
                            Host = $hostAddr
                            Hostname = $hostname
                            Port = [int]$portId
                            Protocol = $proto
                            Service = $service
                            Script = $scriptId
                            Finding = $c.Id
                            Severity = if ($c.Score) { [string]$c.Score } else { $null }
                            Summary = $scriptOut
                            Source = (Split-Path -Leaf $XmlFile)
                        }
                    }
                } else {
                    $rows += [pscustomobject]@{
                        Host = $hostAddr
                        Hostname = $hostname
                        Port = [int]$portId
                        Protocol = $proto
                        Service = $service
                        Script = $scriptId
                        Finding = $null
                        Severity = $null
                        Summary = $scriptOut
                        Source = (Split-Path -Leaf $XmlFile)
                    }
                }
            }
        }
        return $rows
    }

    function Save-JsonCsv {
        param(
            [Parameter(Mandatory)][object[]]$Rows,
            [Parameter(Mandatory)][string]$OutDir,
            [switch]$JSONOnly
        )
        $jsonPath = Join-Path -Path $OutDir -ChildPath 'vulnerabilities.json'
        $Rows | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
        if (-not $JSONOnly) {
            $csvPath = Join-Path -Path $OutDir -ChildPath 'vulnerabilities.csv'
            $Rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        }
    }

    function Generate-HtmlReport {
        param(
            [Parameter(Mandatory)][object[]]$Rows,
            [Parameter(Mandatory)][string]$OutDir
        )
        $htmlPath = Join-Path -Path $OutDir -ChildPath 'vulnerabilities.html'
        $byHost = $Rows | Group-Object Host | Sort-Object Name
        $totalFindings = $Rows.Count
        $now = Get-Date
        $css = @"
body { font-family: Segoe UI, Roboto, Arial, sans-serif; margin: 20px; }
h1 { font-size: 22px; }
small { color: #666; }
.summary { margin: 10px 0 20px; }
.host { margin: 16px 0 28px; }
.host h2 { font-size: 18px; margin-bottom: 6px; }
.table { border-collapse: collapse; width: 100%; }
.table th, .table td { border: 1px solid #ddd; padding: 6px 8px; }
.table th { background: #f4f4f4; text-align: left; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 12px; }
.badge-high { background: #ffebee; color: #c62828; border: 1px solid #ef9a9a; }
.badge-med { background: #fff8e1; color: #ef6c00; border: 1px solid #ffe082; }
.badge-low { background: #e8f5e9; color: #2e7d32; border: 1px solid #a5d6a7; }
"@
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<!DOCTYPE html>')
        [void]$sb.AppendLine('<html lang="fr"><head><meta charset="utf-8"/>')
        [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1"/>')
        [void]$sb.AppendLine('<title>Rapport de vulnérabilités Nmap</title>')
        [void]$sb.AppendLine('<style>')
        [void]$sb.AppendLine($css)
        [void]$sb.AppendLine('</style></head><body>')
        [void]$sb.AppendLine("<h1>Rapport de vulnérabilités Nmap</h1>")
        [void]$sb.AppendLine("<div class='summary'><small>Généré: $now — Total findings: $totalFindings</small></div>")
        foreach ($grp in $byHost) {
            $host = $grp.Name
            $count = $grp.Group.Count
            [void]$sb.AppendLine("<div class='host'>")
            [void]$sb.AppendLine("<h2>$host <small>($count éléments)</small></h2>")
            [void]$sb.AppendLine('<table class="table">')
            [void]$sb.AppendLine('<thead><tr><th>Port</th><th>Proto</th><th>Service</th><th>Script</th><th>Finding</th><th>Score</th><th>Résumé</th></tr></thead>')
            [void]$sb.AppendLine('<tbody>')
            foreach ($row in $grp.Group) {
                $sev = $row.Severity
                $badge = ''
                if ($sev) {
                    if ($sev -ge 7) { $badge = '<span class="badge badge-high">High</span>' }
                    elseif ($sev -ge 4) { $badge = '<span class="badge badge-med">Medium</span>' }
                    else { $badge = '<span class="badge badge-low">Low</span>' }
                }
                $summaryEsc = [System.Net.WebUtility]::HtmlEncode(($row.Summary -replace "`r?`n", ' '))
                [void]$sb.AppendLine("<tr><td>$($row.Port)</td><td>$($row.Protocol)</td><td>$($row.Service)</td><td>$($row.Script)</td><td>$([System.Net.WebUtility]::HtmlEncode($row.Finding))</td><td>$badge $sev</td><td>$summaryEsc</td></tr>")
            }
            [void]$sb.AppendLine('</tbody></table>')
            [void]$sb.AppendLine('</div>')
        }
        [void]$sb.AppendLine('</body></html>')
        $sb.ToString() | Set-Content -Path $htmlPath -Encoding UTF8
        return $htmlPath
    }

    function Get-JobSupport {
        $hasThreadJob = Get-Module -ListAvailable -Name ThreadJob -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ThreadJob = [bool]$hasThreadJob -or ($PSVersionTable.PSEdition -eq 'Core')
        }
    }

    if (-not (Test-CommandAvailable -Name $NmapPath)) {
        Write-Err "Nmap introuvable. Installez-le et/ou ajustez -NmapPath."
        throw "NmapNotFound"
    }

    $cidrs = Resolve-TargetCidrs -Target $Target
    $out = Ensure-OutputPaths -BaseOut $OutputDir
    Write-Info ("Sortie: {0}" -f $out.Root)
}

process {
    $allHosts = @()

    if ($SkipDiscovery) {
        Write-Info "Découverte sautée. Utilisation directe de la cible comme liste d'hôtes."
        $allHosts = $cidrs
    } else {
        Write-Info "Découverte des hôtes actifs..."
        foreach ($cidr in $cidrs) {
            $hosts = Invoke-Discovery -Target $cidr -OutDir $out.Discovery
            Write-Info ("{0} hôte(s) actifs détectés sur {1}" -f ($hosts.Count), $cidr)
            $allHosts += $hosts
        }
        $allHosts = $allHosts | Sort-Object -Unique
    }

    if (-not $allHosts -or $allHosts.Count -eq 0) {
        Write-Warn "Aucun hôte à scanner. Fin."
        return
    }

    Write-Info ("Démarrage du scan de vulnérabilités sur {0} hôte(s) (MaxParallel={1})" -f $allHosts.Count, $MaxParallel)

    $jobSupport = Get-JobSupport
    $jobs = @()

    if ($jobSupport.ThreadJob) {
        foreach ($h in $allHosts) {
            while ($jobs.Count -ge $MaxParallel) {
                Receive-Job -Job $jobs -Keep | Out-Null
                $jobs = $jobs | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'NotStarted' }
                Start-Sleep -Milliseconds 200
            }
            $jobs += Start-ThreadJob -Name "vuln_$h" -ScriptBlock {
                param($Host, $OutDir, $Quick, $TopPorts, $NmapPath)
                $ErrorActionPreference = 'Stop'
                # Réutilise les fonctions minimales nécessaires inline
                function Invoke-NmapLocal {
                    param([string[]]$Arguments, [string]$XmlOutputPath, [string]$NmapPath)
                    $argsList = @(); $argsList += $Arguments; $argsList += @('-oX', $XmlOutputPath)
                    & $NmapPath @argsList | Out-Null
                }
                function ScanHostLocal {
                    param($Host, $OutDir, $Quick, $TopPorts, $NmapPath)
                    $xmlPath = Join-Path -Path $OutDir -ChildPath ("vuln_{0}.xml" -f ($Host -replace '[^a-zA-Z0-9_-]', '_'))
                    $args = @()
                    if ($Quick) { $args += @('-sV', '-Pn', ("--top-ports {0}" -f $TopPorts), '--script', 'vuln,vulners', '-T4', $Host) }
                    else { $args += @('-sV', '-Pn', '-p', '1-65535', '--script', 'vuln,vulners', '-T3', $Host) }
                    $args += @('--script-args', 'mincvss=5.0')
                    Invoke-NmapLocal -Arguments $args -XmlOutputPath $xmlPath -NmapPath $NmapPath
                    return $xmlPath
                }
                $resultPath = ScanHostLocal -Host $Host -OutDir $OutDir -Quick:$Quick -TopPorts $TopPorts -NmapPath $NmapPath
                return $resultPath
            } -ArgumentList @($h, $out.Vuln, $Quick.IsPresent, $TopPorts, $NmapPath)
        }
    } else {
        foreach ($h in $allHosts) {
            while ($jobs.Count -ge $MaxParallel) {
                Receive-Job -Job $jobs -Keep | Out-Null
                $jobs = $jobs | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'NotStarted' }
                Start-Sleep -Milliseconds 200
            }
            $jobs += Start-Job -Name "vuln_$h" -ScriptBlock {
                param($Host, $OutDir, $Quick, $TopPorts, $NmapPath)
                $ErrorActionPreference = 'Stop'
                function Invoke-NmapLocal {
                    param([string[]]$Arguments, [string]$XmlOutputPath, [string]$NmapPath)
                    $argsList = @(); $argsList += $Arguments; $argsList += @('-oX', $XmlOutputPath)
                    & $NmapPath @argsList | Out-Null
                }
                function ScanHostLocal {
                    param($Host, $OutDir, $Quick, $TopPorts, $NmapPath)
                    $xmlPath = Join-Path -Path $OutDir -ChildPath ("vuln_{0}.xml" -f ($Host -replace '[^a-zA-Z0-9_-]', '_'))
                    $args = @()
                    if ($Quick) { $args += @('-sV', '-Pn', ("--top-ports {0}" -f $TopPorts), '--script', 'vuln,vulners', '-T4', $Host) }
                    else { $args += @('-sV', '-Pn', '-p', '1-65535', '--script', 'vuln,vulners', '-T3', $Host) }
                    $args += @('--script-args', 'mincvss=5.0')
                    Invoke-NmapLocal -Arguments $args -XmlOutputPath $xmlPath -NmapPath $NmapPath
                    return $xmlPath
                }
                $resultPath = ScanHostLocal -Host $Host -OutDir $OutDir -Quick:$Quick -TopPorts $TopPorts -NmapPath $NmapPath
                return $resultPath
            } -ArgumentList @($h, $out.Vuln, $Quick.IsPresent, $TopPorts, $NmapPath)
        }
    }

    while ($jobs | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'NotStarted' }) {
        Start-Sleep -Milliseconds 300
    }

    $resultFiles = @()
    foreach ($j in $jobs) {
        try {
            $r = Receive-Job -Job $j -ErrorAction SilentlyContinue
            if ($r) { $resultFiles += $r }
        } catch {}
        Remove-Job -Job $j -Force -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Info ("Résultats XML: {0}" -f ($resultFiles.Count))

    $rows = @()
    foreach ($f in $resultFiles) {
        $rows += Parse-NmapVulnXml -XmlFile $f
    }

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Warn "Aucune vulnérabilité détectée par les scripts NSE (ou aucun service accessible)."
    }

    Save-JsonCsv -Rows $rows -OutDir $out.Reports -JSONOnly:$JSONOnly

    if (-not $NoHTML) {
        $html = Generate-HtmlReport -Rows $rows -OutDir $out.Reports
        Write-Info ("Rapport HTML: {0}" -f $html)
    }

    Write-Info ("Terminé. Dossier de sortie: {0}" -f $out.Root)
}

end {}

