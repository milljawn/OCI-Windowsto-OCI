# Windows Server to OCI Migration Toolkit

Complete automation toolkit for preparing, uploading, and importing Windows Server images to Oracle Cloud Infrastructure (OCI).

## Overview

This toolkit consists of two scripts that automate the entire process of migrating Windows Server VMs to OCI:

1. **Prepare-WindowsForOCI.ps1** - PowerShell script (runs on Windows Server)
2. **upload-and-import-to-oci.sh** - Bash script (runs on Linux/Mac with OCI CLI)

## Prerequisites

### For Windows Preparation (Prepare-WindowsForOCI.ps1)

- Windows Server 2016, 2019, 2022, or 2025
- PowerShell 5.1 or higher
- Administrator privileges
- Active internet connection
- At least 10GB free disk space

### For OCI Upload & Import (upload-and-import-to-oci.sh)

- OCI CLI installed and configured
- Linux or macOS system
- Bash shell
- Network access to OCI
- Prepared Windows image file (VMDK or QCOW2)

## Quick Start Guide

### Phase 1: Prepare Windows Image (On Windows Server)

1. **Download the preparation script** to your Windows Server:
   ```powershell
   # Download Prepare-WindowsForOCI.ps1 to your server
   ```

2. **Run as Administrator**:
   ```powershell
   # Right-click PowerShell and "Run as Administrator"
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   .\Prepare-WindowsForOCI.ps1
   ```

3. **Follow the interactive prompts**:
   - System prerequisites check
   - License information review
   - RDP configuration
   - DHCP setup
   - **VirtIO driver installation** (critical!)
   - Optional: Security hardening
   - Optional: Image generalization (Sysprep)

4. **After preparation**:
   - Shut down the VM
   - Export/clone as VMDK or QCOW2 using your virtualization platform

### Phase 2: Upload & Import (On Linux/Mac with OCI CLI)

1. **Make script executable**:
   ```bash
   chmod +x upload-and-import-to-oci.sh
   ```

2. **Run the script**:
   ```bash
   ./upload-and-import-to-oci.sh
   ```

3. **Provide required information**:
   - Path to your Windows image file
   - OCI region
   - Compartment OCID
   - Bucket name
   - Image name
   - Windows version

4. **Wait for completion** (10-30 minutes depending on image size)

### Phase 3: Post-Import Configuration (On OCI Instance)

1. **Launch instance** from your custom image
2. **Connect via RDP** to the instance
3. **Configure Windows licensing**:
   ```powershell
   # Set KMS server
   slmgr /skms 169.254.169.253:1688
   
   # If non-volume license, set product key
   slmgr /ipk <YOUR-KMS-CLIENT-SETUP-KEY>
   
   # Activate Windows
   slmgr /ato
   
   # Verify
   slmgr /dli
   ```

## Detailed Feature Documentation

### Prepare-WindowsForOCI.ps1 Features

#### System Checks
- ✅ Validates Windows Server version (2016/2019/2022/2025)
- ✅ Checks PowerShell version (5.1+)
- ✅ Verifies administrator privileges
- ✅ Monitors disk space availability

#### License Management
- ✅ Detects volume vs. non-volume licensing
- ✅ Provides guidance for post-import activation
- ✅ Displays current license status

#### Network Configuration
- ✅ Enables Remote Desktop Protocol (RDP)
- ✅ Configures firewall rules for all network profiles
- ✅ Sets all network adapters to DHCP
- ✅ Removes hardcoded MAC addresses

#### VirtIO Driver Installation
- ✅ Provides download instructions
- ✅ Guides through installation process
- ✅ Critical for paravirtualized mode performance

#### Security Hardening
- ✅ Enables Windows Firewall
- ✅ Provides guidance for service management
- ✅ Recommends security best practices

#### Image Generalization
- ✅ Optional Sysprep for multi-instance deployment
- ✅ Creates specialized images for single instances
- ✅ Protects original system with checkpoints

#### Reporting
- ✅ Generates detailed preparation report
- ✅ Saves to desktop for reference
- ✅ Includes all configuration details

### upload-and-import-to-oci.sh Features

#### Validation
- ✅ Verifies OCI CLI installation
- ✅ Confirms OCI CLI configuration
- ✅ Checks image file existence and size
- ✅ Validates image format (VMDK/QCOW2)

#### Object Storage
- ✅ Creates or uses existing bucket
- ✅ Uploads image with progress indication
- ✅ Verifies upload completion
- ✅ Handles large files efficiently

#### Custom Image Import
- ✅ Imports with PARAVIRTUALIZED launch mode
- ✅ Sets correct Windows version
- ✅ Waits for import completion
- ✅ Returns image OCID

#### Results & Documentation
- ✅ Displays next steps clearly
- ✅ Provides CLI commands for instance launch
- ✅ Includes licensing configuration steps
- ✅ Saves results to file

## Important Notes

### VirtIO Drivers (CRITICAL)

**You MUST install VirtIO drivers** before exporting your Windows image. Without these drivers:
- Image will not boot in paravirtualized mode
- Performance will be significantly degraded
- Network connectivity may not work

