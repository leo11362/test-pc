# =====================================================================
#  TEST COMPLET PC - avant achat
#  Lance via LANCER-TEST.bat (droits admin automatiques)
#  Genere un rapport HTML sur le Bureau
# =====================================================================

# ====== CONFIG DE L'ANNONCE (modifie ici pour tester un autre PC) ======
$ANNONCE = @{
    CPU       = 'Ryzen 5 2600'
    GPU       = '1060'
    VRAM      = 6          # Go
    RAM       = 16         # Go
    RAMMHz    = 3200
    RAMMarque = 'Corsair'
    SSD       = 'Samsung'
    SSDGo     = 1000
    Windows   = 'Pro'
    Alim      = 'Corsair 650 W'
}
# =======================================================================

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$results = New-Object System.Collections.ArrayList
function Add-R($cat, $item, $val, $status = 'info') {
    [void]$results.Add([pscustomobject]@{ Cat = $cat; Item = $item; Val = "$val"; Status = $status })
    $c = @{ ok = 'Green'; warn = 'Yellow'; bad = 'Red'; info = 'Gray' }[$status]
    Write-Host ("  [{0,-4}] {1} : {2}" -f $status.ToUpper(), $item, $val) -ForegroundColor $c
}
function Step($t) { Write-Host "`n>> $t" -ForegroundColor Cyan }
function Get-Temp {
    $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature
    if ($t) { [math]::Round((($t | Measure-Object CurrentTemperature -Maximum).Maximum / 10) - 273.15, 1) }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $PSCommandPath) {
    Write-Host "Demande des droits administrateur... clique sur OUI." -ForegroundColor Yellow
    $p = Start-Process powershell -Verb RunAs -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($p) { exit }
    Write-Host "Droits admin refusés : le test continue en mode limité." -ForegroundColor Yellow
}
Clear-Host
Write-Host "=========== TEST COMPLET DU PC ===========" -ForegroundColor Cyan
Write-Host "Durée : 3 à 6 minutes. Ne touche à rien pendant le test." -ForegroundColor Cyan
if (-not $isAdmin) { Write-Host "ATTENTION : pas en admin, certains tests (santé disques) seront incomplets." -ForegroundColor Yellow }

# ---------------------------------------------------------------- SYSTEME
Step "Système"
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
$bb = Get-CimInstance Win32_BaseBoard
Add-R 'Système' 'Fabricant / Modèle' "$($cs.Manufacturer) $($cs.Model)"
Add-R 'Système' 'N° de série' $bios.SerialNumber
Add-R 'Système' 'Carte mère' "$($bb.Manufacturer) $($bb.Product)"
Add-R 'Système' 'BIOS' "$($bios.SMBIOSBIOSVersion)"
Add-R 'Système' 'Windows' "$($os.Caption) (build $($os.BuildNumber))"
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
if ($lic.LicenseStatus -eq 1) { Add-R 'Système' 'Activation Windows' 'Activé' 'ok' } else { Add-R 'Système' 'Activation Windows' 'NON activé (licence à prévoir)' 'warn' }
$age = ((Get-Date) - $os.InstallDate).Days
Add-R 'Système' 'Windows installé le' "$($os.InstallDate.ToString('dd/MM/yyyy')) (il y a $age jours)" $(if ($age -lt 7) { 'warn' } else { 'info' })

# ---------------------------------------------------------------- CPU
Step "Processeur (stress test 30 s)"
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Add-R 'Processeur' 'Modèle' $cpu.Name.Trim()
Add-R 'Processeur' 'Coeurs / Threads' "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
Add-R 'Processeur' 'Fréquence max' "$($cpu.MaxClockSpeed) MHz"
$tIdle = Get-Temp
$dur = 30
$jobs = 1..$cpu.NumberOfLogicalProcessors | ForEach-Object {
    Start-Job -ScriptBlock { param($d) $end = (Get-Date).AddSeconds($d); $n = 0; while ((Get-Date) -lt $end) { for ($i = 0; $i -lt 5000; $i++) { $x = [math]::Sqrt($i) * [math]::Sin($i) }; $n++ }; $n } -ArgumentList $dur
}
Start-Sleep -Seconds 15
$tLoad = Get-Temp
$load = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
$jobs | Wait-Job -Timeout ($dur + 60) | Out-Null
$failed = ($jobs | Where-Object State -ne 'Completed').Count
$jobs | Remove-Job -Force
if ($failed -eq 0) { Add-R 'Processeur' 'Stress test' "Terminé sans plantage (charge ~$load %)" 'ok' } else { Add-R 'Processeur' 'Stress test' "$failed threads ont échoué" 'bad' }
if ($tLoad) {
    $st = if ($tLoad -ge 95) { 'bad' } elseif ($tLoad -ge 85) { 'warn' } else { 'ok' }
    Add-R 'Processeur' 'Température repos / charge' "$tIdle °C / $tLoad °C (capteur ACPI, approximatif)" $st
} else { Add-R 'Processeur' 'Température' 'Capteur non lisible -> vérifie avec HWiNFO' 'info' }

