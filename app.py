from flask import Flask, render_template, jsonify, request, send_from_directory
import json
import subprocess
import os
app = Flask(__name__)

@app.route('/api/apps')
def get_apps():
    with open('supported_apps.json', 'r') as f:
        apps = json.load(f)
    return jsonify(apps)

@app.route('/api/app/<app_id>')
def get_app_details(app_id):
    app_path = f'Apps/{app_id}.json'
    if os.path.exists(app_path):
        with open(app_path, 'r') as f:
            app_details = json.load(f)

        try:
            # Get the global intune_apps data, creating it if doesn't exist
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
    return send_from_directory('Logos', filename)



@app.route('/')
def index():
    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)