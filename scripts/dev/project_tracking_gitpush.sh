#!/bin/bash
#
# /opt/sentigee/scripts/dev/project_tracking_gitpush.sh
# Script to gather project information without self-deployment and push to GitHub
#
# This script logs operations in Eastern Time (EST/EDT) using a legible 12‑hour format.
# Example timestamp: 2025-03-02_203pm
#

# -----------------------------------------------------------------------------
# REQUIREMENTS CHECK
# -----------------------------------------------------------------------------
if ! command -v file >/dev/null 2>&1; then
    echo "Error: 'file' command not found. Please install it." >&2
    exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
    echo "Error: 'zip' command not found. Please install it." >&2
    exit 1
fi
if ! command -v git >/dev/null 2>&1; then
    echo "Error: 'git' command not found. Please install it." >&2
    exit 1
fi

# Define utility commands with their absolute paths (if needed)
FILE_CMD=$(command -v file)
ZIP_CMD=$(command -v zip)
GIT_CMD=$(command -v git)

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
base_dir="/opt/sentigee"
output_dir="/opt/sentigee/scripts/dev/output/project_tracking"
# Generate timestamp in Eastern Time in a legible 12‑hour format (e.g., 2025-03-02_203pm)
timestamp=$(TZ='America/New_York' date +"%Y-%m-%d_%-l%M%P")
systemd_dir="/etc/systemd/system"

# Git repository configuration
git_repo_name="sentigee-194"
git_repo_dir="/tmp/sentigee-194-repo"
github_user="Frimpe01"

# Create output directory and set up files with timestamp in their names.
mkdir -p "$output_dir"
structure_file="$output_dir/${timestamp}_src_files_list.txt"
references_file="$output_dir/${timestamp}_FileReferences.txt"
index_file="$output_dir/${timestamp}_index.txt"
zip_file="$output_dir/${timestamp}_project_files.zip"

# -----------------------------------------------------------------------------
# Instead of a by_type folder, we duplicate the entire structure into all_copy.
# Remove any previous copy so that only the current run is present.
all_copy_dir="$output_dir/all_copy"
rm -rf "$all_copy_dir"
mkdir -p "$all_copy_dir"

# -----------------------------------------------------------------------------
# SKIP_DIRS:
# Only skip directories that hold compiled or third‑party libraries.
# -----------------------------------------------------------------------------
SKIP_DIRS=(
    "node_modules"
    "__pycache__"
    ".venv"
    "venv"
    "site-packages"
    "dist-packages"
)

# -----------------------------------------------------------------------------
# EXTENSIONS TO PROCESS:
# Only source file extensions. (Compiled files like .pyc are now skipped.)
# -----------------------------------------------------------------------------
extensions=("py" "html" "jsx" "sh" "json" "service" "css" "js" "babelrc" "env")

# -----------------------------------------------------------------------------
# LOGGING FUNCTION
# -----------------------------------------------------------------------------
log_operation() {
    local msg="$1"
    echo "$(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P') - $msg"
}

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------
is_binary() {
    "$FILE_CMD" "$1" | grep -q "text" && return 1 || return 0
}

extract_python_references() {
    local file="$1"
    if ! is_binary "$file"; then
        grep -n -E 'import|from|open|Path\(' "$file" 2>/dev/null \
            | sed 's/^/    Line &/' \
            | sed "s|^|    $file references: |"
    fi
}

extract_html_references() {
    local file="$1"
    if ! is_binary "$file"; then
        grep -n -E '{% (extends|include)|url_for|static' "$file" 2>/dev/null \
            | sed 's/^/    Line &/' \
            | sed "s|^|    $file references: |"
    fi
}

# -----------------------------------------------------------------------------
# NEW: Array of compiled file extensions to ignore.
# -----------------------------------------------------------------------------
compiled_extensions=("pyc" "so" "o" "a" "dll")

# -----------------------------------------------------------------------------
# INITIALIZATION
# -----------------------------------------------------------------------------
init_files_with_headers() {
    {
        echo "Sentigee Project Files Structure"
        echo "Generated on: $(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P')"
        echo "================================================"
    } > "$structure_file"

    {
        echo "Sentigee Project Files References Analysis"
        echo "Generated on: $(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P')"
        echo "================================================"
    } > "$references_file"
}

append_structure() {
    echo "$1" >> "$structure_file"
}

append_references() {
    local file="$1"
    local refs="$2"
    {
        echo ""
        echo "File Reference Analysis for $file:"
        echo "$refs"
    } >> "$references_file"
}

# -----------------------------------------------------------------------------
# Writes the processed file content into the duplicated structure under all_copy.
# Each scanned file is output as a .txt file (appending .txt to the original relative path).
# -----------------------------------------------------------------------------
write_to_all_copy() {
    local source_file="$1"
    local content="$2"
    # Determine the relative path from base_dir.
    local rel_path="${source_file#$base_dir/}"
    local dest_file="$all_copy_dir/${rel_path}.txt"
    mkdir -p "$(dirname "$dest_file")"
    printf "%s\n" "$content" > "$dest_file"
}

