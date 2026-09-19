const express = require('express');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;

// A serverless platform reuses a warm instance between invocations and freezes
// it in between, so connection pools have to be sized for one caller rather
// than for a long-lived server. Detected rather than configured, so nothing
// has to be set by hand on either side.
const IS_SERVERLESS = Boolean(process.env.VERCEL || process.env.AWS_LAMBDA_FUNCTION_NAME);

// ---------------------------------------------------------------------------
// PostgreSQL
//
// Two shapes of configuration are accepted because two exist in practice:
//
//   DB_HOST / DB_PORT / DB_USER / ...   discrete variables, what Compose passes
//   DATABASE_URL                        one connection string, which is what
//                                       every managed Postgres hands you
//
// The connection string wins when one is present, so the same code runs
// unchanged against the container on a laptop and against a managed database
// in the cloud. POSTGRES_URL is the name Vercel's own integrations inject.
// ---------------------------------------------------------------------------
const CONNECTION_STRING =
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  '';

const poolConfig = CONNECTION_STRING
  ? {
      connectionString: CONNECTION_STRING,
      // Managed Postgres serves a certificate signed by a root this runtime
      // does not ship, so verification is turned off while the transport stays
      // encrypted -- the setting every provider documents for a Node client.
      // An explicit sslmode=disable in the URL is still honoured.
      ssl: /[?&]sslmode=disable/.test(CONNECTION_STRING)
        ? false
        : { rejectUnauthorized: false },
    }
  : {
      host: process.env.DB_HOST,
      port: process.env.DB_PORT || 5432,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
    };

if (IS_SERVERLESS) {
  // One socket per instance. The default of 10 would have every concurrent
  // invocation hold ten connections open, which exhausts a managed database's
  // connection limit long before it exhausts anything else.
  poolConfig.max = 1;
  poolConfig.idleTimeoutMillis = 10000;
  poolConfig.connectionTimeoutMillis = 10000;
}

const pool = new Pool(poolConfig);

// Without this listener a dropped backend connection is an unhandled 'error'
// event on the pool, which takes the whole process down.
pool.on('error', (err) => console.error('Postgres pool error:', err.message));

// ---------------------------------------------------------------------------
// Redis (optional)
//
// The cache is a performance detail, never a dependency: if no Redis is
// configured, or it is unreachable, every read simply goes to Postgres.
// ---------------------------------------------------------------------------
const REDIS_URL =
  process.env.REDIS_URL ||
  process.env.KV_URL ||
  (process.env.REDIS_HOST
    ? `redis://${process.env.REDIS_HOST}:${process.env.REDIS_PORT || 6379}`
    : '');

let redisClient = null;
let redisReady = false;

if (REDIS_URL) {
  redisClient = createClient({ url: REDIS_URL });
  // Driven by events rather than by the connect() promise alone: node-redis
  // reconnects on its own, so 'ready' can fire many times over a process's
  // life and the flag has to follow the socket rather than the first attempt.
  redisClient.on('ready', () => { redisReady = true; console.log('Connected to Redis'); });
  redisClient.on('end', () => { redisReady = false; });
  redisClient.on('error', (err) => {
    redisReady = false;
    console.error('Redis error:', err.message);
  });
  redisClient.connect().catch((err) => console.error('Redis connect failed:', err.message));
} else {
  console.log('No Redis configured -- the cache is disabled and every read goes to Postgres.');
}

// Cache access degrades instead of failing. A cache that is down is a slower
// response, not a 500, so these three never throw into a request handler.
async function cacheGet(key) {
  if (!redisReady) return null;
  try {
    return await redisClient.get(key);
  } catch (err) {
    console.error('Redis GET failed:', err.message);
    return null;
  }
}

async function cacheSet(key, value, ttlSeconds) {
  if (!redisReady) return;
  try {
    await redisClient.set(key, value, { EX: ttlSeconds });
  } catch (err) {
    console.error('Redis SET failed:', err.message);
  }
}

async function cacheDel(key) {
  if (!redisReady) return;
  try {
    await redisClient.del(key);
  } catch (err) {
    console.error('Redis DEL failed:', err.message);
  }
}

// ---------------------------------------------------------------------------
// Schema bootstrap
//
// Under Compose the official Postgres image applies api/db/init.sql from
// /docker-entrypoint-initdb.d the first time the data volume is empty. A
// managed database has no such hook, so when one is configured by connection
// string the same file is applied from here instead.
//
// It runs at most once per process, and only when the table is genuinely
// absent -- init.sql seeds three rows unconditionally, so re-running it on a
// populated database would duplicate them.
// ---------------------------------------------------------------------------
let schemaReady = null;

function ensureSchema() {
  // Compose already ran init.sql; there is nothing to do and nothing to check.
  if (!CONNECTION_STRING) return Promise.resolve();

  if (!schemaReady) {
    schemaReady = (async () => {
      const { rows } = await pool.query("SELECT to_regclass('public.tasks') AS tbl");
      if (rows[0] && rows[0].tbl) return;

      let sql;
      try {
        sql = fs.readFileSync(path.join(__dirname, 'db', 'init.sql'), 'utf8');
      } catch (err) {
        throw new Error(
          'The tasks table does not exist and api/db/init.sql could not be read ' +
          `(${err.message}). Run that file against your database once, by hand.`
        );
      }

      console.log('tasks table is absent -- applying db/init.sql');
      await pool.query(sql);
      console.log('Schema created and seeded.');
    })().catch((err) => {
      // Clear the memo so the next request retries rather than inheriting a
      // permanent failure from one bad cold start.
      schemaReady = null;
      throw err;
    });
  }

  return schemaReady;
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.get('/api/tasks', async (req, res) => {
  try {
    const cached = await cacheGet('tasks');
    if (cached) return res.json({ source: 'cache', tasks: JSON.parse(cached) });

    await ensureSchema();
    const result = await pool.query(
      'SELECT id, title, description, status, created_at FROM tasks ORDER BY id'
    );
    await cacheSet('tasks', JSON.stringify(result.rows), 30);
    res.json({ source: 'db', tasks: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch tasks' });
  }
});

app.post('/api/tasks', async (req, res) => {
  const { title, description } = req.body;
  if (!title) return res.status(400).json({ error: 'title is required' });
  try {
    await ensureSchema();
    const result = await pool.query(
      'INSERT INTO tasks (title, description, status) VALUES ($1, $2, $3) RETURNING *',
      [title, description || '', 'pending']
    );
    await cacheDel('tasks');
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to create task' });
  }
});

// Listening is what a container does; a serverless platform imports the app and
// calls it per request instead. `require.main === module` is true only for
// `node server.js`, which is exactly the Dockerfile's CMD, so the container
// behaves as it always has and api/index.js gets a plain Express app.
if (require.main === module) {
  app.listen(PORT, () => console.log(`taskflow-api listening on port ${PORT}`));
}

module.exports = app;
