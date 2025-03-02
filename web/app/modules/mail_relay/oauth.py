# Path: /opt/sentigee/web/app/modules/mail_relay/oauth.py
"""
OAuth2 functionality for Mail Relay module.
"""
import os
import json
import logging
import urllib.parse
import requests
from datetime import datetime
from flask import request, redirect, url_for, current_app, flash, session, render_template

from app.modules.mail_relay import bp

# Load configuration from OAuth config file
def load_oauth_config():
    config_file = '/opt/sentigee/EmailRelay/oauth_config.json'
    
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Error loading OAuth config: {str(e)}")
    
    # Default configuration if file doesn't exist - credentials are placeholders
    return {
        'client_id': 'CLIENT_ID_PLACEHOLDER',
        'client_secret': 'CLIENT_SECRET_PLACEHOLDER',
        'tenant_id': 'TENANT_ID_PLACEHOLDER',
        'redirect_uri': 'https://sentigee.com:8443/mail_relay/callback',
        'authority': 'https://login.microsoftonline.com/',
        'scopes': [
            'https://graph.microsoft.com/Mail.Read',
            'https://graph.microsoft.com/Mail.Send',
            'https://graph.microsoft.com/User.Read',
            'offline_access'
        ]
    }

# Token storage path
TOKEN_PATH = '/opt/sentigee/EmailRelay/token_info.json'

# Configure logging
logger = logging.getLogger(__name__)

@bp.route('/initiate-oauth', methods=['POST'])
def initiate_oauth():
    """
    Initiate the OAuth2 flow with Microsoft.
    Redirects the user to Microsoft login page.
    """
    try:
        # Get configuration options from form or JSON
        if request.content_type == 'application/json':
            data = request.json
        else:
            data = request.form.to_dict()
        
        # Load existing OAuth config
        oauth_config = load_oauth_config()
        
        # Add mailbox configuration
        mailbox_type = data.get('mailbox_type', 'primary')
        shared_mailbox = data.get('shared_mailbox', '')
        use_alias = data.get('use_alias', False)
        alias = data.get('alias', '')
        
        # Update configuration with mailbox settings
        oauth_config.update({
            'mailbox_type': mailbox_type,
            'shared_mailbox': shared_mailbox,
            'use_alias': use_alias,
            'alias': alias
        })
        
        # Ensure directory exists
        os.makedirs(os.path.dirname('/opt/sentigee/EmailRelay/oauth_config.json'), exist_ok=True)
        
        # Save configuration
        with open('/opt/sentigee/EmailRelay/oauth_config.json', 'w') as f:
            json.dump(oauth_config, f, indent=2)
        
        # Define required permissions (use from config or default)
        scopes = oauth_config.get('scopes', [
            'https://graph.microsoft.com/Mail.Read',
            'https://graph.microsoft.com/Mail.Send',
            'https://graph.microsoft.com/User.Read',
            'offline_access'  # Required for refresh tokens
        ])
        
        # Build authorization URL
        oauth_params = {
            'client_id': oauth_config['client_id'],
            'response_type': 'code',
            'redirect_uri': oauth_config['redirect_uri'],
            'scope': ' '.join(scopes),
            'response_mode': 'query'
        }
        
        query_string = urllib.parse.urlencode(oauth_params)
        auth_url = f"{oauth_config['authority']}{oauth_config['tenant_id']}/oauth2/v2.0/authorize?{query_string}"
        
        # Store in session for AJAX requests
        session['auth_url'] = auth_url
        
        if request.content_type == 'application/json':
            return {'auth_url': auth_url}
        else:
            return redirect(auth_url)
            
    except Exception as e:
        logger.error(f"Error initiating OAuth: {str(e)}")
        if request.content_type == 'application/json':
            return {'error': str(e)}, 500
        else:
            flash(f"Error initiating OAuth: {str(e)}", 'error')
            return redirect(url_for('mail_relay.index'))

