-- ============================================================
-- PersonalButler · 服务端 MySQL 8 初始化脚本
-- ============================================================
-- 用法：
--   mysql -uroot -p < sql/init.sql
--
-- 表结构说明：
--   1. 每张业务表都用 (device_id, id) 作为复合主键，device_id 对应客户端的
--      AppSyncConfig.deviceID（首次生成的稳定 UUID），用于多设备隔离。
--   2. `id` 是 iOS SwiftData @Model 的主键（多数为 UUID 字符串；AppModule
--      使用如 "schedule" 这样的稳定 slug）。
--   3. Date / Timestamp 字段与客户端 SyncPayload DTO 保持 unix double 语义
--      （Go 侧类型 float64；MySQL 侧使用 DOUBLE），避免时区与精度歧义。
--   4. 敏感字段：password.password_plain / otp.secret_plain 明文入库 —— 与
--      客户端契约一致（仅局域网内使用，二期上 AES 后再迁移）。
--   5. 当前 schema 对齐 iOS 端 SyncMeta.dataVersion = 5。
--      v5 变更：schedule / anniversary / password / otp / food / cook_recipe / note
--      新增 is_demo 列（TINYINT(1) NOT NULL DEFAULT 0），用于客户端「清理Demo数据」
--      按此过滤首启灌入的示例数据；用户自添 / Web 表单录入的数据 is_demo=0。
-- ============================================================

CREATE DATABASE IF NOT EXISTS `personal_butler`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE `personal_butler`;

