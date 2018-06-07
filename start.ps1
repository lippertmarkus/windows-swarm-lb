Function Test-SameSubnet { 
    param ( 
    [parameter(Mandatory=$true)] 
    [Net.IPAddress] 
    $ip1, 
    
    [parameter(Mandatory=$true)] 
    [Net.IPAddress] 
    $ip2, 
    
    [parameter()] 
    [alias("SubnetMask")] 
    [Net.IPAddress] 
    $mask ="255.255.255.0" 
    ) 
    
    if (($ip1.address -band $mask.address) -eq ($ip2.address -band $mask.address)) {$true} 
    else {$false} 
    
}

if(!$env:UP_HOSTNAME) {
    throw "Environment variable UP_HOSTNAME not set"
}

$interfaceAlias = '*container*'

$ipInfo = Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Sort-Object InterfaceIndex | Select-Object -First 1

if (!$ipInfo) {
    throw "Adapter with alias $interfaceAlias not found"
}

$localIp = $ipInfo.IPAddress
Write-Host "Local IP: $localIp"

$PrefixLength = $ipInfo.PrefixLength
[IPAddress]$Mask = (([string]'1'*$PrefixLength + [string]'0'*(32-$PrefixLength)) -split "(\d{8})" -match "\d" | ForEach-Object {[convert]::ToInt32($_,2)}) -split "\D" -join "."

Write-Host "Subnet Mask: $Mask"

Write-Host "Searching docker DNS server.."
$dnsServers = ($ipInfo | Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses

$dockerDnsServer = '';

foreach ($server in $dnsServers) {
    if(Test-SameSubnet -ip1 $localIp -ip2 $server -mask $Mask) {
        $dockerDnsServer = $server
        break
    }
}

if(!$dockerDnsServer) {
    throw "Docker DNS Server not found"
}

Write-Host "Docker DNS Server: $dockerDnsServer"

Write-Host "Setting environment variable DNS_SERVER = $dockerDnsServer"
$env:DNS_SERVER = $dockerDnsServer

Write-Host "Environment variable UP_HOSTNAME = $($env:UP_HOSTNAME)"

Write-Host "Try resolving $($env:UP_HOSTNAME) with $($env:DNS_SERVER).."
$maxTries = 5
for ($i = 1; $i -le $maxTries; $i++) {
    $res = Resolve-DnsName -Name $env:UP_HOSTNAME -Server $env:DNS_SERVER -ErrorAction SilentlyContinue
    if($res) {
        Write-Host "Success!"
        break;
    } elseif($i -ge $maxTries) {
        throw "Can't resolve $($env:UP_HOSTNAME) with DNS Server $($env:DNS_SERVER)"
    } else {
        Write-Host "Can't resolve, trying again in 20s.."
        Start-Sleep -Seconds 20
    }
}

Write-Host "Starting nginx.."
Start-Process C:\openresty\nginx.exe -WorkingDirectory C:\openresty -Wait -NoNewWindow
