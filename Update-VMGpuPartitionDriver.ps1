<# 
If you are opening this file in Powershell ISE you should modify the params section like so...
Remember: GPU Name must match the name of the GPU you assigned when creating the VM...

Param (
[string]$VMName = "NameofyourVM",
[string]$GPUName = "NameofyourGPU",
[string]$VHDname = "VHDXname.vhdx",
[string]$Hostname = $ENV:Computername
)

Command line example:
.\Update-VMGpuPartitionDriver.ps1 -VMName "Windows10" -GPUName "NVIDIA GeForce GTX 1660 Ti" -VHDname "Windows10.vhdx"

If -VHDname is left out, the VM's first virtual hard disk is used.
#>

Param (
[Parameter(Mandatory)][string]$VMName,
[Parameter(Mandatory)][string]$GPUName,
[string]$VHDname,
[string]$Hostname = $ENV:Computername
)

Import-Module "$PSScriptRoot\Add-VMGpuPartitionAdapterFiles.psm1" -Force

$VM = Get-VM -VMName $VMName -ErrorAction Stop

# Pick the system VHD: exact file name match if -VHDname was given, otherwise the VM's first disk
$disks = Get-VMHardDiskDrive -VMName $VMName
if ($VHDname) {
    $disk = $disks | Where-Object { (Split-Path $_.Path -Leaf) -eq $VHDname } | Select-Object -First 1
} else {
    $disk = $disks | Sort-Object ControllerNumber, ControllerLocation | Select-Object -First 1
}
if (-not $disk) { throw "No matching virtual hard disk found on VM '$VMName'." }
$VHDPath = $disk.Path
"Using disk: $VHDPath"

If ((Get-VM -VMName $VMName).State -eq "Running") {
    [bool]$state_was_running = $true
    }

if ((Get-VM -VMName $VMName).State -ne "Off"){
    "Attempting to shutdown VM - make sure there are no unsaved documents..."
    Stop-VM -Name $VMName -Force
    } 

While ((Get-VM -VMName $VMName).State -ne "Off") {
    Start-Sleep -s 3
    "Waiting for VM to shutdown..."
    }

$mounted = $false
try {
    "Mounting Drive..."
    $before = [System.IO.DriveInfo]::GetDrives().Name
    Mount-VHD -Path $VHDPath -ErrorAction Stop | Out-Null
    $mounted = $true

    # Wait up to ~15 seconds for a new drive letter that contains a Windows folder
    $new = $null
    for ($i = 0; $i -lt 15 -and -not $new; $i++) {
        Start-Sleep -Seconds 1
        $new = [System.IO.DriveInfo]::GetDrives() | Where-Object {
            $before -notcontains $_.Name -and (Test-Path "$($_.Name)Windows\System32")
        }
    }
    if (-not $new) {
        throw "Mounted the VHD but no new drive letter with a Windows folder appeared. If automount is disabled, run 'diskpart' then 'automount enable'."
    }
    $DriveLetter = ($new | Select-Object -First 1).Name.TrimEnd('\')   # e.g. "E:"
    "Windows volume mounted at $DriveLetter"

    "Copying GPU Files - this could take a while..."
    Add-VMGPUPartitionAdapterFiles -hostname $Hostname -DriveLetter $DriveLetter -GPUName $GPUName
}
finally {
    if ($mounted) {
        "Dismounting Drive..."
        Dismount-VHD -Path $VHDPath
    }
    If ($state_was_running){
        "Previous State was running so starting VM..."
        Start-VM -Name $VMName
        }
}

"Done..."