# ---------------------------------------------------------------- RAM
Step "Mémoire RAM"
$mods = Get-CimInstance Win32_PhysicalMemory
$tot = [math]::Round(($mods | Measure-Object Capacity -Sum).Sum / 1GB)
$vis = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
Add-R 'RAM' 'Total installé / utilisable' "$tot Go / $vis Go" $(if ($vis -lt $tot * 0.85) { 'warn' } else { 'ok' })
$slots = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
Add-R 'RAM' 'Slots utilisés' "$(@($mods).Count) / $slots"
foreach ($m in $mods) {
    Add-R 'RAM' "Barrette $($m.DeviceLocator)" "$([math]::Round($m.Capacity/1GB)) Go - $($m.ConfiguredClockSpeed) MHz - $($m.Manufacturer) $("$($m.PartNumber)".Trim())"
}
Add-Type -TypeDefinition @"
public static class MemTest {
  public static long[] Run(int mb){
    long errors=0; int chunk=64; const ulong P=0xA5A5A5A5A5A5A5A5UL;
    var list=new System.Collections.Generic.List<ulong[]>();
    try { for(int c=0;c<mb/chunk;c++){ var a=new ulong[chunk*1024*1024/8]; for(long i=0;i<a.Length;i++) a[i]=P^(ulong)i; list.Add(a);} }
    catch(System.OutOfMemoryException){}
    foreach(var a in list){ for(long i=0;i<a.Length;i++) if(a[i]!=(P^(ulong)i)) errors++; for(long i=0;i<a.Length;i++) a[i]=~a[i]; for(long i=0;i<a.Length;i++) if(a[i]!=~(P^(ulong)i)) errors++; }
    long tested=(long)list.Count*chunk; list.Clear(); System.GC.Collect();
    return new long[]{errors,tested};
  }
}
"@
$freeMB = [int]($os.FreePhysicalMemory / 1024 * 0.6)
Write-Host "  Test écriture/lecture sur $freeMB Mo de RAM..."
$r = [MemTest]::Run($freeMB)
if ($r[0] -eq 0) { Add-R 'RAM' 'Test rapide' "$($r[1]) Mo testés, 0 erreur" 'ok' } else { Add-R 'RAM' 'Test rapide' "$($r[0]) ERREURS sur $($r[1]) Mo" 'bad' }
if (@($mods).Count -eq 1) { Add-R 'RAM' 'Dual channel' '1 seule barrette = single channel, perd des FPS (prévoir une 2e barrette)' 'warn' }
else { Add-R 'RAM' 'Dual channel' "$(@($mods).Count) barrettes" 'ok' }
$m0 = @($mods)[0]
$isLaptop = [bool](Get-CimInstance Win32_Battery) -or (@((Get-CimInstance Win32_SystemEnclosure).ChassisTypes) | Where-Object { $_ -in 8, 9, 10, 14, 31 })
if (-not $isLaptop -and $m0.Speed -and $m0.ConfiguredClockSpeed -and $m0.ConfiguredClockSpeed -lt $m0.Speed * 0.9) {
    Add-R 'RAM' 'XMP / EXPO' "RAM à $($m0.ConfiguredClockSpeed) MHz au lieu de $($m0.Speed) : profil XMP pas activé dans le BIOS (pas une panne, se règle en 1 min)" 'warn'
}