# -----------------------------------------------------------------------------
# Process service files (from systemd_dir) similarly.
# They are copied under all_copy/systemd.
# -----------------------------------------------------------------------------
process_service_file() {
    local svc="$1"
    local rel_name="${svc##*/}"
    local dest_dir="$all_copy_dir/systemd"
    mkdir -p "$dest_dir"
    local content="=== File: ${rel_name} ===
=== Path: $svc ===
$(cat "$svc")
=== End of ${rel_name} ===
================================================"
    printf "%s\n" "$content" > "$dest_dir/${rel_name}.txt"
}

# -----------------------------------------------------------------------------
# DIRECTORY SCANNING FUNCTIONS
# -----------------------------------------------------------------------------
process_dir_recursively() {
    local dir="$1"
    local indent="$2"
    local base="$3"

    # Exclude the output directory (and its children such as all_copy) from being scanned.
    if [[ "$dir" == "$output_dir"* ]]; then
        log_operation "Skipping output directory: $dir"
        return
    fi

    # Check if this directory should be skipped based on SKIP_DIRS.
    for skip in "${SKIP_DIRS[@]}"; do
        if [[ "$(basename "$dir")" == "$skip" || "$dir" == *"$skip"* ]]; then
            log_operation "Skipping directory: $dir (matches '$skip')"
            return
        fi
    done

    log_operation "Scanning directory: $dir"
    append_structure "${indent}${dir#$base/}"

    shopt -s dotglob
    for item in "$dir"/*; do
        [ ! -e "$item" ] && continue

        if [ -d "$item" ]; then
            process_dir_recursively "$item" "${indent}    " "$base"
        elif [ -f "$item" ]; then
            process_single_file "$item" "$indent" "$base"
        fi
    done
}

process_single_file() {
    local file="$1"
    local indent="$2"
    local base_dir="$3"

    local filename
    filename="$(basename "$file")"
    local ext="${filename##*.}"

    # Skip file if its extension indicates a compiled library.
    for comp_ext in "${compiled_extensions[@]}"; do
        if [[ "$filename" == *.$comp_ext ]]; then
            log_operation "Skipping compiled library file: $file"
            return
        fi
    done

    append_structure "${indent}├── $filename"

    # Prepare the processed content.
    local rel_path="${file#$base_dir/}"
    local header="=== File: ${rel_path} ===
=== Path: $file ===
"
    local file_size
    file_size=$(stat -c %s "$file" 2>/dev/null || echo 0)
    if [ "$file_size" -gt 5000000 ]; then
        local large_header="${header}[File too large to include - $(numfmt --to=iec-i --suffix=B ${file_size})]
=== End of ${rel_path} ===
================================================"
        write_to_all_copy "$file" "$large_header"
        return
    fi

    if ! is_binary "$file"; then
        local content
        content="$(tr -d '\000' < "$file" 2>/dev/null)"
        header+="${content}
"
    else
        header+="[Binary file]
$("$FILE_CMD" "$file")
"
    fi

    header+="
=== End of ${rel_path} ===
================================================"
    write_to_all_copy "$file" "$header"

    # For .py and .html files, also collect reference analysis.
    case "$ext" in
        py)
            local py_refs
            py_refs="$(extract_python_references "$file")"
            [ -n "$py_refs" ] && append_references "$file" "$py_refs"
            ;;
        html)
            local html_refs
            html_refs="$(extract_html_references "$file")"
            [ -n "$html_refs" ] && append_references "$file" "$html_refs"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# GIT REPOSITORY FUNCTIONS
# -----------------------------------------------------------------------------
setup_git_repo() {
    log_operation "Setting up Git repository at $git_repo_dir"
    
    # Clean up existing directory if it exists
    rm -rf "$git_repo_dir"
    mkdir -p "$git_repo_dir"
    
    # Initialize new git repository
    cd "$git_repo_dir" || {
        log_operation "Error: Failed to change to git repository directory"
        return 1
    }
    
    "$GIT_CMD" init
    "$GIT_CMD" config user.name "Sentigee Automation"
    "$GIT_CMD" config user.email "automation@sentigee.com"
    
    # Create a README.md file
    cat > README.md << EOF
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

This repository is automatically updated using the \`project_tracking_gitpush.sh\` script which captures the current state of the Sentigee project files.

Last updated: $(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P')
EOF
    
    "$GIT_CMD" add README.md
    "$GIT_CMD" commit -m "Initial commit with README"
    
    return 0
}

copy_files_to_repo() {
    log_operation "Copying files to git repository structure"
    
    # Create the basic directory structure
    mkdir -p "$git_repo_dir/EmailRelay"
    mkdir -p "$git_repo_dir/web"
    mkdir -p "$git_repo_dir/scripts"
    mkdir -p "$git_repo_dir/config"
    mkdir -p "$git_repo_dir/docs"
    mkdir -p "$git_repo_dir/systemd"
    
    # Copy files from base_dir to git_repo_dir, preserving structure but excluding skipped directories
    cd "$base_dir" || return 1
    
    # Use find to copy files, excluding directories in SKIP_DIRS
    local exclude_args=""
    for dir in "${SKIP_DIRS[@]}"; do
        exclude_args="$exclude_args -o -path '*/$dir/*'"
    done
    
    find . -type f ! -path "*/output/project_tracking/*" ! -path "*/node_modules/*" ! -path "*/__pycache__/*" ! -path "*/.venv/*" ! -path "*/venv/*" ! -path "*/site-packages/*" ! -path "*/dist-packages/*" -exec bash -c '
        file="$1"
        dest="$2/$file"
        dest_dir=$(dirname "$dest")
        mkdir -p "$dest_dir"
        cp "$file" "$dest"
    ' _ {} "$git_repo_dir" \;
    
    # Copy systemd service files
    if [ -d "$systemd_dir" ]; then
        find "$systemd_dir" -type f -name "sentigee*.service" -exec cp {} "$git_repo_dir/systemd/" \;
    fi
    
    return 0
}

push_to_github() {
    log_operation "Preparing for GitHub repository: $github_user/$git_repo_name"
    
    cd "$git_repo_dir" || return 1
    
    # Add all files
    "$GIT_CMD" add .
    
    # Commit with timestamp
    "$GIT_CMD" commit -m "Sentigee project state as of $(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P')"
    
    # Check if the repository exists
    if ! curl -s -o /dev/null -w "%{http_code}" "https://github.com/$github_user/$git_repo_name" | grep -q "200"; then
        log_operation "Repository $github_user/$git_repo_name does not exist or is not accessible"
        log_operation "Please create the repository manually at https://github.com/new"
        log_operation "Then run the following commands to push the repository:"
        echo ""
        echo "cd $git_repo_dir"
        echo "git remote add origin https://github.com/$github_user/$git_repo_name.git"
        echo "git push -u origin main"
        echo ""
    else
        # Configure remote
        "$GIT_CMD" remote add origin "https://github.com/$github_user/$git_repo_name.git"
        
        # Push to GitHub - note this will require authentication
        # For automation, you should set up SSH keys or personal access tokens
        log_operation "Repository exists. To push changes, run:"
        echo ""
        echo "cd $git_repo_dir"
        echo "git push -u origin main"
        echo ""
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION FLOW
# -----------------------------------------------------------------------------
init_files_with_headers
log_operation "Starting project file tracking and GitHub preparation"

# 1) Scan the base directory, skipping unwanted directories.
if [ -d "$base_dir" ]; then
    process_dir_recursively "$base_dir" "" "$base_dir"
else
    log_operation "Error: Directory $base_dir does not exist"
    exit 1
fi

# 2) Process systemd service files.
if [ -d "$systemd_dir" ]; then
    find "$systemd_dir" -type f -name "sentigee*.service" | sort | while read -r svc; do
        process_service_file "$svc"
    done
fi

# 3) (Optional) Gather counts and append summaries based on the structure file.
total_files=$(grep -c '├──' "$structure_file" 2>/dev/null || echo 0)

# Create an index file with a summary.
{
    echo "Sentigee Project Files Index"
    echo "Generated on: $(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P')"
    echo "================================================"
    echo ""
    echo "Total files processed: $total_files"
    echo ""
    echo "OUTPUT DIRECTORY:"
    echo "$output_dir"
    echo ""
    echo "GIT REPOSITORY:"
    echo "$git_repo_dir"
} > "$index_file"

# 4) Archive the current run's output.
log_operation "Creating archive of current run files: $zip_file"
# Zip the structure, references, index files and the entire all_copy directory preserving structure.
"$ZIP_CMD" -r "$zip_file" "$structure_file" "$references_file" "$index_file" "$all_copy_dir"

# 5) Housekeeping: Remove older .txt files from output_dir that do not match the current run timestamp.
log_operation "Removing older .txt files from previous runs (keeping current run)."
find "$output_dir" -maxdepth 1 -type f -name '*.txt' ! -name "*${timestamp}*.txt" -exec rm -f {} \;

# 6) Setup and push to GitHub repository
setup_git_repo && copy_files_to_repo && push_to_github

# 7) Output final summary.
echo ""
echo "=============================================="
echo "PROJECT FILE SCANNING AND GIT REPO PREPARATION COMPLETE"
echo "=============================================="
echo ""
echo "Total files processed (as per structure file): $total_files"
echo ""
echo "All output text files (duplicated structure) are in: $all_copy_dir"
echo "The archive for this run is:  $zip_file"
echo "Git repository prepared at: $git_repo_dir"
echo ""
echo "$(TZ='America/New_York' date '+%Y-%m-%d_%-l%M%P') - Project file tracking and Git repository preparation completed"