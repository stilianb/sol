import { test, expect } from '@playwright/test';

const apiUrl = process.env.API_URL ?? 'http://localhost:8090';

test('login page renders', async ({ page }) => {
  await page.goto('/login');
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
});

test('register page renders', async ({ page }) => {
  await page.goto('/register');
  await expect(page.getByRole('heading', { name: 'Create account' })).toBeVisible();
});

test('unauthenticated / redirect', async ({ page }) => {
  await page.goto('/');
  await page.waitForURL(/\/login/);
  expect(page.url()).toContain('/login');
});

test('register creates account', async ({ page }) => {
  const email = `e2e-reg-${Date.now()}@example.com`;
  const password = 'e2epassword99';
  await page.goto('/register');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Create account' }).click();
  await page.waitForURL(/\/login/);
  expect(page.url()).toContain('/login');
});
