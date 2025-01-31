
import json
import requests
import os
import time
from base64 import b64encode
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding, hashes, hmac

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
            "packageIdentifier": app_info['bundleId'],
            "bundleId": app_info['bundleId'],
            "versionNumber": app_info['version'],
            "primaryBundleId": app_info['bundleId'],
            "primaryBundleVersion": app_info['version'],
            "informationUrl": app_info.get('homepage', ''),
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

        # Log the payload for debugging
        print("Creating app with payload:", json.dumps(payload, indent=2))

        max_retries = 3
        retry_delay = 5  # seconds
        
        for attempt in range(max_retries):
            response = requests.post(
                f"{self.base_url}/deviceAppManagement/mobileApps",
                headers=self.headers,
                json=payload
            )
            
            if response.ok:
                break
                
            if response.status_code == 503:
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                    
            error_msg = f"Failed to create app: HTTP {response.status_code}"
            try:
                error_details = response.json()
                print("Error response:", json.dumps(error_details, indent=2))
                error_msg += f" - {json.dumps(error_details)}"
            except Exception as e:
                print("Failed to parse error response:", str(e))
                error_msg += f" - {response.text}"
            raise Exception(error_msg)
            
        try:
            result = response.json()
            print("App creation response:", json.dumps(result, indent=2))
            if 'id' not in result:
                raise Exception("App creation response missing required 'id' field")
            
        return result

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
        try:
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
        except Exception as e:
            raise Exception(f"Error during file upload: {str(e)}")

    def finalize_upload(self, app_id, app_type, content_version_id):
        """Finalize the app upload"""
        try:
            # Get current app state first
            current_app = requests.get(
                f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}",
                headers=self.headers
            ).json()
            
            # Start with current app data and update necessary fields
            payload = current_app.copy()
            payload.update({
                "@odata.type": f"#microsoft.graph.{app_type}",
                "committedContentVersion": content_version_id
            })

            # Remove fields that shouldn't be included in update
            fields_to_remove = ['id', '@odata.context', 'createdDateTime', 'lastModifiedDateTime', 'uploadState']
            for field in fields_to_remove:
                payload.pop(field, None)

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
        except Exception as e:
            raise Exception(f"Error finalizing upload: {str(e)}")
