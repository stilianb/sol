import { useEffect, useState } from 'react';
import { getAccessToken } from '@/stores/auth';

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    if (!getAccessToken()) {
      window.location.href = '/login';
    } else {
      setChecked(true);
    }
  }, []);

  if (!checked) return null;
  return <>{children}</>;
}
