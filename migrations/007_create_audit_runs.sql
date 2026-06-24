CREATE TABLE IF NOT EXISTS audit_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    org_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    url TEXT NOT NULL,
    profile TEXT NOT NULL DEFAULT 'desktop',
    scores JSONB,
    psi JSONB,
    builtwith JSONB,
    ran_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_runs_url ON audit_runs(url);
CREATE INDEX IF NOT EXISTS idx_audit_runs_user_id ON audit_runs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_runs_org_id ON audit_runs(org_id);

CREATE TABLE IF NOT EXISTS audit_findings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES audit_runs(id) ON DELETE CASCADE,
    rule_id TEXT NOT NULL,
    category TEXT NOT NULL,
    severity TEXT NOT NULL,
    detail TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS baselines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    run_id UUID NOT NULL REFERENCES audit_runs(id),
    set_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, url)
);
