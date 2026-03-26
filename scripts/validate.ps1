<#
.SYNOPSIS
    Validaciones automáticas post-deploy de la arquitectura 3-tier.

.DESCRIPTION
    Ejecutar DESPUÉS de terraform apply.
    Valida conectividad, Security Groups, RDS y NAT Instance.
    Genera validate_report.txt en el directorio actual.

.PARAMETER TfDir
    Ruta al directorio terraform/environments/prod. Default: terraform/environments/prod

.PARAMETER Region
    Región AWS. Default: us-east-1

.PARAMETER ReportFile
    Nombre del archivo de reporte. Default: validate_report.txt

.EXAMPLE
    .\scripts\validate.ps1
    .\scripts\validate.ps1 -Region us-west-2
#>

param(
    [string]$TfDir      = "terraform/environments/prod",
    [string]$Region     = "us-east-1",
    [string]$ReportFile = "validate_report.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ============================================================
# Helpers
# ============================================================

$script:Results   = [System.Collections.Generic.List[string]]::new()
$script:PassCount = 0
$script:FailCount = 0

function Write-Section {
    param([string]$Title)
    $line = "`n" + ("=" * 60)
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    $script:Results.Add("")
    $script:Results.Add("=" * 60)
    $script:Results.Add("  $Title")
    $script:Results.Add("=" * 60)
}

function Write-Check {
    param(
        [bool]  $Pass,
        [string]$Label,
        [string]$Detail = ""
    )
    if ($Pass) {
        $icon = "[OK]"; $color = "Green"; $script:PassCount++
    } else {
        $icon = "[FAIL]"; $color = "Red"; $script:FailCount++
    }
    $msg = "  $icon  $Label"
    if ($Detail) { $msg += "  ($Detail)" }
    Write-Host $msg -ForegroundColor $color
    $script:Results.Add($msg)
}

function Invoke-Aws {
    param([string]$Args)
    $result = Invoke-Expression "aws $Args --region $Region --output json 2>`$null"
    if ($LASTEXITCODE -ne 0) { return $null }
    return $result | ConvertFrom-Json
}

# ============================================================
# 0. Obtener outputs de Terraform
# ============================================================
Write-Host "`n==> Leyendo outputs de Terraform..." -ForegroundColor Cyan

Push-Location $TfDir
$tfRaw = terraform output -json 2>$null
Pop-Location

if (-not $tfRaw) {
    Write-Host "[ERROR] No se pudieron leer los outputs de Terraform." -ForegroundColor Red
    Write-Host "        Asegúrate de haber ejecutado terraform apply primero." -ForegroundColor Yellow
    exit 1
}

$tf = $tfRaw | ConvertFrom-Json

$ALB_DNS       = $tf.alb_dns_name.value
$ASG_NAME      = $tf.asg_name.value
$NAT_ID        = $tf.nat_instance_id.value
$NAT_PUBLIC_IP = $tf.nat_public_ip.value
$VPC_ID        = $tf.vpc_id.value
$SG_ALB        = $tf.sg_alb_id.value
$SG_BACKEND    = $tf.sg_backend_id.value
$SG_DATABASE   = $tf.sg_database_id.value
$RDS_ID        = $tf.rds_identifier.value

Write-Host "    ALB DNS   : $ALB_DNS"
Write-Host "    ASG       : $ASG_NAME"
Write-Host "    NAT       : $NAT_ID ($NAT_PUBLIC_IP)"
Write-Host "    RDS       : $RDS_ID"

# ============================================================
# Header del reporte
# ============================================================
$Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")

$script:Results.Add("=" * 60)
$script:Results.Add("  REPORTE DE VALIDACION — aws-3tier-enterprise")
$script:Results.Add("  $Timestamp")
$script:Results.Add("=" * 60)
$script:Results.Add("")
$script:Results.Add("  Recursos validados:")
$script:Results.Add("    ALB DNS    : $ALB_DNS")
$script:Results.Add("    ASG        : $ASG_NAME")
$script:Results.Add("    NAT        : $NAT_ID")
$script:Results.Add("    RDS        : $RDS_ID")
$script:Results.Add("    SG ALB     : $SG_ALB")
$script:Results.Add("    SG Backend : $SG_BACKEND")
$script:Results.Add("    SG DB      : $SG_DATABASE")

# ============================================================
# 7A. Conectividad ALB
# ============================================================
Write-Section "7A. Conectividad ALB"

# ALB responde HTTP 200
$albStatus = $null
try {
    $response = Invoke-WebRequest -Uri "http://$ALB_DNS" -TimeoutSec 10 -UseBasicParsing -ErrorAction SilentlyContinue
    $albStatus = $response.StatusCode
} catch { }
Write-Check -Pass ($albStatus -ge 200 -and $albStatus -lt 500) `
    "ALB responde en HTTP" `
    "status=$albStatus  url=http://$ALB_DNS"

# Puerto 22 cerrado en el ALB
$sshOpen = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $conn = $tcp.BeginConnect($ALB_DNS, 22, $null, $null)
    $wait = $conn.AsyncWaitHandle.WaitOne(3000, $false)
    if ($wait) { $sshOpen = $tcp.Connected }
    $tcp.Close()
} catch { }
Write-Check -Pass (-not $sshOpen) "Puerto 22 cerrado en ALB"