# ---------------------------------------------------------------- DISQUES
Step "Disques (santé SMART + vitesse)"
foreach ($d in Get-PhysicalDisk) {
    $rc = $d | Get-StorageReliabilityCounter
    $n = "$($d.FriendlyName)"
    $size = [math]::Round($d.Size / 1GB)
    Add-R 'Disques' $n "$size Go - $($d.MediaType) - $($d.BusType)"
    Add-R 'Disques' "$n : état" $d.HealthStatus $(if ($d.HealthStatus -eq 'Healthy') { 'ok' } else { 'bad' })
    if ($null -ne $rc.Wear) { Add-R 'Disques' "$n : usure SSD" "$($rc.Wear) %" $(if ($rc.Wear -ge 80) { 'bad' } elseif ($rc.Wear -ge 50) { 'warn' } else { 'ok' }) }
    if ($rc.PowerOnHours) { Add-R 'Disques' "$n : heures d'utilisation" "$($rc.PowerOnHours) h (~$([math]::Round($rc.PowerOnHours/24)) jours)" }
    if ($rc.Temperature) { Add-R 'Disques' "$n : température" "$($rc.Temperature) °C" $(if ($rc.Temperature -ge 65) { 'warn' } else { 'ok' }) }
    $err = [int]$rc.ReadErrorsUncorrected + [int]$rc.WriteErrorsUncorrected
    if ($null -ne $rc.ReadErrorsUncorrected) { Add-R 'Disques' "$n : erreurs non corrigées" $err $(if ($err -gt 0) { 'bad' } else { 'ok' }) }
}
foreach ($v in Get-Volume | Where-Object DriveLetter) {
    $free = [math]::Round($v.SizeRemaining / 1GB); $sz = [math]::Round($v.Size / 1GB)
    Add-R 'Disques' "Partition $($v.DriveLetter):" "$free Go libres / $sz Go"
}
if ($isAdmin) {
    Write-Host "  Scan du système de fichiers C:..."
    $scan = Repair-Volume -DriveLetter C -Scan
    Add-R 'Disques' 'Scan erreurs C:' $scan $(if ("$scan" -eq 'NoErrorsFound') { 'ok' } else { 'warn' })
    Write-Host "  Mesure de vitesse (winsat)..."
    $rd = winsat disk -seq -read -drive c 2>$null | Select-String 'MB/s'
    $wr = winsat disk -seq -write -drive c 2>$null | Select-String 'MB/s'
    $rv = if ($rd) { [regex]::Match("$rd", '([\d\.,]+) MB/s').Groups[1].Value } else { '?' }
    $wv = if ($wr) { [regex]::Match("$wr", '([\d\.,]+) MB/s').Groups[1].Value } else { '?' }
    Add-R 'Disques' 'Vitesse C: lecture / écriture' "$rv / $wv Mo/s (SSD NVMe > 1500, SSD SATA ~500, HDD ~100)"
}

# ---------------------------------------------------------------- GPU
Step "Carte graphique"
$vram = @{}
Get-ItemProperty 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' | ForEach-Object {
    if ($_.'HardwareInformation.qwMemorySize') { $vram[$_.DriverDesc] = [math]::Round($_.'HardwareInformation.qwMemorySize' / 1GB, 1) }
}
$virt = 'Parsec|Virtual|Basic Display|Remote|Meta|Citrix|VMware|Hyper-V|DisplayLink|Spacedesk|IddSample'
$gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch $virt })
foreach ($g in $gpus) {
    $vr = if ($vram[$g.Name]) { "$($vram[$g.Name]) Go" } else { "?" }
    Add-R 'GPU' $g.Name "VRAM $vr - pilote $($g.DriverVersion) - $($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)" $(if ($g.Status -eq 'OK') { 'ok' } else { 'bad' })
}
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($smi) {
    $q = & nvidia-smi --query-gpu=name,temperature.gpu,fan.speed,power.limit,pcie.link.width.current,pcie.link.width.max,memory.total --format=csv,noheader,nounits | Select-Object -First 1
    $f = $q -split ',\s*'
    if ($f.Count -ge 7) {
        Add-R 'GPU' 'NVIDIA détectée' "$($f[0]) - $([math]::Round([double]$f[6]/1024,1)) Go VRAM"
        Add-R 'GPU' 'Température au repos' "$($f[1]) °C" $(if ([int]$f[1] -ge 60) { 'warn' } else { 'ok' })
        Add-R 'GPU' 'Ventilateur' "$($f[2]) %"
        Add-R 'GPU' 'Limite de puissance' "$($f[3]) W"
        $st = if ([int]$f[4] -lt [int]$f[5]) { 'warn' } else { 'ok' }
        Add-R 'GPU' 'Port PCIe' "x$($f[4]) sur x$($f[5]) possible" $st
    }
}
$dedic = $gpus | Where-Object { $_.Name -match 'GeForce|RTX|GTX|Radeon RX|Arc' }
if (-not $dedic) { Add-R 'GPU' 'Carte graphique dédiée' "Aucune détectée ! Vérifie que l'écran est branché sur la carte graphique et pas sur la carte mère" 'bad' }

