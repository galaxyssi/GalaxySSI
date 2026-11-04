# Run with Windows PowerShell 5.1 on an adapter supporting the BLE peripheral role.
[CmdletBinding()]
param([switch]$Probe, [ValidateRange(5, 180)][int]$Seconds = 60)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1

function Wait-WinRtOperation($operation, [type]$type) {
    $task = $asTask.MakeGenericMethod($type).Invoke($null, @($operation))
    if (!$task.Wait(10000)) { throw 'WinRT operation timed out.' }
    return ,$task.Result
}

$providerType = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattServiceProvider,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
$providerResult = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattServiceProviderResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
$characteristicResult = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattLocalCharacteristicResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
$parameters = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattLocalCharacteristicParameters,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]::new()
$parameters.CharacteristicProperties = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicProperties,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]::Indicate
$parameters.ReadProtectionLevel = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattProtectionLevel,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]::Plain
$parameters.WriteProtectionLevel = $parameters.ReadProtectionLevel
$result = Wait-WinRtOperation ($providerType::CreateAsync([guid]'00001810-0000-1000-8000-00805f9b34fb')) $providerResult
if ($result.Error -ne 'Success') { throw "Could not create fixture service: $($result.Error)" }
$provider = $result.ServiceProvider
$result = Wait-WinRtOperation ($provider.Service.CreateCharacteristicAsync([guid]'00002a35-0000-1000-8000-00805f9b34fb', $parameters)) $characteristicResult
if ($result.Error -ne 'Success') { throw "Could not create fixture characteristic: $($result.Error)" }
$characteristic = $result.Characteristic
$writerType = [Windows.Storage.Streams.DataWriter,Windows.Storage.Streams,ContentType=WindowsRuntime]
$notifyType = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattClientNotificationResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
$vectorType = [System.Collections.Generic.IReadOnlyList`1].MakeGenericType($notifyType)
$notify = $characteristic.GetType().GetMethods() | Where-Object {
    $_.Name -eq 'NotifyValueAsync' -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1

function Send-FixtureMeasurement([byte[]]$packet) {
    $writer = $writerType::new()
    $writer.WriteBytes($packet)
    $buffer = $writer.DetachBuffer()
    $operation = $notify.Invoke($characteristic, [object[]]@($buffer))
    return ,(Wait-WinRtOperation $operation $vectorType)
}

if ($Probe) {
    Send-FixtureMeasurement ([byte[]]@(0, 124, 0, 82, 0, 96, 0)) | Out-Null
    Write-Output 'Fixture service and indication API available.'
    exit 0
}

$advertising = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattServiceProviderAdvertisingParameters,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]::new()
$advertising.IsConnectable = $true
$advertising.IsDiscoverable = $true
$deadline = [datetime]::UtcNow.AddSeconds($Seconds)
try {
    $provider.StartAdvertising($advertising)
    Write-Output 'Waiting for a collector to subscribe to the synthetic fixture.'
    $now = (Get-Date).AddMinutes(-1)
    [byte[]]$packet = @(0x0e, 124, 0, 82, 0, 96, 0, ($now.Year -band 255), ($now.Year -shr 8),
        $now.Month, $now.Day, $now.Hour, $now.Minute, $now.Second, 68, 0, 2)
    $statuses = @()
    while ([datetime]::UtcNow -lt $deadline) {
        if ($characteristic.SubscribedClients.Count -gt 0) {
            $responses = Send-FixtureMeasurement $packet
            $statuses = @($responses | ForEach-Object Status)
            if ('Success' -in $statuses) { break }
        }
        Start-Sleep -Milliseconds 350
    }
    if ('Success' -notin $statuses) { throw "No indication acknowledged. Advertising status: $($provider.AdvertisementStatus)" }
    Write-Output "Synthetic indication results: $($statuses -join ', ')"
    Start-Sleep -Seconds 5
} finally { $provider.StopAdvertising() }
