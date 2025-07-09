import React from 'react';
import {
  List,
  ListItem,
  ListItemText,
  ListItemIcon,
  ListItemSecondaryAction,
  IconButton,
  Checkbox,
  Typography,
  Chip,
  Box,
  Divider,
} from '@mui/material';
import {
  Edit as EditIcon,
  Delete as DeleteIcon,
  Schedule as ScheduleIcon,
  Warning as WarningIcon,
  CheckCircle as CheckCircleIcon,
} from '@mui/icons-material';
import dayjs from 'dayjs';
import 'dayjs/locale/it';
import relativeTime from 'dayjs/plugin/relativeTime';

// Configura dayjs
dayjs.locale('it');
dayjs.extend(relativeTime);

const TaskList = ({ tasks, onToggleComplete, onEditTask, onDeleteTask }) => {
  const getPriorityColor = (priority) => {
    switch (priority) {
      case 'high':
        return 'error';
      case 'medium':
        return 'warning';
      case 'low':
        return 'success';
      default:
        return 'default';
    }
  };

  const formatDate = (dateString) => {
    if (!dateString) return null;
    
    const date = dayjs(dateString);
    const now = dayjs();
    
    // Informazioni sulla data
    const daysDiff = date.diff(now, 'day');
    const isToday = date.isSame(now, 'day');
    const isTomorrow = date.isSame(now.add(1, 'day'), 'day');
    const isYesterday = date.isSame(now.subtract(1, 'day'), 'day');
    const isPast = date.isBefore(now, 'day');
    
    // Formato della data
    let dateText;
    if (isToday) {
      dateText = 'Oggi';
    } else if (isTomorrow) {
      dateText = 'Domani';
    } else if (isYesterday) {
      dateText = 'Ieri';
    } else if (Math.abs(daysDiff) <= 7) {
      dateText = date.format('dddd DD/MM');
    } else {
      dateText = date.format('DD/MM/YYYY');
    }
    
    // Tempo relativo
    const relativeText = date.fromNow();
    
    return {
      text: dateText,
      relative: relativeText,
      isPast,
      isToday,
      isTomorrow,
      daysDiff,
      fullDate: date.format('DD/MM/YYYY')
    };
  };

  const getDateChipColor = (dateInfo, isCompleted) => {
    if (isCompleted) return 'success';
    if (dateInfo.isPast) return 'error';
    if (dateInfo.isToday) return 'warning';
    if (dateInfo.isTomorrow) return 'info';
    return 'default';
  };

  const getDateIcon = (dateInfo, isCompleted) => {
    if (isCompleted) return <CheckCircleIcon fontSize="small" />;
    if (dateInfo.isPast) return <WarningIcon fontSize="small" />;
    return <ScheduleIcon fontSize="small" />;
  };

  // Ordina le task per data di scadenza
  const sortedTasks = [...tasks].sort((a, b) => {
    // Prima le task completate vanno in fondo
    if (a.completed && !b.completed) return 1;
    if (!a.completed && b.completed) return -1;
    
    // Poi ordina per data di scadenza
    if (!a.due_date && !b.due_date) return 0;
    if (!a.due_date) return 1;
    if (!b.due_date) return -1;
    
    return dayjs(a.due_date).isBefore(dayjs(b.due_date)) ? -1 : 1;
  });

  if (sortedTasks.length === 0) {
    return (
      <Box textAlign="center" py={4}>
        <Typography variant="h6" color="text.secondary">
          Nessuna task ancora
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Clicca "Aggiungi Task" per creare la tua prima task
        </Typography>
      </Box>
    );
  }

  return (
    <List>
      {sortedTasks.map((task, index) => {
        const dateInfo = task.due_date ? formatDate(task.due_date) : null;
        
        return (
          <React.Fragment key={task.id}>
            <ListItem
              sx={{
                bgcolor: task.completed ? 'action.hover' : 'inherit',
                borderRadius: 1,
                mb: 1,
                border: dateInfo?.isPast && !task.completed ? 
                  '1px solid' : 'none',
                borderColor: dateInfo?.isPast && !task.completed ? 
                  'error.main' : 'transparent',
              }}
            >
              <ListItemIcon>
                <Checkbox
                  edge="start"
                  checked={task.completed}
                  onChange={() => onToggleComplete(task)}
                  color="primary"
                />
              </ListItemIcon>
              
              <ListItemText
                primary={
                  <Box display="flex" alignItems="center" gap={1} flexWrap="wrap">
                    <Typography
                      variant="body1"
                      sx={{
                        textDecoration: task.completed ? 'line-through' : 'none',
                        color: task.completed ? 'text.secondary' : 'text.primary',
                        fontWeight: dateInfo?.isPast && !task.completed ? 'bold' : 'normal',
                      }}
                    >
                      {task.title}
                    </Typography>
                    
                    <Chip
                      label={task.priority}
                      size="small"
                      color={getPriorityColor(task.priority)}
                      variant="outlined"
                    />
                    
                    {task.category && (
                      <Chip
                        label={task.category}
                        size="small"
                        variant="outlined"
                      />
                    )}
                    
                    {dateInfo && (
                      <Chip
                        icon={getDateIcon(dateInfo, task.completed)}
                        label={dateInfo.text}
                        size="small"
                        color={getDateChipColor(dateInfo, task.completed)}
                        variant={dateInfo.isPast && !task.completed ? 'filled' : 'outlined'}
                        title={`Scadenza: ${dateInfo.fullDate} (${dateInfo.relative})`}
                      />
                    )}
                  </Box>
                }
                secondary={
                  <Box>
                    {task.description && (
                      <Typography
                        variant="body2"
                        color="text.secondary"
                        sx={{
                          textDecoration: task.completed ? 'line-through' : 'none',
                          mt: 0.5,
                        }}
                      >
                        {task.description}
                      </Typography>
                    )}
                    
                    {dateInfo && (
                      <Box display="flex" alignItems="center" gap={0.5} mt={0.5}>
                        <Typography 
                          variant="caption" 
                          color={dateInfo.isPast && !task.completed ? 'error.main' : 'text.secondary'}
                        >
                          {dateInfo.isPast && !task.completed ? 
                            `⚠️ Scaduta ${dateInfo.relative}` : 
                            `📅 Scadenza ${dateInfo.relative}`
                          }
                        </Typography>
                      </Box>
                    )}
                  </Box>
                }
              />
              
              <ListItemSecondaryAction>
                <IconButton
                  edge="end"
                  aria-label="modifica"
                  onClick={() => onEditTask(task)}
                  sx={{ mr: 1 }}
                >
                  <EditIcon />
                </IconButton>
                <IconButton
                  edge="end"
                  aria-label="elimina"
                  onClick={() => onDeleteTask(task.id)}
                  color="error"
                >
                  <DeleteIcon />
                </IconButton>
              </ListItemSecondaryAction>
            </ListItem>
            
            {index < sortedTasks.length - 1 && <Divider />}
          </React.Fragment>
        );
      })}
    </List>
  );
};

export default TaskList;