# Targets del Target Group healthy
$tgArn = (Invoke-Aws "elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName,``backend``)].TargetGroupArn | [0]'")
if ($tgArn) {
    $tgArn = $tgArn.Trim('"')
    $health = Invoke-Aws "elbv2 describe-target-health --target-group-arn $tgArn"
    $unhealthy = @($health.TargetHealthDescriptions | Where-Object { $_.TargetHealth.State -ne "healthy" })
    $total     = $health.TargetHealthDescriptions.Count
    $healthy   = $total - $unhealthy.Count
    Write-Check -Pass ($unhealthy.Count -eq 0) `
        "Target Group — todos los targets healthy" `
        "$healthy/$total healthy"
} else {
    Write-Check -Pass $false "Target Group — no encontrado"
}

# ============================================================
# 7B. Security Groups
# ============================================================
Write-Section "7B. Security Groups"

function Test-SgHasPublicIngress {
    param([string]$SgId, [int]$Port)
    $sg = Invoke-Aws "ec2 describe-security-groups --group-ids $SgId"
    if (-not $sg) { return $false }
    $rules = $sg.SecurityGroups[0].IpPermissions
    foreach ($rule in $rules) {
        $fromPort = if ($rule.FromPort -eq $null) { 0 } else { $rule.FromPort }
        $toPort   = if ($rule.ToPort   -eq $null) { 65535 } else { $rule.ToPort }
        if ($Port -ge $fromPort -and $Port -le $toPort) {
            foreach ($ipRange in $rule.IpRanges) {
                if ($ipRange.CidrIp -eq "0.0.0.0/0") { return $true }
            }
        }
    }
    return $false
}

function Test-SgHasPort22Public {
    param([string]$SgId)
    return (Test-SgHasPublicIngress -SgId $SgId -Port 22)
}

function Get-SgIngressSources {
    param([string]$SgId, [int]$Port)
    $sg = Invoke-Aws "ec2 describe-security-groups --group-ids $SgId"
    if (-not $sg) { return @() }
    $sources = @()
    foreach ($rule in $sg.SecurityGroups[0].IpPermissions) {
        $fromPort = if ($rule.FromPort -eq $null) { 0 } else { $rule.FromPort }
        $toPort   = if ($rule.ToPort   -eq $null) { 65535 } else { $rule.ToPort }
        if ($Port -ge $fromPort -and $Port -le $toPort) {
            foreach ($ipRange  in $rule.IpRanges)            { $sources += $ipRange.CidrIp }
            foreach ($sgRef    in $rule.UserIdGroupPairs)    { $sources += $sgRef.GroupId  }
        }
    }
    return $sources
}

# sg_alb: tiene ingress 80 y 443 desde 0.0.0.0/0
$alb80  = Test-SgHasPublicIngress -SgId $SG_ALB -Port 80
$alb443 = Test-SgHasPublicIngress -SgId $SG_ALB -Port 443
Write-Check -Pass $alb80  "sg_alb: ingress 80 desde 0.0.0.0/0"
Write-Check -Pass $alb443 "sg_alb: ingress 443 desde 0.0.0.0/0"

