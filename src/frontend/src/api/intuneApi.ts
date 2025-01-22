import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

export interface IntuneApp {
  id?: string;
  displayName: string;
  description: string;
  publisher: string;
  primaryBundleVersion?: string;
}

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export const intuneApi = {
  listApps: async (): Promise<IntuneApp[]> => {
    const response = await api.get<IntuneApp[]>('/apps');
    return response.data;
  },

  getApp: async (id: string): Promise<IntuneApp> => {
    const response = await api.get<IntuneApp>(`/apps/${id}`);
    return response.data;
  },
}; 