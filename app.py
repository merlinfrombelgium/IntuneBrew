from flask import Flask, render_template, jsonify, request, send_from_directory
import json
import subprocess
import os
import logging
import base64

app = Flask(__name__)
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def get_pwsh_path():
    """Get the path to PowerShell 7 (pwsh)"""
    possible_paths = [
        r"C:\Program Files\PowerShell\7\pwsh.exe",
        r"C:\Program Files (x86)\PowerShell\7\pwsh.exe",
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\PowerShell\7\pwsh.exe")
    ]
    
    for path in possible_paths:
        if os.path.exists(path):
            logger.debug(f"Found PowerShell 7 at: {path}")
            return path
            
    logger.error("PowerShell 7 (pwsh) not found in common locations")
    raise FileNotFoundError("PowerShell 7 (pwsh) not found. Please install PowerShell 7 from https://github.com/PowerShell/PowerShell/releases")

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

def is_newer_version(github_version, intune_version):
    """Compare version strings accounting for build numbers."""
    if intune_version == 'Not in Intune':
        return True

    try:
        # Remove hyphens and everything after them for comparison
        gh_version = github_version.split('-')[0]
        it_version = intune_version.split('-')[0]

        # Handle versions with commas (e.g., "3.5.1,16101")
        gh_version_parts = gh_version.split(',')
        it_version_parts = it_version.split(',')

        # Compare main version numbers first
        gh_main_version = gh_version_parts[0].split('.')
        it_main_version = it_version_parts[0].split('.')

        # Pad versions with zeros to make them equal length
        max_length = max(len(gh_main_version), len(it_main_version))
        gh_main_version.extend(['0'] * (max_length - len(gh_main_version)))
        it_main_version.extend(['0'] * (max_length - len(it_main_version)))

        # Compare version components
        for gh, it in zip(gh_main_version, it_main_version):
            gh_num = int(gh)
            it_num = int(it)
            if gh_num != it_num:
                return gh_num > it_num

        # If main versions are equal and there are build numbers
        if len(gh_version_parts) > 1 and len(it_version_parts) > 1:
            gh_build = int(gh_version_parts[1])
            it_build = int(it_version_parts[1])
            return gh_build > it_build

        # If versions are exactly equal
        return github_version != intune_version
    except Exception as e:
        logger.warning(f"Version comparison failed: GitHubVersion='{github_version}', IntuneVersion='{intune_version}'. Error: {e}")
        return False

