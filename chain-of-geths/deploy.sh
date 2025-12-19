#!/bin/bash

# Deploy script to set up the Geth chain on AWS VM from local machine
# Assumes SSH key is set up for passwordless login

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Install prerequisites if not present
if ! command -v aws &> /dev/null || ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo "Installing prerequisites..."
    sudo apt update
    sudo apt install -y unzip ca-certificates curl gnupg lsb-release

    # AWS CLI
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi

    # Docker
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo usermod -aG docker $USER
    fi

    # Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
fi

VM_IP="13.220.218.223"
VM_USER="ubuntu"

# Update this to your PEM key path. Note: don't quote ~ (tilde expansion doesn't happen in quotes).
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/Downloads/chain-of-geths.pem}"

WINDOWS_IP="18.232.131.32"
# Get Windows instance ID from IP
WINDOWS_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=network-interface.addresses.association.public-ip,Values=$WINDOWS_IP" --query 'Reservations[].Instances[].InstanceId' --output text)

echo "Generating keys locally..."
./generate-keys.sh

echo "Building Docker images locally..."
./build-images.sh

echo "Saving Docker images..."
mkdir -p images
for version in v1.10.23 v1.8.27 v1.6.7 v1.3.6; do
    docker save ethereumtimemachine/geth:$version > images/geth-$version.tar
done

echo "Copying files to VM..."

# Ensure remote directory exists before copying.
ssh -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" "mkdir -p /home/$VM_USER/chain-of-geths"

scp -i "$SSH_KEY_PATH" -r output images monitoring generate-keys.sh build-images.sh docker-compose.yml "$VM_USER@$VM_IP:/home/$VM_USER/chain-of-geths/"

echo "Running setup on Ubuntu VM..."
ssh -i "$SSH_KEY_PATH" "$VM_USER@$VM_IP" << 'EOF'
cd /home/ubuntu/chain-of-geths

# Load Docker images
for img in images/*.tar; do
    docker load < $img
done

# Start the chain
docker-compose up -d

echo "Chain started. Check logs with: docker-compose logs -f"
EOF

echo "Setting up Windows VM..."
WINDOWS_ENODE=$(cat output/windows_enode.txt)

# Optional: enforce a deterministic enode for Windows Geth v1.0.0
# by supplying a pre-generated nodekey.
WINDOWS_NODEKEY=$(cat output/data/v1.0.0/nodekey)
aws ssm send-command \
    --instance-ids $WINDOWS_INSTANCE_ID \
    --document-name AWS-RunPowerShellScript \
    --parameters commands="[
        'mkdir C:\\geth-data',
        'Set-Content -Path C:\\geth-data\\nodekey -Value \"$WINDOWS_NODEKEY\" -NoNewline',
        'Invoke-WebRequest -Uri https://github.com/ethereum/go-ethereum/releases/download/v1.0.0/Geth-Win64-20150729141955-1.0.0-0cdc764.zip -OutFile C:\\geth.zip',
        'Expand-Archive C:\\geth.zip C:\\geth',
        'cd C:\\geth',
        'Start-Process -FilePath .\\geth.exe -ArgumentList \"--datadir C:\\geth-data --nodekey C:\\geth-data\\nodekey --port 30308 --nodiscover --bootnodes $WINDOWS_ENODE --http --http.api eth,net,web3 --syncmode full --networkid 1\" -NoNewWindow'
    ]" \
    --output text

echo "Deployment complete."
