-- ============================================================
-- AndoTrack — COMPLETE SCHEMA MIGRATION
-- Derived from all SQLAlchemy models (models/*.py)
-- Run this ONCE on a fresh database.
-- Safe to re-run: uses IF NOT EXISTS throughout.
-- ============================================================

CREATE DATABASE IF NOT EXISTS andotrack
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE andotrack;

-- ── 1. users ─────────────────────────────────────────────────────────────────
-- Source: models/user.py → class User

CREATE TABLE IF NOT EXISTS users (
    id              INT          NOT NULL AUTO_INCREMENT,
    name            VARCHAR(100),
    email           VARCHAR(100) UNIQUE,
    password        VARCHAR(255),
    role            ENUM('runner', 'organizer') DEFAULT 'runner',
    date_of_birth   DATE,
    PRIMARY KEY (id),
    INDEX ix_users_id    (id),
    INDEX ix_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── 2. races ─────────────────────────────────────────────────────────────────
-- Source: models/race.py → class Race

CREATE TABLE IF NOT EXISTS races (
    id                  INT          NOT NULL AUTO_INCREMENT,
    name                VARCHAR(100) NOT NULL,
    distance_km         FLOAT        NOT NULL,
    category            VARCHAR(20),
    status              VARCHAR(20)  DEFAULT 'upcoming',
    -- status lifecycle:
    --   upcoming | registration_open | race_day | active | finished
    description         TEXT,
    location            VARCHAR(255),
    sponsors            TEXT,
    max_participants    INT,
    scheduled_start     DATETIME,
    registration_fee    FLOAT        DEFAULT 0.0,
    banner_url          VARCHAR(500),
    created_at          DATETIME     DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX ix_races_id (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── 3. race_runners ───────────────────────────────────────────────────────────
-- Source: models/race.py → class RaceRunner

CREATE TABLE IF NOT EXISTS race_runners (
    id                  INT      NOT NULL AUTO_INCREMENT,
    race_id             INT      NOT NULL,
    runner_id           INT      NOT NULL,
    registered_at       DATETIME DEFAULT CURRENT_TIMESTAMP,

    -- Registration form fields
    city                VARCHAR(100),
    contact_number      VARCHAR(30),
    is_first_marathon   BOOLEAN  DEFAULT FALSE,
    emergency_contact   VARCHAR(100),
    sex                 ENUM('male', 'female', 'prefer_not_to_say') DEFAULT 'prefer_not_to_say',

    -- Check-in / QR
    qr_token            VARCHAR(100) UNIQUE,
    is_present          BOOLEAN  DEFAULT FALSE,
    checked_in_at       DATETIME,
    race_status         VARCHAR(20) DEFAULT 'registered',
    -- race_status lifecycle: registered → active → finished | dnf | dns
    bib_number          INT,

    PRIMARY KEY (id),
    INDEX ix_race_runners_id       (id),
    INDEX ix_race_runners_qr_token (qr_token),
    CONSTRAINT fk_rr_race   FOREIGN KEY (race_id)   REFERENCES races(id),
    CONSTRAINT fk_rr_runner FOREIGN KEY (runner_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── 4. checkpoints ────────────────────────────────────────────────────────────
-- Source: models/checkpoint.py → class Checkpoint

CREATE TABLE IF NOT EXISTS checkpoints (
    id              INT          NOT NULL AUTO_INCREMENT,
    race_id         INT          NOT NULL,
    name            VARCHAR(100),
    lat             FLOAT,
    lng             FLOAT,
    radius_meters   INT          DEFAULT 20,
    order_number    INT,
    type            VARCHAR(20)  DEFAULT 'timing',
    -- type values: timing | aid_station | km_marker
    PRIMARY KEY (id),
    INDEX ix_checkpoints_id (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── 5. runner_checkpoints ─────────────────────────────────────────────────────
-- Source: models/checkpoint.py → class RunnerCheckpoint

CREATE TABLE IF NOT EXISTS runner_checkpoints (
    id              INT      NOT NULL AUTO_INCREMENT,
    runner_id       INT      NOT NULL,
    checkpoint_id   INT      NOT NULL,
    passed_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX ix_runner_checkpoints_id (id),
    UNIQUE KEY uq_runner_checkpoint (runner_id, checkpoint_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── 6. anomalies ──────────────────────────────────────────────────────────────
-- Source: models/anomaly.py → class Anomaly

CREATE TABLE IF NOT EXISTS anomalies (
    id              INT          NOT NULL AUTO_INCREMENT,
    race_id         INT,
    runner_id       INT,
    detected_at     DATETIME     DEFAULT CURRENT_TIMESTAMP,
    reason          VARCHAR(255),
    score           FLOAT,
    lat             FLOAT,
    lng             FLOAT,
    resolved        BOOLEAN      DEFAULT FALSE,
    PRIMARY KEY (id),
    INDEX ix_anomalies_id (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── 7. race_results ───────────────────────────────────────────────────────────
-- Source: models/result.py → class RaceResult

CREATE TABLE IF NOT EXISTS race_results (
    id              INT      NOT NULL AUTO_INCREMENT,
    race_id         INT      NOT NULL,
    runner_id       INT      NOT NULL,
    rank            INT      NOT NULL,
    distance_metres FLOAT    DEFAULT 0.0,
    distance_km     FLOAT    DEFAULT 0.0,
    pace_min_per_km FLOAT,
    pace_formatted  VARCHAR(20),
    finished_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX ix_race_results_id (id),
    CONSTRAINT fk_result_race   FOREIGN KEY (race_id)   REFERENCES races(id),
    CONSTRAINT fk_result_runner FOREIGN KEY (runner_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE checkpoints
  MODIFY COLUMN lat DOUBLE NOT NULL,
  MODIFY COLUMN lng DOUBLE NOT NULL;

ALTER TABLE anomalies
  MODIFY COLUMN lat DOUBLE,
  MODIFY COLUMN lng DOUBLE;
-- ── Verify ────────────────────────────────────────────────────────────────────

SELECT 'users'             AS `table`, COUNT(*) AS rows FROM users;
SELECT 'races'             AS `table`, COUNT(*) AS rows FROM races;
SELECT 'race_runners'      AS `table`, COUNT(*) AS rows FROM race_runners;
SELECT 'checkpoints'       AS `table`, COUNT(*) AS rows FROM checkpoints;
SELECT 'runner_checkpoints'AS `table`, COUNT(*) AS rows FROM runner_checkpoints;
SELECT 'anomalies'         AS `table`, COUNT(*) AS rows FROM anomalies;
SELECT 'race_results'      AS `table`, COUNT(*) AS rows FROM race_results;