# ---------------------------------------------------------------- BATTERIE
Step "Batterie"
$bat = Get-CimInstance Win32_Battery
$desk = [Environment]::GetFolderPath('Desktop')
if ($bat) {
    $design = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData | Select-Object -First 1).DesignedCapacity
    $full = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
    $cyc = (Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount | Select-Object -First 1).CycleCount
    if ($design -and $full) {
        $h = [math]::Round($full / $design * 100)
        Add-R 'Batterie' 'Santé' "$h % de la capacité d'origine ($full / $design mWh)" $(if ($h -lt 60) { 'bad' } elseif ($h -lt 80) { 'warn' } else { 'ok' })
    }
    if ($cyc) { Add-R 'Batterie' 'Cycles de charge' $cyc }
    Add-R 'Batterie' 'Charge actuelle' "$($bat.EstimatedChargeRemaining) %"
    powercfg /batteryreport /output "$desk\Rapport-Batterie.html" | Out-Null
    Add-R 'Batterie' 'Rapport détaillé' 'Rapport-Batterie.html sur le Bureau'
} else { Add-R 'Batterie' 'Batterie' 'Aucune (PC fixe)' }

# ---------------------------------------------------------------- PERIPHERIQUES
Step "Périphériques et réseau"
$bad = Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
if ($bad) { foreach ($b in $bad) { Add-R 'Périphériques' 'En erreur' "$($b.Name) (code $($b.ConfigManagerErrorCode))" 'bad' } }
else { Add-R 'Périphériques' 'Gestionnaire de périphériques' 'Aucun périphérique en erreur' 'ok' }
foreach ($cls in 'Camera', 'Image', 'Bluetooth', 'AudioEndpoint') {
    $p = Get-PnpDevice -Class $cls -PresentOnly | Where-Object Status -eq 'OK'
    $lab = @{ Camera = 'Webcam'; Image = 'Webcam (image)'; Bluetooth = 'Bluetooth'; AudioEndpoint = 'Audio (HP / micro)' }[$cls]
    if ($p) { Add-R 'Périphériques' $lab (($p.FriendlyName | Select-Object -Unique) -join ' | ') 'ok' }
}
foreach ($a in Get-NetAdapter -Physical) { Add-R 'Réseau' $a.Name "$($a.InterfaceDescription) - $($a.Status) $($a.LinkSpeed)" }
if (Test-Connection 8.8.8.8 -Count 3 -Quiet) { Add-R 'Réseau' 'Internet' 'Connecté' 'ok' } else { Add-R 'Réseau' 'Internet' 'Pas de connexion' 'warn' }

# ---------------------------------------------------------------- JOURNAUX
Step "Historique des plantages (30 derniers jours)"
$since = (Get-Date).AddDays(-30)
$checks = @(
    @{ L = 'Écrans bleus (BSOD)'; F = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since } },
    @{ L = 'Arrêts brutaux / coupures'; F = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } },
    @{ L = 'Erreurs matérielles (WHEA)'; F = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } }
)
foreach ($c in $checks) {
    $n = @(Get-WinEvent -FilterHashtable $c.F -MaxEvents 200).Count
    Add-R 'Plantages' $c.L $n $(if ($n -gt 2) { 'bad' } elseif ($n -gt 0) { 'warn' } else { 'ok' })
}
$sysDisk = (Get-Partition -DriveLetter C).DiskNumber
if ($null -eq $sysDisk) { $sysDisk = 0 }
$dEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk'; Id = 7, 11, 51, 153; StartTime = $since } -MaxEvents 300)
$onSys = 0; $onOther = 0
foreach ($e in $dEv) {
    $m = [regex]::Match("$($e.Message)", '(?:Harddisk|DR|[Dd]isque |[Dd]isk )(\d+)')
    if ($m.Success -and [int]$m.Groups[1].Value -ne $sysDisk) { $onOther++ } else { $onSys++ }
}
Add-R 'Plantages' 'Erreurs sur le disque principal' $onSys $(if ($onSys -gt 2) { 'bad' } elseif ($onSys -gt 0) { 'warn' } else { 'ok' })
if ($onOther) { Add-R 'Plantages' 'Erreurs sur clés USB / disques externes' "$onOther (pas grave pour le PC, ça vient d'un périphérique branché)" 'info' }

