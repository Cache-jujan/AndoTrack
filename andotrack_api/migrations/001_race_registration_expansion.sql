-- ============================================================
-- AndoTrack — Migration: Race & Registration expansion
-- Run this ONCE against your existing andotrack database.
-- Safe to run: all statements use IF NOT EXISTS / IGNORE.
-- ============================================================

USE andotrack;

-- ── races table — new columns ─────────────────────────────

ALTER TABLE races
    ADD COLUMN IF NOT EXISTS category           VARCHAR(20)     DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS description        TEXT            DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS location           VARCHAR(255)    DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS sponsors           TEXT            DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS max_participants   INT             DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS scheduled_start    DATETIME        DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS registration_fee   FLOAT           DEFAULT 0.0,
    ADD COLUMN IF NOT EXISTS banner_url         VARCHAR(500)    DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS created_at         DATETIME        DEFAULT CURRENT_TIMESTAMP;

-- Expand status ENUM to include new lifecycle values
-- (MySQL requires redefining the full ENUM)
ALTER TABLE races
    MODIFY COLUMN status VARCHAR(20) DEFAULT 'upcoming';

-- ── race_runners table — new columns ─────────────────────

ALTER TABLE race_runners
    ADD COLUMN IF NOT EXISTS city               VARCHAR(100)    DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS contact_number     VARCHAR(30)     DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS is_first_marathon  BOOLEAN         DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS emergency_contact  VARCHAR(100)    DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS sex                ENUM('male','female','prefer_not_to_say')
                                                                DEFAULT 'prefer_not_to_say',
    ADD COLUMN IF NOT EXISTS qr_token           VARCHAR(100)    DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS is_present         BOOLEAN         DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS checked_in_at      DATETIME        DEFAULT NULL;

-- Unique index on qr_token so scans are fast and duplicates impossible
ALTER TABLE race_runners
    ADD CONSTRAINT uq_qr_token UNIQUE (qr_token);

-- ── Verify ───────────────────────────────────────────────

SELECT 'races columns:' AS '';
SHOW COLUMNS FROM races;

SELECT 'race_runners columns:' AS '';
SHOW COLUMNS FROM race_runners;