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

This repository is automatically updated using the `project_tracking_gitpush.sh` script which captures the current state of the Sentigee project files.

Last updated: 2025-03-02_209pm