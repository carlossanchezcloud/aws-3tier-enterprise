// src/pages/Turnos.jsx
import React, { useState, useEffect } from 'react';
import { turnosApi, clientesApi, serviciosApi } from '../services/api';

const ESTADOS = ['pendiente','confirmado','cancelado','completado'];
const ESTADO_COLORS = {
    pendiente:   '#f59e0b',
    confirmado:  '#10b981',
    cancelado:   '#ef4444',
    completado:  '#6366f1'
};

export default function Turnos() {
    const [turnos,    setTurnos]    = useState([]);
    const [clientes,  setClientes]  = useState([]);
    const [servicios, setServicios] = useState([]);
    const [loading,   setLoading]   = useState(true);
    const [error,     setError]     = useState(null);
    const [showForm,  setShowForm]  = useState(false);
    const [filtroFecha, setFiltroFecha] = useState('');
    const [form, setForm] = useState({
        clienteId: '', servicioId: '', fechaHora: '', notas: ''
    });

    const cargarDatos = async () => {
        setLoading(true);
        setError(null);
        try {
            const params = filtroFecha ? { fecha: filtroFecha } : {};
            const [t, c, s] = await Promise.all([
                turnosApi.getAll(params),
                clientesApi.getAll(),
                serviciosApi.getAll()
            ]);
            setTurnos(t);
            setClientes(c);
            setServicios(s);
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { cargarDatos(); }, [filtroFecha]);

    const handleSubmit = async (e) => {
        e.preventDefault();
        try {
            await turnosApi.create(form);
            setShowForm(false);
            setForm({ clienteId: '', servicioId: '', fechaHora: '', notas: '' });
            cargarDatos();
        } catch (err) {
            setError(err.message);
        }
    };

    const cambiarEstado = async (id, estado) => {
        try {
            await turnosApi.updateEstado(id, estado);
            cargarDatos();
        } catch (err) { setError(err.message); }
    };

    const eliminar = async (id) => {
        if (!confirm('¿Eliminar este turno?')) return;
        try {
            await turnosApi.delete(id);
            cargarDatos();
        } catch (err) { setError(err.message); }
    };

    return (
        <div className="page">
            <div className="page-header">
                <h1>Agenda de Turnos</h1>
                <div className="header-actions">
                    <input
                        type="date" value={filtroFecha}
                        onChange={e => setFiltroFecha(e.target.value)}
                        className="input-field"
                    />
                    <button className="btn btn-primary" onClick={() => setShowForm(true)}>
                        + Nuevo Turno
                    </button>
                </div>
            </div>

            {error && <div className="alert alert-error">{error}</div>}

            {showForm && (
                <div className="modal-overlay" onClick={() => setShowForm(false)}>
                    <div className="modal" onClick={e => e.stopPropagation()}>
                        <h2>Nuevo Turno</h2>
                        <form onSubmit={handleSubmit} className="form">
                            <label>Cliente
                                <select required value={form.clienteId}
                                    onChange={e => setForm({...form, clienteId: e.target.value})}>
                                    <option value="">Seleccionar...</option>
                                    {clientes.map(c => (
                                        <option key={c.id} value={c.id}>{c.nombre} {c.apellido}</option>
                                    ))}
                                </select>
                            </label>
                            <label>Servicio
                                <select required value={form.servicioId}
                                    onChange={e => setForm({...form, servicioId: e.target.value})}>
                                    <option value="">Seleccionar...</option>
                                    {servicios.map(s => (
                                        <option key={s.id} value={s.id}>{s.nombre} — ${Number(s.precio).toLocaleString()}</option>
                                    ))}
                                </select>
                            </label>
                            <label>Fecha y Hora
                                <input type="datetime-local" required value={form.fechaHora}
                                    onChange={e => setForm({...form, fechaHora: e.target.value})}/>
                            </label>
                            <label>Notas
                                <textarea rows={2} value={form.notas}
                                    onChange={e => setForm({...form, notas: e.target.value})}
                                    placeholder="Observaciones opcionales..."/>
                            </label>
                            <div className="form-actions">
                                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>Cancelar</button>
                                <button type="submit" className="btn btn-primary">Reservar</button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {loading ? (
                <div className="loading">Cargando turnos...</div>
            ) : (
                <div className="table-wrapper">
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>Fecha y Hora</th>
                                <th>Cliente</th>
                                <th>Servicio</th>
                                <th>Precio</th>
                                <th>Estado</th>
                                <th>Acciones</th>
                            </tr>
                        </thead>
                        <tbody>
                            {turnos.length === 0 ? (
                                <tr><td colSpan={6} style={{textAlign:'center',color:'#6b7280'}}>No hay turnos para este día</td></tr>
                            ) : turnos.map(t => (
                                <tr key={t.id}>
                                    <td>{new Date(t.fechaHora).toLocaleString('es-CO')}</td>
                                    <td>{t.cliente?.nombre} {t.cliente?.apellido}</td>
                                    <td>{t.servicio?.nombre}</td>
                                    <td>${Number(t.servicio?.precio || 0).toLocaleString()}</td>
                                    <td>
                                        <select
                                            value={t.estado}
                                            onChange={e => cambiarEstado(t.id, e.target.value)}
                                            style={{
                                                background: ESTADO_COLORS[t.estado] + '22',
                                                color: ESTADO_COLORS[t.estado],
                                                border: `1px solid ${ESTADO_COLORS[t.estado]}44`,
                                                borderRadius: '6px', padding: '4px 8px', fontWeight: 600
                                            }}
                                        >
                                            {ESTADOS.map(e => <option key={e} value={e}>{e}</option>)}
                                        </select>
                                    </td>
                                    <td>
                                        <button className="btn btn-danger btn-sm" onClick={() => eliminar(t.id)}>✕</button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}
