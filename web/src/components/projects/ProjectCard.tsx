import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { api } from '@/lib/api';
import type { Project } from '@/types/project';

interface AuditScore {
  scores: Record<string, number>;
}

const statusVariant: Record<Project['status'], 'default' | 'secondary' | 'outline'> = {
  draft: 'outline',
  in_progress: 'secondary',
  complete: 'default',
};

interface Props {
  project: Project;
  onDelete: (id: string) => Promise<void>;
}

export function ProjectCard({ project, onDelete }: Props) {
  const [auditLoading, setAuditLoading] = useState(false);
  const [scores, setScores] = useState<Record<string, number> | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  async function runAudit() {
    setAuditLoading(true);
    try {
      const result = await api.post<AuditScore>(`/projects/${project.id}/audit`, {});
      setScores(result.scores);
    } finally {
      setAuditLoading(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{project.name}</CardTitle>
        <CardDescription className="truncate">{project.primary_url}</CardDescription>
      </CardHeader>
      <CardContent className="flex items-center gap-2">
        <Badge variant={statusVariant[project.status]}>{project.status.replace('_', ' ')}</Badge>
        {scores && (
          <span className="text-xs text-muted-foreground">
            perf: {scores['performance'] ?? '—'}
          </span>
        )}
      </CardContent>
      <CardFooter className="flex gap-2">
        <Button size="sm" onClick={runAudit} disabled={auditLoading}>
          {auditLoading ? 'Running...' : 'Run audit'}
        </Button>
        {confirmDelete ? (
          <>
            <Button size="sm" variant="destructive" onClick={() => onDelete(project.id)}>
              Confirm
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setConfirmDelete(false)}>
              Cancel
            </Button>
          </>
        ) : (
          <Button size="sm" variant="ghost" onClick={() => setConfirmDelete(true)}>
            Delete
          </Button>
        )}
      </CardFooter>
    </Card>
  );
}