# sg_alb: NO tiene puerto 22 abierto
Write-Check -Pass (-not (Test-SgHasPort22Public -SgId $SG_ALB)) `
    "sg_alb: puerto 22 NO expuesto a Internet"

# sg_backend: NO tiene ingress desde 0.0.0.0/0
$backendPublic = Test-SgHasPublicIngress -SgId $SG_BACKEND -Port 3000
Write-Check -Pass (-not $backendPublic) `
    "sg_backend: puerto 3000 NO expuesto a Internet"

$backend22 = Test-SgHasPort22Public -SgId $SG_BACKEND
Write-Check -Pass (-not $backend22) `
    "sg_backend: puerto 22 NO expuesto a Internet"

# sg_database: NO tiene ingress desde 0.0.0.0/0 en 3306
$dbPublic = Test-SgHasPublicIngress -SgId $SG_DATABASE -Port 3306
Write-Check -Pass (-not $dbPublic) `
    "sg_database: puerto 3306 NO expuesto a Internet"

# sg_database: ingress 3306 solo desde sg_backend
$dbSources = Get-SgIngressSources -SgId $SG_DATABASE -Port 3306
$dbOnlyBackend = ($dbSources.Count -gt 0) -and ($dbSources | Where-Object { $_ -ne $SG_BACKEND }).Count -eq 0
Write-Check -Pass $dbOnlyBackend `
    "sg_database: ingress 3306 solo desde sg_backend" `
    "sources=$($dbSources -join ', ')"