-- ---------- sync_meta：每设备最近一次同步元信息 ----------
DROP TABLE IF EXISTS `sync_meta`;
CREATE TABLE `sync_meta` (
    `device_id`       VARCHAR(64)  NOT NULL,
    `sync_timestamp`  BIGINT       NOT NULL,
    `app_version`     VARCHAR(32)  NOT NULL DEFAULT '',
    `data_version`    INT          NOT NULL DEFAULT 5,
    `updated_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- todo（v4 新增 task_type / recipe_id / expected_ingredients / checked_ingredients） ----------
DROP TABLE IF EXISTS `todo`;
CREATE TABLE `todo` (
    `device_id`             VARCHAR(64)  NOT NULL,
    `id`                    VARCHAR(64)  NOT NULL,
    `name`                  VARCHAR(255) NOT NULL DEFAULT '',
    `source`                VARCHAR(32)  NOT NULL DEFAULT '',
    `due_date`              DOUBLE       NULL,
    `is_done`               TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`            DOUBLE       NOT NULL DEFAULT 0,
    `task_type`             VARCHAR(32)  NULL,
    `recipe_id`             VARCHAR(64)  NULL,
    `expected_ingredients`  TEXT         NULL,
    `checked_ingredients`   TEXT         NULL,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_todo_device_done` (`device_id`, `is_done`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- schedule ----------
DROP TABLE IF EXISTS `schedule`;
CREATE TABLE `schedule` (
    `device_id`                 VARCHAR(64)  NOT NULL,
    `id`                        VARCHAR(64)  NOT NULL,
    `title`                     VARCHAR(255) NOT NULL DEFAULT '',
    `remark`                    TEXT         NULL,
    `start_date`                DOUBLE       NOT NULL DEFAULT 0,
    `end_date`                  DOUBLE       NULL,
    `is_all_day`                TINYINT(1)   NOT NULL DEFAULT 0,
    `reminder_minutes_before`   INT          NULL,
    `color_tag`                 VARCHAR(32)  NOT NULL DEFAULT '',
    `is_completed`              TINYINT(1)   NOT NULL DEFAULT 0,
    `is_demo`                   TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_schedule_device_start` (`device_id`, `start_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- anniversary ----------
DROP TABLE IF EXISTS `anniversary`;
CREATE TABLE `anniversary` (
    `device_id`            VARCHAR(64)  NOT NULL,
    `id`                   VARCHAR(64)  NOT NULL,
    `name`                 VARCHAR(255) NOT NULL DEFAULT '',
    `date`                 DOUBLE       NOT NULL DEFAULT 0,
    `is_lunar`             TINYINT(1)   NOT NULL DEFAULT 0,
    `type`                 VARCHAR(32)  NOT NULL DEFAULT '',
    `reminder_days_before` INT          NULL,
    `emoji`                VARCHAR(16)  NOT NULL DEFAULT '',
    `is_demo`              TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- password（明文字段仅限局域网） ----------
DROP TABLE IF EXISTS `password`;
CREATE TABLE `password` (
    `device_id`       VARCHAR(64)  NOT NULL,
    `id`              VARCHAR(64)  NOT NULL,
    `platform`        VARCHAR(128) NOT NULL DEFAULT '',
    `account`         VARCHAR(255) NOT NULL DEFAULT '',
    `type_text`       VARCHAR(64)  NOT NULL DEFAULT '',
    `category`        VARCHAR(64)  NOT NULL DEFAULT '',
    `password_plain`  TEXT         NULL,
    `updated_at`      DOUBLE       NOT NULL DEFAULT 0,
    `is_demo`         TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_password_device_platform` (`device_id`, `platform`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- otp（TOTP Base32 密钥同上） ----------
DROP TABLE IF EXISTS `otp`;
CREATE TABLE `otp` (
    `device_id`     VARCHAR(64)  NOT NULL,
    `id`            VARCHAR(64)  NOT NULL,
    `issuer`        VARCHAR(128) NOT NULL DEFAULT '',
    `account_name`  VARCHAR(255) NOT NULL DEFAULT '',
    `secret_plain`  TEXT         NULL,
    `period`        INT          NOT NULL DEFAULT 30,
    `digits`        INT          NOT NULL DEFAULT 6,
    `order_idx`     INT          NOT NULL DEFAULT 0,
    `is_demo`       TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_otp_device_order` (`device_id`, `order_idx`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- food（v2 位置字段 / v3 rating→DOUBLE + icon_image_base64 / v5 is_demo） ----------
DROP TABLE IF EXISTS `food`;
CREATE TABLE `food` (
    `device_id`           VARCHAR(64)  NOT NULL,
    `id`                  VARCHAR(64)  NOT NULL,
    `name`                VARCHAR(255) NOT NULL DEFAULT '',
    `emoji`               VARCHAR(16)  NOT NULL DEFAULT '',
    `rating`              DOUBLE       NOT NULL DEFAULT 0,
    `tags`                TEXT         NULL,
    `remark`              TEXT         NULL,
    `date`                DOUBLE       NOT NULL DEFAULT 0,
    `category`            VARCHAR(64)  NOT NULL DEFAULT '',
    `place_name`          VARCHAR(255) NULL,
    `address`             TEXT         NULL,
    `latitude`            DOUBLE       NULL,
    `longitude`           DOUBLE       NULL,
    `icon_image_base64`   LONGTEXT     NULL,
    `is_demo`             TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_food_device_date` (`device_id`, `date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- cook_recipe（v4：移除旧 ingredients 文本字段，新增 ingredients_legacy_raw / icon_image_base64 / v5 is_demo） ----------
DROP TABLE IF EXISTS `cook_recipe`;
CREATE TABLE `cook_recipe` (
    `device_id`               VARCHAR(64)  NOT NULL,
    `id`                      VARCHAR(64)  NOT NULL,
    `name`                    VARCHAR(255) NOT NULL DEFAULT '',
    `emoji`                   VARCHAR(16)  NOT NULL DEFAULT '',
    `difficulty`              VARCHAR(32)  NOT NULL DEFAULT '',
    `minutes`                 INT          NOT NULL DEFAULT 0,
    `category`                VARCHAR(64)  NOT NULL DEFAULT '',
    `ingredients_legacy_raw`  TEXT         NULL,
    `steps`                   TEXT         NULL,
    `tips`                    TEXT         NULL,
    `icon_image_base64`       LONGTEXT     NULL,
    `is_demo`                 TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- cook_ingredient（v4 新增：菜谱结构化食材子项） ----------
DROP TABLE IF EXISTS `cook_ingredient`;
CREATE TABLE `cook_ingredient` (
    `device_id`   VARCHAR(64)  NOT NULL,
    `id`          VARCHAR(64)  NOT NULL,
    `recipe_id`   VARCHAR(64)  NOT NULL,
    `name`        VARCHAR(255) NOT NULL DEFAULT '',
    `amount`      VARCHAR(64)  NOT NULL DEFAULT '',
    `order_idx`   INT          NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_cook_ingredient_recipe` (`device_id`, `recipe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- cook_cart（v4 新增：烹饪车项） ----------
DROP TABLE IF EXISTS `cook_cart`;
CREATE TABLE `cook_cart` (
    `device_id`   VARCHAR(64)  NOT NULL,
    `id`          VARCHAR(64)  NOT NULL,
    `recipe_id`   VARCHAR(64)  NOT NULL,
    `servings`    INT          NOT NULL DEFAULT 1,
    `added_at`    DOUBLE       NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_cook_cart_recipe` (`device_id`, `recipe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- note ----------
DROP TABLE IF EXISTS `note`;
CREATE TABLE `note` (
    `device_id`  VARCHAR(64)  NOT NULL,
    `id`         VARCHAR(64)  NOT NULL,
    `title`      VARCHAR(255) NOT NULL DEFAULT '',
    `content`    MEDIUMTEXT   NULL,
    `tag`        VARCHAR(64)  NOT NULL DEFAULT '',
    `created_at` DOUBLE       NOT NULL DEFAULT 0,
    `updated_at` DOUBLE       NOT NULL DEFAULT 0,
    `is_demo`    TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`),
    KEY `idx_note_device_updated` (`device_id`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- app_module ----------
DROP TABLE IF EXISTS `app_module`;
CREATE TABLE `app_module` (
    `device_id`         VARCHAR(64)  NOT NULL,
    `id`                VARCHAR(64)  NOT NULL,
    `name`              VARCHAR(64)  NOT NULL DEFAULT '',
    `tag`               VARCHAR(32)  NOT NULL DEFAULT '',
    `icon_system_name`  VARCHAR(64)  NOT NULL DEFAULT '',
    `order_idx`         INT          NOT NULL DEFAULT 0,
    `coming_soon`       TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`device_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- app_setting（预留：MVP 现为空 map） ----------
DROP TABLE IF EXISTS `app_setting`;
CREATE TABLE `app_setting` (
    `device_id` VARCHAR(64) NOT NULL,
    `key`       VARCHAR(64) NOT NULL,
    `value`     TEXT        NULL,
    PRIMARY KEY (`device_id`, `key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
