from flask import Flask, render_template, jsonify, request, send_from_directory, send_file
import json
import subprocess
import os
import logging
import time
import requests
from app_upload import IntuneUploader
import io
import jwt
import time
import uuid
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.x509 import load_pem_x509_certificate
from cryptography.hazmat.backends import default_backend
import os.path
import base64
from pathlib import Path

app = Flask(__name__)
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def expand_path(path):
    """Expand path with support for ~ on all platforms."""
    # First use pathlib to handle ~
    expanded = str(Path(path).expanduser())
    # Then normalize the path for the current OS
    return str(Path(expanded).resolve())

@app.route('/api/token/', methods=['GET'])
def get_token():
    logger.info('Getting token using certificate authentication')
    try:
        with open('config.json', 'r') as f:
            config = json.load(f)
        
        # Load the private key with cross-platform path
        key_path = expand_path(config['azure']['keyPath'])
        logger.debug(f'Reading key file from {key_path}')
        with open(key_path, 'rb') as key_file:
            key_data = key_file.read()
            logger.debug(f'Read {len(key_data)} bytes from key file')
            private_key = serialization.load_pem_private_key(
                key_data,
                password=None,
                backend=default_backend()
            )
            logger.debug('Successfully loaded PEM private key')
        
        # Load the certificate with cross-platform path
        cert_path = expand_path(config['azure']['certificatePath'])
        logger.debug(f'Reading certificate from {cert_path}')
        with open(cert_path, 'rb') as cert_file:
            cert_data = cert_file.read()
            logger.debug(f'Read {len(cert_data)} bytes from certificate file')
            cert = load_pem_x509_certificate(cert_data, default_backend())
            logger.debug('Successfully loaded PEM certificate')
        
        # Get the certificate thumbprint using SHA1 (which is what Azure uses)
        cert_bytes = cert.fingerprint(hashes.SHA1())
        thumbprint = ''.join([f'{b:02X}' for b in cert_bytes])
        logger.debug(f'Certificate thumbprint (SHA1): {thumbprint}')
        
        # Create the JWT header with the certificate thumbprint
        header = {
            'alg': 'RS256',
            'typ': 'JWT',
            'x5t': base64.b64encode(cert_bytes).decode('utf-8').rstrip('=')
        }
        
        # Create the JWT payload
        now = int(time.time())
        payload = {
            'aud': f'https://login.microsoftonline.com/{config["azure"]["tenantId"]}/oauth2/v2.0/token',
            'exp': now + 3600,
            'iss': config['azure']['appId'],
            'jti': str(uuid.uuid4()),
            'nbf': now,
            'sub': config['azure']['appId']
        }
        
        # Create the client assertion
        client_assertion = jwt.encode(
            payload,
            private_key,
            algorithm='RS256',
            headers=header
        )
        
        # Get the token from Azure AD
        token_url = f'https://login.microsoftonline.com/{config["azure"]["tenantId"]}/oauth2/v2.0/token'
        token_data = {
            'client_id': config['azure']['appId'],
            'client_assertion': client_assertion,
            'client_assertion_type': 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
            'scope': 'https://graph.microsoft.com/.default',
            'grant_type': 'client_credentials'
        }
        
        logger.debug('Requesting token from Azure AD')
        response = requests.post(token_url, data=token_data)
        if response.status_code != 200:
            logger.error(f'Token request failed: {response.text}')
            return jsonify({'error': 'Failed to get token'}), response.status_code
            
        token_response = response.json()
        logger.debug('Successfully obtained token')
        return jsonify({
            'access_token': token_response['access_token'],
            'expires_in': token_response['expires_in'],
            'token_type': token_response['token_type']
        })
        
    except Exception as e:
        logger.error(f'Error getting token: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/api/apps')
def get_apps():
    logger.info('Fetching supported apps')
    try:
        with open('supported_apps.json', 'r') as f:
            apps = json.load(f)
        logger.info(f'Found {len(apps)} supported apps')
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
            token = request.headers.get('Authorization', '').split(' ')[1]
            uploader = IntuneUploader(token)
            
            # Query Intune for app status
            filter_query = f"displayName eq '{app_details['name']}'"
            response = requests.get(
                f"{uploader.base_url}/deviceAppManagement/mobileApps?$filter=(isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSPkgApp')) and {filter_query}",
                headers=uploader.headers
            )
            
            intune_apps = response.json().get('value', [])
            if intune_apps:
                intune_app = intune_apps[0]
                intune_version = intune_app.get('versionNumber', 'Unknown')
                status = ('Update Available' if app_details['version'] > intune_version else 'Up-to-date')
                color = ('yellow' if status == 'Update Available' else 'green')
                app_details['intuneStatus'] = {
                    'status': status,
                    'color': color,
                    'intuneVersion': intune_version
                }
            else:
                app_details['intuneStatus'] = {
                    'status': 'Not in Intune',
                    'color': 'red',
                    'intuneVersion': 'Not in Intune'
                }

        except Exception as e:
            app_details['intuneStatus'] = {'error': str(e)}

        return jsonify(app_details)
    return jsonify({'error': 'App not found'}), 404

@app.route('/Logos/<path:filename>')
def serve_logo(filename):
    try:
        return send_from_directory('Logos', filename)
    except:
        # If logo doesn't exist, return the placeholder image
        if os.path.exists('static/empty.png'):
            return send_from_directory('static', 'empty.png')
        else:
            # If even the placeholder is missing, return a minimal 1x1 transparent PNG
            return send_file(
                io.BytesIO(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x00\x00\x02\x00\x01\xe5\x27\xde\xfc\x00\x00\x00\x00IEND\xaeB`\x82'),
                mimetype='image/png'
            )

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