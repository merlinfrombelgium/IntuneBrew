
import json
import requests
import os
from base64 import b64encode
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding, hashes, hmac
import os

class IntuneUploader:
    def __init__(self, access_token):
        self.access_token = access_token
        self.base_url = "https://graph.microsoft.com/beta"
        self.headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }

    def create_app(self, app_info):
        """Create the app in Intune"""
        app_type = "macOSDmgApp" if app_info['fileName'].endswith('.dmg') else "macOSPkgApp"
        
        payload = {
            "@odata.type": f"#microsoft.graph.{app_type}",
            "displayName": app_info['name'],
            "description": app_info['description'],
            "publisher": app_info['name'],
            "fileName": app_info['fileName'],
            "bundleId": app_info['bundleId'],
            "versionNumber": app_info['version'],
            "primaryBundleId": app_info['bundleId'],
            "primaryBundleVersion": app_info['version'],
            "minimumSupportedOperatingSystem": {
                "@odata.type": "#microsoft.graph.macOSMinimumOperatingSystem",
                "v11_0": True
            },
            "includedApps": [{
                "@odata.type": "#microsoft.graph.macOSIncludedApp",
                "bundleId": app_info['bundleId'],
                "bundleVersion": app_info['version']
            }]
        }

        response = requests.post(
            f"{self.base_url}/deviceAppManagement/mobileApps",
            headers=self.headers,
            json=payload
        )
        return response.json()

    def encrypt_file(self, file_path):
        """Encrypt the app file for upload"""
        # Generate encryption keys
        aes_key = os.urandom(32)
        hmac_key = os.urandom(32)
        iv = os.urandom(16)

        # Read and hash original file
        with open(file_path, 'rb') as f:
            file_data = f.read()
            sha256 = hashes.Hash(hashes.SHA256())
            sha256.update(file_data)
            file_digest = sha256.finalize()

        # Encrypt file
        padder = padding.PKCS7(128).padder()
        padded_data = padder.update(file_data) + padder.finalize()
        
        cipher = Cipher(algorithms.AES(aes_key), modes.CBC(iv))
        encryptor = cipher.encryptor()
        encrypted_data = encryptor.update(padded_data) + encryptor.finalize()

        # Calculate HMAC
        h = hmac.HMAC(hmac_key, hashes.SHA256())
        h.update(iv + encrypted_data)
        mac = h.finalize()

        # Write encrypted file
        encrypted_file_path = f"{file_path}.bin"
        with open(encrypted_file_path, 'wb') as f:
            f.write(mac + iv + encrypted_data)

        return {
            "encryptionKey": b64encode(aes_key).decode(),
            "macKey": b64encode(hmac_key).decode(),
            "initializationVector": b64encode(iv).decode(),
            "mac": b64encode(mac).decode(),
            "profileIdentifier": "ProfileVersion1",
            "fileDigest": b64encode(file_digest).decode(),
            "fileDigestAlgorithm": "SHA256"
        }

    def upload_file(self, app_id, app_type, file_path, encryption_info):
        """Handle the complete file upload process"""
        # Create content version
        content_version = requests.post(
            f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions",
            headers=self.headers,
            json={}
        ).json()

        # Create file entry
        file_size = os.path.getsize(file_path)
        encrypted_size = os.path.getsize(f"{file_path}.bin")
        
        file_body = {
            "@odata.type": "#microsoft.graph.mobileAppContentFile",
            "name": os.path.basename(file_path),
            "size": file_size,
            "sizeEncrypted": encrypted_size,
            "isDependency": False
        }

        content_file = requests.post(
            f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions/{content_version['id']}/files",
            headers=self.headers,
            json=file_body
        ).json()

        # Get Azure Storage URI
        file_uri = None
        while not file_uri:
            status = requests.get(
                f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions/{content_version['id']}/files/{content_file['id']}",
                headers=self.headers
            ).json()
            if status['uploadState'] == 'azureStorageUriRequestSuccess':
                file_uri = status['azureStorageUri']

        # Upload to Azure Storage
        with open(f"{file_path}.bin", 'rb') as f:
            requests.put(
                file_uri,
                headers={"x-ms-blob-type": "BlockBlob"},
                data=f
            )

        # Commit the file
        requests.post(
            f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions/{content_version['id']}/files/{content_file['id']}/commit",
            headers=self.headers,
            json={"fileEncryptionInfo": encryption_info}
        )

        return content_version['id']

    def finalize_upload(self, app_id, app_type, content_version_id):
        """Finalize the app upload"""
        payload = {
            "@odata.type": f"#microsoft.graph.{app_type}",
            "committedContentVersion": content_version_id
        }
        
        # First, get the current app state
        try:
            current_app = requests.get(
                f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}",
                headers=self.headers
            ).json()
            
            # Preserve existing fields while updating necessary ones
            for key in ['displayName', 'description', 'publisher', 'largeIcon']:
                if key in current_app:
                    payload[key] = current_app[key]
        except Exception as e:
            logging.error(f"Error fetching current app state: {str(e)}")
            
        response = requests.patch(
            f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}",
            headers=self.headers,
            json=payload
        )
        
        if not response.ok:
            error_msg = f"Failed to finalize upload: {response.status_code}"
            try:
                error_details = response.json()
                error_msg += f" - {json.dumps(error_details)}"
            except:
                error_msg += f" - {response.text}"
            raise Exception(error_msg)
            
        return response.json()
