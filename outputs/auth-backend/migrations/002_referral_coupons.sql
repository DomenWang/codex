CREATE TABLE IF NOT EXISTS referral_edges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invited_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    referrer_depth integer NOT NULL DEFAULT 1 CHECK (referrer_depth >= 1 AND referrer_depth <= 3),
    invited_idfv_hash text,
    invited_ip_hash text,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'qualified', 'revoked')),
    qualified_transaction_id text,
    revoked_transaction_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    qualified_at timestamptz,
    revoked_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS referral_edges_invited_user_unique_idx
    ON referral_edges(invited_user_id)
    WHERE invited_user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS referral_edges_idfv_once_idx
    ON referral_edges(invited_idfv_hash)
    WHERE invited_idfv_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS referral_edges_ip_once_idx
    ON referral_edges(invited_ip_hash)
    WHERE invited_ip_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS referral_edges_referrer_created_at_idx
    ON referral_edges(referrer_user_id, created_at);

CREATE TABLE IF NOT EXISTS user_coupons (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    coupon_type text NOT NULL CHECK (coupon_type IN ('REF100_OFF', 'REF50_UNIVERSAL')),
    source_referral_id uuid REFERENCES referral_edges(id) ON DELETE SET NULL,
    used_at timestamptz,
    claimed_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS user_coupons_one_type_per_user_idx
    ON user_coupons(user_id, coupon_type)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS user_coupons_user_id_idx
    ON user_coupons(user_id);
