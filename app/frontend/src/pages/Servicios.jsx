// src/pages/Servicios.jsx
import React, { useState, useEffect } from 'react';
import { serviciosApi } from '../services/api';

// Íconos simples por categoría según nombre del servicio
const ICON_MAP = {
    'corte':    '✂',
    'tinte':    '🎨',
    'manicure': '💅',
    'pedicure': '🦶',
    'alisado':  '💆',
    'default':  '✨'
};

const getIcon = (nombre = '') => {
    const n = nombre.toLowerCase();
    return Object.keys(ICON_MAP).find(k => n.includes(k))
        ? ICON_MAP[Object.keys(ICON_MAP).find(k => n.includes(k))]
        : ICON_MAP.default;
};

export default function Servicios() {
    const [servicios, setServicios] = useState([]);
    const [loading,   setLoading]   = useState(true);
    const [error,     setError]     = useState(null);
    const [showForm,  setShowForm]  = useState(false);
    const [editando,  setEditando]  = useState(null);
    const [mostrarTodos, setMostrarTodos] = useState(false);
    const [form, setForm] = useState({
        nombre: '', descripcion: '', duracionMin: '', precio: '', activo: true
    });

    const cargar = async () => {
        setLoading(true);
        setError(null);
        try {
            const data = await serviciosApi.getAll();
            const lista = Array.isArray(data) ? data : (Array.isArray(data?.data) ? data.data : []);
            setServicios(lista);
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { cargar(); }, [mostrarTodos]);

    const abrirNuevo = () => {
        setEditando(null);
        setForm({ nombre: '', descripcion: '', duracionMin: '', precio: '', activo: true });
        setShowForm(true);
    };

    const abrirEditar = (s) => {
        setEditando(s);
        setForm({
            nombre:      s.nombre,
            descripcion: s.descripcion || '',
            duracionMin: s.duracionMin,
            precio:      s.precio,
            activo:      s.activo
        });
        setShowForm(true);
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError(null);
        try {
            const payload = {
                ...form,
                duracionMin: Number(form.duracionMin),
                precio:      Number(form.precio)
            };
            if (editando) {
                await serviciosApi.update(editando.id, payload);
            } else {
                await serviciosApi.create(payload);
            }
            setShowForm(false);
            cargar();
        } catch (err) {
            setError(err.message);
        }
    };

    const toggleActivo = async (s) => {
        try {
            await serviciosApi.update(s.id, { activo: !s.activo });
            cargar();
        } catch (err) {
            setError(err.message);
        }
    };

    return (
        <div className="page">
            <div className="page-header">
                <h1>Servicios</h1>
                <div className="header-actions">
                    <label className="toggle-label">
                        <input
                            type="checkbox"
                            checked={mostrarTodos}
                            onChange={e => setMostrarTodos(e.target.checked)}
                        />
                        Ver desactivados
                    </label>
                    <button className="btn btn-primary" onClick={abrirNuevo}>
                        + Nuevo Servicio
                    </button>
                </div>
            </div>

            {error && <div className="alert alert-error">{error}</div>}

            {showForm && (
                <div className="modal-overlay" onClick={() => setShowForm(false)}>
                    <div className="modal" onClick={e => e.stopPropagation()}>
                        <h2>{editando ? 'Editar Servicio' : 'Nuevo Servicio'}</h2>
                        <form onSubmit={handleSubmit} className="form">
                            <label>Nombre del servicio
                                <input
                                    required
                                    type="text"
                                    value={form.nombre}
                                    onChange={e => setForm({ ...form, nombre: e.target.value })}
                                    placeholder="Ej: Corte y estilizado"
                                />
                            </label>
                            <label>Descripción
                                <textarea
                                    rows={2}
                                    value={form.descripcion}
                                    onChange={e => setForm({ ...form, descripcion: e.target.value })}
                                    placeholder="Descripción breve del servicio…"
                                />
                            </label>
                            <div className="form-row">
                                <label>Duración (minutos)
                                    <input
                                        required
                                        type="number"
                                        min="1"
                                        value={form.duracionMin}
                                        onChange={e => setForm({ ...form, duracionMin: e.target.value })}
                                        placeholder="30"
                                    />
                                </label>
                                <label>Precio (COP)
                                    <input
                                        required
                                        type="number"
                                        min="0"
                                        step="500"
                                        value={form.precio}
                                        onChange={e => setForm({ ...form, precio: e.target.value })}
                                        placeholder="25000"
                                    />
                                </label>
                            </div>
                            {editando && (
                                <label className="checkbox-label">
                                    <input
                                        type="checkbox"
                                        checked={form.activo}
                                        onChange={e => setForm({ ...form, activo: e.target.checked })}
                                    />
                                    Servicio activo (disponible para reservas)
                                </label>
                            )}
                            <div className="form-actions">
                                <button
                                    type="button"
                                    className="btn btn-secondary"
                                    onClick={() => setShowForm(false)}
                                >
                                    Cancelar
                                </button>
                                <button type="submit" className="btn btn-primary">
                                    {editando ? 'Guardar cambios' : 'Crear servicio'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {loading ? (
                <div className="loading">Cargando servicios…</div>
            ) : (
                <div className="servicios-grid">
                    {servicios.length === 0 ? (
                        <p className="empty-state">No hay servicios registrados.</p>
                    ) : servicios.map(s => (
                        <div
                            key={s.id}
                            className={`servicio-card ${!s.activo ? 'inactivo' : ''}`}
                        >
                            <div className="servicio-icon">{getIcon(s.nombre)}</div>
                            <div className="servicio-info">
                                <h3 className="servicio-nombre">{s.nombre}</h3>
                                {s.descripcion && (
                                    <p className="servicio-desc">{s.descripcion}</p>
                                )}
                                <div className="servicio-meta">
                                    <span className="meta-tag">⏱ {s.duracionMin} min</span>
                                    <span className="meta-tag precio">
                                        ${Number(s.precio).toLocaleString('es-CO')}
                                    </span>
                                    <span className={`meta-tag estado ${s.activo ? 'activo' : 'inactivo'}`}>
                                        {s.activo ? 'Activo' : 'Inactivo'}
                                    </span>
                                </div>
                            </div>
                            <div className="card-actions">
                                <button
                                    className="btn btn-secondary btn-sm"
                                    onClick={() => abrirEditar(s)}
                                >
                                    Editar
                                </button>
                                <button
                                    className={`btn btn-sm ${s.activo ? 'btn-warning' : 'btn-success'}`}
                                    onClick={() => toggleActivo(s)}
                                >
                                    {s.activo ? 'Desactivar' : 'Activar'}
                                </button>
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
