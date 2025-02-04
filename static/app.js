// MSAL configuration and Graph API integration
const msalConfig = {
  auth: {
    clientId: window.AZURE_CLIENT_ID || '',
    authority: `https://login.microsoftonline.com/${window.AZURE_TENANT_ID || ''}`
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false
  }
};

const msalInstance = new msal.PublicClientApplication(msalConfig);

// Token management
let cachedToken = null;
let tokenExpiry = null;

async function getTokenSilently() {
    // Check if we have a valid cached token
    if (cachedToken && tokenExpiry && Date.now() < tokenExpiry) {
        return cachedToken;
    }

    try {
        const response = await fetch('/api/token/', {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        if (!response.ok) {
            throw new Error('Failed to get token');
        }
        
        const data = await response.json();
        cachedToken = data.access_token;
        // Set token expiry to 55 minutes (tokens usually valid for 1 hour)
        tokenExpiry = Date.now() + (55 * 60 * 1000);
        return cachedToken;
    } catch (error) {
        console.error('Error getting token:', error);
        throw error;
    }
}

// Since we're using certificate auth, we don't need interactive login
function getAccount() {
    return true; // Certificate auth is always "logged in"
}

const graphScopes = ['https://graph.microsoft.com/.default'];

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
  const response = await callGraphAPI('/deviceAppManagement/mobileApps?$filter=(isof(\'microsoft.graph.macOSDmgApp\') or isof(\'microsoft.graph.macOSPkgApp\'))');
  console.log('Raw Graph API response:', JSON.stringify(response, null, 2));
  return response.value;
}

// Cache for Intune apps
let intuneAppsCache = null;
let lastFetchTime = null;
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

async function getIntuneAppsCached() {
  const now = Date.now();
  if (!intuneAppsCache || !lastFetchTime || (now - lastFetchTime) > CACHE_DURATION) {
    console.log('Fetching fresh Intune apps data...');
    intuneAppsCache = await getIntuneApps();
    lastFetchTime = now;
  } else {
    console.log('Using cached Intune apps data');
  }
  return intuneAppsCache;
}

async function refreshIntuneCache() {
  console.log('Forcing refresh of Intune apps cache...');
  intuneAppsCache = await getIntuneApps();
  lastFetchTime = Date.now();
  return intuneAppsCache;
}

async function getSpecificIntuneApp(appName) {
  const apps = await getIntuneAppsCached();
  // Find all versions of the app
  const appVersions = apps.filter(app => app.displayName.toLowerCase() === appName.toLowerCase());
  
  if (appVersions.length === 0) return null;
  if (appVersions.length === 1) return appVersions[0];
  
  // Sort by lastModifiedDateTime and primaryBundleVersion to get the latest version
  return appVersions.sort((a, b) => {
    // First try to compare by lastModifiedDateTime
    const dateA = new Date(a.lastModifiedDateTime);
    const dateB = new Date(b.lastModifiedDateTime);
    if (dateA > dateB) return -1;
    if (dateA < dateB) return 1;
    
    // If dates are equal, compare versions
    return compareVersions(b.primaryBundleVersion, a.primaryBundleVersion);
  })[0];
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

// Add this before the App component
function ConfirmDialog({ isOpen, onClose, onConfirm, appName, currentStatus, currentVersion, newVersion }) {
    if (!isOpen) return null;

    return (
        <div className="fixed inset-0 bg-gray-800 bg-opacity-75 flex items-center justify-center z-50">
            <div className="bg-gray-900 text-white rounded-lg p-6 max-w-md w-full mx-4 shadow-xl">
                <h2 className="text-xl font-semibold mb-4">IntuneBrew says</h2>
                <p className="mb-4">Are you sure you want to update {appName}?</p>
                <div className="space-y-2 mb-6">
                    <p>Current status: {currentStatus}</p>
                    <p>Current version: {currentVersion}</p>
                    <p>New version: {newVersion}</p>
                </div>
                <div className="flex justify-end space-x-4">
                    <button
                        onClick={onClose}
                        className="px-4 py-2 text-gray-300 hover:text-white"
                    >
                        Cancel
                    </button>
                    <button
                        onClick={onConfirm}
                        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
                    >
                        OK
                    </button>
                </div>
            </div>
        </div>
    );
}

function App() {
    const [apps, setApps] = React.useState([]);
    const [selectedApp, setSelectedApp] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [appStatuses, setAppStatuses] = React.useState({});
    const [uploadStates, setUploadStates] = React.useState({});
    const [isAuthenticated, setIsAuthenticated] = React.useState(false);
    const [showConfirmDialog, setShowConfirmDialog] = React.useState(false);
    const [confirmDialogProps, setConfirmDialogProps] = React.useState(null);
    const [searchQuery, setSearchQuery] = React.useState('');
    const [statusFilter, setStatusFilter] = React.useState('all');
    const [newApps, setNewApps] = React.useState([]);
    const [cachedLogos, setCachedLogos] = React.useState({});

    // Group and filter apps
    const groupedAndFilteredApps = React.useMemo(() => {
        const groups = {
            'New ⭐': [],
            'Needs Update': [],
            'Up-to-date': [],
            'Not in Intune': []
        };

        apps.forEach(([id, url]) => {
            const status = appStatuses[id]?.status || 'Not in Intune';
            const appName = id.replace(/_/g, ' ');
            
            // Apply search filter
            if (searchQuery && !appName.toLowerCase().includes(searchQuery.toLowerCase())) {
                return;
            }

            // Check if app is new
            if (newApps.includes(id)) {
                groups['New ⭐'].push([id, url]);
                return;
            }

            // Group apps by status
            if (status === 'Up-to-date') {
                groups['Up-to-date'].push([id, url]);
            } else if (status === 'Not in Intune') {
                groups['Not in Intune'].push([id, url]);
            } else {
                groups['Needs Update'].push([id, url]);
            }
        });

        // Filter by status if needed
        if (statusFilter !== 'all') {
            return { [statusFilter]: groups[statusFilter] };
        }

        return groups;
    }, [apps, appStatuses, searchQuery, statusFilter, newApps]);

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
                const intuneApps = await getIntuneAppsCached();
                const statuses = {};
                
                for (const [id] of apps) {
                    const appName = id.replace(/_/g, ' ');
                    console.log(`\nChecking app: ${appName}`);
                    
                    // Find all versions of the app
                    const appVersions = intuneApps.filter(app => 
                        app.displayName.toLowerCase() === appName.toLowerCase()
                    );
                    console.log('Found versions in Intune:', appVersions.map(app => ({
                        version: app.primaryBundleVersion,
                        modified: app.lastModifiedDateTime
                    })));
                    
                    // Get the latest version by comparing version numbers and lastModifiedDateTime
                    const intuneApp = appVersions.sort((a, b) => {
                        // First compare version numbers
                        const versionComparison = compareVersions(b.primaryBundleVersion, a.primaryBundleVersion);
                        if (versionComparison !== 0) return versionComparison;
                        
                        // If versions are equal, use lastModifiedDateTime
                        const dateA = new Date(a.lastModifiedDateTime);
                        const dateB = new Date(b.lastModifiedDateTime);
                        return dateB - dateA;
                    })[0];
                    
                    console.log('Found in Intune:', intuneApp ? 'Yes' : 'No');
                    if (intuneApp) {
                        console.log('Latest Intune version:', intuneApp.primaryBundleVersion);
                        console.log('Last modified:', intuneApp.lastModifiedDateTime);
                        
                        // Log if there are multiple versions
                        if (appVersions.length > 1) {
                            console.log('Warning: Multiple versions found in Intune:', 
                                appVersions.map(app => `${app.primaryBundleVersion} (${app.lastModifiedDateTime})`));
                        }
                    }
                    
                    // Get the local app version
                    const localAppResponse = await fetch(`/api/app/${id}`);
                    const localApp = await localAppResponse.json();
                    const localVersion = localApp.version;
                    console.log('Local version:', localVersion);
                    
                    if (intuneApp) {
                        // Compare versions
                        const intuneVersion = intuneApp.primaryBundleVersion || 'Not available';
                        console.log('Comparing versions:', {
                            intuneVersion,
                            localVersion,
                            intuneVersionRaw: intuneApp.primaryBundleVersion,
                            lastModified: intuneApp.lastModifiedDateTime
                        });
                        
                        const comparison = compareVersions(intuneVersion, localVersion);
                        const needsUpdate = comparison < 0;
                        console.log('Version comparison result:', {
                            comparison,
                            needsUpdate
                        });
                        
                        statuses[id] = {
                            status: needsUpdate ? 'Needs Update' : 'Up-to-date',
                            color: needsUpdate ? 'yellow' : 'green',
                            intuneVersion: intuneVersion,
                            lastModified: intuneApp.lastModifiedDateTime,
                            multipleVersions: appVersions.length > 1 ? appVersions.map(app => ({
                                version: app.primaryBundleVersion,
                                modified: app.lastModifiedDateTime
                            })) : null
                        };
                        console.log('Set status:', statuses[id]);
                    } else {
                        statuses[id] = {
                            status: 'Not in Intune',
                            color: 'red',
                            intuneVersion: 'Not in Intune'
                        };
                        console.log('Set status: Not in Intune');
                    }
                }
                console.log('\nFinal statuses:', statuses);
                setAppStatuses(statuses);
            } catch (error) {
                console.error('Error fetching Intune status:', error);
            }
            setLoading(false);
        }

        if (apps.length > 0) {
            fetchIntuneStatus();
        }
    }, [isAuthenticated, apps]);

    // Update the version comparison function to be more robust
    function compareVersions(ver1, ver2) {
        console.log('\nComparing versions:', { ver1, ver2 });
        
        // Handle undefined, null, or special values
        if (!ver1 || !ver2 || ver1 === 'Not available' || ver1 === 'Not in Intune') {
            console.log('Special case detected:', { ver1, ver2 });
            return 0;
        }
        
        try {
            // Handle complex version strings (e.g., "1.2.3,45678" or "1.2.3-beta")
            const cleanVer1 = ver1.split(/[,\-]/)[0].trim();
            const cleanVer2 = ver2.split(/[,\-]/)[0].trim();
            console.log('Cleaned versions:', { cleanVer1, cleanVer2 });
            
            const parts1 = cleanVer1.split('.');
            const parts2 = cleanVer2.split('.');
            console.log('Version parts:', { parts1, parts2 });
            
            // Compare each part numerically
            const maxLength = Math.max(parts1.length, parts2.length);
            for (let i = 0; i < maxLength; i++) {
                const num1 = parseInt(parts1[i] || '0', 10);
                const num2 = parseInt(parts2[i] || '0', 10);
                console.log(`Comparing part ${i}:`, { num1, num2 });
                
                if (isNaN(num1) || isNaN(num2)) {
                    console.warn('Invalid version number:', { ver1, ver2, part1: parts1[i], part2: parts2[i] });
                    continue;
                }
                
                if (num1 > num2) {
                    console.log(`${num1} > ${num2}, returning 1`);
                    return 1;  // ver1 is newer
                }
                if (num1 < num2) {
                    console.log(`${num1} < ${num2}, returning -1`);
                    return -1; // ver2 is newer
                }
            }
            
            console.log('Versions are equal, returning 0');
            return 0; // versions are equal
        } catch (error) {
            console.error('Version comparison error:', error, { ver1, ver2 });
            return 0; // Return equal if comparison fails
        }
    }

    // Add logo caching
    const getLogoUrl = React.useCallback((id) => {
        if (cachedLogos[id]) {
            return cachedLogos[id];
        }
        return `/Logos/${id}.png`;
    }, [cachedLogos]);

    // Load and cache logos on initial load and refresh
    const cacheLogos = React.useCallback(async () => {
        const newCache = {};
        for (const [id] of apps) {
            try {
                const response = await fetch(`/Logos/${id}.png`);
                if (response.ok) {
                    const blob = await response.blob();
                    newCache[id] = URL.createObjectURL(blob);
                }
            } catch (error) {
                console.error(`Error caching logo for ${id}:`, error);
            }
        }
        setCachedLogos(newCache);
    }, [apps]);

    // Clean up object URLs on unmount
    React.useEffect(() => {
        return () => {
            Object.values(cachedLogos).forEach(url => {
                URL.revokeObjectURL(url);
            });
        };
    }, [cachedLogos]);

    // Load logos when apps are loaded
    React.useEffect(() => {
        if (apps.length > 0) {
            cacheLogos();
        }
    }, [apps, cacheLogos]);

    // Update the refresh button click handler
    const handleRefresh = async () => {
        setLoading(true);
        await refreshIntuneCache(); // Force refresh of Intune data
        await cacheLogos(); // Refresh logo cache
        setLoading(false);
    };

    // Add this effect to check for updates
    React.useEffect(() => {
        async function checkUpdates() {
            try {
                const response = await fetch('/api/updates/check');
                const data = await response.json();
                if (data.added_apps && data.added_apps.length > 0) {
                    setNewApps(data.added_apps);
                }
            } catch (error) {
                console.error('Error checking updates:', error);
            }
        }
        checkUpdates();
    }, []);

    const placeholderLogo = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='128' height='128' viewBox='0 0 24 24'%3E%3Cpath fill='%23cccccc' d='M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z'/%3E%3C/svg%3E";

    const handleUpload = async () => {
        const appId = selectedApp.name.toLowerCase().replace(/\s+/g, '_');
        
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
                body: JSON.stringify({
                    ...selectedApp,
                    updateExisting: true
                })
            });
            if (!response.ok) throw new Error(await response.text());
            const result = await response.json();
            setUploadStates(prev => ({
                ...prev,
                [appId]: { status: 'success', timestamp: new Date().toISOString() }
            }));
            
            // Only refresh the specific app's status
            const intuneApp = await getSpecificIntuneApp(selectedApp.name);
            const newStatuses = {...appStatuses};
            newStatuses[appId] = {
                status: intuneApp ? 'Up-to-date' : 'Not in Intune',
                color: intuneApp ? 'green' : 'red',
                intuneVersion: intuneApp?.primaryBundleVersion || 'Not in Intune'
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
        setShowConfirmDialog(false);
    };

    return (
        <div className="min-h-screen bg-gray-100 relative">
            <div className="floating-container">
                {loading ? (
                    <div className="spinner"></div>
                ) : (
                    <button 
                        onClick={handleRefresh}
                        className="refresh-button"
                    >
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
                        Made with ❤️ by <a href="https://github.com/ugurkocde" className="text-blue-600 hover:text-blue-800">Ugur Koc</a> | <a href="https://github.com/ugurkocde/IntuneBrew" className="text-blue-600 hover:text-blue-800">GitHub Repository</a>
                    </div>
                </div>
            </header>
            <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
                <div className="mb-6 flex flex-col sm:flex-row gap-4 items-center">
                    <div className="relative flex-1">
                        <input
                            type="text"
                            placeholder="Search apps..."
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                            className="w-full px-4 py-2 rounded-lg border focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                        />
                        {searchQuery && (
                            <button
                                onClick={() => setSearchQuery('')}
                                className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
                            >
                                ✕
                            </button>
                        )}
                    </div>
                    <div className="flex gap-2">
                        <button
                            onClick={() => setStatusFilter('all')}
                            className={`px-4 py-2 rounded-lg ${statusFilter === 'all' ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
                        >
                            All
                        </button>
                        <button
                            onClick={() => setStatusFilter('Needs Update')}
                            className={`px-4 py-2 rounded-lg ${statusFilter === 'Needs Update' ? 'bg-yellow-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
                        >
                            Needs Update
                        </button>
                        <button
                            onClick={() => setStatusFilter('Up-to-date')}
                            className={`px-4 py-2 rounded-lg ${statusFilter === 'Up-to-date' ? 'bg-green-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
                        >
                            Up-to-date
                        </button>
                        <button
                            onClick={() => setStatusFilter('Not in Intune')}
                            className={`px-4 py-2 rounded-lg ${statusFilter === 'Not in Intune' ? 'bg-red-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
                        >
                            Not in Intune
                        </button>
                    </div>
                </div>

                {Object.entries(groupedAndFilteredApps).map(([group, groupApps]) => 
                    groupApps.length > 0 && (
                        <div key={group} className="mb-8">
                            <h2 className="text-xl font-semibold mb-4 text-gray-700">{group} ({groupApps.length})</h2>
                            <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-3">
                                {groupApps.map(([id, url]) => (
                                    <div key={id} 
                                         className="bg-white overflow-hidden shadow rounded-lg hover:shadow-lg cursor-pointer relative h-[120px]"
                                         onClick={async () => {
                                             try {
                                                 const token = await getTokenSilently();
                                                 const res = await fetch(`/api/app/${id}`, {
                                                     headers: {
                                                         'Authorization': `Bearer ${token}`
                                                     }
                                                 });
                                                 if (!res.ok) {
                                                     console.error('Server response:', await res.text());
                                                     throw new Error('Failed to fetch app details');
                                                 }
                                                 const data = await res.json();
                                                 setSelectedApp(data);
                                             } catch (error) {
                                                 console.error('Error loading app details:', error);
                                                 if (error.message.includes('No active account')) {
                                                     await signIn();
                                                 }
                                             }
                                         }}>
                                        {/* Status Triangle */}
                                        <div 
                                            className="absolute top-0 right-0 w-8 h-8"
                                            style={{
                                                background: `linear-gradient(45deg, transparent 50%, ${
                                                    appStatuses[id]?.color === 'red' ? '#DC2626' :
                                                    appStatuses[id]?.color === 'yellow' ? '#D97706' :
                                                    '#059669'
                                                } 50%)`
                                            }}
                                        />
                                        
                                        <div className="p-3 flex items-center space-x-3 h-full">
                                            <img src={getLogoUrl(id)} 
                                                 className="w-12 h-12 object-contain flex-shrink-0"
                                                 onError={(e) => {
                                                     if (!e.target.retryAttempt) {
                                                         e.target.retryAttempt = true;
                                                         e.target.src = placeholderLogo;
                                                         e.target.title = "Logo needed";
                                                     }
                                                 }}/>
                                            <h2 className="text-sm font-medium truncate">
                                                {id.replace(/_/g, ' ')}
                                            </h2>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )
                )}

                {selectedApp && (
                    <div 
                        className="fixed inset-0 bg-gray-800 bg-opacity-75 overflow-y-auto h-full w-full z-40 backdrop-blur-sm"
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
                                        src={getLogoUrl(selectedApp.name.toLowerCase().replace(/\s+/g, '_'))}
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
                                                         appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')].intuneVersion !== 'Not available' && 
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
                                                const isUpdate = currentStatus?.status === 'Up-to-date';

                                                if (isUpdate) {
                                                    setConfirmDialogProps({
                                                        appName: selectedApp.name,
                                                        currentStatus: currentStatus.status,
                                                        currentVersion: selectedApp.version,
                                                        newVersion: selectedApp.version
                                                    });
                                                    setShowConfirmDialog(true);
                                                    return;
                                                }

                                                await handleUpload();
                                            }}
                                            className={`px-4 py-2 rounded ${
                                                uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'uploading'
                                                    ? 'bg-gray-400 cursor-not-allowed'
                                                    : uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'error'
                                                    ? 'bg-red-600 hover:bg-red-700'
                                                    : appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'Up-to-date'
                                                    ? 'bg-blue-600 hover:bg-blue-700'
                                                    : 'bg-green-600 hover:bg-green-700'
                                            } text-white`}
                                            disabled={uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'uploading'}
                                        >
                                            {uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'uploading'
                                                ? 'Uploading...'
                                                : uploadStates[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'error'
                                                ? 'Error - Try again'
                                                : appStatuses[selectedApp.name.toLowerCase().replace(/\s+/g, '_')]?.status === 'Up-to-date'
                                                ? 'Update'
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
            <ConfirmDialog
                isOpen={showConfirmDialog}
                onClose={() => setShowConfirmDialog(false)}
                onConfirm={handleUpload}
                {...confirmDialogProps}
            />
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