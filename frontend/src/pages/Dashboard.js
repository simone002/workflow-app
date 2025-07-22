import React, { useState, useEffect } from 'react';
import {
  Container,
  Typography,
  Box,
  Paper,
  Grid,
  Card,
  CardContent,
  Button,
  AppBar,
  Toolbar,
  IconButton,
  Fab,
  Alert,
  CircularProgress,
} from '@mui/material';
import {
  Add as AddIcon,
  ExitToApp as LogoutIcon,
  Assignment as TaskIcon,
  CheckCircle as CompletedIcon,
  Schedule as PendingIcon,
  Category as CategoryIcon,
  Warning as WarningIcon,
  Today as TodayIcon,
  DateRange as DateRangeIcon,
  Schedule as ScheduleIcon,
} from '@mui/icons-material';
import dayjs from 'dayjs';
import 'dayjs/locale/it';
import { useAuth } from '../contexts/AuthContext';
import { tasksAPI } from '../services/api';
import TaskList from '../components/TaskList';
import TaskForm from '../components/TaskForm';

dayjs.locale('it');

const Dashboard = () => {
  const [tasks, setTasks] = useState([]);
  const [stats, setStats] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [openTaskForm, setOpenTaskForm] = useState(false);
  const [editingTask, setEditingTask] = useState(null);

  const { user, logout } = useAuth();

  const fetchTasks = async () => {
    try {
      const response = await tasksAPI.getTasks();
      setTasks(response.data);
    } catch (error) {
      setError('Errore nel caricamento delle task');
      console.error('Error fetching tasks:', error);
    }
  };

  const fetchStats = async () => {
    try {
      const response = await tasksAPI.getStats();
      setStats(response.data);
    } catch (error) {
      console.error('Error fetching stats:', error);
    }
  };

  useEffect(() => {
    const loadData = async () => {
      setLoading(true);
      await Promise.all([fetchTasks(), fetchStats()]);
      setLoading(false);
    };
    loadData();
  }, []);

  // Calcola statistiche delle date
  const getDateStats = () => {
    const today = dayjs();
    const tomorrow = today.add(1, 'day');
    const nextWeek = today.add(7, 'day');
    
    const overdueTasks = tasks.filter(task => 
      !task.completed && 
      task.due_date && 
      dayjs(task.due_date).isBefore(today, 'day')
    ).length;
    
    const todayTasks = tasks.filter(task => 
      !task.completed && 
      task.due_date && 
      dayjs(task.due_date).isSame(today, 'day')
    ).length;
    
    const tomorrowTasks = tasks.filter(task => 
      !task.completed && 
      task.due_date && 
      dayjs(task.due_date).isSame(tomorrow, 'day')
    ).length;
    
    const thisWeekTasks = tasks.filter(task => 
      !task.completed && 
      task.due_date && 
      dayjs(task.due_date).isBefore(nextWeek, 'day') &&
      dayjs(task.due_date).isAfter(today, 'day')
    ).length;
    
    const noDateTasks = tasks.filter(task => 
      !task.completed && !task.due_date
    ).length;
    
    return {
      overdue: overdueTasks,
      today: todayTasks,
      tomorrow: tomorrowTasks,
      thisWeek: thisWeekTasks,
      noDate: noDateTasks,
    };
  };

  const handleCreateTask = async (taskData) => {
    try {
      const response = await tasksAPI.createTask(taskData);
      setTasks([response.data, ...tasks]);
      setOpenTaskForm(false);
      fetchStats();
    } catch (error) {
      setError('Errore nella creazione della task');
      console.error('Error creating task:', error);
    }
  };

  const handleUpdateTask = async (taskId, taskData) => {
    try {
      const response = await tasksAPI.updateTask(taskId, taskData);
      setTasks(tasks.map(task => task.id === taskId ? response.data : task));
      setEditingTask(null);
      fetchStats();
    } catch (error) {
      setError('Errore nell\'aggiornamento della task');
      console.error('Error updating task:', error);
    }
  };

  const handleDeleteTask = async (taskId) => {
    try {
      await tasksAPI.deleteTask(taskId);
      setTasks(tasks.filter(task => task.id !== taskId));
      fetchStats();
    } catch (error) {
      setError('Errore nell\'eliminazione della task');
      console.error('Error deleting task:', error);
    }
  };

  // 🔧 SOSTITUISCI questa funzione nel tuo Dashboard.js

  const handleToggleComplete = async (task) => {
    try {
      console.log('Toggling task completion:', task.id, 'from', task.completed, 'to', !task.completed);
      
      // 🎯 Prepara i dati completi per l'update (INCLUDENDO completed)
      const updateData = {
        title: task.title,
        description: task.description || '',
        category: task.category || '',
        priority: task.priority || 'medium',
        completed: !task.completed  // 🔥 QUESTO È IL CAMPO CHIAVE!
      };
      
      // Aggiungi due_date se esiste
      if (task.due_date) {
        updateData.due_date = task.due_date;
      }
      
      console.log('Sending update data:', updateData);
      
      // 🚀 Invia la richiesta PUT al backend
      const response = await tasksAPI.updateTask(task.id, updateData);
      console.log('Backend response:', response.data);
      
      // ✅ Aggiorna lo stato locale con la risposta del backend
      setTasks(tasks.map(t => t.id === task.id ? response.data : t));
      
      // 📊 Aggiorna le statistiche
      fetchStats();
      
      // 🎉 Feedback di successo
      console.log(`Task "${task.title}" ${response.data.completed ? 'completata' : 'riaperta'}!`);
      
    } catch (error) {
      console.error('Error toggling complete:', error);
      
      // 🔍 Log dettagliato dell'errore per debug
      if (error.response) {
        console.error('Response status:', error.response.status);
        console.error('Response data:', error.response.data);
      }
      
      setError('Errore nel cambiamento dello stato della task: ' + (error.response?.data?.error || error.message));
    }
  };

  

  const handleEditTask = (task) => {
    setEditingTask(task);
    setOpenTaskForm(true);
  };

  const handleCloseForm = () => {
    setOpenTaskForm(false);
    setEditingTask(null);
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" height="100vh">
        <CircularProgress />
      </Box>
    );
  }

  const dateStats = getDateStats();

  return (
    <Box sx={{ flexGrow: 1 }}>
      <AppBar position="static">
        <Toolbar>
          <TaskIcon sx={{ mr: 2 }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            Workflow - Benvenuto {user?.username}
          </Typography>
          <IconButton color="inherit" onClick={logout}>
            <LogoutIcon />
          </IconButton>
        </Toolbar>
      </AppBar>

      <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>
            {error}
          </Alert>
        )}

        {/* Statistiche Generali */}
        <Typography variant="h5" gutterBottom>
          Panoramica Generale
        </Typography>
        <Grid container spacing={3} sx={{ mb: 4 }}>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <TaskIcon color="primary" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Task Totali
                    </Typography>
                    <Typography variant="h5">
                      {stats.total_tasks || 0}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <CompletedIcon color="success" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Completate
                    </Typography>
                    <Typography variant="h5">
                      {stats.completed_tasks || 0}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <PendingIcon color="warning" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      In Sospeso
                    </Typography>
                    <Typography variant="h5">
                      {stats.pending_tasks || 0}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <CategoryIcon color="info" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Categorie
                    </Typography>
                    <Typography variant="h5">
                      {stats.categories_count || 0}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Statistiche Date */}
        <Typography variant="h5" gutterBottom>
          Scadenze
        </Typography>
        <Grid container spacing={3} sx={{ mb: 4 }}>
          <Grid item xs={12} sm={6} md={2.4}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <WarningIcon color="error" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Scadute
                    </Typography>
                    <Typography variant="h5" color="error">
                      {dateStats.overdue}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={2.4}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <TodayIcon color="warning" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Oggi
                    </Typography>
                    <Typography variant="h5" color="warning.main">
                      {dateStats.today}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={2.4}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <DateRangeIcon color="info" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Domani
                    </Typography>
                    <Typography variant="h5" color="info.main">
                      {dateStats.tomorrow}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={2.4}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <DateRangeIcon color="success" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Questa Settimana
                    </Typography>
                    <Typography variant="h5" color="success.main">
                      {dateStats.thisWeek}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} sm={6} md={2.4}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <ScheduleIcon color="disabled" sx={{ mr: 1 }} />
                  <Box>
                    <Typography color="textSecondary" gutterBottom>
                      Senza Data
                    </Typography>
                    <Typography variant="h5" color="text.secondary">
                      {dateStats.noDate}
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Lista Task */}
        <Paper sx={{ p: 3 }}>
          <Box display="flex" justifyContent="space-between" alignItems="center" mb={3}>
            <Typography variant="h5">Le Tue Task</Typography>
            <Button
              variant="contained"
              startIcon={<AddIcon />}
              onClick={() => setOpenTaskForm(true)}
            >
              Aggiungi Task
            </Button>
          </Box>
          
          <TaskList
            tasks={tasks}
            onToggleComplete={handleToggleComplete}
            onEditTask={handleEditTask}
            onDeleteTask={handleDeleteTask}
          />
        </Paper>

        {/* Floating Action Button */}
        <Fab
          color="primary"
          aria-label="aggiungi"
          sx={{ position: 'fixed', bottom: 16, right: 16 }}
          onClick={() => setOpenTaskForm(true)}
        >
          <AddIcon />
        </Fab>

        {/* Task Form Modal */}
        <TaskForm
          open={openTaskForm}
          onClose={handleCloseForm}
          onSubmit={editingTask ? 
            (data) => handleUpdateTask(editingTask.id, data) : 
            handleCreateTask
          }
          initialData={editingTask}
          title={editingTask ? 'Modifica Task' : 'Crea Nuova Task'}
        />
      </Container>
    </Box>
  );
};

export default Dashboard;
