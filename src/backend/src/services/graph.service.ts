import { Client } from '@microsoft/microsoft-graph-client';
import 'isomorphic-fetch';
import { AuthService } from './auth.service';

interface IntuneApp {
  id?: string;
  displayName: string;
  description: string;
  publisher: string;
  primaryBundleVersion?: string;
  '@odata.type'?: string;
}

interface IntuneAppResponse {
  id: string;
  displayName: string;
  description?: string;
  publisher?: string;
  primaryBundleVersion?: string;
  '@odata.type': string;
}

interface GraphErrorResponse {
  response?: {
    status: number;
    statusText: string;
    text(): Promise<string>;
  };
  message?: string;
}

export class GraphService {
  private client: Client;
  private static instance: GraphService;

  private constructor() {
    try {
      console.log('Initializing GraphService...');
      this.client = AuthService.getInstance().getGraphClient();
      console.log('GraphService initialized successfully');
    } catch (error: unknown) {
      console.error('Error initializing GraphService:', error);
      throw error;
    }
  }

  public static getInstance(): GraphService {
    if (!GraphService.instance) {
      console.log('Creating new GraphService instance...');
      GraphService.instance = new GraphService();
    }
    return GraphService.instance;
  }

  public async listIntuneApps(): Promise<IntuneApp[]> {
    try {
      console.log('Fetching Intune apps...');
      
      // Test the client connection first
      try {
        await this.client.api('/deviceAppManagement').get();
        console.log('Graph API connection test successful');
      } catch (error: unknown) {
        console.error('Graph API connection test failed:', error);
        throw error;
      }

      const response = await this.client
        .api('/deviceAppManagement/mobileApps')
        .select('id,displayName,description,publisher')
        .get();

      console.log('Response received:', JSON.stringify(response, null, 2));

      if (!response || !response.value) {
        console.error('Invalid response format:', response);
        throw new Error('Invalid response format from Graph API');
      }

      // Filter macOS apps and map to our interface
      const macOSApps = response.value
        .filter((app: IntuneAppResponse) => {
          console.log('Checking app type:', app['@odata.type']);
          return app['@odata.type'] === '#microsoft.graph.macOSDmgApp' || 
                 app['@odata.type'] === '#microsoft.graph.macOSPkgApp';
        })
        .map((app: IntuneAppResponse) => {
          console.log('Mapping app:', app.displayName);
          return {
            id: app.id,
            displayName: app.displayName,
            description: app.description || '',
            publisher: app.publisher || '',
            primaryBundleVersion: '',
            '@odata.type': app['@odata.type']
          };
        });

      console.log('Mapped macOS apps:', JSON.stringify(macOSApps, null, 2));

      // For each macOS app, fetch additional details
      const appsWithDetails = await Promise.all(
        macOSApps.map(async (app: IntuneApp) => {
          try {
            console.log(`Fetching details for app ${app.id}...`);
            const details = await this.getIntuneApp(app.id!);
            console.log(`Details received for app ${app.id}:`, details);
            return {
              ...app,
              primaryBundleVersion: details.primaryBundleVersion || ''
            };
          } catch (error: unknown) {
            console.error(`Error fetching details for app ${app.id}:`, error);
            return app;
          }
        })
      );

      return appsWithDetails;
    } catch (error: unknown) {
      console.error('Error in listIntuneApps:', error);
      const graphError = error as GraphErrorResponse;
      if (graphError.response) {
        console.error('Graph API Error Response:', {
          status: graphError.response.status,
          statusText: graphError.response.statusText,
          body: await graphError.response.text()
        });
      }
      throw error;
    }
  }

  public async getIntuneApp(appId: string): Promise<IntuneApp> {
    try {
      console.log(`Fetching Intune app ${appId}...`);
      const response = await this.client
        .api(`/deviceAppManagement/mobileApps/${appId}`)
        .get();
      console.log(`App ${appId} details:`, response);
      return response;
    } catch (error: unknown) {
      console.error(`Error fetching Intune app ${appId}:`, error);
      const graphError = error as GraphErrorResponse;
      if (graphError.response) {
        console.error('Graph API Error Response:', {
          status: graphError.response.status,
          statusText: graphError.response.statusText,
          body: await graphError.response.text()
        });
      }
      throw error;
    }
  }

  // Add more methods for creating/updating apps, managing content versions, etc.
} 