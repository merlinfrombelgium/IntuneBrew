import json
import requests
import os
import time
import subprocess
from base64 import b64encode
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding, hashes, hmac
import random

class IntuneUploader:
    def __init__(self, access_token):
        self.access_token = access_token
        self.base_url = "https://graph.microsoft.com/beta"
        self.headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }

    def create_app(self, app_info):
        """Create or update the app in Intune"""
        app_type = "macOSDmgApp" if app_info['fileName'].endswith('.dmg') else "macOSPkgApp"
        
        # First try to get bundle ID from app_info
        bundle_id = app_info.get('bundleId')
        
        # If not available, create one from the app name
        if not bundle_id:
            clean_name = ''.join(c.lower() for c in app_info['name'] if c.isalnum() or c.isspace())
            clean_name = clean_name.replace(' ', '')
            bundle_id = f"com.intunebrew.{clean_name}"
            print(f"Using generated bundle ID: {bundle_id}")

        # Check if we should update an existing app
        if app_info.get('updateExisting'):
            print("Looking for existing app to update...")
            filter_query = f"displayName eq '{app_info['name']}'"
            response = requests.get(
                f"{self.base_url}/deviceAppManagement/mobileApps?$filter=(isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSPkgApp')) and {filter_query}",
                headers=self.headers
            )
            
            if response.ok:
                existing_apps = response.json().get('value', [])
                if existing_apps:
                    existing_app = existing_apps[0]
                    print(f"Found existing app with ID: {existing_app['id']}")
                    
                    # Update the existing app
                    payload = {
                        "@odata.type": f"#microsoft.graph.{app_type}",
                        "displayName": app_info['name'],
                        "description": app_info['description'],
                        "publisher": app_info.get('publisher', app_info['name']),
                        "developer": app_info.get('developer', 'Microsoft Corporation'),
                        "owner": app_info.get('owner', 'Microsoft'),
                        "fileName": app_info['fileName'],
                        "packageIdentifier": bundle_id,
                        "bundleId": bundle_id,
                        "versionNumber": app_info['version'],
                        "primaryBundleId": bundle_id,
                        "primaryBundleVersion": app_info['version'],
                        "informationUrl": app_info.get('homepage', ''),
                        "privacyInformationUrl": app_info.get('privacyUrl', 'https://privacy.microsoft.com/en-us/privacystatement'),
                        "minimumSupportedOperatingSystem": {
                            "@odata.type": "#microsoft.graph.macOSMinimumOperatingSystem",
                            "v11_0": True
                        },
                        "includedApps": [{
                            "@odata.type": "#microsoft.graph.macOSIncludedApp",
                            "bundleId": bundle_id,
                            "bundleVersion": app_info['version']
                        }]
                    }
                    
                    response = requests.patch(
                        f"{self.base_url}/deviceAppManagement/mobileApps/{existing_app['id']}",
                        headers=self.headers,
                        json=payload
                    )
                    
                    if response.ok:
                        print("Successfully updated existing app")
                        return existing_app
                    else:
                        print(f"Failed to update app: {response.status_code}")
                        try:
                            print(f"Error details: {response.json()}")
                        except:
                            print(f"Error text: {response.text}")
        
        # If not updating or update failed, create new app
        payload = {
            "@odata.type": f"#microsoft.graph.{app_type}",
            "displayName": app_info['name'],
            "description": app_info['description'],
            "publisher": app_info.get('publisher', app_info['name']),
            "developer": app_info.get('developer', 'Microsoft Corporation'),
            "owner": app_info.get('owner', 'Microsoft'),
            "fileName": app_info['fileName'],
            "packageIdentifier": bundle_id,
            "bundleId": bundle_id,
            "versionNumber": app_info['version'],
            "primaryBundleId": bundle_id,
            "primaryBundleVersion": app_info['version'],
            "informationUrl": app_info.get('homepage', ''),
            "privacyInformationUrl": app_info.get('privacyUrl', 'https://privacy.microsoft.com/en-us/privacystatement'),
            "minimumSupportedOperatingSystem": {
                "@odata.type": "#microsoft.graph.macOSMinimumOperatingSystem",
                "v11_0": True
            },
            "includedApps": [{
                "@odata.type": "#microsoft.graph.macOSIncludedApp",
                "bundleId": bundle_id,
                "bundleVersion": app_info['version']
            }]
        }

        # Log the payload for debugging
        print("Creating app with payload:", json.dumps(payload, indent=2))

        max_retries = 5  # Increased from 3 to 5
        base_delay = 10  # Starting with 10 seconds
        max_delay = 60   # Maximum delay of 60 seconds
        
        last_error = None
        for attempt in range(max_retries):
            try:
                response = requests.post(
                    f"{self.base_url}/deviceAppManagement/mobileApps",
                    headers=self.headers,
                    json=payload,
                    timeout=30  # Add explicit timeout
                )
                
                if response.ok:
                    break
                
                # Handle different status codes
                if response.status_code == 503:
                    # Get retry-after header if available
                    retry_after = response.headers.get('Retry-After')
                    if retry_after:
                        delay = int(retry_after)
                    else:
                        # Exponential backoff with jitter
                        delay = min(base_delay * (2 ** attempt) + random.uniform(0, 5), max_delay)
                    
                    print(f"Service unavailable (503). Retrying in {delay:.1f} seconds... (Attempt {attempt + 1}/{max_retries})")
                    time.sleep(delay)
                    continue
                
                # For other error codes, raise immediately
                error_msg = f"Failed to create app: HTTP {response.status_code}"
                try:
                    error_details = response.json()
                    print("Error response:", json.dumps(error_details, indent=2))
                    error_msg += f" - {json.dumps(error_details)}"
                except Exception as e:
                    print("Failed to parse error response:", str(e))
                    error_msg += f" - {response.text}"
                raise Exception(error_msg)
                
            except requests.exceptions.Timeout:
                print(f"Request timed out. Retrying... (Attempt {attempt + 1}/{max_retries})")
                delay = min(base_delay * (2 ** attempt), max_delay)
                time.sleep(delay)
                continue
                
            except requests.exceptions.RequestException as e:
                last_error = str(e)
                if attempt < max_retries - 1:
                    delay = min(base_delay * (2 ** attempt), max_delay)
                    print(f"Request failed: {str(e)}. Retrying in {delay:.1f} seconds... (Attempt {attempt + 1}/{max_retries})")
                    time.sleep(delay)
                    continue
                raise Exception(f"Failed to create app after {max_retries} attempts. Last error: {last_error}")
        
        if not response.ok:
            raise Exception(f"Failed to create app after {max_retries} attempts. Last error: {last_error}")
            
        try:
            result = response.json()
            print("App creation response:", json.dumps(result, indent=2))
            if 'id' not in result:
                raise Exception("App creation response missing required 'id' field")
            return result
        except Exception as e:
            print(f"Error processing app creation response: {str(e)}")
            raise

    def encrypt_file(self, file_path):
        """Encrypt the app file for upload"""
        # Generate encryption keys
        aes_key = os.urandom(32)  # AES-256
        hmac_key = os.urandom(32)  # HMAC-SHA256
        iv = os.urandom(16)  # AES block size

        # Calculate hash of original file
        with open(file_path, 'rb') as f:
            file_data = f.read()
            sha256 = hashes.Hash(hashes.SHA256())
            sha256.update(file_data)
            file_digest = sha256.finalize()

        # Encrypt file without padding (PowerShell doesn't use padding)
        cipher = Cipher(algorithms.AES(aes_key), modes.CBC(iv))
        encryptor = cipher.encryptor()
        
        # Calculate the number of blocks and pad the last block if necessary
        block_size = 16  # AES block size
        data_size = len(file_data)
        if data_size % block_size != 0:
            padding_size = block_size - (data_size % block_size)
            file_data += bytes([padding_size] * padding_size)
        
        encrypted_data = encryptor.update(file_data) + encryptor.finalize()

        # Write encrypted file with HMAC at the start
        encrypted_file_path = f"{file_path}.bin"
        
        # First write a placeholder for HMAC (32 bytes)
        with open(encrypted_file_path, 'wb') as f:
            f.write(bytes(32))  # Placeholder for HMAC
            f.write(iv)
            f.write(encrypted_data)
        
        # Calculate HMAC over IV + encrypted data
        with open(encrypted_file_path, 'rb') as f:
            f.seek(32)  # Skip HMAC placeholder
            data_for_hmac = f.read()  # Read IV + encrypted data
            h = hmac.HMAC(hmac_key, hashes.SHA256())
            h.update(data_for_hmac)
            mac = h.finalize()
        
        # Write the actual HMAC at the start
        with open(encrypted_file_path, 'r+b') as f:
            f.write(mac)

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
            print(f"Created content version: {content_version['id']}")

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
            print(f"Created content file: {content_file['id']}")

            # Get Azure Storage URI
            print("Waiting for Azure Storage URI...")
            max_attempts = 60  # 5 minutes total
            attempt = 0
            file_uri = None
            
            while not file_uri and attempt < max_attempts:
                status = requests.get(
                    f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions/{content_version['id']}/files/{content_file['id']}",
                    headers=self.headers
                ).json()
                
                if status.get('uploadState') == 'azureStorageUriRequestSuccess':
                    file_uri = status['azureStorageUri']
                    print("Received Azure Storage URI")
                elif status.get('uploadState') in ['failed', 'error']:
                    print(f"Failed to get Azure Storage URI. Status: {status.get('uploadState')}")
                    try:
                        print(f"Error details: {json.dumps(status, indent=2)}")
                    except:
                        print(f"Error details: {status}")
                    raise Exception("Failed to get Azure Storage URI")
                
                if not file_uri:
                    print(f"Waiting for Azure Storage URI (attempt {attempt + 1}/{max_attempts})...")
                    time.sleep(5)
                    attempt += 1

            if not file_uri:
                raise Exception("Timeout waiting for Azure Storage URI")

            # Upload to Azure Storage using blocks
            print("Uploading encrypted file to Azure Storage...")
            block_size = 4 * 1024 * 1024  # 4 MB chunks
            blocks = []
            
            with open(f"{file_path}.bin", 'rb') as f:
                block_num = 0
                while True:
                    block_data = f.read(block_size)
                    if not block_data:
                        break
                        
                    # Generate block ID (must be base64 encoded and consistent length)
                    block_id = b64encode(f"block-{block_num:04d}".encode()).decode()
                    blocks.append(block_id)
                    
                    # Upload block with retries
                    max_retries = 3
                    for retry in range(max_retries):
                        try:
                            block_uri = f"{file_uri}&comp=block&blockid={block_id}"
                            upload_response = requests.put(
                                block_uri,
                                headers={
                                    "x-ms-blob-type": "BlockBlob",
                                    "x-ms-version": "2021-08-06",
                                    "Content-Length": str(len(block_data))
                                },
                                data=block_data
                            )
                            
                            if upload_response.ok:
                                uploaded_mb = (block_num + 1) * block_size / (1024 * 1024)
                                total_mb = encrypted_size / (1024 * 1024)
                                print(f"\rProgress: {uploaded_mb:.1f} MB / {total_mb:.1f} MB ({(uploaded_mb/total_mb*100):.1f}%)", end="", flush=True)
                                break
                            else:
                                print(f"\nBlock upload failed (attempt {retry + 1}/{max_retries}): {upload_response.status_code}")
                                try:
                                    print(f"Error details: {upload_response.text}")
                                except:
                                    pass
                                if retry == max_retries - 1:
                                    raise Exception(f"Failed to upload block after {max_retries} attempts")
                                time.sleep(5)
                        except Exception as e:
                            if retry == max_retries - 1:
                                raise Exception(f"Error uploading block: {str(e)}")
                            time.sleep(5)
                    
                    block_num += 1
            
            print("\nFinalizing blob upload...")
            # Construct block list XML
            block_list_xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
            for block_id in blocks:
                block_list_xml += f'<Latest>{block_id}</Latest>'
            block_list_xml += '</BlockList>'
            
            # Commit block list
            commit_blocks_uri = f"{file_uri}&comp=blocklist"
            commit_response = requests.put(
                commit_blocks_uri,
                data=block_list_xml,
                headers={
                    "x-ms-version": "2017-04-17"  # Match the SAS token version
                }
            )
            
            if not commit_response.ok:
                print(f"Failed to commit block list: {commit_response.status_code}")
                try:
                    print(f"Error details: {commit_response.text}")
                except:
                    pass
                raise Exception("Failed to commit block list")
            
            print("File upload completed")

            # Commit the file
            print("Committing file...")
            commit_response = requests.post(
                f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions/{content_version['id']}/files/{content_file['id']}/commit",
                headers=self.headers,
                json={"fileEncryptionInfo": encryption_info}
            )
            if not commit_response.ok:
                print(f"Commit request failed: {commit_response.status_code}")
                try:
                    error_details = commit_response.json()
                    print(f"Commit error details: {json.dumps(error_details, indent=2)}")
                except:
                    print(f"Commit error text: {commit_response.text}")
                raise Exception("File commit request failed")
            print("File commit request sent successfully")

            # Wait for file commit to complete
            print("Waiting for file commit to complete...")
            max_attempts = 60  # 5 minutes total
            for attempt in range(max_attempts):
                status = requests.get(
                    f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}/microsoft.graph.{app_type}/contentVersions/{content_version['id']}/files/{content_file['id']}",
                    headers=self.headers
                ).json()
                
                print(f"File status (attempt {attempt + 1}): {status.get('uploadState', 'unknown')}")
                
                if status.get('uploadState') == 'commitFileSuccess':
                    print("File commit succeeded!")
                    break
                    
                if status.get('uploadState') == 'commitFileFailed':
                    try:
                        print(f"Full status response: {json.dumps(status, indent=2)}")
                    except:
                        print(f"Full status response: {status}")
                    raise Exception("File commit failed")
                    
                if attempt < max_attempts - 1:
                    print("Waiting 5 seconds before next check...")
                    time.sleep(5)  # Wait 5 seconds between checks
                else:
                    raise Exception("Timeout waiting for file commit to complete")

            return content_version['id']  # Only return the content version ID
        except Exception as e:
            raise Exception(f"Error during file upload: {str(e)}")

    def add_app_logo(self, app_id, app_type, app_name):
        """Add logo to the app in Intune"""
        try:
            # Convert app name to logo filename format
            logo_filename = app_name.lower().replace(" ", "_") + ".png"
            logo_path = os.path.join("Logos", logo_filename)
            
            # Check if we have a local logo file
            if not os.path.exists(logo_path):
                print(f"No logo found at {logo_path}, skipping logo upload")
                return
            
            # Read the local logo file
            with open(logo_path, 'rb') as f:
                logo_data = f.read()
            
            # Convert to base64
            logo_base64 = b64encode(logo_data).decode()
            
            # Prepare the logo update payload
            logo_body = {
                "@odata.type": f"#microsoft.graph.{app_type}",
                "largeIcon": {
                    "@odata.type": "#microsoft.graph.mimeContent",
                    "type": "image/png",
                    "value": logo_base64
                }
            }
            
            # Update the app with the logo
            response = requests.patch(
                f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}",
                headers=self.headers,
                json=logo_body
            )
            
            if response.ok:
                logger.info("Logo added successfully")
            else:
                logger.warning(f"Could not add app logo. Status code: {response.status_code}")
                try:
                    logger.warning(f"Error details: {response.json()}")
                except:
                    logger.warning(f"Error text: {response.text}")
        except Exception as e:
            logger.warning(f"Could not add app logo. Error: {str(e)}")

    def finalize_upload(self, app_id, app_type, content_version_id):
        """Finalize the app upload"""
        try:
            # Get current app state to preserve important fields
            current_app = requests.get(
                f"{self.base_url}/deviceAppManagement/mobileApps/{app_id}",
                headers=self.headers
            ).json()

            print("Current app state:", json.dumps(current_app, indent=2))

            # Build payload with required fields
            payload = {
                "@odata.type": f"#microsoft.graph.{app_type}",
                "committedContentVersion": str(content_version_id)  # Ensure it's a string
            }

            # Copy over required fields if they exist
            for field in [
                "displayName", "description", "publisher", "fileName",
                "bundleId", "versionNumber", "primaryBundleId", "primaryBundleVersion",
                "minimumSupportedOperatingSystem", "developer", "owner", "privacyInformationUrl"
            ]:
                if field in current_app:
                    payload[field] = current_app[field]

            print("Finalize payload:", json.dumps(payload, indent=2))

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

            # Add logo after successful finalization
            self.add_app_logo(app_id, app_type, current_app['displayName'])

            # For 204 No Content, just return success
            if response.status_code == 204:
                print("Successfully finalized upload")
                return True

            # For other successful responses, return the JSON
            return response.json()
        except Exception as e:
            raise Exception(f"Error finalizing upload: {str(e)}")