# ---------------------------------------------------------------- CONFORMITE ANNONCE
Step "Comparaison avec l'annonce"
$conf = New-Object System.Collections.ArrayList
function Add-C($comp, $ann, $reel, $st, $note = '') {
    [void]$conf.Add([pscustomobject]@{ Comp = $comp; Ann = "$ann"; Reel = "$reel"; Status = $st; Note = "$note" })
    $c = @{ ok = 'Green'; warn = 'Yellow'; bad = 'Red'; info = 'Gray' }[$st]
    Write-Host ("  [{0,-4}] {1} : annonce '{2}' / réel '{3}'" -f $st.ToUpper(), $comp, $ann, $reel) -ForegroundColor $c
}
$cpuName = $cpu.Name.Trim()
Add-C 'Processeur' $ANNONCE.CPU $cpuName $(if ($cpuName -match [regex]::Escape($ANNONCE.CPU)) { 'ok' } else { 'bad' })

$gpuAll = $gpus.Name -join ' / '
Add-C 'Carte graphique' $ANNONCE.GPU $gpuAll $(if ($gpuAll -match $ANNONCE.GPU) { 'ok' } else { 'bad' })
$vramGo = if ($smi -and $f.Count -ge 7) { [math]::Round([double]$f[6] / 1024, 1) } else { ($vram.Values | Measure-Object -Maximum).Maximum }
if ($vramGo) {
    $okV = $vramGo -ge $ANNONCE.VRAM * 0.9
    Add-C 'Mémoire carte graphique' "$($ANNONCE.VRAM) Go" "$vramGo Go" $(if ($okV) { 'ok' } else { 'bad' }) $(if (-not $okV) { 'Arnaque classique : version moins puissante vendue comme la grosse' })
}

Add-C 'RAM' "$($ANNONCE.RAM) Go" "$tot Go" $(if ($tot -ge $ANNONCE.RAM) { 'ok' } else { 'bad' })
$ramSpeed = ($mods | Measure-Object Speed -Maximum).Maximum
Add-C 'Vitesse RAM' "$($ANNONCE.RAMMHz) MHz" "$ramSpeed MHz (réglée à $($m0.ConfiguredClockSpeed) MHz)" $(if ($ramSpeed -ge $ANNONCE.RAMMHz * 0.95) { 'ok' } else { 'warn' })
$ramTxt = "$(($mods.Manufacturer | Select-Object -Unique) -join ', ') $((($mods | ForEach-Object { "$($_.PartNumber)".Trim() }) | Select-Object -Unique) -join ', ')"
$okR = ($ramTxt -match $ANNONCE.RAMMarque) -or ($ANNONCE.RAMMarque -eq 'Corsair' -and $ramTxt -match '\bCM[A-Z]')
Add-C 'Marque RAM' $ANNONCE.RAMMarque $ramTxt $(if ($okR) { 'ok' } else { 'info' }) $(if (-not $okR) { "Windows lit mal la marque, regarde l'étiquette sur les barrettes" })

$ssd = Get-PhysicalDisk | Where-Object { $_.FriendlyName -match $ANNONCE.SSD } | Select-Object -First 1
if ($ssd) {
    $sg = [math]::Round($ssd.Size / 1GB)
    $note = if ($ssd.FriendlyName -notmatch 'PRO') { "L'annonce dit 'Pro' : ici ce n'est pas un modèle PRO (EVO/QVO = moins haut de gamme)" } else { '' }
    $st = if ($sg -lt $ANNONCE.SSDGo * 0.88) { 'bad' } elseif ($note) { 'warn' } else { 'ok' }
    Add-C 'SSD' "$($ANNONCE.SSD) Pro $($ANNONCE.SSDGo) Go" "$($ssd.FriendlyName) ($sg Go utilisables)" $st $note
} else {
    Add-C 'SSD' "$($ANNONCE.SSD) $($ANNONCE.SSDGo) Go" ((Get-PhysicalDisk).FriendlyName -join ' / ') 'bad' "Aucun disque $($ANNONCE.SSD) trouvé"
}

$okW = ($os.Caption -match '11') -and ($os.Caption -match $ANNONCE.Windows) -and ($lic.LicenseStatus -eq 1)
Add-C 'Windows' "Windows 11 $($ANNONCE.Windows)" "$($os.Caption) - $(if ($lic.LicenseStatus -eq 1) { 'activé' } else { 'NON activé' })" $(if ($okW) { 'ok' } else { 'warn' }) $(if ($lic.LicenseStatus -ne 1) { 'Licence Windows à racheter : argument pour négocier' })
Add-C 'Alimentation' $ANNONCE.Alim 'Pas lisible par logiciel' 'info' "Ouvre le boîtier et regarde l'étiquette sur l'alim"

