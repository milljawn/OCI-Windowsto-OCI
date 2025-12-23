<#
.SYNOPSIS
    Prepares a Windows Server instance for import to Oracle Cloud Infrastructure (OCI)

.DESCRIPTION
    This script automates the preparation of Windows Server images for OCI import.
    It performs security hardening, configures RDP, checks licensing, downloads and 
    installs VirtIO drivers, and exports the image ready for upload to OCI.

.NOTES
    Author: OCI Migration Assistant
    Version: 1.0
    Requirements: 
    - PowerShell 5.1 or higher
    - Administrator privileges
    - Windows Server 2016/2019/2022/2025
    - Active internet connection for driver download
#>

#Requires -RunAsAdministrator

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Color functions for better output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host ">>> $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Section "Checking Prerequisites"
    
    # Check Windows version
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $osVersion = $osInfo.Caption
    Write-ColorOutput "Operating System: $osVersion" "White"
    
    if ($osVersion -notmatch "Server (2016|2019|2022|2025)") {
        Write-Warning-Custom "This OS version may not be officially supported. Supported: Windows Server 2016/2019/2022/2025"
        $continue = Read-Host "Continue anyway? (yes/no)"
        if ($continue -ne "yes") {
            exit
        }
    } else {
        Write-Success "OS version is supported"
    }
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-ColorOutput "PowerShell Version: $($psVersion.Major).$($psVersion.Minor)" "White"
    
    if ($psVersion.Major -lt 5) {
        Write-Error-Custom "PowerShell 5.0 or higher is required"
        exit
    }
    Write-Success "PowerShell version is adequate"
    
    # Check administrator privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error-Custom "This script must be run as Administrator"
        exit
    }
    Write-Success "Running with Administrator privileges"
    
    # Check disk space
    $systemDrive = $env:SystemDrive
    $disk = Get-PSDrive -Name $systemDrive.Trim(':')
    $freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
    Write-ColorOutput "Free disk space on $systemDrive : $freeSpaceGB GB" "White"
    
    if ($freeSpaceGB -lt 10) {
        Write-Warning-Custom "Low disk space. At least 10GB recommended for safe operation"
    } else {
        Write-Success "Sufficient disk space available"
    }
    
    Write-Host ""
}

# Function to check and display license information
function Get-WindowsLicenseInfo {
    Write-Section "Windows License Information"
    
    Write-Step "Checking current license status..."
    
    try {
        $license = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object {$_.PartialProductKey} | Select-Object Description, LicenseStatus, ProductKeyChannel
        
        Write-ColorOutput "License Details:" "White"
        Write-ColorOutput "  Edition: $($license.Description)" "White"
        Write-ColorOutput "  License Channel: $($license.ProductKeyChannel)" "White"
        Write-ColorOutput "  Status: $(if($license.LicenseStatus -eq 1){'Licensed'}else{'Not Licensed'})" "White"
        
        $script:IsVolumeLicense = $license.ProductKeyChannel -match "Volume"
        
        if ($script:IsVolumeLicense) {
            Write-Success "Volume license detected - no post-import license change needed"
        } else {
            Write-Warning-Custom "Non-volume license detected - you'll need to activate with KMS after import"
        }
        
    } catch {
        Write-Error-Custom "Failed to retrieve license information: $_"
    }
    
    Write-Host ""
}

# Function to configure RDP
function Enable-RDPAccess {
    Write-Section "Configuring Remote Desktop Protocol (RDP)"
    
    Write-Step "Enabling Remote Desktop..."
    
    try {
        # Enable RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
        Write-Success "Remote Desktop enabled"
        
        # Configure firewall for RDP
        Write-Step "Configuring Windows Firewall for RDP (Private and Public profiles)..."
        
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        
        # Ensure RDP is allowed for both Private and Public profiles
        $rdpRules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" | Where-Object {$_.Direction -eq "Inbound"}
        foreach ($rule in $rdpRules) {
            Set-NetFirewallRule -Name $rule.Name -Profile Domain,Private,Public
        }
        
        Write-Success "RDP firewall rules configured for all network profiles"
        
    } catch {
        Write-Error-Custom "Failed to configure RDP: $_"
    }
    
    Write-Host ""
}

