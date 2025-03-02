#!/bin/bash
#
# /opt/sentigee/scripts/dev/prepare_github_push.sh
# Script to prepare files for GitHub push without direct authentication
#
# This script creates a structured export that can be easily pushed to GitHub
# using external tools or web interfaces.

# Generate timestamp in Eastern Time (12-hour format with AM/PM)
timestamp=$(TZ='America/New_York' date +"%Y-%m-%d_%-l%M%P")
export_dir="/tmp/sentigee-github-export"
repo_name="sentigee-194"

# Create a fresh export directory
rm -rf "$export_dir"
mkdir -p "$export_dir"

# First run the project tracking script
echo "Running project tracking script..."
/opt/sentigee/scripts/dev/project_tracking.sh

# Create a README file in the export directory
cat > "$export_dir/README.md" << EOF
# Sentigee Mail Relay Project

This repository contains the source code for the Sentigee mail relay system, which provides:

- SMTP server relay through Microsoft 365 using OAuth2 authentication
- Web interface for configuration and monitoring
- Secure connection options with SSL/TLS

## Project Structure

The project is organized with the following components:

- **web/**: Flask web application for configuration
- **EmailRelay/**: Core mail relay functionality
- **scripts/**: Utility and setup scripts
- **systemd/**: Service configuration files

## Repository Automation

This export was created on: $timestamp
EOF

# Copy the current project structure
echo "Creating export of source files..."
mkdir -p "$export_dir/scripts/dev"
mkdir -p "$export_dir/web"
mkdir -p "$export_dir/EmailRelay"
mkdir -p "$export_dir/config"
mkdir -p "$export_dir/docs"
mkdir -p "$export_dir/systemd"

# Copy the script files
cp /opt/sentigee/scripts/dev/project_tracking.sh "$export_dir/scripts/dev/"
cp /opt/sentigee/scripts/dev/project_tracking_gitpush.sh "$export_dir/scripts/dev/"
cp /opt/sentigee/scripts/dev/filesList.sh "$export_dir/scripts/dev/" 2>/dev/null || true

# Copy project tracking output (just the current run)
tracking_dir="/opt/sentigee/scripts/dev/output/project_tracking"
latest_archive=$(find "$tracking_dir" -name "*.zip" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$latest_archive" ]; then
    mkdir -p "$export_dir/archive"
    cp "$latest_archive" "$export_dir/archive/"
    echo "Included latest project archive: $(basename "$latest_archive")"
fi

# Create a README for the scripts directory
cat > "$export_dir/scripts/dev/README.md" << EOF
# Development Scripts

This directory contains scripts used for development and administration of the Sentigee project.

## project_tracking.sh

This script scans the entire Sentigee project structure, logs all files and directories, and creates a snapshot of the current state.

## project_tracking_gitpush.sh

An enhanced version of project_tracking.sh that additionally creates a Git repository with the project files.

## prepare_github_push.sh

This script (the one that created this export) prepares a structured directory for easy GitHub uploading.
EOF

# Create instructions for uploading
cat > "$export_dir/UPLOAD_INSTRUCTIONS.md" << EOF
# GitHub Upload Instructions

This directory contains an export of the Sentigee project prepared for GitHub upload.

## Option 1: Using GitHub Web Interface

1. Go to https://github.com/Frimpe01/$repo_name
2. Use the "Add file" dropdown and select "Upload files"
3. Drag and drop files from this directory
4. Add a commit message (e.g., "Update project files as of $timestamp")
5. Click "Commit changes"

## Option 2: Using Git Command Line

If you have Git and GitHub credentials configured on your computer:

\`\`\`bash
# Clone the repository
git clone https://github.com/Frimpe01/$repo_name.git
cd $repo_name

# Copy files from this export directory
cp -r $export_dir/* .

# Commit and push
git add .
git commit -m "Update project files as of $timestamp"
git push
\`\`\`

## Option 3: Using GitHub Desktop

1. Open GitHub Desktop
2. Clone the repository: Frimpe01/$repo_name
3. Copy the files from this export directory to the local repository
4. Commit with message: "Update project files as of $timestamp"
5. Push to GitHub
EOF

echo "Export completed successfully!"
echo "Files are ready for GitHub upload at: $export_dir"
echo ""
echo "Follow the instructions in $export_dir/UPLOAD_INSTRUCTIONS.md to complete the GitHub push."