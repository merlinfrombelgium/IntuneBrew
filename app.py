from flask import Flask, render_template, jsonify, request, send_from_directory
import json
import subprocess
import os
import logging
import base64
import requests
from packaging.version import parse as parse_version

app = Flask(__name__)
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Load configuration
try:
    with open('config.json', 'r') as f:
        config = json.load(f)
    HOST = config['webserver']['host']
    PORT = config['webserver']['port']
except Exception as e:
    logger.warning(f'Failed to load config.json, using defaults: {str(e)}')
    HOST = '0.0.0.0'
    PORT = 5000  # Default Flask port

@app.route('/api/apps')
def get_apps():
    logger.info('Fetching supported apps')
    try:
        with open('supported_apps.json', 'r') as f:
            apps = json.load(f)
        logger.debug(f'Found {len(apps)} supported apps')
        return jsonify(apps)
    except Exception as e:
        logger.error(f'Error loading supported apps: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/api/intune-status')
def get_intune_status():
    logger.info('Fetching Intune status')
    try:
        # Load config for auth
        with open('config.json', 'r') as f:
            config = json.load(f)
        
        # Get the full path to pwsh.exe and script directory
        pwsh_path = subprocess.check_output(['where', 'pwsh'], shell=True).decode().strip()
        script_dir = os.path.dirname(os.path.abspath(__file__))
        functions_path = os.path.join(script_dir, 'functions.ps1')
        
        logger.debug(f'PowerShell path: {pwsh_path}')
        logger.debug(f'Functions path: {functions_path}')
        
        # Run PowerShell command with proper auth and function loading
        ps_script = f'''
            $ErrorActionPreference = "Continue"
            $VerbosePreference = "SilentlyContinue"
            
            Set-Location "{script_dir}"
            
            if (-not (Test-Path "{functions_path}")) {{
                Write-Error "functions.ps1 not found at {functions_path}"
                exit 1
            }}

            try {{
                . "{functions_path}"
                Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
                Connect-MgGraph -ClientId '{config['azure']['appId']}' -TenantId '{config['azure']['tenantId']}' -CertificateThumbprint '{config['azure']['certThumbprint']}' -NoWelcome -ErrorAction Stop
                Get-IntuneApps
            }}
            catch {{
                Write-Error "Error in PowerShell script: $_"
                Write-Error $_.ScriptStackTrace
                exit 1
            }}
        '''
        
        # Use subprocess.run with a list of arguments
        result = subprocess.run(
            [pwsh_path, '-NoProfile', '-Command', ps_script],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode != 0:
            logger.error(f'PowerShell script failed with exit code {result.returncode}')
            return jsonify({'error': f'PowerShell error: {result.stderr}'}), 500

        # Load the supported apps from local JSON
        with open('supported_apps.json', 'r') as f:
            supported_apps = json.load(f)

        # Process the Intune data
        try:
            logger.debug(f'Raw PowerShell output: {result.stdout}')
            intune_data = json.loads(result.stdout)
            if isinstance(intune_data, str):
                intune_data = json.loads(intune_data)  # Parse again if it's a string
            logger.debug(f'Intune data type: {type(intune_data)}')
            logger.debug(f'First intune app: {json.dumps(intune_data[0] if isinstance(intune_data, list) else "Not a list", indent=2)}')
            results = []
            
            # Process each supported app
            for app_id, _ in supported_apps.items():
                try:
                    # Get app info from local JSON file
                    app_path = os.path.join('Apps', f'{app_id}.json')
                    with open(app_path, 'r') as f:
                        github_app = json.load(f)
                    logger.debug(f'Processing app {app_id}: {json.dumps(github_app, indent=2)}')
                    
                    # Find matching Intune app
                    intune_app = next((app for app in intune_data if isinstance(app, dict) and app.get('displayName') == github_app.get('name')), None)
                    
                    # Get Intune version
                    intune_version = "Not in Intune"
                    if intune_app:
                        if 'versionNumber' in intune_app and intune_app['versionNumber']:
                            intune_version = intune_app['versionNumber']
                        elif 'primaryBundleVersion' in intune_app and intune_app['primaryBundleVersion']:
                            intune_version = intune_app['primaryBundleVersion']
                        else:
                            intune_version = "Version Unknown"
                    
                    # Determine status
                    if intune_version == "Not in Intune":
                        status = "Not Deployed"
                    elif intune_version == "Version Unknown":
                        status = "Unknown"
                    else:
                        # Compare versions
                        github_version = github_app.get('version')
                        status = "Update Available" if is_newer_version(github_version, intune_version) else "Up to Date"
                    
                    results.append({
                        'Name': github_app.get('name'),
                        'GitHubVersion': github_app.get('version'),
                        'IntuneVersion': intune_version,
                        'Status': status
                    })
                    
                except Exception as e:
                    logger.warning(f'Error processing app {app_id}: {str(e)}')
                    continue
            
            return jsonify(results)
            
        except json.JSONDecodeError as e:
            logger.error(f'Error decoding PowerShell output: {str(e)}')
            return jsonify({'error': 'Invalid JSON from PowerShell'}), 500
            
    except Exception as e:
        logger.error(f'Error getting Intune status: {str(e)}', exc_info=True)
        return jsonify([]), 200

def is_newer_version(github_version, intune_version):
    """Compare version strings accounting for build numbers."""
    if intune_version == 'Not in Intune':
        return True
        
    try:
        # Remove hyphens and everything after them
        gh_version = github_version.split('-')[0]
        it_version = intune_version.split('-')[0]
        
        # Handle versions with commas (e.g., "3.5.1,16101")
        gh_parts = gh_version.split(',')
        it_parts = it_version.split(',')
        
        # Compare main version numbers
        gh_main = parse_version(gh_parts[0])
        it_main = parse_version(it_parts[0])
        
        if gh_main != it_main:
            return gh_main > it_main
            
        # If main versions are equal and there are build numbers
        if len(gh_parts) > 1 and len(it_parts) > 1:
            try:
                gh_build = int(gh_parts[1])
                it_build = int(it_parts[1])
                return gh_build > it_build
            except ValueError:
                pass
                
        # If versions are exactly equal
        return github_version != intune_version
        
    except Exception:
        logger.warning(f'Version comparison failed: GitHub={github_version}, Intune={intune_version}')
        return False

@app.route('/api/app/<app_id>')
def get_app_details(app_id):
    logger.info(f'Fetching details for app: {app_id}')
    app_path = f'Apps/{app_id}.json'
    if os.path.exists(app_path):
        logger.debug(f'Loading app details from {app_path}')
        with open(app_path, 'r') as f:
            app_details = json.load(f)

        try:
            if not hasattr(get_app_details, 'intune_apps'):
                # Load config for auth
                with open('config.json', 'r') as f:
                    config = json.load(f)
                
                # Get the full path to pwsh.exe
                pwsh_path = subprocess.check_output(['where', 'pwsh'], shell=True).decode().strip()
                logger.debug(f'PowerShell path: {pwsh_path}')
                
                # Run PowerShell command with proper auth and function loading
                script_dir = os.path.dirname(os.path.abspath(__file__))
                functions_path = os.path.join(script_dir, 'functions.ps1')
                ps_script = f'''
                    Set-Location "{script_dir}";
                    Write-Host "Starting PowerShell script execution..." 2>&1;
                    Write-Host "Current directory: $(Get-Location)" 2>&1;
                    Write-Host "Loading functions.ps1..." 2>&1;
                    if (-not (Test-Path "{functions_path}")) {{
                        Write-Error "functions.ps1 not found at {functions_path}";
                        exit 1;
                    }}
                    . "{functions_path}";
                    Write-Host "Connecting to Graph..." 2>&1;
                    Connect-MgGraph -ClientId '{config['azure']['appId']}' -TenantId '{config['azure']['tenantId']}' -CertificateThumbprint '{config['azure']['certThumbprint']}' -NoWelcome;
                    Write-Host "Setting up variables..." 2>&1;
                    $githubJsonUrls = @();
                    $supportedApps = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/ugurkocde/IntuneBrew/refs/heads/main/supported_apps.json' -Method Get;
                    $githubJsonUrls = $supportedApps.PSObject.Properties.Value;
                    Get-IntuneApps | ConvertTo-Json -Depth 10
                '''
               
                # Use subprocess.run with a list of arguments
                result = subprocess.run(
                    [pwsh_path, '-NoProfile', '-Command', ps_script],
                    capture_output=True,
                    text=True,
                    check=True
                )
                get_app_details.intune_apps = json.loads(result.stdout)

            # Find matching app
            intune_app = next((app for app in get_app_details.intune_apps if app['Name'] == app_details['name']), None)

            if intune_app:
                status = ('Not in Intune' if intune_app['IntuneVersion'] == 'Not in Intune'
                         else 'Update Available' if intune_app['GitHubVersion'] > intune_app['IntuneVersion']
                         else 'Up-to-date')
                color = ('red' if status == 'Not in Intune'
                        else 'yellow' if status == 'Update Available'
                        else 'green')
                app_details['intuneStatus'] = {
                    'status': status,
                    'color': color,
                    'intuneVersion': intune_app['IntuneVersion']
                }

        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            app_details['intuneStatus'] = {'error': str(e)}

        return jsonify(app_details)
    return jsonify({'error': 'App not found'}), 404

@app.route('/Logos/<path:filename>')
def serve_logo(filename):
    try:
        return send_from_directory('Logos', filename)
    except:
        # Return a transparent 1x1 pixel PNG for missing logos
        empty_pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='
        if os.path.exists('static/empty.png'):
            return send_from_directory('static', 'empty.png')
        else:
            return base64.b64decode(empty_pixel), 200, {'Content-Type': 'image/png'}

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/test', methods=['GET'])
def test_powershell():
    logger.info('Testing PowerShell connection')
    try:
        # Get the full path to pwsh.exe
        pwsh_path = subprocess.check_output(['where', 'pwsh'], shell=True).decode().strip()
        logger.debug(f'PowerShell path: {pwsh_path}')
        
        # Run PowerShell command directly with the test script
        ps_script = '''. ./test.ps1; Say-Hello | ConvertTo-Json'''
        
        # Use subprocess.run with a list of arguments
        result = subprocess.run(
            [pwsh_path, '-NoProfile', '-Command', ps_script],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        return jsonify({'message': data})
    except Exception as e:
        logger.error(f'Error in test endpoint: {str(e)}', exc_info=True)
        return jsonify({'error': str(e)}), 500

# Debug route to show all registered routes
@app.route('/debug/routes')
def list_routes():
    routes = []
    for rule in app.url_map.iter_rules():
        routes.append({
            "endpoint": rule.endpoint,
            "methods": list(rule.methods),
            "route": str(rule)
        })
    return jsonify(routes)

if __name__ == '__main__':
    logger.info(f'Starting Flask server on {HOST}:{PORT}')
    logger.info('Registered routes:')
    for rule in app.url_map.iter_rules():
        logger.info(f'  {rule.methods} {rule}')
    app.run(host=HOST, port=PORT)