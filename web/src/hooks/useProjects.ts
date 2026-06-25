import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import type { Project } from '@/types/project';

export function useProjects() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<Project[]>('/projects')
      .then(setProjects)
      .catch((e: Error) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  async function createProject(data: {
    name: string;
    primary_url: string;
    competitor_urls: string[];
  }): Promise<Project> {
    const p = await api.post<Project>('/projects', data);
    setProjects(prev => [p, ...prev]);
    return p;
  }

  async function deleteProject(id: string): Promise<void> {
    await api.delete(`/projects/${id}`);
    setProjects(prev => prev.filter(p => p.id !== id));
  }

  return { projects, loading, error, createProject, deleteProject };
}
