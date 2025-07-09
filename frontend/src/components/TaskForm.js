import React, { useState, useEffect } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Button,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Box,
  FormControlLabel,
  Checkbox,
} from '@mui/material';
import { DatePicker } from '@mui/x-date-pickers/DatePicker';
import { LocalizationProvider } from '@mui/x-date-pickers/LocalizationProvider';
import { AdapterDayjs } from '@mui/x-date-pickers/AdapterDayjs';
import dayjs from 'dayjs';
import 'dayjs/locale/it';

dayjs.locale('it');

const TaskForm = ({ open, onClose, onSubmit, initialData, title }) => {
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    category: '',
    priority: 'medium',
    due_date: null,
    completed: false,
  });

  useEffect(() => {
    if (initialData) {
      setFormData({
        title: initialData.title || '',
        description: initialData.description || '',
        category: initialData.category || '',
        priority: initialData.priority || 'medium',
        due_date: initialData.due_date ? dayjs(initialData.due_date) : null,
        completed: initialData.completed || false,
      });
    } else {
      setFormData({
        title: '',
        description: '',
        category: '',
        priority: 'medium',
        due_date: null,
        completed: false,
      });
    }
  }, [initialData, open]);

  const handleChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value,
    });
  };

  const handleDateChange = (date) => {
    setFormData({
      ...formData,
      due_date: date,
    });
  };

  const handleCheckboxChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.checked,
    });
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    
    // USA LO STESSO FORMATO IDENTICO CHE FUNZIONA PER CREATE
    const submitData = {
      title: formData.title.trim(),
      description: formData.description.trim(),
      category: formData.category.trim(),
      priority: formData.priority,
    };
    
    // Aggiungi due_date solo se presente
    if (formData.due_date && formData.due_date.isValid()) {
      submitData.due_date = formData.due_date.format('YYYY-MM-DD');
    }
    
    // NON INVIARE COMPLETED - gestito separatamente dal toggle
    // Il backend ha validation schema che non accetta completed
    
    console.log('Sending data (identical to CREATE):', submitData);
    onSubmit(submitData);
  };

  const today = dayjs();
  const getQuickDate = (days) => dayjs().add(days, 'day');

  return (
    <LocalizationProvider dateAdapter={AdapterDayjs} adapterLocale="it">
      <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
        <DialogTitle>{title}</DialogTitle>
        <DialogContent>
          <Box component="form" onSubmit={handleSubmit} sx={{ mt: 1 }}>
            <TextField
              margin="normal"
              required
              fullWidth
              id="title"
              label="Titolo Task"
              name="title"
              value={formData.title}
              onChange={handleChange}
              autoFocus
            />
            
            <TextField
              margin="normal"
              fullWidth
              id="description"
              label="Descrizione"
              name="description"
              multiline
              rows={3}
              value={formData.description}
              onChange={handleChange}
            />
            
            <TextField
              margin="normal"
              fullWidth
              id="category"
              label="Categoria"
              name="category"
              value={formData.category}
              onChange={handleChange}
              placeholder="es: Lavoro, Personale, Shopping"
            />
            
            <FormControl fullWidth margin="normal">
              <InputLabel id="priority-label">Priorità</InputLabel>
              <Select
                labelId="priority-label"
                id="priority"
                name="priority"
                value={formData.priority}
                label="Priorità"
                onChange={handleChange}
              >
                <MenuItem value="low">Bassa</MenuItem>
                <MenuItem value="medium">Media</MenuItem>
                <MenuItem value="high">Alta</MenuItem>
              </Select>
            </FormControl>
            
            <Box sx={{ mt: 2, mb: 1 }}>
              <DatePicker
                label="Data di Scadenza"
                value={formData.due_date}
                onChange={handleDateChange}
                minDate={today}
                format="DD/MM/YYYY"
                slotProps={{
                  textField: {
                    fullWidth: true,
                    margin: "normal",
                    helperText: "Seleziona una data di scadenza (opzionale)"
                  }
                }}
              />
              
              <Box sx={{ display: 'flex', gap: 1, mt: 1, flexWrap: 'wrap' }}>
                <Button
                  size="small"
                  variant="outlined"
                  onClick={() => handleDateChange(getQuickDate(0))}
                >
                  Oggi
                </Button>
                <Button
                  size="small"
                  variant="outlined"
                  onClick={() => handleDateChange(getQuickDate(1))}
                >
                  Domani
                </Button>
                <Button
                  size="small"
                  variant="outlined"
                  onClick={() => handleDateChange(getQuickDate(7))}
                >
                  Prossima settimana
                </Button>
                <Button
                  size="small"
                  variant="outlined"
                  onClick={() => handleDateChange(null)}
                >
                  Rimuovi data
                </Button>
              </Box>
            </Box>
            
            {/* Mostra checkbox solo per info, ma non inviare il valore */}
            {initialData && (
              <FormControlLabel
                control={
                  <Checkbox
                    checked={formData.completed}
                    onChange={handleCheckboxChange}
                    name="completed"
                    color="primary"
                  />
                }
                label="Task completata (usa il checkbox nella lista per cambiare)"
                sx={{ mt: 1 }}
                disabled
              />
            )}
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={onClose}>Annulla</Button>
          <Button onClick={handleSubmit} variant="contained">
            {initialData ? 'Aggiorna' : 'Crea'} Task
          </Button>
        </DialogActions>
      </Dialog>
    </LocalizationProvider>
  );
};

export default TaskForm;
