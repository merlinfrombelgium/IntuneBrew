
function App() {
    const [apps, setApps] = React.useState([]);
    const [selectedApp, setSelectedApp] = React.useState(null);

    React.useEffect(() => {
        fetch('/api/apps')
            .then(res => res.json())
            .then(data => setApps(Object.entries(data)));
    }, []);

    return (
        <div className="min-h-screen bg-gray-100">
            <header className="bg-white shadow">
                <div className="max-w-7xl mx-auto py-6 px-4">
                    <h1 className="text-3xl font-bold text-gray-900">IntuneBrew</h1>
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
                                 onError={(e) => e.target.style.display = 'none'}/>
                            <h2 className="text-xl font-semibold">{id.replace(/_/g, ' ')}</h2>
                        </div>
                    ))}
                </div>
            </main>
        </div>
    );
}

ReactDOM.render(<App />, document.getElementById('root'));
