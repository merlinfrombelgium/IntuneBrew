from flask import Flask, render_template, jsonify, request, send_from_directory
import json
import subprocess
import os
import logging

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

@app.route('/api/intune-status')
def get_intune_status():
    logger.info('Fetching Intune status')
    try:
        ps_cmd = 'pwsh -Command "& {. ./IntuneBrew.ps1; Get-IntuneApps | ConvertTo-Json}"'
        logger.debug(f'Executing command: {ps_cmd}')
        ps_output = subprocess.check_output(ps_cmd, shell=True).decode()
        data = json.loads(ps_output)
        logger.debug(f'Retrieved status for {len(data)} apps')
        return jsonify(data)
    except Exception as e:
        logger.error(f'Error getting Intune status: {str(e)}')
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
            if not hasattr(get_app_details, 'intune_apps'):
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
        return send_from_directory('static', 'empty.png') if os.path.exists('static/empty.png') else (empty_pixel.decode('base64'), 200, {'Content-Type': 'image/png'})



@app.route('/')
def index():
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)