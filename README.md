<h1 align="center">🍺 IntuneBrew</font></h1>

IntuneBrew is a PowerShell-based tool that simplifies the process of uploading and managing macOS applications in Microsoft Intune. It automates the entire workflow from downloading apps to uploading them to Intune, complete with proper metadata and logos.

> [!IMPORTANT]
> 🚧 **Public Preview Notice**
> 
> IntuneBrew is currently in Public Preview. While it's fully functional, you might encounter some rough edges. Your feedback and contributions are crucial in making this tool better!
> 
> - 📝 [Submit Feedback](https://github.com/ugurkocde/IntuneBrew/issues/new?labels=feedback)
> - 🐛 [Report Bugs](https://github.com/ugurkocde/IntuneBrew/issues/new?labels=bug)
> - 💡 [Request Features](https://github.com/ugurkocde/IntuneBrew/issues/new?labels=enhancement)
>
> Thank you for being an early adopter! 🙏

![IntuneBrew Demo](IntuneBrew_Demo.gif)

## ✨ Features
- 🚀 Automated app uploads to Microsoft Intune
- 📦 Supports both .dmg and .pkg files
- 🔄 Automatic version checking and updates
- 🖼️ Automatic app icon integration
- 📊 Progress tracking for large file uploads
- 🔐 Secure authentication with Microsoft Graph API
- 🎯 Smart duplicate detection
- 💫 Bulk upload support

## 🚀 Getting Started

### Prerequisites

- PowerShell 7.0 or higher
- Microsoft Graph PowerShell SDK
- Azure App Registration with appropriate permissions OR Manual Connection via Interactive Sign-In
- Windows or macOS operating system

### Installation

1. Clone the repository:
2. Install required PowerShell modules:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

3. Configure your environment variables or update the config file with your Azure AD details.

## 📝 Usage

### Basic Usage

```powershell
.\IntuneBrew.ps1
```

Follow the interactive prompts to:
1. Select which apps to upload
2. Authenticate with Microsoft Graph
3. Monitor the upload progress
4. View the results in Intune

### Supported Applications

Currently supported applications include:
- Adobe Acrobat Reader
- Company Portal
- Google Chrome
- KeePassXC
- Microsoft Teams
- Mozilla Firefox
- Parallels Desktop
- Slack
- Spotify
- Windows App
- Zoom

> [!NOTE]
> Missing an app? Feel free to [request additional app support](https://github.com/ugurkocde/IntuneBrew/issues/new?labels=app-request) by creating an issue!

## 🔧 Configuration

### Azure App Registration

1. Create a new App Registration in Azure
2. Add the following API permissions:
   - DeviceManagementApps.ReadWrite.All
3. Update the parameters in the script with your Azure details.
    - $appid = '<YourAppIdHere>' # App ID of the App Registration
    - $tenantid = '<YourTenantIdHere>' # Tenant ID of your EntraID
    - $certThumbprint = '<YourCertificateThumbprintHere>' # Thumbprint of the certificate associated with the App Registration

## 🤔 Troubleshooting

### Common Issues

1. **File Access Errors**
   - Ensure no other process is using the file
   - Try deleting temporary files manually
   - Restart the script

2. **Upload Failures**
   - Check your internet connection
   - Verify Azure AD permissions
   - Ensure file sizes don't exceed Intune limits

3. **Authentication Issues**
   - Verify your Azure AD credentials
   - Check tenant ID configuration
   - Ensure required permissions are granted

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Thanks to all contributors who have helped shape IntuneBrew
- Microsoft Graph API documentation and community
- The PowerShell community for their invaluable resources

## 📞 Support

If you encounter any issues or have questions:
1. Check the [Issues](https://github.com/ugurkocde/IntuneBrew/issues) page
2. Review the troubleshooting guide
3. Open a new issue if needed

---

Made with ❤️ by [Ugur Koc](https://github.com/ugurkocde)

## Certificate-Based Authentication Setup

IntuneBrew uses certificate-based authentication with Microsoft Graph API for enhanced security. Here's how to set it up:

### 1. Generate a Self-Signed Certificate

```powershell
# Generate a new self-signed certificate
$cert = New-SelfSignedCertificate -Subject "CN=IntuneBrew" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2) `
    -KeyUsageProperty Sign `
    -KeyUsage DigitalSignature `
    -Type SSLServerAuthentication

# Export the certificate for Azure AD
$certPath = "intunebrew.cer"
Export-Certificate -Cert $cert -FilePath $certPath -Type CERT

# Export the certificate in PEM format for the application
$pemPath = "intunebrew.pem"
$base64 = [System.Convert]::ToBase64String($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
"-----BEGIN CERTIFICATE-----`n" + ($base64 -replace '.{64}', '$0`n') + "`n-----END CERTIFICATE-----" | Out-File -FilePath $pemPath -Encoding ASCII

Write-Host "Certificate thumbprint: $($cert.Thumbprint)"
```

### 2. Configure Azure AD App Registration

1. Create a new App Registration in Azure Portal
2. Navigate to "Certificates & secrets"
3. Upload the `.cer` file generated above
4. Add the required API permissions:
   - DeviceManagementApps.ReadWrite.All
5. Grant admin consent for the permissions

### 3. Configure Environment Variables

Create a `.env` file with the following variables:
```env
# Azure AD App Registration details
AZURE_APP_ID=your-app-id
AZURE_TENANT_ID=your-tenant-id

# Certificate configuration
AZURE_CLIENT_CERT_PATH=intunebrew.pem
```

### 4. Verify Certificate Setup

The application will automatically use certificate-based authentication when the environment variables are properly configured. The certificate will be used to obtain access tokens from Azure AD for Microsoft Graph API calls.