# Ningún SG tiene puerto 22 al mundo
$db22 = Test-SgHasPort22Public -SgId $SG_DATABASE
Write-Check -Pass (-not $db22) `
    "sg_database: puerto 22 NO expuesto a Internet"

# ============================================================
# 7C. RDS
# ============================================================
Write-Section "7C. RDS MySQL"

$rds = Invoke-Aws "rds describe-db-instances --db-instance-identifier $RDS_ID"
if ($rds -and $rds.DBInstances.Count -gt 0) {
    $db = $rds.DBInstances[0]

    Write-Check -Pass (-not $db.PubliclyAccessible) `
        "RDS publicly_accessible = false"

    Write-Check -Pass ($db.MultiAZ) `
        "RDS multi_az = true" `
        "SecondaryAZ=$($db.SecondaryAvailabilityZone)"

    Write-Check -Pass ($db.StorageEncrypted) `
        "RDS storage_encrypted = true"

    Write-Check -Pass ($db.DBInstanceStatus -eq "available") `
        "RDS status = available" `
        "status=$($db.DBInstanceStatus)"

    Write-Check -Pass ($db.Engine -eq "mysql") `
        "RDS engine = MySQL" `
        "version=$($db.EngineVersion)"
} else {
    Write-Check -Pass $false "RDS — instancia no encontrada ($RDS_ID)"
}

# ============================================================
# 7D. NAT Instance
# ============================================================
Write-Section "7D. NAT Instance"

$natInstance = Invoke-Aws "ec2 describe-instances --instance-ids $NAT_ID"
if ($natInstance -and $natInstance.Reservations.Count -gt 0) {
    $inst = $natInstance.Reservations[0].Instances[0]

    # source_dest_check = false en la ENI principal
    $eniId      = $inst.NetworkInterfaces[0].NetworkInterfaceId
    $eni        = Invoke-Aws "ec2 describe-network-interfaces --network-interface-ids $eniId"
    $srcDstChk  = $eni.NetworkInterfaces[0].SourceDestCheck
    Write-Check -Pass (-not $srcDstChk) `
        "NAT source_dest_check = false" `
        "eni=$eniId"

    # Instancia en estado running
    Write-Check -Pass ($inst.State.Name -eq "running") `
        "NAT Instance en estado running"

    # EIP asociada
    $hasEip = ($inst.PublicIpAddress -eq $NAT_PUBLIC_IP)
    Write-Check -Pass $hasEip `
        "NAT EIP asociada correctamente" `
        "ip=$NAT_PUBLIC_IP"

    # Rutas privadas apuntan a la ENI de la NAT
    $routeTables = Invoke-Aws "ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID Name=tag:Name,Values=*private-app*"
    if ($routeTables -and $routeTables.RouteTables.Count -gt 0) {
        $allRoutesOk = $true
        foreach ($rt in $routeTables.RouteTables) {
            $defaultRoute = $rt.Routes | Where-Object { $_.DestinationCidrBlock -eq "0.0.0.0/0" }
            if (-not $defaultRoute -or $defaultRoute.NetworkInterfaceId -ne $eniId) {
                $allRoutesOk = $false
                break
            }
        }
        Write-Check -Pass $allRoutesOk `
            "Rutas privadas app apuntan a ENI de NAT Instance" `
            "eni=$eniId  tablas=$($routeTables.RouteTables.Count)"
    } else {
        Write-Check -Pass $false "Tablas de rutas privadas app — no encontradas"
    }

    # Conectividad a Internet desde EC2 privada via SSM
    Write-Host "`n  Probando conectividad Internet via SSM (puede tardar ~30s)..." -ForegroundColor Yellow

    $asgInstances = Invoke-Aws "autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME"
    $targetInstanceId = $null
    if ($asgInstances -and $asgInstances.AutoScalingGroups.Count -gt 0) {
        $inServiceInstances = $asgInstances.AutoScalingGroups[0].Instances |
            Where-Object { $_.LifecycleState -eq "InService" }
        if ($inServiceInstances) {
            $targetInstanceId = $inServiceInstances[0].InstanceId
        }
    }

    if ($targetInstanceId) {
        $ssmCmd = Invoke-Aws "ssm send-command --instance-ids $targetInstanceId --document-name AWS-RunShellScript --parameters commands=[`"curl -s --max-time 10 https://checkip.amazonaws.com`"]"
        if ($ssmCmd) {
            $cmdId = $ssmCmd.Command.CommandId
            Start-Sleep -Seconds 20

            $ssmResult = Invoke-Aws "ssm get-command-invocation --command-id $cmdId --instance-id $targetInstanceId"
            $ssmStatus = $ssmResult.Status
            $ssmOutput = $ssmResult.StandardOutputContent.Trim()

            $hasPublicIp = ($ssmOutput -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")
            Write-Check -Pass ($hasPublicIp -and $ssmOutput -eq $NAT_PUBLIC_IP) `
                "EC2 privada sale a Internet via NAT" `
                "ec2=$targetInstanceId  ip_salida=$ssmOutput  nat_ip=$NAT_PUBLIC_IP"
        } else {
            Write-Check -Pass $false "SSM send-command — falló el envío del comando"
        }
    } else {
        Write-Check -Pass $false "No hay instancias InService en el ASG para test SSM"
    }

} else {
    Write-Check -Pass $false "NAT Instance — no encontrada ($NAT_ID)"
}

# ============================================================
# 7E. Reporte final
# ============================================================
Write-Section "RESUMEN FINAL"

$Total = $script:PassCount + $script:FailCount
$script:Results.Add("")
$script:Results.Add("  Total  : $Total validaciones")
$script:Results.Add("  Passed : $($script:PassCount)")
$script:Results.Add("  Failed : $($script:FailCount)")
$script:Results.Add("")

$summaryColor = if ($script:FailCount -eq 0) { "Green" } else { "Red" }
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor $summaryColor
Write-Host "  Total  : $Total validaciones" -ForegroundColor White
Write-Host "  Passed : $($script:PassCount)" -ForegroundColor Green
Write-Host "  Failed : $($script:FailCount)" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host ("=" * 60) -ForegroundColor $summaryColor

# Escribir reporte a disco
$script:Results | Out-File -FilePath $ReportFile -Encoding utf8
Write-Host "`n  Reporte guardado en: $ReportFile" -ForegroundColor Cyan

# Exit code para uso en CI/CD
exit $(if ($script:FailCount -gt 0) { 1 } else { 0 })