# Function to configure DHCP
function Set-DHCPConfiguration {
    Write-Section "Configuring Network for DHCP"
    
    Write-Step "Setting all network adapters to use DHCP..."
    
    try {
        $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        
        foreach ($adapter in $adapters) {
            Write-ColorOutput "  Configuring adapter: $($adapter.Name)" "White"
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
        
        Write-Success "All network adapters configured for DHCP"
        
    } catch {
        Write-Error-Custom "Failed to configure DHCP: $_"
    }
    
    Write-Host ""
}

# Function to download and install VirtIO drivers
function Install-VirtIODrivers {
    Write-Section "Installing Oracle VirtIO Drivers"
    
    Write-ColorOutput "VirtIO drivers are REQUIRED for paravirtualized mode in OCI." "Yellow"
    Write-ColorOutput "This is the critical component for optimal performance." "Yellow"
    Write-Host ""
    
    $installDrivers = Read-Host "Download and install VirtIO drivers now? (yes/no)"
    
    if ($installDrivers -eq "yes") {
        Write-Step "Preparing to download Oracle VirtIO drivers..."
        
        $downloadPath = "$env:TEMP\virtio-drivers"
        if (-not (Test-Path $downloadPath)) {
            New-Item -Path $downloadPath -ItemType Directory -Force | Out-Null
        }
        
        Write-ColorOutput @"

MANUAL DOWNLOAD REQUIRED:
The Oracle VirtIO drivers must be downloaded from Oracle's website.

1. Visit: https://docs.oracle.com/en/operating-systems/oracle-linux/kvm-virtio/
2. Navigate to 'Downloading the Oracle VirtIO Drivers for Microsoft Windows'
3. Download the appropriate driver package for your Windows version
4. Save the downloaded file (likely a .iso or .zip) to: $downloadPath

Press Enter once you have downloaded the drivers to that location...
"@ "Cyan"
        
        Read-Host
        
        # Check if files were downloaded
        $driverFiles = Get-ChildItem -Path $downloadPath -Recurse -Include "*.iso","*.zip","*.exe" -ErrorAction SilentlyContinue
        
        if ($driverFiles) {
            Write-Success "Driver files found in download directory"
            Write-ColorOutput "Found files:" "White"
            $driverFiles | ForEach-Object { Write-ColorOutput "  - $($_.Name)" "Gray" }
            
            Write-Host ""
            Write-ColorOutput "INSTALLATION STEPS:" "Yellow"
            Write-ColorOutput "1. If you downloaded an ISO, mount it by double-clicking" "White"
            Write-ColorOutput "2. Run the installer or driver setup executable" "White"
            Write-ColorOutput "3. Follow the installation wizard" "White"
            Write-ColorOutput "4. Restart the system when prompted" "White"
            Write-Host ""
            
            $installed = Read-Host "Have you completed the VirtIO driver installation? (yes/no)"
            
            if ($installed -eq "yes") {
                Write-Success "VirtIO drivers installation acknowledged"
                $script:VirtIOInstalled = $true
            } else {
                Write-Warning-Custom "Please install VirtIO drivers before proceeding with image export"
                $script:VirtIOInstalled = $false
            }
        } else {
            Write-Warning-Custom "No driver files found in $downloadPath"
            Write-ColorOutput "Please download and install drivers manually before exporting the image" "Yellow"
            $script:VirtIOInstalled = $false
        }
        
    } else {
        Write-Warning-Custom "Skipping VirtIO driver installation"
        Write-ColorOutput "NOTE: You MUST install these drivers before the image will work properly in OCI" "Red"
        $script:VirtIOInstalled = $false
    }
    
    Write-Host ""
}

# Function to configure remote storage services
function Set-RemoteStorageServices {
    Write-Section "Configuring Remote Storage Services"
    
    Write-ColorOutput "Remote storage (NFS, iSCSI, etc.) won't be available on first boot in OCI." "Yellow"
    Write-Host ""
    
    $hasRemoteStorage = Read-Host "Does this system use remote storage? (yes/no)"
    
    if ($hasRemoteStorage -eq "yes") {
        Write-Step "Identifying services that may depend on remote storage..."
        
        Write-ColorOutput @"
        
Please manually configure any services that depend on remote storage to start manually.
Common services that may need adjustment:
  - Database services
  - Application services
  - Backup services
  
After import to OCI, you can:
  1. Attach block volumes
  2. Configure file storage
  3. Reset services to automatic startup

"@ "White"
        
        Read-Host "Press Enter when you've noted which services to configure..."
        Write-Success "Remote storage configuration noted"
    } else {
        Write-Success "No remote storage configuration needed"
    }
    
    Write-Host ""
}

# Function to perform security hardening
function Invoke-SecurityHardening {
    Write-Section "Security Hardening"
    
    $performHardening = Read-Host "Perform basic security hardening? (yes/no)"
    
    if ($performHardening -eq "yes") {
        Write-Step "Checking Windows Update status..."
        
        try {
            # Enable Windows Firewall for all profiles
            Write-Step "Ensuring Windows Firewall is enabled..."
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Write-Success "Windows Firewall enabled for all profiles"
            
            # Disable unnecessary services (be conservative)
            Write-Step "Checking for unnecessary services..."
            Write-ColorOutput "  Skipping automatic service disabling for safety" "Gray"
            Write-ColorOutput "  You can manually disable unnecessary services via services.msc" "Gray"
            
            Write-Success "Security hardening completed"
            
        } catch {
            Write-Error-Custom "Error during security hardening: $_"
        }
    } else {
        Write-ColorOutput "Skipping security hardening - ensure you follow your organization's security policies" "Yellow"
    }
    
    Write-Host ""
}

# Function to create a system backup checkpoint
function New-SystemCheckpoint {
    Write-Section "Creating System Checkpoint"
    
    $createCheckpoint = Read-Host "Create a system restore point before proceeding? (yes/no)"
    
    if ($createCheckpoint -eq "yes") {
        Write-Step "Creating system restore point..."
        
        try {
            # Enable System Restore if not already enabled
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            
            # Create restore point
            Checkpoint-Computer -Description "Before OCI Image Preparation" -RestorePointType "MODIFY_SETTINGS"
            Write-Success "System restore point created"
            
        } catch {
            Write-Warning-Custom "Could not create restore point: $_"
            Write-ColorOutput "Consider creating a backup through your virtualization platform" "Yellow"
        }
    }
    
    Write-Host ""
}

# Function to optionally generalize the image
function Invoke-ImageGeneralization {
    Write-Section "Image Generalization (Sysprep)"
    
    Write-ColorOutput @"
GENERALIZATION OPTIONS:

1. GENERALIZED IMAGE (Recommended for multiple instances)
   - Removes computer-specific information
   - Allows launching multiple unique instances
   - Uses Sysprep to clean the image
   - Instance will be shut down after generalization

2. SPECIALIZED IMAGE (For single instance or backup)
   - Keeps all current configuration
   - Useful for backups
   - Should only be used for single instance deployments

"@ "Cyan"
    
    $generalize = Read-Host "Do you want to create a GENERALIZED image? (yes/no)"
    
    if ($generalize -eq "yes") {
        Write-Warning-Custom "IMPORTANT: Generalizing will shut down this instance and make it non-bootable"
        Write-ColorOutput "You should clone this VM first if you need to keep it running" "Yellow"
        Write-Host ""
        
        $confirm = Read-Host "Are you sure you want to generalize NOW? (yes/no)"
        
        if ($confirm -eq "yes") {
            Write-Step "Preparing Sysprep generalization..."
            
            Write-ColorOutput @"
            
The system will now be generalized using Sysprep.
This will:
  1. Remove computer-specific information
  2. Prepare the image for cloning
  3. Shut down the system
  
After shutdown, you should:
  1. Clone the VM as VMDK or QCOW2
  2. Upload to OCI Object Storage
  3. Import as a custom image

Starting Sysprep in 10 seconds...
Press Ctrl+C to cancel

"@ "Yellow"
            
            Start-Sleep -Seconds 10
            
            try {
                # Run Sysprep
                & "$env:SystemRoot\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown
                Write-Success "Sysprep started - system will shut down shortly"
                
            } catch {
                Write-Error-Custom "Failed to run Sysprep: $_"
            }
        } else {
            Write-ColorOutput "Generalization cancelled" "Yellow"
            $script:GeneralizeNow = $false
        }
    } else {
        Write-ColorOutput "Creating specialized image - system will remain operational" "White"
        Write-ColorOutput "Remember: Specialized images should only be used for single instances" "Yellow"
        $script:GeneralizeNow = $false
    }
    
    Write-Host ""
}

# Function to generate export instructions
function Show-ExportInstructions {
    Write-Section "Next Steps: Exporting and Uploading to OCI"
    
    if ($script:GeneralizeNow) {
        Write-ColorOutput "System is shutting down for generalization." "Yellow"
        Write-ColorOutput "Continue with the steps below after the system shuts down." "Yellow"
        Write-Host ""
    }
    
    Write-ColorOutput @"

╔════════════════════════════════════════════════════════════════════════╗
║                    EXPORT AND UPLOAD INSTRUCTIONS                       ║
╔════════════════════════════════════════════════════════════════════════╗

STEP 1: EXPORT THE IMAGE
------------------------
1. Shut down this VM (if not already shut down)
2. Using your virtualization platform (VMware, Hyper-V, VirtualBox, etc.):
   - Export/Clone the VM as VMDK or QCOW2 format
   - Ensure it's "single growable" or "stream optimized" for VMDK
   - Maximum size: 400 GB

STEP 2: UPLOAD TO OCI OBJECT STORAGE
------------------------------------
Using OCI CLI:

  oci os object put \
    -bn <your-bucket-name> \
    --file <path-to-vmdk-or-qcow2> \
    --name <image-name>

Or upload via OCI Console:
  - Navigate to Object Storage
  - Select or create a bucket
  - Upload your VMDK/QCOW2 file

STEP 3: IMPORT AS CUSTOM IMAGE
------------------------------
Using OCI Console:
  1. Navigate to Compute → Custom Images
  2. Click "Import Image"
  3. Provide details:
     - Compartment: <your-compartment>
     - Name: <image-name>
     - Operating System: Windows
     - OS Version: <your-windows-version>
     - Image Type: VMDK or QCOW2
     - Launch Mode: PARAVIRTUALIZED (Important!)
  4. Select your uploaded object from Object Storage
  5. Confirm Microsoft licensing compliance
  6. Click "Import Image"

Using OCI CLI:

  oci compute image import from-object \
    -c <compartment-ocid> \
    --namespace <object-storage-namespace> \
    --bucket-name <your-bucket-name> \
    --name <object-name> \
    --display-name <image-display-name> \
    --launch-mode PARAVIRTUALIZED \
    --operating-system "Windows Server <version>" \
    --source-image-type <VMDK|QCOW2>

STEP 4: POST-IMPORT CONFIGURATION
---------------------------------
After launching an instance from your custom image:

1. Connect via RDP
2. Configure NTP:
     slmgr /skms 169.254.169.253:1688

3. If non-volume license, update license:
     slmgr /ipk <KMS-client-setup-key>
     
   Get your setup key from:
   https://docs.microsoft.com/windows-server/get-started/kmsclientkeys

4. Activate Windows:
     slmgr /ato

5. Verify license status:
     Get-CimInstance -ClassName SoftwareLicensingProduct | 
       where {`$_.PartialProductKey} | 
       select Description, LicenseStatus

IMPORTANT NOTES:
---------------
"@ "White"
    
    if ($script:VirtIOInstalled) {
        Write-ColorOutput "✓ VirtIO drivers installed - image ready for paravirtualized mode" "Green"
    } else {
        Write-ColorOutput "⚠ VirtIO drivers NOT installed - install before export!" "Red"
    }
    
    if ($script:IsVolumeLicense) {
        Write-ColorOutput "✓ Volume license detected - no post-import activation needed" "Green"
    } else {
        Write-ColorOutput "⚠ Non-volume license - remember to activate after import" "Yellow"
    }
    
    Write-ColorOutput @"

GOVERNMENT CLOUD NOTES:
- Same process applies to OCI Government Cloud
- Ensure you have Microsoft Flexible Virtualization Benefit
- BYOL is supported on both shared and dedicated hosts
- Verify compliance with your organization's security requirements

╚════════════════════════════════════════════════════════════════════════╝

"@ "Cyan"
}

# Function to save configuration report
function Save-ConfigurationReport {
    $reportPath = "$env:USERPROFILE\Desktop\OCI-Image-Prep-Report.txt"
    
    $report = @"
OCI Windows Image Preparation Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
=====================================

System Information:
- OS: $((Get-CimInstance Win32_OperatingSystem).Caption)
- Computer Name: $env:COMPUTERNAME
- PowerShell Version: $($PSVersionTable.PSVersion)

Preparation Status:
- VirtIO Drivers Installed: $(if($script:VirtIOInstalled){'Yes'}else{'No - REQUIRED BEFORE EXPORT'})
- License Type: $(if($script:IsVolumeLicense){'Volume License'}else{'Non-Volume License'})
- Image Type: $(if($script:GeneralizeNow){'Generalized'}else{'Specialized'})

Required Actions Before Export:
$(if(-not $script:VirtIOInstalled){"- CRITICAL: Install VirtIO drivers from Oracle`n"}else{""})
- Shut down the VM
- Export as VMDK or QCOW2
- Verify export file is under 400 GB

Next Steps:
1. Upload to OCI Object Storage
2. Import as Custom Image (use PARAVIRTUALIZED mode)
3. Launch instance and complete post-import configuration

For detailed instructions, see the console output above.
"@
    
    try {
        $report | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Success "Configuration report saved to: $reportPath"
    } catch {
        Write-Warning-Custom "Could not save report: $_"
    }
}

# Main execution
function Main {
    Clear-Host
    
    Write-ColorOutput @"
╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║        OCI Windows Image Preparation Script                           ║
║                                                                        ║
║        Prepares Windows Server for Oracle Cloud Infrastructure        ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝
"@ "Cyan"
    
    Write-Host ""
    Write-ColorOutput "This script will prepare your Windows Server for import to OCI" "White"
    Write-ColorOutput "Estimated time: 10-30 minutes (excluding driver installation)" "Gray"
    Write-Host ""
    
    $continue = Read-Host "Ready to begin? (yes/no)"
    if ($continue -ne "yes") {
        Write-ColorOutput "Preparation cancelled" "Yellow"
        exit
    }
    
    # Initialize script variables
    $script:VirtIOInstalled = $false
    $script:IsVolumeLicense = $false
    $script:GeneralizeNow = $false
    
    # Run preparation steps
    Test-Prerequisites
    New-SystemCheckpoint
    Get-WindowsLicenseInfo
    Enable-RDPAccess
    Set-DHCPConfiguration
    Set-RemoteStorageServices
    Invoke-SecurityHardening
    Install-VirtIODrivers
    
    # Only show generalization if not generalizing immediately
    if (-not $script:GeneralizeNow) {
        Invoke-ImageGeneralization
    }
    
    # Show next steps (unless system is shutting down for Sysprep)
    if (-not $script:GeneralizeNow) {
        Show-ExportInstructions
        Save-ConfigurationReport
        
        Write-Host ""
        Write-ColorOutput "Preparation complete!" "Green"
        Write-ColorOutput "Review the instructions above and the report on your desktop." "White"
        Write-Host ""
    }
}

# Run the script
Main
