const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const AWS = require('aws-sdk');
require('dotenv').config();

// 🎓 BACKEND SEMPLIFICATO PER ESAME
// ✅ Include: Cognito, SNS, SQS in modo basilare per dimostrare conoscenza

const app = express();
const PORT = process.env.PORT || 3000;

// Configurazione AWS
const region = process.env.AWS_REGION || 'eu-west-1';
AWS.config.update({ region });

const sns = new AWS.SNS();
const sqs = new AWS.SQS();
const cognito = new AWS.CognitoIdentityServiceProvider();

// Variabili ambiente
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;
const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID;
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN;
const SQS_QUEUE_URL = process.env.SQS_QUEUE_URL;

// Middleware base
app.use(cors());
app.use(express.json());

// Database connection
const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'workflow',
  connectionLimit: 5
};

const pool = mysql.createPool(dbConfig);

// 🔐 FUNZIONI COGNITO SEMPLIFICATE
const registerWithCognito = async (email, password) => {
  try {
    const params = {
      UserPoolId: COGNITO_USER_POOL_ID,
      Username: email,
      TemporaryPassword: password,
      MessageAction: 'SUPPRESS',
      UserAttributes: [
        { Name: 'email', Value: email },
        { Name: 'email_verified', Value: 'true' }
      ]
    };
    
    await cognito.adminCreateUser(params).promise();
    
    await cognito.adminSetUserPassword({
      UserPoolId: COGNITO_USER_POOL_ID,
      Username: email,
      Password: password,
      Permanent: true
    }).promise();
    
    console.log(`✅ Utente Cognito creato: ${email}`);
    return true;
  } catch (error) {
    console.log(`⚠️ Cognito registration failed: ${error.message}`);
    return false; // Fallback a registrazione locale
  }
};

const loginWithCognito = async (email, password) => {
  try {
    const params = {
      AuthFlow: 'ADMIN_NO_SRP_AUTH',
      UserPoolId: COGNITO_USER_POOL_ID,
      ClientId: COGNITO_CLIENT_ID,
      AuthParameters: {
        USERNAME: email,
        PASSWORD: password
      }
    };
    
    const result = await cognito.adminInitiateAuth(params).promise();
    console.log(`✅ Login Cognito riuscito: ${email}`);
    return result.AuthenticationResult;
  } catch (error) {
    console.log(`⚠️ Cognito login failed: ${error.message}`);
    return null; // Fallback a login locale
  }
};

// 📧 FUNZIONE SNS SEMPLIFICATA
const sendSNSNotification = async (message, subject = 'Workflow Notification') => {
  try {
    const params = {
      TopicArn: SNS_TOPIC_ARN,
      Message: JSON.stringify(message),
      Subject: subject
    };
    
    const result = await sns.publish(params).promise();
    console.log(`📧 SNS notification sent: ${result.MessageId}`);
  } catch (error) {
    console.log(`⚠️ SNS failed: ${error.message}`);
  }
};

// 📤 FUNZIONE SQS SEMPLIFICATA
const sendToSQS = async (message) => {
  try {
    const params = {
      QueueUrl: SQS_QUEUE_URL,
      MessageBody: JSON.stringify(message)
    };
    
    const result = await sqs.sendMessage(params).promise();
    console.log(`📤 SQS message sent: ${result.MessageId}`);
  } catch (error) {
    console.log(`⚠️ SQS failed: ${error.message}`);
  }
};

// JWT middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Token richiesto' });
  }

  jwt.verify(token, process.env.JWT_SECRET || 'fallback-secret', (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Token non valido' });
    }
    req.user = user;
    next();
  });
};

// 🏥 HEALTH CHECK SEMPLIFICATO
app.get('/health', async (req, res) => {
  try {
    // Test database
    await pool.execute('SELECT 1');
    
    const health = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        database: '✅ Connected',
        cognito: COGNITO_USER_POOL_ID ? '✅ Configured' : '❌ Not configured',
        sns: SNS_TOPIC_ARN ? '✅ Configured' : '❌ Not configured',
        sqs: SQS_QUEUE_URL ? '✅ Configured' : '❌ Not configured'
      }
    };
    
    res.json(health);
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', error: error.message });
  }
});

