#!/bin/bash

################################################################################
# OCI Windows Image Upload and Import Script
# 
# This script automates uploading a Windows VMDK/QCOW2 image to OCI Object 
# Storage and importing it as a custom compute image.
#
# Prerequisites:
# - OCI CLI installed and configured
# - Windows image prepared using Prepare-WindowsForOCI.ps1
# - Image file (VMDK or QCOW2) accessible locally
################################################################################

set -e  # Exit on error

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_step() {
    echo -e "${YELLOW}>>> $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if OCI CLI is installed
    if ! command -v oci &> /dev/null; then
        print_error "OCI CLI is not installed"
        echo ""
        echo "Install OCI CLI:"
        echo "  bash -c \"\$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)\""
        echo ""
        echo "Or visit: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
        exit 1
    fi
    print_success "OCI CLI is installed"
    
    # Check OCI CLI version
    OCI_VERSION=$(oci --version 2>&1 | head -n 1)
    print_info "OCI CLI Version: $OCI_VERSION"
    
    # Check if OCI CLI is configured
    if ! oci iam region list &> /dev/null; then
        print_error "OCI CLI is not configured"
        echo ""
        echo "Configure OCI CLI:"
        echo "  oci setup config"
        echo ""
        exit 1
    fi
    print_success "OCI CLI is configured"
    
    echo ""
}

# Function to get user inputs
get_user_inputs() {
    print_header "Configuration"
    
    # Image file path
    while true; do
        read -p "Enter the full path to your Windows image file (VMDK or QCOW2): " IMAGE_FILE
        IMAGE_FILE="${IMAGE_FILE/#\~/$HOME}"  # Expand ~ to home directory
        
        if [[ -f "$IMAGE_FILE" ]]; then
            IMAGE_SIZE=$(du -h "$IMAGE_FILE" | cut -f1)
            IMAGE_SIZE_BYTES=$(stat -f%z "$IMAGE_FILE" 2>/dev/null || stat -c%s "$IMAGE_FILE" 2>/dev/null)
            IMAGE_SIZE_GB=$((IMAGE_SIZE_BYTES / 1024 / 1024 / 1024))
            
            print_success "Image file found: $IMAGE_FILE"
            print_info "Image size: $IMAGE_SIZE (~${IMAGE_SIZE_GB}GB)"
            
            if [[ $IMAGE_SIZE_GB -gt 400 ]]; then
                print_error "Image size exceeds 400GB limit for OCI custom images"
                exit 1
            fi
            
            # Detect image type
            if [[ "$IMAGE_FILE" == *.vmdk ]]; then
                IMAGE_TYPE="VMDK"
            elif [[ "$IMAGE_FILE" == *.qcow2 ]]; then
                IMAGE_TYPE="QCOW2"
            else
                print_error "Image file must be .vmdk or .qcow2"
                exit 1
            fi
            print_info "Detected image type: $IMAGE_TYPE"
            break
        else
            print_error "File not found: $IMAGE_FILE"
        fi
    done
    
    echo ""
    
    # Get OCI region
    print_step "Fetching available regions..."
    REGIONS=$(oci iam region list --query 'data[*].name' --raw-output 2>/dev/null | tr '\n' ' ')
    echo "Available regions: $REGIONS"
    echo ""
    
    # Show current region
    CURRENT_REGION=$(oci iam region list --query 'data[?"is-home-region"==`true`].name | [0]' --raw-output 2>/dev/null || echo "")
    if [[ -n "$CURRENT_REGION" ]]; then
        print_info "Your home region: $CURRENT_REGION"
    fi
    
    read -p "Enter OCI region (or press Enter to use home region): " OCI_REGION
    if [[ -z "$OCI_REGION" ]]; then
        OCI_REGION=$CURRENT_REGION
    fi
    print_info "Using region: $OCI_REGION"
    
    echo ""
    
    # Get compartment OCID
    print_step "Enter your compartment information"
    echo "You can find compartment OCIDs in OCI Console: Identity & Security > Compartments"
    read -p "Enter compartment OCID: " COMPARTMENT_OCID
    
    echo ""
    
    # Get or create bucket
    print_step "Object Storage Bucket"
    read -p "Enter Object Storage bucket name (will be created if it doesn't exist): " BUCKET_NAME
    
    echo ""
    
    # Get object name
    IMAGE_FILENAME=$(basename "$IMAGE_FILE")
    read -p "Enter object name in bucket (default: $IMAGE_FILENAME): " OBJECT_NAME
    if [[ -z "$OBJECT_NAME" ]]; then
        OBJECT_NAME=$IMAGE_FILENAME
    fi
    
    echo ""
    
    # Get image details
    print_step "Custom Image Details"
    read -p "Enter custom image name: " IMAGE_NAME
    
    echo ""
    echo "Select Windows version:"
    echo "  1) Windows Server 2016"
    echo "  2) Windows Server 2019"
    echo "  3) Windows Server 2022"
    echo "  4) Windows Server 2025"
    read -p "Enter selection (1-4): " WIN_VERSION_CHOICE
    
    case $WIN_VERSION_CHOICE in
        1) WINDOWS_VERSION="Windows Server 2016" ;;
        2) WINDOWS_VERSION="Windows Server 2019" ;;
        3) WINDOWS_VERSION="Windows Server 2022" ;;
        4) WINDOWS_VERSION="Windows Server 2025" ;;
        *) 
            print_error "Invalid selection"
            exit 1
            ;;
    esac
    
    echo ""
    
    # Summary
    print_header "Configuration Summary"
    echo "Image File:        $IMAGE_FILE"
    echo "Image Type:        $IMAGE_TYPE"
    echo "Image Size:        $IMAGE_SIZE"
    echo "OCI Region:        $OCI_REGION"
    echo "Compartment OCID:  $COMPARTMENT_OCID"
    echo "Bucket Name:       $BUCKET_NAME"
    echo "Object Name:       $OBJECT_NAME"
    echo "Image Name:        $IMAGE_NAME"
    echo "Windows Version:   $WINDOWS_VERSION"
    echo ""
    
    read -p "Proceed with this configuration? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        print_warning "Operation cancelled"
        exit 0
    fi
    
    echo ""
}

