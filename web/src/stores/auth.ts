import { api } from '@/lib/api';

export interface User {
  id: string;
  email: string;
  email_verified: boolean;
  mfa_enabled: boolean;
}

export interface AuthTokens {
  access_token: string;
  refresh_token: string;
}

export function getAccessToken(): string | null {
  return localStorage.getItem('access_token');
}

export function setTokens(tokens: AuthTokens): void {
  localStorage.setItem('access_token', tokens.access_token);
  localStorage.setItem('refresh_token', tokens.refresh_token);
}

export function clearTokens(): void {
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
}

export async function refreshSession(): Promise<void> {
  const refresh_token = localStorage.getItem('refresh_token');
  if (!refresh_token) throw new Error('No refresh token');
  const tokens = await api.post<AuthTokens>('/auth/refresh', { refresh_token });
  setTokens(tokens);
}

export async function signIn(
  email: string,
  password: string,
): Promise<{ mfa_required?: boolean; mfa_token?: string }> {
  const res = await api.post<AuthTokens & { mfa_required?: boolean; mfa_token?: string }>(
    '/auth/login',
    { email, password },
  );
  if (!res.mfa_required) {
    setTokens({ access_token: res.access_token, refresh_token: res.refresh_token });
  }
  return { mfa_required: res.mfa_required, mfa_token: res.mfa_token };
}

export async function signUp(email: string, password: string): Promise<void> {
  await api.post<unknown>('/auth/register', { email, password });
}

export async function signOut(): Promise<void> {
  try {
    const refresh_token = localStorage.getItem('refresh_token');
    await api.post<unknown>('/auth/logout', { refresh_token });
  } finally {
    clearTokens();
  }
}

export async function getMe(): Promise<User> {
  return api.get<User>('/user/me');
}
