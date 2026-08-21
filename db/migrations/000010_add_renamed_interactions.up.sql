-- The P0 renamed interactions (docs/PRD.md §6/§7.2, docs/FRONTEND_GUIDELINES.md
-- §7): Pranam (like), Satsang (comment), Prasad (share), Smaran (save),
-- Sevak (follow). Jugalbandi (remix/duet, P1) and the long-press Pranam
-- reaction variants Shanti/Gyaan/Kripa (P2) are deliberately out of scope —
-- see PRD.md §7.2's own priority split. Table/column names stay functional
-- (pranams, not likes, to match the product's own vocabulary — but no
-- "Pranam" business logic lives outside this migration and internal/social;
-- the poetic name is real here, not just a display-layer relabel the way
-- reels.like_count's comment describes for that earlier table).

-- Per-creator comment mode (docs/GAPS.md's "comment default should flip to
-- reflection only" item, resolved here: every creator now starts
-- reflection_only and opts into open themselves, the reverse of the old
-- default). No creator-facing settings screen to flip it ships in this
-- slice — the default flip is the actual gap being closed; a UI to change
-- it later is separate, unbuilt work.
ALTER TABLE users ADD COLUMN comments_mode TEXT NOT NULL DEFAULT 'reflection_only'
    CHECK (comments_mode IN ('reflection_only', 'open'));

-- like_count/comment_count already exist (migration 000004); Prasad and
-- Smaran need the same shape of counter.
ALTER TABLE reels ADD COLUMN share_count BIGINT NOT NULL DEFAULT 0 CHECK (share_count >= 0);
ALTER TABLE reels ADD COLUMN save_count BIGINT NOT NULL DEFAULT 0 CHECK (save_count >= 0);

-- Pranam (like) — one row per (reel, user); toggled by inserting/deleting
-- this row (internal/social.Service.TogglePranam), not a boolean flag, so
-- "who pranam'd this" stays a real, queryable list for later (a reel's
-- Pranam count breakdown, an artist's own notifications) rather than
-- needing a second table bolted on afterward.
CREATE TABLE pranams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (reel_id, user_id)
);
CREATE INDEX pranams_reel_id_idx ON pranams(reel_id);

-- Smaran (save/bookmark) — same toggle shape as Pranam. user_id is indexed
-- too (unlike pranams) because "my saved reels" is a real screen a Smaran
-- feature implies, even though this slice doesn't build that screen yet.
CREATE TABLE smarans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (reel_id, user_id)
);
CREATE INDEX smarans_reel_id_idx ON smarans(reel_id);
CREATE INDEX smarans_user_id_idx ON smarans(user_id);

-- Sevak (follow) — joining a creator's circle, so this is user-to-user, not
-- reel-scoped like the three tables above.
CREATE TABLE sevaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (follower_id, creator_id),
    CHECK (follower_id <> creator_id)
);
CREATE INDEX sevaks_follower_id_idx ON sevaks(follower_id);
CREATE INDEX sevaks_creator_id_idx ON sevaks(creator_id);

-- Satsang (comment) — a flat list, deliberately no reply/parent-comment
-- column: neither comments_mode value changes anything structural in this
-- slice (no reply threading is built at all yet, that's P1+ scope). The one
-- real, enforced difference reflection_only makes today is a shorter max
-- length (internal/social.Service.PostSatsang) — nudging toward a brief
-- reflection rather than long back-and-forth, without pretending to ship a
-- moderation feature that isn't actually built.
CREATE TABLE satsang_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX satsang_comments_reel_id_created_at_idx ON satsang_comments(reel_id, created_at DESC);
