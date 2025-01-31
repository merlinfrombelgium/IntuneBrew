// MSAL configuration and Graph API integration
const msalConfig = {
  auth: {
    clientId: window.AZURE_CLIENT_ID || '',
    authority: `https://login.microsoftonline.com/${window.AZURE_TENANT_ID || ''}`,
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false
  }
};

const msalInstance = new msal.PublicClientApplication(msalConfig);

// Handle the redirect promise
msalInstance.handleRedirectPromise().catch(err => {
    console.error(err);
});

// Login function
async function signIn() {
    try {
        const loginRequest = {
            scopes: ["DeviceManagementApps.ReadWrite.All"]
        };
        await msalInstance.loginPopup(loginRequest);
        window.location.reload();
    } catch (err) {
        console.error("Login failed:", err);
    }
}

// Check if user is authenticated
function getAccount() {
    const currentAccounts = msalInstance.getAllAccounts();
    if (currentAccounts.length === 0) {
        signIn();
        return null;
    } else if (currentAccounts.length > 1) {
        console.warn("Multiple accounts detected.");
        return currentAccounts[0];
    } else {
        return currentAccounts[0];
    }
}

const graphScopes = ['DeviceManagementApps.ReadWrite.All'];

async function getTokenSilently() {
    const account = getAccount();
    if (!account) {
        throw new Error('No active account');
    }

    try {
        const response = await msalInstance.acquireTokenSilent({
            scopes: graphScopes,
            account: account
        });
        return response.accessToken;
    } catch (error) {
        if (error instanceof msal.InteractionRequiredAuthError) {
            return msalInstance.acquireTokenPopup({
                scopes: graphScopes,
                account: account
            }).then(response => {
                return response.accessToken;
            });
        }
        throw error;
    }
}

async function callGraphAPI(endpoint, method = 'GET', body = null) {
  const token = await getTokenSilently();
  const headers = {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  };

  const options = {
    method,
    headers,
    body: body ? JSON.stringify(body) : null
  };

  const response = await fetch(`https://graph.microsoft.com/beta${endpoint}`, options);
  if (!response.ok) {
    throw new Error(`Graph API error: ${response.statusText}`);
  }
  return response.json();
}

async function getIntuneApps() {
  const response = await callGraphAPI('/deviceAppManagement/mobileApps');
  return response.value.filter(app => 
    app['@odata.type']?.includes('macOS')
  );
}

async function uploadAppToIntune(appInfo) {
  // Create app in Intune
  const appBody = {
    '@odata.type': '#microsoft.graph.macOSPkgApp',
    displayName: appInfo.name,
    description: appInfo.description,
    publisher: appInfo.publisher,
    fileName: appInfo.fileName,
    bundleId: appInfo.bundleId,
    versionNumber: appInfo.version,
    // Add other required properties
  };

  const app = await callGraphAPI('/deviceAppManagement/mobileApps', 'POST', appBody);

  // Handle content version and file upload
  // This would need to be implemented based on your specific requirements
  return app;
}

