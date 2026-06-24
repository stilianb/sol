import { useEffect, useState } from 'react';
import { getAccessToken } from '@/stores/auth';
import { CrawlApp } from './CrawlApp';

export function AppShell() {
  const [authed, setAuthed] = useState(false);

  useEffect(() => {
    if (!getAccessToken()) {
      window.location.href = '/login';
    } else {
      setAuthed(true);
    }
  }, []);

  if (!authed) return null;
  return <CrawlApp />;
}