def handle_callback():
    """
    Handle the OAuth2 callback from Microsoft.
    Exchanges authorization code for access and refresh tokens.
    """
    try:
        # Load OAuth config
        oauth_config = load_oauth_config()
        
        # Get authorization code from query parameters
        code = request.args.get('code')
        error = request.args.get('error')
        
        # Handle error
        if error:
            error_description = request.args.get('error_description', 'Unknown error')
            logger.error(f"OAuth error: {error}. {error_description}")
            
            # Log to a dedicated error log
            os.makedirs('/opt/sentigee/logs', exist_ok=True)
            with open('/opt/sentigee/logs/oauth_error.log', 'a') as f:
                f.write(f"{datetime.now().isoformat()} - Error: {error} - {error_description}\n")
                
            return redirect(url_for('mail_relay.index', error=error, error_description=error_description))
        
        # Validate code
        if not code:
            logger.error("No authorization code received")
            return redirect(url_for('mail_relay.index', error='no_code', error_description='No authorization code was received'))
        
        # Exchange code for token
        token_url = f"{oauth_config['authority']}{oauth_config['tenant_id']}/oauth2/v2.0/token"
        token_data = {
            'client_id': oauth_config['client_id'],
            'client_secret': oauth_config['client_secret'],
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': oauth_config['redirect_uri']
        }
        
        # Make request to token endpoint
        token_response = requests.post(token_url, data=token_data)
        
        if token_response.status_code != 200:
            logger.error(f"Token request failed: {token_response.text}")
            return redirect(url_for('mail_relay.index', error='token_request_failed', 
                                   error_description=f'Failed to obtain token: {token_response.text}'))
        
        # Parse token response
        token_info = token_response.json()
        
        # Add additional information
        token_info['expires_at'] = datetime.now().timestamp() + token_info.get('expires_in', 3600)
        token_info['last_refreshed'] = datetime.now().isoformat()
        token_info['last_refresh_attempt'] = datetime.now().isoformat()
        token_info['last_refresh_result'] = 'success'
        
        # Get user information
        user_info = get_user_info(token_info.get('access_token'))
        token_info.update(user_info)
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)
        
        # Save token
        with open(TOKEN_PATH, 'w') as f:
            json.dump({'tokens': [token_info]}, f, indent=2)
        
        # Log success
        os.makedirs('/opt/sentigee/logs', exist_ok=True)
        with open('/opt/sentigee/logs/oauth_success.log', 'a') as f:
            f.write(f"{datetime.now().isoformat()} - Success: Token obtained for {user_info.get('user_email', 'unknown')}\n")
        
        logger.info(f"OAuth token obtained successfully for {user_info.get('user_email', 'unknown')}")
        return redirect(url_for('mail_relay.index', success=True))
        
    except Exception as e:
        logger.exception(f"Error in OAuth callback: {str(e)}")
        return redirect(url_for('mail_relay.index', error='internal_error', 
                               error_description=f'Internal error: {str(e)}'))

def get_user_info(access_token):
    """
    Get user information from Microsoft Graph API.
    
    Args:
        access_token (str): Access token for Microsoft Graph API
        
    Returns:
        dict: User information
    """
    user_info = {
        'user_display_name': 'Unknown',
        'user_email': 'Unknown',
        'is_admin': False
    }
    
    try:
        # Get user profile
        graph_url = 'https://graph.microsoft.com/v1.0/me'
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        user_response = requests.get(graph_url, headers=headers)
        
        if user_response.status_code == 200:
            user_data = user_response.json()
            user_info['user_display_name'] = user_data.get('displayName', 'Unknown')
            user_info['user_email'] = user_data.get('mail') or user_data.get('userPrincipalName', 'Unknown')
            
            # Check if user is admin
            roles_url = 'https://graph.microsoft.com/v1.0/me/memberOf'
            roles_response = requests.get(roles_url, headers=headers)
            
            if roles_response.status_code == 200:
                roles_data = roles_response.json()
                is_admin = any(
                    role.get('displayName') and 'admin' in role.get('displayName', '').lower()
                    for role in roles_data.get('value', [])
                )
                user_info['is_admin'] = is_admin
                
                # If admin, get list of users
                if is_admin:
                    users_url = 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,mail,userPrincipalName&$top=100'
                    users_response = requests.get(users_url, headers=headers)
                    
                    if users_response.status_code == 200:
                        users_data = users_response.json()
                        user_info['tenant_users'] = users_data.get('value', [])
    except Exception as e:
        logger.exception(f"Error getting user info: {str(e)}")
    
    return user_info

@bp.route('/revoke-token', methods=['POST'])
def revoke_token():
    """
    Revoke the OAuth token.
    """
    try:
        if os.path.exists(TOKEN_PATH):
            os.remove(TOKEN_PATH)
            logger.info("OAuth token revoked")
            
        if request.content_type == 'application/json':
            return {'success': True, 'message': 'Token revoked successfully'}
        else:
            flash('Token revoked successfully', 'success')
            return redirect(url_for('mail_relay.index'))
            
    except Exception as e:
        logger.exception(f"Error revoking token: {str(e)}")
        
        if request.content_type == 'application/json':
            return {'success': False, 'error': str(e)}, 500
        else:
            flash(f"Error revoking token: {str(e)}", 'error')
            return redirect(url_for('mail_relay.index'))
