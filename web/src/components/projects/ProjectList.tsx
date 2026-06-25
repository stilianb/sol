import { ProjectCard } from './ProjectCard';
import type { Project } from '@/types/project';

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center text-muted-foreground">
      <p className="text-sm">No projects yet.</p>
      <p className="text-xs mt-1">Create one to get started.</p>
    </div>
  );
}

interface Props {
  projects: Project[];
  loading: boolean;
  onDelete: (id: string) => Promise<void>;
}

export function ProjectList({ projects, loading, onDelete }: Props) {
  if (loading) return <div className="text-sm text-muted-foreground py-8">Loading...</div>;
  if (projects.length === 0) return <EmptyState />;
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {projects.map(p => (
        <ProjectCard key={p.id} project={p} onDelete={onDelete} />
      ))}
    </div>
  );
}
