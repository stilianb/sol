export const API_BASE = (import.meta.env.PUBLIC_API_URL as string | undefined) ?? (import.meta.env.DEV ? 'http://localhost:8080' : '');
