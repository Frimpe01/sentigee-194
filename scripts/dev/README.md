# Development Scripts

This directory contains scripts used for development and administration of the Sentigee project.

## project_tracking.sh

This script scans the entire Sentigee project structure, logs all files and directories, and creates a snapshot of the current state. It's useful for tracking changes over time and creates the following output files:

- A structured listing of all files and directories
- Reference analysis for Python and HTML files
- A text copy of each source file for future comparison
- A zip archive of all the above for easy access

## project_tracking_gitpush.sh

An enhanced version of `project_tracking.sh` that additionally:

1. Creates a Git repository with the Sentigee project files
2. Prepares the repository for pushing to GitHub
3. Copies all relevant files while maintaining the directory structure
4. Excludes common directories like `__pycache__`, `node_modules`, and virtual environments
5. Provides instructions for completing the GitHub push process

### Usage

```bash
# Run the script to track files and prepare Git repository
/opt/sentigee/scripts/dev/project_tracking_gitpush.sh

# Follow the displayed instructions to push to GitHub if needed
```

### Output

- `/opt/sentigee/scripts/dev/output/project_tracking/` - Contains all output files
- `/tmp/sentigee-194-repo/` - Temporary Git repository with the project files

## prepare_github_push.sh

A simpler alternative to `project_tracking_gitpush.sh` that creates an export package suitable for GitHub upload through multiple methods. This is useful when direct Git operations might not work due to authentication issues.

### Usage

```bash
# Run the script to create an export package
/opt/sentigee/scripts/dev/prepare_github_push.sh

# Follow the instructions in the output to complete the upload
```

### Output

- `/tmp/sentigee-github-export/` - Contains the export package with README and instructions
- `/tmp/sentigee-github-export/UPLOAD_INSTRUCTIONS.md` - Detailed upload instructions for different methods

### Features

- Creates a clean export with key project files
- Provides multiple options for uploading (web UI, command line, GitHub Desktop)
- Includes the latest project tracking archive
- No authentication required on the server side

### Requirements

The script requires the following tools:
- `file` - For identifying file types
- `zip` - For creating archives
- `git` - For Git operations