import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { GraphService } from './services/graph.service';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });

const app = express();
const port = process.env.API_PORT || 3001;

// Middleware
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:5173',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  credentials: true,
}));
app.use(express.json());

// Initialize GraphService
let graphService: GraphService;
try {
  console.log('Initializing GraphService...');
  graphService = GraphService.getInstance();
  console.log('GraphService initialized successfully');
} catch (error) {
  console.error('Failed to initialize GraphService:', error);
  process.exit(1);
}

// Routes
app.get('/api/apps', async (req, res) => {
  try {
    console.log('Received request for /api/apps');
    const apps = await graphService.listIntuneApps();
    console.log('Successfully fetched apps');
    res.json(apps);
  } catch (error) {
    console.error('Error fetching apps:', error);
    if (error instanceof Error) {
      res.status(500).json({ error: error.message });
    } else {
      res.status(500).json({ error: 'Failed to fetch apps' });
    }
  }
});

app.get('/api/apps/:id', async (req, res) => {
  try {
    console.log(`Received request for /api/apps/${req.params.id}`);
    const app = await graphService.getIntuneApp(req.params.id);
    console.log('Successfully fetched app');
    res.json(app);
  } catch (error) {
    console.error('Error fetching app:', error);
    if (error instanceof Error) {
      res.status(500).json({ error: error.message });
    } else {
      res.status(500).json({ error: 'Failed to fetch app' });
    }
  }
});

// Error handling middleware
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Unhandled error:', err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
}); 