@app.route('/api/intune-status')
def get_intune_status():
    logger.info('Fetching Intune status')
    try:
        # Try to read from cache first
        cache_file = 'intune_cache.json'
        if os.path.exists(cache_file):
            logger.debug('Reading from Intune cache')
            with open(cache_file, 'r') as f:
                intune_data = json.load(f)
                if intune_data is None:
                    logger.info('Intune cache is empty, fetching from PowerShell')
                    # Get fresh data from PowerShell
                    pwsh_path = get_pwsh_path()
                    ps_script = '''
                    $ErrorActionPreference = 'Stop'
                    $VerbosePreference = 'Continue'
                    
                    # Only dot-source the function definitions
                    Write-Verbose 'Loading function definitions from IntuneBrew.ps1...'
                    . ([ScriptBlock]::Create((Get-Content "./IntuneBrew.ps1" -Raw)))
                    
                    Write-Verbose 'Loading config.json...'
                    $config = Get-Content -Raw -Path 'config.json' | ConvertFrom-Json
                    
                    Write-Verbose 'Connecting to Graph API...'
                    Connect-MgGraph -ClientId $config.azure.appId -TenantId $config.azure.tenantId -CertificateThumbprint $config.azure.certThumbprint -NoWelcome
                    
                    Write-Verbose 'Getting Intune apps...'
                    $result = Get-IntuneApps -GuiMode
                    
                    Write-Verbose 'Converting result to JSON...'
                    if ($null -eq $result) { 
                        Write-Verbose 'No results found, returning empty array'
                        $result = @() 
                    }
                    Write-Output ($result | ConvertTo-Json -Depth 10)
                    '''
                    logger.debug(f'Executing PowerShell script: {ps_script}')
                    try:
                        process = subprocess.Popen(
                            [pwsh_path, "-NoProfile", "-Command", ps_script],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True
                        )
                        stdout, stderr = process.communicate()
                        logger.debug(f'PowerShell stdout: {stdout}')
                        if stderr:
                            logger.error(f'PowerShell stderr: {stderr}')
                        
                        if process.returncode != 0:
                            logger.error(f'PowerShell process failed with return code: {process.returncode}')
                            return jsonify([]), 200
                            
                        if not stdout.strip():
                            logger.error('Empty response from PowerShell')
                            return jsonify([]), 200
                            
                        intune_data = json.loads(stdout)
                        # Save to cache
                        with open(cache_file, 'w') as f:
                            json.dump(intune_data, f)
                    except subprocess.CalledProcessError as e:
                        logger.error(f'PowerShell error: {e.stderr.decode() if e.stderr else "No error output"}')
                        return jsonify([]), 200
                    except json.JSONDecodeError as e:
                        logger.error(f'JSON decode error: {e}')
                        logger.error(f'Raw stdout: {stdout}')
                        if stderr:
                            logger.error(f'Raw stderr: {stderr}')
                        return jsonify([]), 200
        else:
            logger.info('Cache not found, fetching from PowerShell')
            # Get fresh data from PowerShell
            pwsh_path = get_pwsh_path()
            ps_script = '''
            $ErrorActionPreference = 'Stop'
            $VerbosePreference = 'Continue'
            
            # Only dot-source the function definitions
            Write-Verbose 'Loading function definitions from IntuneBrew.ps1...'
            . ([ScriptBlock]::Create((Get-Content "./IntuneBrew.ps1" -Raw)))
            
            Write-Verbose 'Loading config.json...'
            $config = Get-Content -Raw -Path 'config.json' | ConvertFrom-Json
            
            Write-Verbose 'Connecting to Graph API...'
            Connect-MgGraph -ClientId $config.azure.appId -TenantId $config.azure.tenantId -CertificateThumbprint $config.azure.certThumbprint -NoWelcome
            
            Write-Verbose 'Getting Intune apps...'
            $result = Get-IntuneApps -GuiMode
            
            Write-Verbose 'Converting result to JSON...'
            if ($null -eq $result) { 
                Write-Verbose 'No results found, returning empty array'
                $result = @() 
            }
            Write-Output ($result | ConvertTo-Json -Depth 10)
            '''
            logger.debug(f'Executing PowerShell script: {ps_script}')
            try:
                process = subprocess.Popen(
                    [pwsh_path, "-NoProfile", "-Command", ps_script],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )
                stdout, stderr = process.communicate()
                logger.debug(f'PowerShell stdout: {stdout}')
                if stderr:
                    logger.error(f'PowerShell stderr: {stderr}')
                
                if process.returncode != 0:
                    logger.error(f'PowerShell process failed with return code: {process.returncode}')
                    return jsonify([]), 200
                    
                if not stdout.strip():
                    logger.error('Empty response from PowerShell')
                    return jsonify([]), 200
                    
                intune_data = json.loads(stdout)
                # Save to cache
                with open(cache_file, 'w') as f:
                    json.dump(intune_data, f)
            except subprocess.CalledProcessError as e:
                logger.error(f'PowerShell error: {e.stderr.decode() if e.stderr else "No error output"}')
                return jsonify([]), 200
            except json.JSONDecodeError as e:
                logger.error(f'JSON decode error: {e}')
                logger.error(f'Raw stdout: {stdout}')
                if stderr:
                    logger.error(f'Raw stderr: {stderr}')
                return jsonify([]), 200

        # Get supported apps data
        with open('supported_apps.json', 'r') as f:
            supported_apps = json.load(f)

        # Process each app
        result = []
        for app_name, github_url in supported_apps.items():
            try:
                # Get GitHub version
                app_json_path = f'Apps/{app_name.lower()}.json'
                with open(app_json_path, 'r') as f:
                    github_data = json.load(f)
                    github_version = github_data['version']

                # Find matching Intune app
                intune_app = next((app for app in intune_data if app['Name'] == github_data['name']), None)
                intune_version = intune_app['IntuneVersion'] if intune_app else 'Not in Intune'

                # Determine status
                if intune_version == 'Not in Intune':
                    status = 'Not in Intune'
                else:
                    status = 'Update Available' if is_newer_version(github_version, intune_version) else 'Up-to-date'

                result.append({
                    'Name': github_data['name'],
                    'IntuneVersion': intune_version,
                    'GitHubVersion': github_version,
                    'Status': status
                })
            except Exception as e:
                logger.error(f'Error processing app {app_name}: {str(e)}')
                continue

        logger.debug(f'Processed status for {len(result)} apps')
        return jsonify(result)
    except Exception as e:
        logger.error(f'Error getting Intune status: {str(e)}')
        return jsonify([]), 200

@app.route('/api/app/<app_id>')
def get_app_details(app_id):
    logger.info(f'Fetching details for app: {app_id}')
    app_path = f'Apps/{app_id}.json'
    if os.path.exists(app_path):
        logger.debug(f'Loading app details from {app_path}')
        with open(app_path, 'r') as f:
            app_details = json.load(f)

        try:
            # Try to read from cache first
            cache_file = 'intune_cache.json'
            if os.path.exists(cache_file):
                logger.debug('Reading from Intune cache')
                with open(cache_file, 'r') as f:
                    get_app_details.intune_apps = json.load(f)
            else:
                # Fallback to PowerShell if cache doesn't exist
                logger.debug('Cache not found, fetching from PowerShell')
                ps_cmd = 'pwsh -Command "& {. ./IntuneBrew.ps1; Get-IntuneApps | ConvertTo-Json}"'
                ps_output = subprocess.check_output(ps_cmd, shell=True).decode()
                get_app_details.intune_apps = json.loads(ps_output)

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
            # Convert base64 string to bytes and return as PNG
            return base64.b64decode(empty_pixel), 200, {'Content-Type': 'image/png'}

@app.route('/')
def index():
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)