# Function to create or verify bucket
setup_bucket() {
    print_header "Setting Up Object Storage Bucket"
    
    print_step "Checking if bucket '$BUCKET_NAME' exists..."
    
    # Get namespace
    NAMESPACE=$(oci os ns get --query 'data' --raw-output 2>/dev/null)
    print_info "Object Storage namespace: $NAMESPACE"
    
    # Check if bucket exists
    if oci os bucket get --bucket-name "$BUCKET_NAME" --namespace "$NAMESPACE" &>/dev/null; then
        print_success "Bucket '$BUCKET_NAME' exists"
    else
        print_warning "Bucket '$BUCKET_NAME' does not exist"
        print_step "Creating bucket..."
        
        oci os bucket create \
            --compartment-id "$COMPARTMENT_OCID" \
            --name "$BUCKET_NAME" \
            --namespace "$NAMESPACE" \
            --region "$OCI_REGION" > /dev/null
        
        print_success "Bucket '$BUCKET_NAME' created"
    fi
    
    echo ""
}

# Function to upload image
upload_image() {
    print_header "Uploading Image to Object Storage"
    
    print_step "Uploading $IMAGE_FILE to bucket $BUCKET_NAME..."
    print_info "This may take a while depending on file size and network speed..."
    
    # Upload with progress
    oci os object put \
        --bucket-name "$BUCKET_NAME" \
        --namespace "$NAMESPACE" \
        --file "$IMAGE_FILE" \
        --name "$OBJECT_NAME" \
        --region "$OCI_REGION" \
        --force
    
    print_success "Image uploaded successfully"
    
    # Verify upload
    print_step "Verifying upload..."
    UPLOADED_SIZE=$(oci os object head \
        --bucket-name "$BUCKET_NAME" \
        --namespace "$NAMESPACE" \
        --name "$OBJECT_NAME" \
        --query 'content-length' \
        --raw-output 2>/dev/null)
    
    UPLOADED_SIZE_GB=$((UPLOADED_SIZE / 1024 / 1024 / 1024))
    print_success "Upload verified - Size: ${UPLOADED_SIZE_GB}GB"
    
    echo ""
}

# Function to import custom image
import_custom_image() {
    print_header "Importing Custom Image"
    
    print_step "Creating custom image '$IMAGE_NAME'..."
    print_info "This process can take 10-30 minutes depending on image size"
    
    # Create import image request
    IMAGE_IMPORT_OUTPUT=$(oci compute image import from-object \
        --compartment-id "$COMPARTMENT_OCID" \
        --namespace "$NAMESPACE" \
        --bucket-name "$BUCKET_NAME" \
        --name "$OBJECT_NAME" \
        --display-name "$IMAGE_NAME" \
        --launch-mode PARAVIRTUALIZED \
        --operating-system "$WINDOWS_VERSION" \
        --source-image-type "$IMAGE_TYPE" \
        --region "$OCI_REGION" \
        --wait-for-state AVAILABLE \
        --max-wait-seconds 3600)
    
    # Extract image OCID
    IMAGE_OCID=$(echo "$IMAGE_IMPORT_OUTPUT" | grep '"id":' | head -n 1 | awk -F'"' '{print $4}')
    
    print_success "Custom image imported successfully"
    print_info "Image OCID: $IMAGE_OCID"
    
    echo ""
    
    # Get image details
    print_step "Retrieving image details..."
    IMAGE_STATE=$(oci compute image get --image-id "$IMAGE_OCID" --query 'data."lifecycle-state"' --raw-output)
    
    print_success "Image state: $IMAGE_STATE"
    
    echo ""
}