# ---------------------------------------------------------------- RAPPORT HTML
Step "Génération du rapport"
$enc = { param($s) [System.Net.WebUtility]::HtmlEncode("$s") }
$nb = @{ ok = 0; warn = 0; bad = 0 }
$results | ForEach-Object { if ($nb.ContainsKey($_.Status)) { $nb[$_.Status]++ } }
$rows = ''
foreach ($grp in $results | Group-Object Cat) {
    $rows += "<h2>$(& $enc $grp.Name)</h2><table>"
    foreach ($r in $grp.Group) { $rows += "<tr class='$($r.Status)'><td class='dot'></td><td>$(& $enc $r.Item)</td><td>$(& $enc $r.Val)</td></tr>" }
    $rows += "</table>"
}
$conf | ForEach-Object { if ($nb.ContainsKey($_.Status)) { $nb[$_.Status]++ } }
$badList = @($conf | Where-Object Status -eq 'bad' | ForEach-Object { "$($_.Comp) : annonce '$($_.Ann)' mais réel '$($_.Reel)'. $($_.Note)" }) +
           @($results | Where-Object Status -eq 'bad' | ForEach-Object { "$($_.Item) : $($_.Val)" })
$warnList = @($conf | Where-Object Status -eq 'warn' | ForEach-Object { "$($_.Comp) : $($_.Reel). $($_.Note)" }) +
            @($results | Where-Object Status -eq 'warn' | ForEach-Object { "$($_.Item) : $($_.Val)" })
$goodKeys = 'Stress test', 'Test rapide', 'état', 'Écrans bleus', 'Arrêts brutaux', 'Erreurs matérielles', 'disque principal', 'Gestionnaire de périphériques', 'Port PCIe', 'Scan erreurs'
$goodList = @($results | Where-Object { $it = $_.Item; $_.Status -eq 'ok' -and @($goodKeys | Where-Object { $it -like "*$_*" }).Count -gt 0 } | ForEach-Object { "$($_.Item) : $($_.Val)" })
$nConfOk = @($conf | Where-Object Status -eq 'ok').Count

if ($badList.Count -gt 0) { $vc = 'bad'; $vt = "❌ À ÉVITER ou à négocier très fort : $($badList.Count) vrai(s) problème(s)" }
elseif ($warnList.Count -gt 0) { $vc = 'warn'; $vt = "⚠️ BON PC, quelques points à négocier ($($warnList.Count))" }
else { $vc = 'ok'; $vt = "✅ CONFORME à l'annonce et en bonne santé : tu peux y aller" }

function Li($arr, $empty) { if ($arr.Count) { '<ul>' + (($arr | ForEach-Object { "<li>$(& $enc $_)</li>" }) -join '') + '</ul>' } else { "<p style='color:#888'>$empty</p>" } }
$confRows = ($conf | ForEach-Object { "<tr class='$($_.Status)'><td class='dot'></td><td>$(& $enc $_.Comp)</td><td>$(& $enc $_.Ann)</td><td>$(& $enc $_.Reel)$(if ($_.Note) { "<br><small style='color:#f39c12'>$(& $enc $_.Note)</small>" })</td></tr>" }) -join ''
$verdict = "<div class='v $vc'>$vt</div>" +
    "<h2>Conforme à l'annonce ? ($nConfOk / $($conf.Count) vérifiés OK)</h2><table><tr style='color:#888'><td></td><td>Pièce</td><td>Annonce</td><td>Réel</td></tr>$confRows</table>" +
    "<h2 style='color:#e74c3c'>❌ Problèmes</h2>" + (Li $badList 'Aucun problème grave détecté.') +
    "<h2 style='color:#f39c12'>⚠️ À surveiller / arguments pour négocier</h2>" + (Li $warnList 'Rien à signaler.') +
    "<h2 style='color:#2ecc71'>✅ Ce qui est bon</h2>" + (Li $goodList 'Voir le détail plus bas.') +
    "<h2 style='margin-top:40px;color:#888'>Détail complet des tests</h2>"

