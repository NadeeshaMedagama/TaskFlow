CREATE TABLE IF NOT EXISTS tasks (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO tasks (title, description, status) VALUES
  ('Set up project repo', 'Initialize git and folder structure', 'done'),
  ('Containerize the API', 'Write a production-grade Dockerfile', 'pending'),
  ('Containerize the frontend', 'Serve static files via nginx', 'pending');
