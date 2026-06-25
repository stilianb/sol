import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

const apiUrl = process.env.API_URL ?? 'http://localhost:8090';
const email = `e2e-proj-${Date.now()}@example.com`;
const password = 'e2epassword99';

test.beforeAll(async ({ request }) => {
  await request.post(`${apiUrl}/auth/register`, { data: { email, password } });
});

test('/projects unauthenticated redirects to /login', async ({ page }) => {
  await page.goto('/projects');
  await page.waitForURL(/\/login/);
  expect(page.url()).toContain('/login');
});

test('projects page loads after login', async ({ page }) => {
  await loginAs(page, email, password);
  await page.goto('/projects');
  await expect(page.getByText('Create project')).toBeVisible();
});

test('create project shows card', async ({ page }) => {
  const name = `Test Project ${Date.now()}`;
  await loginAs(page, email, password);
  await page.goto('/projects');
  await page.getByLabel('Name').fill(name);
  await page.getByLabel('Primary URL').fill('https://example.com');
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.getByText(name)).toBeVisible();
});
