from flask import Flask, render_template, jsonify, request, send_from_directory
import json
import subprocess
import os
import logging
import time
import requests
from app_upload import IntuneUploader

app = Flask(__name__)
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

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

# Cache for Intune status
intune_status_cache = None
last_fetch_time = 0
CACHE_DURATION = 60  # Cache duration in seconds

@app.route('/api/intune-status')
def get_intune_status():
    global intune_status_cache, last_fetch_time
    current_time = time.time()
    
    logger.info('Fetching Intune status')
    try:
        # Check if cache is still valid
        if intune_status_cache and (current_time - last_fetch_time) < CACHE_DURATION:
            logger.debug('Returning cached Intune status')
            return jsonify(intune_status_cache)
        
        # Get token from request headers
        token = request.headers.get('Authorization', '').split(' ')[1]
        if not token:
            return jsonify({'error': 'No authorization token provided'}), 401

        # Use the IntuneUploader to get app status
        uploader = IntuneUploader(token)
        response = requests.get(
            f"{uploader.base_url}/deviceAppManagement/mobileApps?$filter=(isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSPkgApp'))",
            headers=uploader.headers
        )
        
        apps = response.json().get('value', [])
        data = []
        
        # Process each app
        for app in apps:
            app_data = {
                'Name': app.get('displayName', ''),
                'IntuneVersion': app.get('versionNumber', 'Unknown'),
                'GitHubVersion': 'N/A'  # This would need to be fetched from your GitHub repo
            }
            data.append(app_data)
            
        # Update cache
        intune_status_cache = data
        last_fetch_time = current_time
        
        logger.debug(f'Retrieved status for {len(data)} apps')
        return jsonify(data)
    except Exception as e:
        logger.error(f'Error getting Intune status: {str(e)}')
        return jsonify([]), 200  # Return empty array instead of error

@app.route('/api/upload', methods=['POST'])
def upload_app():
    try:
        token = request.headers.get('Authorization').split(' ')[1]
        app_info = request.json
        
        uploader = IntuneUploader(token)
        app = uploader.create_app(app_info)
        
        # Download the app package
        response = requests.get(app_info['url'])
        temp_file = f"/tmp/{app_info['fileName']}"
        with open(temp_file, 'wb') as f:
            f.write(response.content)
        
        # Upload to Intune
        encryption_info = uploader.encrypt_file(temp_file)
        app_type = "macOSDmgApp" if app_info['fileName'].endswith('.dmg') else "macOSPkgApp"
        content_version_id = uploader.upload_file(app['id'], app_type, temp_file, encryption_info)
        result = uploader.finalize_upload(app['id'], app_type, content_version_id)
        
        # Cleanup
        os.remove(temp_file)
        if os.path.exists(f"{temp_file}.bin"):
            os.remove(f"{temp_file}.bin")
            
        return jsonify(result)
    except Exception as e:
        logger.error(f'Upload failed: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/api/app/<app_id>')
def get_app_details(app_id):
    logger.info(f'Fetching details for app: {app_id}')
    app_path = f'Apps/{app_id}.json'
    if os.path.exists(app_path):
        logger.debug(f'Loading app details from {app_path}')
        with open(app_path, 'r') as f:
            app_details = json.load(f)

        try:
            # Get token from request headers
            token = request.headers.get('Authorization', '').split(' ')[1]
            
            # Use Graph API directly
            uploader = IntuneUploader(token)
            response = requests.get(
                f"{uploader.base_url}/deviceAppManagement/mobileApps?$filter=displayName eq '{app_details['name']}'",
                headers=uploader.headers
            )
            
            intune_apps = response.json().get('value', [])
            intune_app = next((app for app in intune_apps if app.get('displayName') == app_details['name']), None)

            if intune_app:
                status = ('Not in Intune' if not intune_app.get('versionNumber') 
                         else 'Update Available' if app_details['version'] > intune_app['versionNumber']
                         else 'Up-to-date')

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
        return send_from_directory('static', 'empty.png') if os.path.exists('static/empty.png') else (empty_pixel.decode('base64'), 200, {'Content-Type': 'image/png'})



@app.route('/')
def index():
    try:
        with open('config.json', 'r') as f:
            config = json.load(f)
        return render_template('index.html', 
                             azure_client_id=config['azure']['appId'],
                             azure_tenant_id=config['azure']['tenantId'])
    except Exception as e:
        logger.error(f'Error loading config: {str(e)}')
        return jsonify({'error': 'Configuration error'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)