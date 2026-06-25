import { useEffect, useState } from 'react';
import { getAccessToken, getMe, signOut } from '@/stores/auth';
import type { User } from '@/stores/auth';
import { CrawlApp } from './CrawlApp';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from '@/components/ui/dropdown-menu';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';

export function AppShell() {
  const [authed, setAuthed] = useState(false);
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    if (!getAccessToken()) {
      window.location.href = '/login';
      return;
    }
    setAuthed(true);
    getMe().then(setUser).catch(() => {});
  }, []);

  if (!authed) return null;

  function handleSignOut() {
    signOut().then(() => {
      window.location.href = '/login';
    }).catch(() => {
      window.location.href = '/login';
    });
  }

  const initials = user?.email ? user.email[0].toUpperCase() : '?';

  return (
    <div className="min-h-screen flex flex-col">
      <nav className="border-b px-6 py-3 flex items-center gap-6">
        <span className="font-semibold text-foreground">sol</span>
        <a href="/" className="text-sm text-muted-foreground hover:text-foreground">
          Audit
        </a>
        <a href="/projects" className="text-sm text-muted-foreground hover:text-foreground">
          Projects
        </a>
        <div className="ml-auto flex items-center gap-3">
          {user && (
            <span className="text-sm text-muted-foreground hidden sm:block">
              {user.email}
            </span>
          )}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="sm" className="p-0 size-8 rounded-full">
                <Avatar size="sm">
                  <AvatarFallback>{initials}</AvatarFallback>
                </Avatar>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={handleSignOut}>
                Sign out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </nav>
      <main className="flex-1 p-6">
        <CrawlApp />
      </main>
    </div>
  );
}