function App() {
    const [apps, setApps] = React.useState([]);
    const [selectedApp, setSelectedApp] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [appStatuses, setAppStatuses] = React.useState({});
    const [uploadStates, setUploadStates] = React.useState({});
    const [isAuthenticated, setIsAuthenticated] = React.useState(false);

    React.useEffect(() => {
        // Check authentication status
        const account = getAccount();
        setIsAuthenticated(!!account);
        
        // Load supported apps
        fetch('/api/apps')
            .then(res => res.json())
            .then(data => {
                const appEntries = Object.entries(data);
                setApps(appEntries);
                setLoading(false);
            });
    }, []);

    React.useEffect(() => {
        async function fetchIntuneStatus() {
            if (!isAuthenticated) return;
            
            setLoading(true);
            try {
                const intuneApps = await getIntuneApps();
                const statuses = {};
                apps.forEach(([id]) => {
                    const intuneApp = intuneApps.find(app => 
                        app.displayName.toLowerCase() === id.toLowerCase());
                    statuses[id] = {
                        status: intuneApp ? 'Up-to-date' : 'Not in Intune',
                        color: intuneApp ? 'green' : 'red',
                        intuneVersion: intuneApp?.versionNumber || 'Not in Intune'
                    };
                });
                setAppStatuses(statuses);
            } catch (error) {
                console.error('Error fetching Intune status:', error);
            }
            setLoading(false);
        }

        fetchIntuneStatus();
    }, [isAuthenticated, apps]);

    const placeholderLogo = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='128' height='128' viewBox='0 0 24 24'%3E%3Cpath fill='%23cccccc' d='M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z'/%3E%3C/svg%3E";
    
    return (
        <div className="min-h-screen bg-gray-100 relative">
            <div className="floating-container">
                {loading ? (
                    <div className="spinner"></div>
                ) : (
                    <button onClick={() => {setLoading(true); getIntuneApps().then(()=>setLoading(false));}} className="refresh-button">
                        🔄
                    </button>
                )}
            </div>
            <header className="bg-white shadow">
                <div className="max-w-7xl mx-auto py-6 px-4">
                    <img src="/static/banner.png" 
                         alt="IntuneBrew Banner" 
                         className="banner" />
                    <div className="text-center mt-4 text-gray-600">
                        Made with ❤️ by <a href="https://github.com/ugurkocde" className="text-blue-600 hover:text-blue-800">Ugur Koc</a>
                    </div>
                </div>
            </header>
            <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    {apps.map(([id, url]) => (
                        <div key={id} 
                             className="bg-white overflow-hidden shadow rounded-lg p-4 hover:shadow-lg cursor-pointer"
                             onClick={async () => {
                                 try {
                                     const res = await fetch(`/api/app/${id}`);
                                     if (!res.ok) throw new Error('Failed to fetch app details');
                                     const data = await res.json();
                                     setSelectedApp(data);
                                 } catch (error) {
                                     console.error('Error loading app details:', error);
                                 }
                             }}>
                            <img src={`/Logos/${id}.png`} 
                                 className="w-16 h-16 object-contain mb-4"
                                 onError={(e) => {
                                     if (!e.target.retryAttempt) {
                                         e.target.retryAttempt = true;
                                         e.target.src = placeholderLogo;
                                         e.target.title = "Logo needed";
                                     }
                                 }}/>
                            <div>
                                <div className="flex flex-col items-center mb-4">
                                {appStatuses[id] && (
                                    <span 
                                        className="status-badge mb-2"
                                        style={{
                                            backgroundColor: appStatuses[id].color === 'red' ? '#FEE2E2' :
                                                           appStatuses[id].color === 'yellow' ? '#FEF3C7' :
                                                           '#D1FAE5',
                                            color: appStatuses[id].color === 'red' ? '#DC2626' :
                                                   appStatuses[id].color === 'yellow' ? '#D97706' :
                                                   '#059669'
                                        }}
                                    >
                                        {appStatuses[id].status}
                                    </span>
                                )}
                                <h2 className="text-xl font-semibold text-center">{id.replace(/_/g, ' ')}</h2>
                            </div>
                            </div>
                        </div>
                    ))}
                </div>

                {selectedApp && (
                    <div 
                        className="fixed inset-0 bg-gray-800 bg-opacity-75 overflow-y-auto h-full w-full z-50 backdrop-blur-sm"
                        onClick={(e) => {
                            if (e.target === e.currentTarget) {
                                setSelectedApp(null);
                            }
                        }}
                    >
                        <div className="relative top-20 mx-auto p-6 border w-[42rem] shadow-2xl rounded-lg bg-white">
                            <div className="flex justify-between items-center mb-6">
                                <div className="flex items-center gap-4">
                                    <img 
                                        src={`/Logos/${selectedApp.name.toLowerCase().replace(/\s+/g, '_')}.png`}
                                        onError={(e) => {
                                            e.target.onerror = null;
                                            e.target.src = placeholderLogo;
                                        }}
                                        className="w-10 h-10 object-contain"
                                        alt={selectedApp.name}
                                    />
                                    <h3 className="text-2xl font-bold">{selectedApp.name}</h3>
                                </div>
                                <button 
                                    onClick={() => setSelectedApp(null)}
                                    className="text-gray-500 hover:text-gray-700 text-xl"
                                >
                                    ✕
                                </button>
                            </div>
                            <div className="space-y-4">
                                <div className="space-y-4">
                                    <div className="space-y-2">
                                        <div className="relative group flex items-center space-x-2">
                                            <span className="font-semibold w-24">Version:</span>
                                            <code className="bg-gray-100 p-2 rounded flex-1">{selectedApp.version}</code>
                                            <button onClick={() => navigator.clipboard.writeText(selectedApp.version)} className="text-blue-600 hover:text-blue-800">
                                                📋
                                            </button>
                                        </div>
                                        {appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')] && (
                                            <div className="flex items-center space-x-2">
                                                <span className="font-semibold w-24">Intune:</span>
                                                <div className="flex-1">
                                                    <span 
                                                        className="status-badge"
                                                        style={{
                                                            backgroundColor: appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].color === 'red' ? '#FEE2E2' :
                                                                            appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].color === 'yellow' ? '#FEF3C7' :
                                                                            '#D1FAE5',
                                                            color: appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].color === 'red' ? '#DC2626' :
                                                                    appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].color === 'yellow' ? '#D97706' :
                                                                    '#059669'
                                                        }}
                                                    >
                                                        {appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].status}
                                                        {appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].intuneVersion !== 'Not in Intune' && 
                                                            ` (${appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].intuneVersion})`}
                                                    </span>
                                                </div>
                                            </div>
                                        )}
                                        {selectedApp.previous_version && (
                                            <div className="absolute hidden group-hover:block bg-black text-white p-2 rounded -top-8 left-24 text-sm">
                                                Previous: {selectedApp.previous_version}
                                            </div>
                                        )}
                                    </div>

                                    {uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')] && (
                                        <div className="mt-2 text-sm">
                                            <div className="text-gray-600">
                                                Last {uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].status === 'error' ? 'attempt' : 'updated'}: {
                                                    new Date(uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].timestamp).toLocaleString()
                                                }
                                            </div>
                                            {uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].status === 'error' && (
                                                <div className="mt-1 text-red-600">
                                                    Error details: {uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].error}
                                                </div>
                                            )}
                                        </div>
                                    )}

                                    <div className="flex items-center space-x-2">
                                        <span className="font-semibold w-24">Bundle ID:</span>
                                        <code className="bg-gray-100 p-2 rounded flex-1">{selectedApp.bundleId || 'Not specified'}</code>
                                        <button onClick={() => navigator.clipboard.writeText(selectedApp.bundleId)} className="text-blue-600 hover:text-blue-800">
                                            📋
                                        </button>
                                    </div>

                                    <div className="flex items-center space-x-2">
                                        <span className="font-semibold w-24">URL:</span>
                                        <code className="bg-gray-100 p-2 rounded flex-1 break-all">{selectedApp.url}</code>
                                        <button onClick={() => navigator.clipboard.writeText(selectedApp.url)} className="text-blue-600 hover:text-blue-800">
                                            📋
                                        </button>
                                    </div>

                                    <div className="flex items-center space-x-2">
                                        <span className="font-semibold w-24">Filename:</span>
                                        <code className="bg-gray-100 p-2 rounded flex-1">{selectedApp.fileName}</code>
                                        <button onClick={() => navigator.clipboard.writeText(selectedApp.fileName)} className="text-blue-600 hover:text-blue-800">
                                            📋
                                        </button>
                                    </div>
                                </div>

                                <div className="col-span-2">
                                    <p className="font-semibold mb-1">Description:</p>
                                    <p className="break-words bg-gray-100 p-2 rounded">{selectedApp.description}</p>
                                </div>

                                <div className="pt-4 flex justify-between items-center">
                                    <div className="flex gap-2">
                                        <div className="relative">
                                            <button 
                                                onClick={() => document.getElementById('exportMenu').classList.toggle('hidden')}
                                                className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                                            >
                                                Export
                                            </button>
                                            <div id="exportMenu" className="hidden absolute left-0 mt-2 w-32 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5">
                                                <div className="py-1">
                                                    <button
                                                        onClick={() => exportData(selectedApp, 'csv')}
                                                        className="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 w-full text-left"
                                                    >
                                                        CSV
                                                    </button>
                                                    <button
                                                        onClick={() => exportData(selectedApp, 'json')}
                                                        className="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 w-full text-left"
                                                    >
                                                        JSON
                                                    </button>
                                                    <button
                                                        onClick={() => exportData(selectedApp, 'yaml')}
                                                        className="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 w-full text-left"
                                                    >
                                                        YAML
                                                    </button>
                                                </div>
                                            </div>
                                        </div>
                                        <button
                                            onClick={async () => {
                                                const appId = selectedApp.name.toLowerCase().replace(/\s+/g, '_');
                                                const currentStatus = appStatuses[appId];
                                                
                                                // Check if app is already in Intune with same version
                                                if (currentStatus?.intuneVersion === selectedApp.version) {
                                                    return; // Already up to date, do nothing
                                                }
                                                
                                                setUploadStates(prev => ({
                                                    ...prev,
                                                    [appId]: { status: 'uploading', timestamp: new Date().toISOString() }
                                                }));
                                                try {
                                                    const token = await getTokenSilently();
                                                    const response = await fetch('/api/upload', {
                                                        method: 'POST',
                                                        headers: {
                                                            'Content-Type': 'application/json',
                                                            'Authorization': `Bearer ${token}`
                                                        },
                                                        body: JSON.stringify(selectedApp)
                                                    });
                                                    if (!response.ok) throw new Error(await response.text());
                                                    const result = await response.json();
                                                    setUploadStates(prev => ({
                                                        ...prev,
                                                        [appId]: { status: 'success', timestamp: new Date().toISOString() }
                                                    }));
                                                    // Refresh Intune status
                                                    const intuneApps = await getIntuneApps();
                                                    const newStatuses = {...appStatuses};
                                                    const intuneApp = intuneApps.find(app => 
                                                        app.displayName.toLowerCase() === selectedApp.name.toLowerCase()
                                                    );
                                                    newStatuses[appId] = {
                                                        status: intuneApp ? 'Up-to-date' : 'Not in Intune',
                                                        color: intuneApp ? 'green' : 'red',
                                                        intuneVersion: intuneApp?.versionNumber || 'Not in Intune'
                                                    };
                                                    setAppStatuses(newStatuses);
                                                } catch (error) {
                                                    console.error('Upload error:', error);
                                                    setUploadStates(prev => ({
                                                        ...prev,
                                                        [appId]: { 
                                                            status: 'error', 
                                                            timestamp: new Date().toISOString(),
                                                            error: error.message
                                                        }
                                                    }));
                                                }
                                                setSelectedApp(null);
                                            }}
                                            className={`px-4 py-2 rounded ${
                                                uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'uploading'
                                                    ? 'bg-gray-400 cursor-not-allowed'
                                                    : uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'error'
                                                    ? 'bg-red-600 hover:bg-red-700'
                                                    : appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'Up-to-date'
                                                    ? 'bg-gray-400 cursor-not-allowed'
                                                    : 'bg-green-600 hover:bg-green-700'
                                            } text-white`}
                                            disabled={uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'uploading' || 
                                                     (appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'Up-to-date' &&
                                                      appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.intuneVersion === selectedApp.version)}
                                        >
                                            {uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'uploading'
                                                ? 'Uploading...'
                                                : uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'error'
                                                ? 'Error - Try again'
                                                : appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'Up-to-date'
                                                ? 'Already uploaded'
                                                : 'Upload to Intune'}
                                        </button>
                                    </div>
                                    <a 
                                        href={selectedApp.homepage}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        className="text-blue-600 hover:text-blue-800"
                                    >
                                        Visit Homepage →
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>
                )}
            </main>
            <footer className="text-center py-4 text-gray-600">
                Made with ❤️ by <a href="https://github.com/ugurkocde" className="text-blue-600 hover:text-blue-800">Ugur Koc</a> | <a href="https://github.com/ugurkocde/IntuneBrew" className="text-blue-600 hover:text-blue-800">GitHub Repository</a>
            </footer>
        </div>
    );
}

