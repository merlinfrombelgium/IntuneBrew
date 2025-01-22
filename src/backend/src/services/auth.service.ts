import { ClientCertificateCredential } from '@azure/identity';
import { TokenCredentialAuthenticationProvider } from '@microsoft/microsoft-graph-client/authProviders/azureTokenCredentials';
import { Client } from '@microsoft/microsoft-graph-client';
import { readFileSync } from 'fs';
import * as path from 'path';

export class AuthService {
  private graphClient: Client;
  private static instance: AuthService;

  private constructor() {
    const tenantId = process.env.AZURE_TENANT_ID || '';
    const clientId = process.env.AZURE_APP_ID || '';
    const certPath = process.env.AZURE_CLIENT_CERT_PATH || '';

    try {
      // Read the certificate file
      const resolvedPath = path.resolve(__dirname, '..', '..', '..', '..', certPath);
      console.log('Attempting to read certificate from:', resolvedPath);

      const certificate = readFileSync(resolvedPath, 'utf8');
      console.log('Certificate file read successfully');

      // Create the credential with the certificate
      const credential = new ClientCertificateCredential(
        tenantId,
        clientId,
        {
          certificate: certificate
        }
      );

      const authProvider = new TokenCredentialAuthenticationProvider(credential, {
        scopes: ['https://graph.microsoft.com/.default']
      });

      this.graphClient = Client.initWithMiddleware({
        authProvider: authProvider,
      });
    } catch (error) {
      console.error('Error configuring certificate:', error);
      if (error instanceof Error) {
        throw new Error(`Failed to configure certificate: ${error.message}. Please check the AZURE_CLIENT_CERT_PATH environment variable.`);
      } else {
        throw new Error('Failed to configure certificate. Please check the AZURE_CLIENT_CERT_PATH environment variable.');
      }
    }
  }

  public static getInstance(): AuthService {
    if (!AuthService.instance) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  public getGraphClient(): Client {
    return this.graphClient;
  }
} 