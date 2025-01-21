
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