// Export functionality
function exportData(app, format) {
    let content = '';
    const filename = `${app.name.toLowerCase().replace(/\s+/g, '_')}`;

    switch (format) {
        case 'csv':
            content = `Name,Version,Bundle ID,URL,Filename,Description\n"${app.name}","${app.version}","${app.bundleId || ''}","${app.url}","${app.fileName}","${app.description}"`;
            download(`${filename}.csv`, content);
            break;
        case 'json':
            content = JSON.stringify(app, null, 2);
            download(`${filename}.json`, content);
            break;
        case 'yaml':
            content = `name: ${app.name}
version: ${app.version}
bundleId: ${app.bundleId || ''}
url: ${app.url}
fileName: ${app.fileName}
description: ${app.description}
homepage: ${app.homepage}`;
            download(`${filename}.yaml`, content);
            break;
    }
}

function download(filename, content) {
    const element = document.createElement('a');
    element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(content));
    element.setAttribute('download', filename);
    element.style.display = 'none';
    document.body.appendChild(element);
    element.click();
    document.body.removeChild(element);
}

// Close export menu when clicking outside
document.addEventListener('click', (e) => {
    const exportMenu = document.getElementById('exportMenu');
    const exportButton = e.target.closest('button');

    if (exportMenu && !exportMenu.classList.contains('hidden') && !exportButton) {
        exportMenu.classList.add('hidden');
    }
});

class ErrorBoundary extends React.Component {
    constructor(props) {
        super(props);
        this.state = { hasError: false };
    }

    static getDerivedStateFromError(error) {
        return { hasError: true };
    }

    componentDidCatch(error, errorInfo) {
        console.error('React Error:', error, errorInfo);
    }

    render() {
        if (this.state.hasError) {
            return <div className="text-red-600 p-4">Something went wrong. Please refresh the page.</div>;
        }
        return this.props.children;
    }
}

ReactDOM.render(
    <ErrorBoundary>
        <App />
    </ErrorBoundary>,
    document.getElementById('root')
);

// Add global error handler
window.onerror = function(msg, url, lineNo, columnNo, error) {
    console.error('Global error:', msg, url, lineNo, columnNo, error);
    return false;
};