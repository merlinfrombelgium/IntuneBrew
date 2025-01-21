function App() {
    const [apps, setApps] = React.useState([]);
    const [selectedApp, setSelectedApp] = React.useState(null);

    React.useEffect(() => {
        fetch('/api/apps')
            .then(res => res.json())
            .then(data => setApps(Object.entries(data)));
    }, []);

    const placeholderLogo = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='128' height='128' viewBox='0 0 24 24'%3E%3Cpath fill='%23cccccc' d='M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z'/%3E%3C/svg%3E";

    return (
        <div className="min-h-screen bg-gray-100">
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
                             onClick={() => {
                                 fetch(`/api/app/${id}`)
                                     .then(res => res.json())
                                     .then(data => setSelectedApp(data));
                             }}>
                            <img src={`/Logos/${id}.png`} 
                                 className="w-16 h-16 object-contain mb-4"
                                 onError={(e) => {
                                     e.target.onerror = null;
                                     e.target.src = placeholderLogo;
                                     e.target.title = "Logo needed";
                                 }}/>
                            <h2 className="text-xl font-semibold">{id.replace(/_/g, ' ')}</h2>
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
                                    <div className="relative group flex items-center space-x-2">
                                        <span className="font-semibold w-24">Version:</span>
                                        <code className="bg-gray-100 p-2 rounded flex-1">{selectedApp.version}</code>
                                        <button onClick={() => navigator.clipboard.writeText(selectedApp.version)} className="text-blue-600 hover:text-blue-800">
                                            📋
                                        </button>
                                        {selectedApp.previous_version && (
                                            <div className="absolute hidden group-hover:block bg-black text-white p-2 rounded -top-8 left-24 text-sm">
                                                Previous: {selectedApp.previous_version}
                                            </div>
                                        )}
                                    </div>
                                    
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

ReactDOM.render(<App />, document.getElementById('root'));