// 📝 REGISTRAZIONE UTENTE (con Cognito + fallback)
app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password } = req.body;

    // Validazione semplice
    if (!username || !email || !password) {
      return res.status(400).json({ error: 'Tutti i campi sono richiesti' });
    }

    if (password.length < 6) {
      return res.status(400).json({ error: 'Password deve essere almeno 6 caratteri' });
    }

    // Check se utente esiste
    const [existing] = await pool.execute(
      'SELECT id FROM users WHERE email = ? OR username = ?',
      [email, username]
    );

    if (existing.length > 0) {
      return res.status(409).json({ error: 'Utente già esistente' });
    }

    // 🔐 Prova registrazione Cognito
    const cognitoSuccess = await registerWithCognito(email, password);

    // Hash password per database locale
    const hashedPassword = await bcrypt.hash(password, 10);

    // Salva nel database
    const [result] = await pool.execute(
      'INSERT INTO users (username, email, password, cognito_enabled, created_at) VALUES (?, ?, ?, ?, NOW())',
      [username, email, hashedPassword, cognitoSuccess]
    );

    // Genera JWT
    const token = jwt.sign(
      { userId: result.insertId, username, email },
      process.env.JWT_SECRET || 'fallback-secret',
      { expiresIn: '24h' }
    );

    // 📧 Invia notifica SNS
    await sendSNSNotification({
      type: 'user_registered',
      username,
      email,
      timestamp: new Date().toISOString()
    }, 'Nuova Registrazione Utente');

    // 📤 Invia evento a SQS
    await sendToSQS({
      event: 'user_registered',
      userId: result.insertId,
      username,
      email,
      timestamp: new Date().toISOString()
    });

    console.log(`👤 Nuovo utente registrato: ${username} (${email})`);

    res.status(201).json({
      message: 'Utente creato con successo',
      token,
      user: { 
        id: result.insertId, 
        username, 
        email,
        cognitoEnabled: cognitoSuccess
      }
    });
  } catch (error) {
    console.error('❌ Errore registrazione:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// 🔑 LOGIN UTENTE (con Cognito + fallback)
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email e password richieste' });
    }

    // Trova utente nel database
    const [users] = await pool.execute(
      'SELECT id, username, email, password, cognito_enabled FROM users WHERE email = ?',
      [email]
    );

    if (users.length === 0) {
      return res.status(401).json({ error: 'Credenziali non valide' });
    }

    const user = users[0];

    // 🔐 Prova login Cognito se abilitato
    let cognitoResult = null;
    if (user.cognito_enabled) {
      cognitoResult = await loginWithCognito(email, password);
    }

    // Se Cognito fallisce, prova login locale
    if (!cognitoResult) {
      const validPassword = await bcrypt.compare(password, user.password);
      if (!validPassword) {
        return res.status(401).json({ error: 'Credenziali non valide' });
      }
      console.log(`🔓 Login locale: ${email}`);
    } else {
      console.log(`🔓 Login Cognito: ${email}`);
    }

    // Genera JWT
    const token = jwt.sign(
      { userId: user.id, username: user.username, email },
      process.env.JWT_SECRET || 'fallback-secret',
      { expiresIn: '24h' }
    );

    // 📤 Invia evento login a SQS
    await sendToSQS({
      event: 'user_login',
      userId: user.id,
      username: user.username,
      email,
      loginMethod: cognitoResult ? 'cognito' : 'local',
      timestamp: new Date().toISOString()
    });

    res.json({
      message: 'Login effettuato con successo',
      token,
      user: { 
        id: user.id, 
        username: user.username, 
        email,
        loginMethod: cognitoResult ? 'cognito' : 'local'
      }
    });
  } catch (error) {
    console.error('❌ Errore login:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// 📋 GET TASKS
app.get('/api/tasks', authenticateToken, async (req, res) => {
  try {
    const [tasks] = await pool.execute(
      'SELECT * FROM tasks WHERE user_id = ? ORDER BY created_at DESC',
      [req.user.userId]
    );

    res.json(tasks);
  } catch (error) {
    console.error('❌ Errore get tasks:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// ➕ CREATE TASK (con notifiche)
app.post('/api/tasks', authenticateToken, async (req, res) => {
  try {
    const { title, description = '', category = '', priority = 'medium', due_date = null } = req.body;

    if (!title) {
      return res.status(400).json({ error: 'Titolo richiesto' });
    }

    const [result] = await pool.execute(
      'INSERT INTO tasks (user_id, title, description, category, priority, due_date, created_at) VALUES (?, ?, ?, ?, ?, ?, NOW())',
      [req.user.userId, title, description, category, priority, due_date]
    );

    const [newTask] = await pool.execute(
      'SELECT * FROM tasks WHERE id = ?',
      [result.insertId]
    );

    // 📧 Notifica SNS per task ad alta priorità
    if (priority === 'high') {
      await sendSNSNotification({
        type: 'high_priority_task',
        taskId: result.insertId,
        title,
        username: req.user.username,
        timestamp: new Date().toISOString()
      }, 'Task Alta Priorità Creata');
    }

    // 📤 Invia a SQS per processing
    await sendToSQS({
      event: 'task_created',
      taskId: result.insertId,
      userId: req.user.userId,
      title,
      priority,
      category,
      timestamp: new Date().toISOString()
    });

    console.log(`📝 Nuova task: ${title} (${priority})`);

    res.status(201).json(newTask[0]);
  } catch (error) {
    console.error('❌ Errore create task:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// ✏️ UPDATE TASK (con notifica completamento)
app.put('/api/tasks/:id', authenticateToken, async (req, res) => {
  try {
    const { title, description, category, priority, due_date, completed } = req.body;
    const taskId = req.params.id;

    // Get current task state
    const [currentTask] = await pool.execute(
      'SELECT completed, title FROM tasks WHERE id = ? AND user_id = ?',
      [taskId, req.user.userId]
    );

    if (currentTask.length === 0) {
      return res.status(404).json({ error: 'Task non trovata' });
    }

    const wasCompleted = currentTask[0].completed;
    const taskTitle = currentTask[0].title;

    const [result] = await pool.execute(
      'UPDATE tasks SET title = ?, description = ?, category = ?, priority = ?, due_date = ?, completed = ?, updated_at = NOW() WHERE id = ? AND user_id = ?',
      [title || taskTitle, description || '', category || '', priority || 'medium', due_date, completed || false, taskId, req.user.userId]
    );

    // 📧 Notifica completamento task
    if (!wasCompleted && completed) {
      await sendSNSNotification({
        type: 'task_completed',
        taskId,
        title: title || taskTitle,
        username: req.user.username,
        timestamp: new Date().toISOString()
      }, 'Task Completata');

      console.log(`✅ Task completata: ${title || taskTitle}`);
    }

    // 📤 Invia evento a SQS
    await sendToSQS({
      event: completed && !wasCompleted ? 'task_completed' : 'task_updated',
      taskId: parseInt(taskId),
      userId: req.user.userId,
      title: title || taskTitle,
      completed,
      timestamp: new Date().toISOString()
    });

    const [updatedTask] = await pool.execute(
      'SELECT * FROM tasks WHERE id = ?',
      [taskId]
    );

    res.json(updatedTask[0]);
  } catch (error) {
    console.error('❌ Errore update task:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// 🗑️ DELETE TASK
app.delete('/api/tasks/:id', authenticateToken, async (req, res) => {
  try {
    const taskId = req.params.id;

    const [taskInfo] = await pool.execute(
      'SELECT title FROM tasks WHERE id = ? AND user_id = ?',
      [taskId, req.user.userId]
    );

    if (taskInfo.length === 0) {
      return res.status(404).json({ error: 'Task non trovata' });
    }

    await pool.execute(
      'DELETE FROM tasks WHERE id = ? AND user_id = ?',
      [taskId, req.user.userId]
    );

    // 📤 Invia evento eliminazione a SQS
    await sendToSQS({
      event: 'task_deleted',
      taskId: parseInt(taskId),
      userId: req.user.userId,
      title: taskInfo[0].title,
      timestamp: new Date().toISOString()
    });

    console.log(`🗑️ Task eliminata: ${taskInfo[0].title}`);

    res.json({ message: 'Task eliminata con successo' });
  } catch (error) {
    console.error('❌ Errore delete task:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// 📊 STATISTICHE UTENTE
app.get('/api/stats', authenticateToken, async (req, res) => {
  try {
    const [stats] = await pool.execute(`
      SELECT 
        COUNT(*) as total_tasks,
        SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END) as completed_tasks,
        SUM(CASE WHEN completed = 0 THEN 1 ELSE 0 END) as pending_tasks,
        COUNT(DISTINCT category) as categories_count
      FROM tasks 
      WHERE user_id = ?
    `, [req.user.userId]);

    res.json(stats[0]);
  } catch (error) {
    console.error('❌ Errore stats:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// 🔍 ENDPOINT ADMIN - Visualizza messaggi SQS (per demo esame)
app.get('/api/admin/queue-messages', async (req, res) => {
  try {
    const params = {
      QueueUrl: SQS_QUEUE_URL,
      MaxNumberOfMessages: 10,
      WaitTimeSeconds: 1
    };

    const result = await sqs.receiveMessage(params).promise();
    const messages = result.Messages || [];

    const processedMessages = messages.map(msg => {
      try {
        return {
          messageId: msg.MessageId,
          body: JSON.parse(msg.Body),
          timestamp: msg.Attributes?.SentTimestamp
        };
      } catch (e) {
        return {
          messageId: msg.MessageId,
          body: msg.Body,
          error: 'Invalid JSON'
        };
      }
    });

    // Non eliminare i messaggi per permettere di vederli nella demo
    console.log(`📤 Trovati ${messages.length} messaggi in coda SQS`);

    res.json({
      queueUrl: SQS_QUEUE_URL,
      messageCount: messages.length,
      messages: processedMessages
    });

  } catch (error) {
    console.error('❌ Errore lettura SQS:', error);
    res.status(500).json({ error: 'Errore lettura coda SQS' });
  }
});

// 📱 ENDPOINT DEMO - Info sui servizi AWS (per presentazione esame)
app.get('/api/demo/aws-services', async (req, res) => {
  try {
    const services = {
      cognito: {
        userPoolId: COGNITO_USER_POOL_ID,
        clientId: COGNITO_CLIENT_ID,
        status: COGNITO_USER_POOL_ID ? 'Configurato' : 'Non configurato',
        description: 'Gestione autenticazione utenti'
      },
      sns: {
        topicArn: SNS_TOPIC_ARN,
        status: SNS_TOPIC_ARN ? 'Configurato' : 'Non configurato',
        description: 'Invio notifiche push'
      },
      sqs: {
        queueUrl: SQS_QUEUE_URL,
        status: SQS_QUEUE_URL ? 'Configurato' : 'Non configurato',
        description: 'Code messaggi asincroni'
      },
      rds: {
        host: process.env.DB_HOST,
        status: process.env.DB_HOST ? 'Configurato' : 'Non configurato',
        description: 'Database MySQL gestito'
      }
    };

    // Test connettività servizi
    try {
      await pool.execute('SELECT 1');
      services.rds.connectivity = '✅ Connesso';
    } catch (e) {
      services.rds.connectivity = '❌ Errore connessione';
    }

    console.log('📋 Richiesta info servizi AWS per demo esame');

    res.json({
      timestamp: new Date().toISOString(),
      region: region,
      services,
      architecture: {
        frontend: 'React.js su S3 Static Website',
        backend: 'Node.js su ECS Fargate',
        database: 'MySQL su RDS',
        authentication: 'AWS Cognito User Pool',
        notifications: 'AWS SNS',
        queueing: 'AWS SQS',
        monitoring: 'CloudWatch Logs'
      }
    });

  } catch (error) {
    console.error('❌ Errore demo services:', error);
    res.status(500).json({ error: 'Errore interno del server' });
  }
});

// Inizializzazione database SEMPLIFICATA
async function initDatabase() {
  try {
    console.log('🗄️ Inizializzando database...');
    
    // Tabella utenti (con supporto Cognito)
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        cognito_enabled BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Tabella task semplificata
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS tasks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        description TEXT,
        category VARCHAR(100),
        priority ENUM('low', 'medium', 'high') DEFAULT 'medium',
        completed BOOLEAN DEFAULT FALSE,
        due_date DATE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `);

    console.log('✅ Database inizializzato con successo');
  } catch (error) {
    console.error('❌ Errore inizializzazione database:', error);
    process.exit(1);
  }
}

// Gestione errori globali
process.on('uncaughtException', (error) => {
  console.error('💥 Uncaught Exception:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('💥 Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Avvio server
app.listen(PORT, async () => {
  await initDatabase();
  
  console.log(`✅ Workflow Backend started on port ${PORT}`);
  console.log(`🏥 Health: http://localhost:${PORT}/health`);
  
  // Log servizi AWS se configurati
  if (COGNITO_USER_POOL_ID) console.log(`🔐 Cognito: ${COGNITO_USER_POOL_ID}`);
  if (SNS_TOPIC_ARN) console.log(`📧 SNS: ${SNS_TOPIC_ARN}`);
  if (SQS_QUEUE_URL) console.log(`📤 SQS: ${SQS_QUEUE_URL}`);
});

module.exports = app;