Download from: https://docs.oracle.com/en/operating-systems/oracle-linux/kvm-virtio/

### Image Requirements

- **Format**: VMDK (single growable or stream optimized) or QCOW2
- **Maximum size**: 400 GB
- **Boot configuration**: BIOS (can change to UEFI after import)
- **Disk**: Single boot disk only
- **Network**: DHCP configured
- **No hardcoded MAC addresses**

### Licensing

#### Microsoft Flexible Virtualization Benefit
Since October 2022, Microsoft allows BYOL for Windows Server on **both shared and dedicated hosts** in OCI when you have:
- Software Assurance, OR
- Subscription licenses

This applies to OCI (including Government Cloud) as an "Authorized Outsourcer."

#### Volume vs. Non-Volume Licenses
- **Volume License**: No post-import activation needed
- **Non-Volume License**: Must activate with KMS after import

Get KMS client setup keys from:
https://docs.microsoft.com/windows-server/get-started/kmsclientkeys

### Government Cloud Support

Both scripts work identically for OCI Government Cloud:
- Same preparation process
- Same import procedure
- BYOL supported on shared and dedicated hosts
- Ensure compliance with security requirements

## Troubleshooting

### Image Won't Boot in OCI

**Problem**: Instance fails to boot or is inaccessible
**Solution**: 
- Verify VirtIO drivers were installed before export
- Check that image was imported with PARAVIRTUALIZED mode
- Ensure image size is under 400 GB
- Verify DHCP is configured

### License Activation Fails

**Problem**: Windows activation fails after import
**Solution**:
- Ensure time is correctly configured (NTP)
- Verify KMS server is set to 169.254.169.253:1688
- Check that correct KMS client setup key is used
- Wait up to 48 hours for license status to update
- Verify network security rules allow KMS traffic

### Upload Takes Too Long

**Problem**: Image upload to Object Storage is very slow
**Solution**:
- Check network bandwidth
- Upload from a system closer to OCI region
- Consider using OCI FastConnect for large transfers
- Break into smaller chunks if necessary

### Cannot Connect via RDP

**Problem**: RDP connection fails after launch
**Solution**:
- Verify security list allows TCP port 3389
- Check Windows Firewall settings in VNC console
- Ensure RDP is enabled in Windows
- Verify public IP is correct
- Check instance state is RUNNING

## Advanced Usage

### Automated Deployment

You can chain these scripts together in a CI/CD pipeline:

```bash
# 1. Prepare image (on Windows)
powershell.exe -ExecutionPolicy Bypass -File Prepare-WindowsForOCI.ps1

# 2. Export image (using virtualization tools)
# ... platform-specific export commands ...

# 3. Upload and import (on Linux)
./upload-and-import-to-oci.sh
```

### Custom Configuration

Both scripts can be modified for specific requirements:

- **Prepare-WindowsForOCI.ps1**: Edit security hardening steps
- **upload-and-import-to-oci.sh**: Adjust timeout values or add tags

### Multiple Images

To prepare multiple images:

```bash
# Process each image
for image in *.vmdk; do
    IMAGE_FILE="$image" ./upload-and-import-to-oci.sh
done
```

## Support & Resources

### Official Documentation

- [OCI Custom Image Import](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/importingcustomimagewindows.htm)
- [Microsoft Licensing on OCI](https://docs.oracle.com/en-us/iaas/Content/Compute/References/microsoftlicensing.htm)
- [Oracle VirtIO Drivers](https://docs.oracle.com/en/operating-systems/oracle-linux/kvm-virtio/)
- [Microsoft Flexible Virtualization Benefit](https://www.microsoft.com/licensing/news/options-for-hosted-cloud)

### Common Questions

**Q: Can I use these scripts for Windows 10/11?**
A: These scripts are designed for Windows Server. Windows 10/11 requires BYOL and dedicated VM hosts.

**Q: Do I need to shut down the VM before running the preparation script?**
A: No, the script runs on the live system. Shutdown only when exporting the image.

**Q: Can I use this for Government Cloud?**
A: Yes! The process is identical. Just specify your Government Cloud region.

**Q: How long does the entire process take?**
A: Typically 1-2 hours total:
- Preparation: 15-30 minutes
- Export: 10-30 minutes (depends on platform)
- Upload: 10-60 minutes (depends on image size and bandwidth)
- Import: 10-30 minutes

**Q: What if I don't have access to install VirtIO drivers?**
A: VirtIO drivers are REQUIRED. Without them, the image won't work properly in OCI. You must have the ability to install drivers before proceeding.

## Version History

**v1.0** - Initial release
- Windows Server preparation automation
- OCI upload and import automation
- Comprehensive error handling
- Interactive guided workflow

## License

These scripts are provided as-is for use in preparing Windows Server images for Oracle Cloud Infrastructure. Always follow Microsoft licensing terms and Oracle Cloud policies.

## Contributing

Improvements and suggestions are welcome. Please test thoroughly before submitting changes.

---

**Created for OCI Windows Server migration projects**
**Supporting Government Cloud and Commercial Cloud deployments**