# Function to display next steps
show_next_steps() {
    print_header "Import Complete - Next Steps"
    
    cat << EOF

${GREEN}✓ Your Windows image has been successfully imported to OCI${NC}

${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}

${YELLOW}Image Details:${NC}
  Name:         $IMAGE_NAME
  OCID:         $IMAGE_OCID
  Region:       $OCI_REGION
  Launch Mode:  PARAVIRTUALIZED
  OS:           $WINDOWS_VERSION

${YELLOW}To Launch an Instance:${NC}

  ${BLUE}Via Console:${NC}
    1. Go to: Compute > Instances > Create Instance
    2. Under Image: Select "Custom Images"
    3. Choose: $IMAGE_NAME
    4. Configure instance shape and networking
    5. Launch instance

  ${BLUE}Via CLI:${NC}
    oci compute instance launch \\
      --compartment-id $COMPARTMENT_OCID \\
      --availability-domain <AD-NAME> \\
      --shape VM.Standard2.1 \\
      --image-id $IMAGE_OCID \\
      --subnet-id <SUBNET-OCID> \\
      --display-name "Windows-Instance"

${YELLOW}Post-Launch Configuration (via RDP):${NC}

  1. Connect to instance via RDP using public IP
  
  2. Configure KMS for licensing:
     ${BLUE}slmgr /skms 169.254.169.253:1688${NC}
  
  3. If non-volume license, set KMS client key:
     ${BLUE}slmgr /ipk <YOUR-KMS-CLIENT-SETUP-KEY>${NC}
     
     Get your key from:
     https://docs.microsoft.com/windows-server/get-started/kmsclientkeys
  
  4. Activate Windows:
     ${BLUE}slmgr /ato${NC}
  
  5. Verify license status:
     ${BLUE}slmgr /dli${NC}

${YELLOW}For Government Cloud:${NC}
  - Process is identical in Government Cloud regions
  - Ensure Microsoft Flexible Virtualization Benefit compliance
  - BYOL supported on both shared and dedicated hosts

${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}

${GREEN}Image import complete! You can now launch Windows instances.${NC}

EOF
}

# Function to save results
save_results() {
    RESULTS_FILE="$HOME/oci-image-import-results.txt"
    
    cat > "$RESULTS_FILE" << EOF
OCI Windows Image Import Results
Generated: $(date)
═══════════════════════════════════════════════════════════════

Configuration:
  Image File:         $IMAGE_FILE
  Image Type:         $IMAGE_TYPE
  OCI Region:         $OCI_REGION
  Compartment:        $COMPARTMENT_OCID
  Bucket:             $BUCKET_NAME
  Object Name:        $OBJECT_NAME

Image Details:
  Image Name:         $IMAGE_NAME
  Image OCID:         $IMAGE_OCID
  Windows Version:    $WINDOWS_VERSION
  Launch Mode:        PARAVIRTUALIZED
  State:              AVAILABLE

Next Steps:
1. Launch instance using image OCID: $IMAGE_OCID
2. Connect via RDP
3. Configure Windows licensing (see instructions above)

Generated by OCI Windows Image Import Script
EOF
    
    print_success "Results saved to: $RESULTS_FILE"
    echo ""
}

# Main execution
main() {
    clear
    
    cat << "EOF"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║              OCI Windows Image Upload & Import Script                     ║
║                                                                            ║
║              Upload VMDK/QCOW2 to OCI and create custom image             ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝

EOF
    
    echo "This script will:"
    echo "  1. Upload your Windows image to OCI Object Storage"
    echo "  2. Import it as a custom compute image"
    echo "  3. Configure it for paravirtualized mode"
    echo ""
    
    read -p "Ready to begin? (yes/no): " START
    if [[ "$START" != "yes" ]]; then
        print_warning "Operation cancelled"
        exit 0
    fi
    
    echo ""
    
    # Execute workflow
    check_prerequisites
    get_user_inputs
    setup_bucket
    upload_image
    import_custom_image
    show_next_steps
    save_results
    
    print_success "All operations completed successfully!"
}

# Run the script
main
EOF