$head = @'
<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Rapport PC</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#0f1115;color:#e6e6e6;max-width:900px;margin:auto;padding:20px}
h1{margin-bottom:4px}h2{margin-top:28px;border-bottom:1px solid #333;padding-bottom:4px;font-size:18px}
table{width:100%;border-collapse:collapse}td{padding:6px 8px;border-bottom:1px solid #222;vertical-align:top}
td:nth-child(2){width:38%;color:#aaa}.dot{width:12px}.dot:before{content:"";display:inline-block;width:10px;height:10px;border-radius:50%;background:#555}
.ok .dot:before{background:#2ecc71}.warn .dot:before{background:#f39c12}.bad .dot:before{background:#e74c3c}.bad td{color:#ff8a80}
.v{padding:14px;border-radius:8px;font-weight:bold;font-size:18px;margin:14px 0}.v.ok{background:#16351f}.v.warn{background:#3d2e0e}.v.bad{background:#3d1414}
button{background:#2d6cdf;color:#fff;border:0;padding:10px 16px;border-radius:6px;font-size:15px;cursor:pointer;margin:4px 4px 4px 0}
#kb{margin-top:10px;display:none}#kb span{display:inline-block;min-width:34px;padding:6px;margin:2px;border:1px solid #444;border-radius:4px;text-align:center;font-size:12px}
#kb span.hit{background:#2ecc71;color:#000}#fs{position:fixed;inset:0;display:none;z-index:9}
li{margin:5px 0}
</style></head><body>
'@
$tools = @'
<h2>Stress test carte graphique (2 min)</h2>
<p>Ouvre d'abord le <b>Gestionnaire des tâches</b> (Ctrl+Maj+Échap) &gt; Performance &gt; GPU pour voir la température. Puis lance le test.</p>
<button onclick="gpu()">Lancer le stress test GPU</button>
<div id="gpuInfo" style="color:#aaa;margin-top:6px"></div>
<p style="color:#888;font-size:14px">C'est OK si : pas de plantage, pas d'écran noir, pas de taches/carrés colorés bizarres (artefacts), et GPU sous ~85 °C. Un PC qui redémarre pendant le test = alim ou GPU en fin de vie.</p>
<h2>Tests manuels intégrés</h2>
<button onclick="pix()">Test pixels morts de l'écran</button>
<button onclick="document.getElementById('kb').style.display='block'">Test clavier</button>
<div id="kb"><p>Appuie sur chaque touche : elle devient verte.</p><div id="keys"></div></div>
<div id="fs"></div>
<canvas id="gc" style="position:fixed;inset:0;width:100vw;height:100vh;display:none;z-index:10"></canvas>
<div id="gh" style="position:fixed;top:10px;left:10px;z-index:11;display:none;background:#000c;padding:8px 12px;border-radius:6px;font:16px monospace"></div>
<h2>Checklist PC gamer (à faire à la main)</h2><ul>
<li><b>Compare avec l'annonce</b> : modèle exact du CPU, de la carte graphique, quantité de RAM et taille du SSD dans le rapport ci-dessus</li>
<li><b>Ouvre le boîtier</b> : poussière, câbles propres, pas de composants qui bougent, pas de condensateurs gonflés</li>
<li><b>Alimentation</b> : note la marque et les watts sur l'étiquette (marque connue = Corsair, Seasonic, be quiet!, MSI... évite les noms inconnus)</li>
<li>L'écran est branché sur la <b>carte graphique</b> (ports en bas, horizontaux) et pas sur la carte mère</li>
<li>Tous les ventilos tournent, pas de bruit de grattement ou de sifflement (coil whine léger = normal)</li>
<li>Ports USB avant et arrière avec une clé, prise casque/micro en façade</li>
<li>Demande la facture d'achat (garantie) et les boîtes si possible</li>
</ul>
<script>
const cols=['#000','#fff','#f00','#0f0','#00f'];let ci=0;const fs=document.getElementById('fs');
function pix(){ci=0;fs.style.background=cols[0];fs.style.display='block';document.documentElement.requestFullscreen&&document.documentElement.requestFullscreen();}
fs.onclick=()=>{ci++;if(ci>=cols.length){fs.style.display='none';document.exitFullscreen&&document.exitFullscreen();}else fs.style.background=cols[ci];};
document.addEventListener('fullscreenchange',()=>{if(!document.fullscreenElement){fs.style.display='none';stopGpu&&stopGpu();}});
let stopGpu=null;
function gpu(){
  const c=document.getElementById('gc'),h=document.getElementById('gh'),info=document.getElementById('gpuInfo');
  c.style.display='block';h.style.display='block';
  document.documentElement.requestFullscreen&&document.documentElement.requestFullscreen();
  const dpr=window.devicePixelRatio||1;c.width=innerWidth*dpr;c.height=innerHeight*dpr;
  const gl=c.getContext('webgl',{powerPreference:'high-performance'});
  if(!gl){info.textContent='WebGL indisponible : pilote graphique absent ou cassé (mauvais signe).';c.style.display='none';h.style.display='none';return;}
  const dbg=gl.getExtension('WEBGL_debug_renderer_info');
  const gname=dbg?gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL):'?';
  const vs='attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';
  const fsrc='precision highp float;uniform float t;uniform vec2 r;void main(){vec2 u=(gl_FragCoord.xy*2.-r)/r.y;vec3 col=vec3(0.);for(int i=0;i<250;i++){float f=float(i);u=abs(u)/max(dot(u,u),0.05)-0.85+0.08*sin(t*0.4+f*0.02);col+=0.004*vec3(abs(u.x),abs(u.y),0.6);}gl_FragColor=vec4(clamp(col,0.,1.),1.);}';
  function sh(type,src){const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);return s;}
  const pr=gl.createProgram();gl.attachShader(pr,sh(gl.VERTEX_SHADER,vs));gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,fsrc));gl.linkProgram(pr);gl.useProgram(pr);
  const b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
  const loc=gl.getAttribLocation(pr,'p');gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
  const ut=gl.getUniformLocation(pr,'t'),ur=gl.getUniformLocation(pr,'r');
  gl.uniform2f(ur,c.width,c.height);
  const start=performance.now(),DUR=120000;let passes=1,frames=0,last=start,fpsList=[],lost=false,run=true;
  c.addEventListener('webglcontextlost',()=>{lost=true;});
  stopGpu=()=>{run=false;};
  function loop(now){
    if(!run||lost||now-start>DUR){finish();return;}
    gl.uniform1f(ut,(now-start)/1000);
    for(let i=0;i<passes;i++)gl.drawArrays(gl.TRIANGLES,0,3);
    frames++;
    if(now-last>=1000){const fps=frames*1000/(now-last);fpsList.push(fps*passes);
      if(fps>50)passes++;else if(fps<30&&passes>1)passes--;
      frames=0;last=now;
      h.textContent=gname+' | '+Math.round((now-start)/1000)+' / 120 s | charge x'+passes+' | Échap pour arrêter';}
    requestAnimationFrame(loop);
  }
  function finish(){
    c.style.display='none';h.style.display='none';stopGpu=null;
    document.fullscreenElement&&document.exitFullscreen();
    const dur=Math.round((performance.now()-start)/1000);
    const avg=fpsList.length?Math.round(fpsList.reduce((a,x)=>a+x,0)/fpsList.length):0;
    if(lost)info.innerHTML='<b style="color:#e74c3c">Le pilote graphique a planté pendant le test ('+dur+' s). Mauvais signe pour la carte graphique.</b>';
    else info.innerHTML='Test terminé après '+dur+' s sur '+gname+'. Score : <b>'+avg+'</b> (plus c\'est haut, plus la carte est puissante). Pas de plantage = <span style="color:#2ecc71">OK</span>. Regarde la température max atteinte dans le Gestionnaire des tâches.';
  }
  requestAnimationFrame(loop);
}
const k=document.getElementById('keys');const seen={};
document.addEventListener('keydown',e=>{if(document.getElementById('kb').style.display!=='block')return;e.preventDefault();
if(!seen[e.code]){const s=document.createElement('span');s.textContent=e.key===' '?'Espace':e.key;s.className='hit';k.appendChild(s);seen[e.code]=1;}});
</script></body></html>
'@
$date = Get-Date -Format 'dd/MM/yyyy HH:mm'
$html = $head + "<h1>Rapport PC</h1><div style='color:#888'>$(& $enc "$($cs.Manufacturer) $($cs.Model)") - $date</div>" + $verdict + $rows + $tools
$out = Join-Path $desk ("Rapport-PC-" + (Get-Date -Format 'yyyyMMdd-HHmm') + ".html")
$html | Out-File -FilePath $out -Encoding UTF8
Write-Host "`nRapport : $out" -ForegroundColor Green
Write-Host "OK: $($nb.ok)   A surveiller: $($nb.warn)   Problemes: $($nb.bad)" -ForegroundColor Cyan
Write-Host ("VERDICT : " + ($vt -replace '^\S+\s', '')) -ForegroundColor @{ ok = 'Green'; warn = 'Yellow'; bad = 'Red' }[$vc]
Start-Process $out

Write-Host ""
Read-Host "Test terminé. Appuie sur Entrée pour fermer"
