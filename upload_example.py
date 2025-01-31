
from app_upload import IntuneUploader

# Initialize with your access token
uploader = IntuneUploader(access_token="your_access_token")

# App info from your JSON
app_info = {
    "name": "Test App",
    "description": "Test Description",
    "version": "1.0",
    "bundleId": "com.test.app",
    "fileName": "test.pkg"
}

# Upload process
app = uploader.create_app(app_info)
encryption_info = uploader.encrypt_file("path/to/your/app.pkg")
app_type = "macOSPkgApp"  # or "macOSDmgApp" for .dmg files
content_version_id = uploader.upload_file(app['id'], app_type, "path/to/your/app.pkg", encryption_info)
uploader.finalize_upload(app['id'], app_type, content_version_id)
