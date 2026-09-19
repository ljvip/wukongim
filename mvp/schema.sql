-- 微信类 IM MVP 业务数据库（PostgreSQL 15+）
-- WuKongIM 自己负责消息存储；本文件只保存业务数据和消息元数据。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    uid TEXT PRIMARY KEY,
    username TEXT UNIQUE,
    email TEXT UNIQUE,
    phone TEXT UNIQUE,
    password_hash TEXT NOT NULL,
    nickname TEXT NOT NULL DEFAULT '',
    avatar_url TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (username IS NOT NULL OR email IS NOT NULL OR phone IS NOT NULL)
);

CREATE TABLE groups (
    group_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    avatar_url TEXT NOT NULL DEFAULT '',
    owner_uid TEXT NOT NULL REFERENCES users(uid),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disbanded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE group_members (
    group_id TEXT NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
    uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    muted_until TIMESTAMPTZ,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, uid)
);

CREATE TABLE conversation_reads (
    uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    channel_type TEXT NOT NULL CHECK (channel_type IN ('person', 'group')),
    channel_id TEXT NOT NULL,
    last_read_message_id TEXT NOT NULL DEFAULT '',
    last_read_seq BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (uid, channel_type, channel_id)
);

-- 仅保存撤回等业务元数据，不复制消息正文。
CREATE TABLE message_metadata (
    message_id TEXT PRIMARY KEY,
    channel_type TEXT NOT NULL CHECK (channel_type IN ('person', 'group')),
    channel_id TEXT NOT NULL,
    sender_uid TEXT NOT NULL REFERENCES users(uid),
    message_type TEXT NOT NULL CHECK (message_type IN ('text', 'image', 'file')),
    sent_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    revoked_by TEXT REFERENCES users(uid)
);

CREATE INDEX idx_group_members_uid ON group_members(uid);
CREATE INDEX idx_message_metadata_channel ON message_metadata(channel_type, channel_id, sent_at DESC);
CREATE INDEX idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
