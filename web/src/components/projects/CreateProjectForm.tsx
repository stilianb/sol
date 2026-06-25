import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription } from '@/components/ui/alert';

interface Props {
  onCreate: (data: { name: string; primary_url: string; competitor_urls: string[] }) => Promise<void>;
}

export function CreateProjectForm({ onCreate }: Props) {
  const [name, setName] = useState('');
  const [primaryUrl, setPrimaryUrl] = useState('');
  const [competitors, setCompetitors] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const competitor_urls = competitors
      .split('\n')
      .map(s => s.trim())
      .filter(Boolean);
    try {
      await onCreate({ name, primary_url: primaryUrl, competitor_urls });
      setName('');
      setPrimaryUrl('');
      setCompetitors('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create project');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>New project</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          {error && (
            <Alert variant="destructive">
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="proj-name">Name</Label>
            <Input id="proj-name" required value={name} onChange={e => setName(e.target.value)} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="proj-url">Primary URL</Label>
            <Input id="proj-url" type="url" required value={primaryUrl} onChange={e => setPrimaryUrl(e.target.value)} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="proj-competitors">Competitors (one URL per line)</Label>
            <textarea
              id="proj-competitors"
              className="flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-xs placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50"
              value={competitors}
              onChange={e => setCompetitors(e.target.value)}
              placeholder="https://competitor.com"
            />
          </div>
          <Button type="submit" disabled={loading}>
            {loading ? 'Creating...' : 'Create project'}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
