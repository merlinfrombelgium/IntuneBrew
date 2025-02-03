import requests
import json
import os
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class GitHubSync:
    def __init__(self):
        self.repo_owner = "ugurkocde"
        self.repo_name = "IntuneBrew"
        self.api_base_url = f"https://api.github.com/repos/{self.repo_owner}/{self.repo_name}"
        self.raw_base_url = f"https://raw.githubusercontent.com/{self.repo_owner}/{self.repo_name}/main"
        self.last_check_file = "last_check.json"

    def _get_latest_commit_hash(self):
        """Get the latest commit hash from GitHub"""
        try:
            response = requests.get(f"{self.api_base_url}/commits/main")
            if response.ok:
                return response.json()['sha']
            logger.error(f"Failed to get latest commit hash: {response.status_code}")
            return None
        except Exception as e:
            logger.error(f"Error getting latest commit hash: {str(e)}")
            return None

    def _get_stored_state(self):
        """Get the stored state from last check"""
        try:
            if os.path.exists(self.last_check_file):
                with open(self.last_check_file, 'r') as f:
                    return json.load(f)
            return {}
        except Exception as e:
            logger.error(f"Error reading stored state: {str(e)}")
            return {}

    def _save_state(self, state):
        """Save the current state"""
        try:
            with open(self.last_check_file, 'w') as f:
                json.dump(state, f, indent=4)
        except Exception as e:
            logger.error(f"Error saving state: {str(e)}")

    def _download_file(self, path):
        """Download a file from GitHub"""
        try:
            response = requests.get(f"{self.raw_base_url}/{path}")
            if response.ok:
                return response.json() if path.endswith('.json') else response.content
            logger.error(f"Failed to download file {path}: {response.status_code}")
            return None
        except Exception as e:
            logger.error(f"Error downloading file {path}: {str(e)}")
            return None

    def _save_file(self, path, content):
        """Save content to a local file"""
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if isinstance(content, (dict, list)):
                with open(path, 'w') as f:
                    json.dump(content, f, indent=4)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
        except Exception as e:
            logger.error(f"Error saving file {path}: {str(e)}")

    def check_for_updates(self):
        """Check for updates in the GitHub repository"""
        try:
            # Get latest commit hash
            latest_hash = self._get_latest_commit_hash()
            if not latest_hash:
                return []

            # Get stored state
            stored_state = self._get_stored_state()
            stored_hash = stored_state.get('commit_hash')

            # If no changes, return early
            if stored_hash == latest_hash:
                logger.info("No updates found")
                return []

            # Get current and new apps list
            current_apps = set(stored_state.get('apps', []))
            new_apps_json = self._download_file('supported_apps.json')
            if not new_apps_json:
                return []

            new_apps = set(new_apps_json.keys())
            added_apps = list(new_apps - current_apps)

            if added_apps:
                logger.info(f"Found {len(added_apps)} new apps")
                # Download new app files and logos
                for app_name in added_apps:
                    app_json = self._download_file(f"Apps/{app_name}.json")
                    if app_json:
                        self._save_file(f"Apps/{app_name}.json", app_json)
                    logo = self._download_file(f"Logos/{app_name}.png")
                    if logo:
                        self._save_file(f"Logos/{app_name}.png", logo)

                # Save the full supported_apps.json
                self._save_file('supported_apps.json', new_apps_json)

            # Update stored state
            self._save_state({
                'commit_hash': latest_hash,
                'apps': list(new_apps),
                'last_check': datetime.utcnow().isoformat()
            })

            return added_apps

        except Exception as e:
            logger.error(f"Error checking for updates: {str(e)}")
            return []

    def get_last_check(self):
        """Get the last check timestamp"""
        state = self._get_stored_state()
        return state.get('last_check') 