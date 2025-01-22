import { useState, useEffect } from 'react';
import { Container, Grid, Modal, Title, Text, LoadingOverlay } from '@mantine/core';
import { AppCard } from './components/AppCard';
import { intuneApi, IntuneApp } from './api/intuneApi';

function App() {
  const [apps, setApps] = useState<IntuneApp[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedApp, setSelectedApp] = useState<IntuneApp | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadApps();
  }, []);

  const loadApps = async () => {
    try {
      setLoading(true);
      const data = await intuneApi.listApps();
      setApps(data);
      setError(null);
    } catch (err) {
      setError('Failed to load apps');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleViewDetails = (app: IntuneApp) => {
    setSelectedApp(app);
  };

  const handlePublish = async (app: IntuneApp) => {
    // TODO: Implement publish/update functionality
    console.log('Publishing app:', app);
  };

  return (
    <Container size="xl" py="xl">
      <LoadingOverlay visible={loading} />
      
      <Title order={1} mb="xl">IntuneBrew Apps</Title>
      
      {error && (
        <Text color="red" mb="xl">
          {error}
        </Text>
      )}

      <Grid>
        {apps.map((app) => (
          <Grid.Col key={app.id} xs={12} sm={6} md={4} lg={3}>
            <AppCard
              app={app}
              onViewDetails={handleViewDetails}
              onPublish={handlePublish}
            />
          </Grid.Col>
        ))}
      </Grid>

      <Modal
        opened={!!selectedApp}
        onClose={() => setSelectedApp(null)}
        title={selectedApp?.displayName}
        size="lg"
      >
        {selectedApp && (
          <>
            <Text size="sm" mb="md">
              <strong>Version:</strong> {selectedApp.primaryBundleVersion || 'Not Published'}
            </Text>
            <Text size="sm" mb="md">
              <strong>Publisher:</strong> {selectedApp.publisher}
            </Text>
            <Text size="sm">
              <strong>Description:</strong>
              <br />
              {selectedApp.description}
            </Text>
          </>
        )}
      </Modal>
    </Container>
  );
}

export default App;
