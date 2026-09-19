const express = require('express');
const { Pool } = require('pg');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

const redisClient = createClient({
  url: `redis://${process.env.REDIS_HOST}:${process.env.REDIS_PORT || 6379}`
});
redisClient.on('error', (err) => console.error('Redis error:', err.message));

let redisReady = false;
redisClient.connect()
  .then(() => { redisReady = true; console.log('Connected to Redis'); })
  .catch((err) => console.error('Redis connect failed:', err.message));

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.get('/api/tasks', async (req, res) => {
  try {
    if (redisReady) {
      const cached = await redisClient.get('tasks');
      if (cached) return res.json({ source: 'cache', tasks: JSON.parse(cached) });
    }
    const result = await pool.query(
      'SELECT id, title, description, status, created_at FROM tasks ORDER BY id'
    );
    if (redisReady) {
      await redisClient.set('tasks', JSON.stringify(result.rows), { EX: 30 });
    }
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
    const result = await pool.query(
      'INSERT INTO tasks (title, description, status) VALUES ($1, $2, $3) RETURNING *',
      [title, description || '', 'pending']
    );
    if (redisReady) await redisClient.del('tasks');
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to create task' });
  }
});

app.listen(PORT, () => console.log(`taskflow-api listening on port ${PORT}`));
