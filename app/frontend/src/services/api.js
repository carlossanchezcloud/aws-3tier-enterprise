// src/services/api.js
// Cliente HTTP centralizado con Axios
// VITE_API_URL apunta a la IP privada del backend en la VPC

import axios from 'axios';

const api = axios.create({
    baseURL:        import.meta.env.VITE_API_URL,
    timeout:        10000,
    headers:        { 'Content-Type': 'application/json' },
    withCredentials: true   // necesario si el backend exige cookies/auth
});

// Interceptor de respuesta: manejo centralizado de errores
api.interceptors.response.use(
    response => response.data,
    error => {
        const message =
            error.response?.data?.error ||
            error.response?.data?.message ||
            error.message ||
            'Error desconocido';
        return Promise.reject(new Error(message));
    }
);

// ── Clientes ─────────────────────────────────────────────────
export const clientesApi = {
    getAll:  ()         => api.get('/clientes'),
    getById: (id)       => api.get(`/clientes/${id}`),
    create:  (data)     => api.post('/clientes', data),
    update:  (id, data) => api.put(`/clientes/${id}`, data),
    delete:  (id)       => api.delete(`/clientes/${id}`)
};

// ── Servicios ─────────────────────────────────────────────────
export const serviciosApi = {
    getAll:  ()     => api.get('/servicios'),
    getById: (id)   => api.get(`/servicios/${id}`),
    create:  (data) => api.post('/servicios', data),
    update:  (id, data) => api.put(`/servicios/${id}`, data)
};

// ── Turnos ─────────────────────────────────────────────────
export const turnosApi = {
    getAll:       (params) => api.get('/turnos', { params }),
    getById:      (id)     => api.get(`/turnos/${id}`),
    create:       (data)   => api.post('/turnos', data),
    updateEstado: (id, estado) => api.patch(`/turnos/${id}/estado`, { estado }),
    delete:       (id)     => api.delete(`/turnos/${id}`)
};

export default api;
