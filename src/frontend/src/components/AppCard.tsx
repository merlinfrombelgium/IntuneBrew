import { Card, Text, Badge, Button, Group } from '@mantine/core';
import { IntuneApp } from '../api/intuneApi';

interface AppCardProps {
  app: IntuneApp;
  onViewDetails: (app: IntuneApp) => void;
  onPublish: (app: IntuneApp) => void;
}

export function AppCard({ app, onViewDetails, onPublish }: AppCardProps) {
  return (
    <Card shadow="sm" padding="lg" radius="md" withBorder>
      <Group position="apart" mt="md" mb="xs">
        <Text weight={500}>{app.displayName}</Text>
        <Badge color={app.primaryBundleVersion ? 'blue' : 'gray'}>
          {app.primaryBundleVersion || 'Not Published'}
        </Badge>
      </Group>

      <Text size="sm" color="dimmed" lineClamp={2}>
        {app.description}
      </Text>

      <Text size="sm" mt="md">
        Publisher: {app.publisher}
      </Text>

      <Group position="apart" mt="md">
        <Button variant="light" color="blue" onClick={() => onViewDetails(app)}>
          View Details
        </Button>
        <Button color="green" onClick={() => onPublish(app)}>
          {app.primaryBundleVersion ? 'Update' : 'Publish'}
        </Button>
      </Group>
    </Card>
  );
} 