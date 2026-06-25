import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

const apiUrl = process.env.API_URL ?? 'http://localhost:8090';
const email = `e2e-login-${Date.now()}@example.com`;
const password = 'e2epassword99';

test.beforeAll(async ({ request }) => {
  await request.post(`${apiUrl}/auth/register`, { data: { email, password } });
});

test('login with bad password shows error', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill('wrongpassword');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
});

test('login success redirects to app', async ({ page }) => {
  await loginAs(page, email, password);
  expect(page.url()).not.toContain('/login');
});

test('nav shows user email after login', async ({ page }) => {
  await loginAs(page, email, password);
  await expect(page.getByText(email)).toBeVisible();
});

test('sign out redirects to login', async ({ page }) => {
  await loginAs(page, email, password);
  await page.getByRole('button').filter({ hasText: email[0].toUpperCase() }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await page.waitForURL(/\/login/);
  expect(page.url()).toContain('/login');
});
