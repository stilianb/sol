import { test, expect } from '@playwright/test';

test('login page renders form', async ({ page }) => {
  await page.goto('/login');
  await expect(page.getByLabel('Email')).toBeVisible();
  await expect(page.getByLabel('Password')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible();
});

test('register page renders form', async ({ page }) => {
  await page.goto('/register');
  await expect(page.getByLabel('Email')).toBeVisible();
  await expect(page.getByLabel('Password')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Create account' })).toBeVisible();
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
