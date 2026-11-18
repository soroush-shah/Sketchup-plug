CREATE TABLE IF NOT EXISTS users (
  id {PK},
  email VARCHAR(190) NOT NULL UNIQUE,
  name VARCHAR(190) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'viewer',
  active TINYINT NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  last_login_at DATETIME NULL
) {ENGINE};

CREATE TABLE IF NOT EXISTS api_tokens (
  id {PK},
  user_id INT UNSIGNED NOT NULL,
  name VARCHAR(190) NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  prefix VARCHAR(16) NOT NULL,
  revoked TINYINT NOT NULL DEFAULT 0,
  last_used_at DATETIME NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) {ENGINE};

CREATE TABLE IF NOT EXISTS projects (
  id {PK},
  name VARCHAR(190) NOT NULL,
  description TEXT NULL,
  created_by INT UNSIGNED NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) {ENGINE};

CREATE TABLE IF NOT EXISTS models (
  id {PK},
  project_id INT UNSIGNED NOT NULL,
  name VARCHAR(190) NOT NULL,
  description TEXT NULL,
  current_version_id INT UNSIGNED NULL,
  created_by INT UNSIGNED NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) {ENGINE};

CREATE TABLE IF NOT EXISTS model_versions (
  id {PK},
  model_id INT UNSIGNED NOT NULL,
  version_no INT UNSIGNED NOT NULL,
  note TEXT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'uploading',
  has_3d TINYINT NOT NULL DEFAULT 0,
  source VARCHAR(20) NOT NULL DEFAULT 'plugin',
  approval_status VARCHAR(30) NOT NULL DEFAULT 'pending',
  approval_note TEXT NULL,
  approved_by INT UNSIGNED NULL,
  approved_at DATETIME NULL,
  stats_json {JSON} NULL,
  created_by INT UNSIGNED NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL
) {ENGINE};

CREATE TABLE IF NOT EXISTS files (
  id {PK},
  version_id INT UNSIGNED NOT NULL,
  kind VARCHAR(20) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  path VARCHAR(500) NOT NULL,
  size {BIG} NOT NULL,
  original_size {BIG} NOT NULL,
  sha256 CHAR(64) NULL,
  mime VARCHAR(100) NOT NULL,
  gzipped TINYINT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (version_id) REFERENCES model_versions(id) ON DELETE CASCADE
) {ENGINE};

CREATE TABLE IF NOT EXISTS permissions (
  id {PK},
  user_id INT UNSIGNED NOT NULL,
  project_id INT UNSIGNED NULL,
  model_id INT UNSIGNED NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'viewer',
  created_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
  FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE CASCADE
) {ENGINE};

CREATE TABLE IF NOT EXISTS share_links (
  id {PK},
  token VARCHAR(64) NOT NULL UNIQUE,
  model_id INT UNSIGNED NOT NULL,
  version_id INT UNSIGNED NULL,
  label VARCHAR(190) NULL,
  password_hash VARCHAR(255) NULL,
  expires_at DATETIME NULL,
  allow_download TINYINT NOT NULL DEFAULT 0,
  allow_comments TINYINT NOT NULL DEFAULT 0,
  watermark VARCHAR(190) NULL,
  view_state_json {JSON} NULL,
  views INT UNSIGNED NOT NULL DEFAULT 0,
  revoked TINYINT NOT NULL DEFAULT 0,
  created_by INT UNSIGNED NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE CASCADE,
  FOREIGN KEY (version_id) REFERENCES model_versions(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) {ENGINE};

CREATE TABLE IF NOT EXISTS annotations (
  id {PK},
  model_id INT UNSIGNED NOT NULL,
  version_id INT UNSIGNED NULL,
  parent_id INT UNSIGNED NULL,
  user_id INT UNSIGNED NULL,
  author_name VARCHAR(190) NOT NULL,
  type VARCHAR(20) NOT NULL,
  title VARCHAR(255) NULL,
  body TEXT NULL,
  data_json {JSON} NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) {ENGINE};

CREATE TABLE IF NOT EXISTS upload_sessions (
  id VARCHAR(40) NOT NULL PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  version_id INT UNSIGNED NOT NULL,
  kind VARCHAR(20) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  total_size {BIG} NOT NULL,
  original_size {BIG} NOT NULL,
  chunk_size INT UNSIGNED NOT NULL,
  total_chunks INT UNSIGNED NOT NULL,
  received_json {JSON} NOT NULL,
  sha256 CHAR(64) NULL,
  gzipped TINYINT NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  created_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (version_id) REFERENCES model_versions(id) ON DELETE CASCADE
) {ENGINE};

CREATE TABLE IF NOT EXISTS audit_log (
  id {PK},
  user_id INT UNSIGNED NULL,
  action VARCHAR(60) NOT NULL,
  target VARCHAR(190) NULL,
  details TEXT NULL,
  ip VARCHAR(64) NULL,
  created_at DATETIME NOT NULL
) {ENGINE};

CREATE INDEX idx_models_project ON models(project_id);
CREATE INDEX idx_versions_model ON model_versions(model_id);
CREATE INDEX idx_files_version ON files(version_id);
CREATE INDEX idx_perm_user ON permissions(user_id);
CREATE INDEX idx_ann_model ON annotations(model_id);
CREATE INDEX idx_audit_action ON audit_log(action, ip, created_at)
