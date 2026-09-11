//! Encrypted physical SQLite shards. All mutation files participate in one
//! rollback-journal transaction; WAL must never be used for this store.
mod codec;
mod records;
mod session;
use crate::store::{MAX_NEIGHBORS, Node, ROOT};
use aes_gcm::aead::{OsRng, rand_core::RngCore};
use codec::{Crypto, Metadata};
use diskann::{ANNError, ANNResult};
use rusqlite::{Connection, OpenFlags, OptionalExtension, config::DbConfig, limits::Limit, params};
pub use session::SqliteSession;
use std::{
    fs,
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::Duration,
};
use zeroize::Zeroizing;

trait SqlResult<T> {
    fn ann(self) -> ANNResult<T>;
}
impl<T> SqlResult<T> for rusqlite::Result<T> {
    fn ann(self) -> ANNResult<T> {
        self.map_err(|error| ANNError::message(format!("Native index SQLite: {error}")))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StoreConfig {
    pub dimensions: usize,
    pub shards: usize,
    /// Aggregate SQLite pager-cache target; not a whole-process RSS limit.
    pub cache_bytes: usize,
}
impl StoreConfig {
    fn validate(&self) -> ANNResult<()> {
        if !(1..=8192).contains(&self.dimensions)
            || !self.shards.is_power_of_two()
            || self.shards > 64
            || self.cache_bytes < (self.shards + 1) * 16 * 1024
            || self.cache_bytes > 256 * 1024 * 1024
        {
            return Err(ANNError::message(
                "Invalid native index storage configuration",
            ));
        }
        Ok(())
    }
    fn shard_for(&self, id: u64) -> usize {
        // A stable integer mix spreads sequential and sparse 64-bit identities.
        let mut value = id.wrapping_add(0x9e3779b97f4a7c15);
        value = (value ^ (value >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        value = (value ^ (value >> 27)).wrapping_mul(0x94d049bb133111eb);
        ((value ^ (value >> 31)) as usize) & (self.shards - 1)
    }
}

struct Active {
    token: u64,
    writable: bool,
    failed: bool,
    dirty: bool,
    meta: Metadata,
}
struct Inner {
    connection: Option<Connection>,
    crypto: Option<Crypto>,
    active: Option<Active>,
}
pub struct SqliteIndexStore {
    config: StoreConfig,
    inner: Mutex<Inner>,
    next_token: AtomicU64,
}

impl SqliteIndexStore {
    pub fn create(
        path: &Path,
        key: Zeroizing<[u8; 32]>,
        identity: [u8; 32],
        config: StoreConfig,
        root: &[f32],
    ) -> ANNResult<Arc<Self>> {
        config.validate()?;
        Node::new(root).validate(config.dimensions)?;
        // Refuse an existing directory. Failed creation is not an empty valid store.
        fs::create_dir(path)?;
        let crypto = Crypto::new(key, identity);
        let mut instance = [0; 16];
        OsRng.fill_bytes(&mut instance);
        let meta = Metadata {
            dimensions: config.dimensions,
            shards: config.shards,
            generation: 1,
            count: 1,
            instance,
        };
        let connection = connect(path, config, true)?;
        connection.execute_batch("BEGIN IMMEDIATE").ann()?;
        let result = (|| -> ANNResult<()> {
            connection.execute_batch("CREATE TABLE index_state (id INTEGER PRIMARY KEY CHECK(id=1), sealed BLOB NOT NULL)").ann()?;
            connection.execute_batch("CREATE TABLE index_records (key BLOB PRIMARY KEY CHECK(length(key) BETWEEN 1 AND 64), \
                revision INTEGER NOT NULL CHECK(revision>0), ciphertext BLOB NOT NULL) WITHOUT ROWID").ann()?;
            for shard in 0..config.shards {
                connection.execute_batch(&format!("CREATE TABLE s{shard}.nodes (id BLOB PRIMARY KEY CHECK(length(id)=8), \
                    revision INTEGER NOT NULL CHECK(revision>0), ciphertext BLOB NOT NULL) WITHOUT ROWID")).ann()?;
            }
            write_node(
                &connection,
                &crypto,
                config,
                &meta,
                ROOT,
                &Node::new(root),
                true,
            )?;
            connection
                .execute(
                    "INSERT INTO index_state(id,sealed) VALUES(1,?)",
                    [crypto.encode_meta(&meta)?],
                )
                .ann()?;
            connection.execute_batch("COMMIT").ann()?;
            Ok(())
        })();
        if let Err(error) = result {
            let _ = connection.execute_batch("ROLLBACK");
            return Err(error);
        }
        #[cfg(unix)]
        {
            fs::File::open(path)?.sync_all()?;
            fs::File::open(
                path.parent()
                    .ok_or_else(|| ANNError::message("Missing index parent"))?,
            )?
            .sync_all()?;
        }
        Ok(Arc::new(Self {
            config,
            inner: Mutex::new(Inner {
                connection: Some(connection),
                crypto: Some(crypto),
                active: None,
            }),
            next_token: AtomicU64::new(1),
        }))
    }
    pub fn open(
        path: &Path,
        key: Zeroizing<[u8; 32]>,
        identity: [u8; 32],
        config: StoreConfig,
    ) -> ANNResult<Arc<Self>> {
        config.validate()?;
        let crypto = Crypto::new(key, identity);
        let connection = connect(path, config, false)?;
        connection.execute_batch("BEGIN").ann()?;
        let meta = read_meta(&connection, &crypto, config)?;
        read_node(&connection, &crypto, config, &meta, ROOT)?
            .ok_or_else(|| ANNError::message("Native index root is missing"))?;
        connection.execute_batch("COMMIT").ann()?;
        Ok(Arc::new(Self {
            config,
            inner: Mutex::new(Inner {
                connection: Some(connection),
                crypto: Some(crypto),
                active: None,
            }),
            next_token: AtomicU64::new(1),
        }))
    }
    pub fn begin(
        self: &Arc<Self>,
        writable: bool,
        cancelled: Arc<AtomicBool>,
    ) -> ANNResult<Arc<SqliteSession>> {
        if cancelled.load(Ordering::Acquire) {
            return Err(ANNError::message("Native index operation cancelled"));
        }
        let mut inner = self
            .inner
            .lock()
            .map_err(|_| ANNError::message("Native index owner poisoned"))?;
        if inner.active.is_some() {
            return Err(ANNError::message(
                "Native index already has an active session",
            ));
        }
        let token = self
            .next_token
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |v| v.checked_add(1))
            .map_err(|_| ANNError::message("Native index session identity exhausted"))?;
        let connection = inner
            .connection
            .as_ref()
            .ok_or_else(|| ANNError::message("Native index is closed"))?;
        connection
            .execute_batch(if writable { "BEGIN IMMEDIATE" } else { "BEGIN" })
            .ann()?;
        let result = read_meta(connection, inner.crypto.as_ref().unwrap(), self.config).and_then(
            |mut meta| {
                if writable {
                    meta.generation = meta
                        .generation
                        .checked_add(1)
                        .filter(|v| *v <= i64::MAX as u64)
                        .ok_or_else(|| ANNError::message("Native index generation overflow"))?;
                }
                Ok(meta)
            },
        );
        match result {
            Ok(meta) => {
                inner.active = Some(Active {
                    token,
                    writable,
                    failed: false,
                    dirty: false,
                    meta,
                })
            }
            Err(error) => {
                if connection.execute_batch("ROLLBACK").is_err() {
                    inner.connection = None;
                    inner.crypto = None;
                }
                return Err(error);
            }
        }
        Ok(Arc::new(SqliteSession::new(self.clone(), token, cancelled)))
    }
    pub fn close(&self) -> ANNResult<()> {
        let mut inner = self
            .inner
            .lock()
            .map_err(|_| ANNError::message("Native index owner poisoned"))?;
        if inner.active.is_some() {
            return Err(ANNError::message(
                "Close the active native index session first",
            ));
        }
        inner.connection = None;
        inner.crypto = None;
        Ok(())
    }
    pub fn config(&self) -> StoreConfig {
        self.config
    }
    pub fn shard_for(&self, id: u64) -> usize {
        self.config.shard_for(id)
    }
}

fn connect(path: &Path, config: StoreConfig, create: bool) -> ANNResult<Connection> {
    let path = fs::canonicalize(path)?;
    let mut flags = OpenFlags::SQLITE_OPEN_READ_WRITE
        | OpenFlags::SQLITE_OPEN_NO_MUTEX
        | OpenFlags::SQLITE_OPEN_NOFOLLOW;
    if create {
        flags |= OpenFlags::SQLITE_OPEN_CREATE;
    }
    let connection = Connection::open_with_flags(path.join("catalog.sqlite"), flags).ann()?;
    connection.busy_timeout(Duration::ZERO).ann()?;
    connection
        .set_db_config(DbConfig::SQLITE_DBCONFIG_TRUSTED_SCHEMA, false)
        .ann()?;
    connection
        .set_db_config(DbConfig::SQLITE_DBCONFIG_ENABLE_ATTACH_CREATE, create)
        .ann()?;
    if connection.limit(Limit::SQLITE_LIMIT_ATTACHED).ann()? < config.shards as i32 {
        return Err(ANNError::message(
            "SQLite build cannot attach the configured native index shards",
        ));
    }
    connection.set_prepared_statement_cache_capacity(config.shards * 3 + 4);
    for shard in 0..config.shards {
        let file = path.join(format!("nodes-{shard:02x}.sqlite"));
        if !create && !fs::symlink_metadata(&file)?.file_type().is_file() {
            return Err(ANNError::message(
                "Native index shard is not a regular file",
            ));
        }
        connection
            .execute(
                &format!("ATTACH DATABASE ? AS s{shard}"),
                [file
                    .to_str()
                    .ok_or_else(|| ANNError::message("Invalid native index path"))?],
            )
            .ann()?;
    }
    let cache_kib = config.cache_bytes / 1024 / (config.shards + 1);
    for schema in
        std::iter::once("main".to_owned()).chain((0..config.shards).map(|v| format!("s{v}")))
    {
        if create {
            // Keep typical 384D vectors plus adjacency on index B-tree pages.
            connection
                .execute_batch(&format!("PRAGMA {schema}.page_size=16384"))
                .ann()?;
        }
        let mode: String = connection
            .query_row(&format!("PRAGMA {schema}.journal_mode=DELETE"), [], |row| {
                row.get(0)
            })
            .ann()?;
        if mode != "delete" {
            return Err(ANNError::message("Native index requires rollback journals"));
        }
        connection
            .execute_batch(&format!(
                "PRAGMA {schema}.synchronous=EXTRA; PRAGMA {schema}.mmap_size=0; \
            PRAGMA {schema}.cache_size=-{cache_kib}; PRAGMA {schema}.secure_delete=ON;"
            ))
            .ann()?;
    }
    connection.execute_batch("PRAGMA temp_store=MEMORY").ann()?;
    Ok(connection)
}

fn read_meta(connection: &Connection, crypto: &Crypto, config: StoreConfig) -> ANNResult<Metadata> {
    let encrypted: Option<Vec<u8>> = connection
        .query_row(
            "SELECT CASE WHEN length(sealed)=76 THEN sealed END FROM index_state WHERE id=1",
            [],
            |row| row.get(0),
        )
        .ann()?;
    let meta = crypto.decode_meta(
        &encrypted.ok_or_else(|| ANNError::message("Invalid native index metadata envelope"))?,
    )?;
    if meta.dimensions != config.dimensions
        || meta.shards != config.shards
        || meta.count == 0
        || meta.generation == 0
        || meta.generation > i64::MAX as u64
    {
        return Err(ANNError::message(
            "Native index metadata/configuration mismatch",
        ));
    }
    Ok(meta)
}
fn read_node(
    connection: &Connection,
    crypto: &Crypto,
    config: StoreConfig,
    meta: &Metadata,
    id: u64,
) -> ANNResult<Option<Node>> {
    let schema = config.shard_for(id);
    let max_bytes = 40 + config.dimensions * 4 + MAX_NEIGHBORS * 8;
    let result: Option<(i64, Option<Vec<u8>>)> = connection.prepare_cached(&format!(
        "SELECT revision,CASE WHEN length(ciphertext) BETWEEN 40 AND ? THEN ciphertext END FROM s{schema}.nodes WHERE id=?")).ann()?
        .query_row(params![max_bytes as i64, id.to_le_bytes().as_slice()], |row| Ok((row.get(0)?, row.get(1)?))).optional().ann()?;
    result
        .map(|(revision, envelope)| {
            if revision <= 0 || revision as u64 > meta.generation {
                return Err(ANNError::message("Invalid native index node revision"));
            }
            crypto.decode_node(
                meta,
                id,
                revision as u64,
                &envelope.ok_or_else(|| ANNError::message("Invalid native index node envelope"))?,
            )
        })
        .transpose()
}
fn write_node(
    connection: &Connection,
    crypto: &Crypto,
    config: StoreConfig,
    meta: &Metadata,
    id: u64,
    node: &Node,
    insert: bool,
) -> ANNResult<()> {
    let envelope = crypto.encode_node(meta, id, meta.generation, node)?;
    let shard = config.shard_for(id);
    let changed = if insert {
        connection
            .prepare_cached(&format!(
                "INSERT INTO s{shard}.nodes(revision,ciphertext,id) VALUES(?,?,?)"
            ))
            .ann()?
            .execute(params![
                meta.generation as i64,
                envelope,
                id.to_le_bytes().as_slice()
            ])
            .ann()?
    } else {
        connection
            .prepare_cached(&format!(
                "UPDATE s{shard}.nodes SET revision=?,ciphertext=? WHERE id=?"
            ))
            .ann()?
            .execute(params![
                meta.generation as i64,
                envelope,
                id.to_le_bytes().as_slice()
            ])
            .ann()?
    };
    if changed != 1 {
        return Err(ANNError::message(
            "Native index node mutation lost its target",
        ));
    }
    Ok(())
}
