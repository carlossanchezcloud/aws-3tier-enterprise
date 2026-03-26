// src/pages/Clientes.jsx
import React, { useState, useEffect } from 'react';
import { clientesApi } from '../services/api';

export default function Clientes() {
    const [clientes, setClientes] = useState([]);
    const [loading,  setLoading]  = useState(true);
    const [error,    setError]    = useState(null);
    const [showForm, setShowForm] = useState(false);
    const [editando, setEditando] = useState(null);   // cliente que se está editando
    const [busqueda, setBusqueda] = useState('');
    const [form, setForm] = useState({
        nombre: '', apellido: '', email: '', telefono: ''
    });

    const cargar = async () => {
        setLoading(true);
        setError(null);
        try {
            const data = await clientesApi.getAll();
            setClientes(data);
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => { cargar(); }, []);

    const abrirNuevo = () => {
        setEditando(null);
        setForm({ nombre: '', apellido: '', email: '', telefono: '' });
        setShowForm(true);
    };

    const abrirEditar = (cliente) => {
        setEditando(cliente);
        setForm({
            nombre:   cliente.nombre,
            apellido: cliente.apellido,
            email:    cliente.email,
            telefono: cliente.telefono || ''
        });
        setShowForm(true);
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError(null);
        try {
            if (editando) {
                await clientesApi.update(editando.id, form);
            } else {
                await clientesApi.create(form);
            }
            setShowForm(false);
            cargar();
        } catch (err) {
            setError(err.message);
        }
    };

    const eliminar = async (id) => {
        if (!confirm('¿Eliminar este cliente? También se eliminarán sus turnos.')) return;
        try {
            await clientesApi.delete(id);
            cargar();
        } catch (err) {
            setError(err.message);
        }
    };

    const clientesFiltrados = clientes.filter(c =>
        `${c.nombre} ${c.apellido} ${c.email}`.toLowerCase().includes(busqueda.toLowerCase())
    );

    return (
        <div className="page">
            <div className="page-header">
                <h1>Clientes</h1>
                <div className="header-actions">
                    <input
                        className="input-field"
                        type="search"
                        placeholder="Buscar por nombre o email…"
                        value={busqueda}
                        onChange={e => setBusqueda(e.target.value)}
                    />
                    <button className="btn btn-primary" onClick={abrirNuevo}>
                        + Nuevo Cliente
                    </button>
                </div>
            </div>

            {error && <div className="alert alert-error">{error}</div>}

            {showForm && (
                <div className="modal-overlay" onClick={() => setShowForm(false)}>
                    <div className="modal" onClick={e => e.stopPropagation()}>
                        <h2>{editando ? 'Editar Cliente' : 'Nuevo Cliente'}</h2>
                        <form onSubmit={handleSubmit} className="form">
                            <div className="form-row">
                                <label>Nombre
                                    <input
                                        required
                                        type="text"
                                        value={form.nombre}
                                        onChange={e => setForm({ ...form, nombre: e.target.value })}
                                        placeholder="María"
                                    />
                                </label>
                                <label>Apellido
                                    <input
                                        required
                                        type="text"
                                        value={form.apellido}
                                        onChange={e => setForm({ ...form, apellido: e.target.value })}
                                        placeholder="García"
                                    />
                                </label>
                            </div>
                            <label>Email
                                <input
                                    required
                                    type="email"
                                    value={form.email}
                                    onChange={e => setForm({ ...form, email: e.target.value })}
                                    placeholder="maria@ejemplo.com"
                                />
                            </label>
                            <label>Teléfono
                                <input
                                    type="tel"
                                    value={form.telefono}
                                    onChange={e => setForm({ ...form, telefono: e.target.value })}
                                    placeholder="+57 300 000 0000"
                                />
                            </label>
                            <div className="form-actions">
                                <button
                                    type="button"
                                    className="btn btn-secondary"
                                    onClick={() => setShowForm(false)}
                                >
                                    Cancelar
                                </button>
                                <button type="submit" className="btn btn-primary">
                                    {editando ? 'Guardar cambios' : 'Crear cliente'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {loading ? (
                <div className="loading">Cargando clientes…</div>
            ) : (
                <div className="cards-grid">
                    {clientesFiltrados.length === 0 ? (
                        <p className="empty-state">
                            {busqueda ? 'No se encontraron resultados.' : 'Aún no hay clientes registrados.'}
                        </p>
                    ) : clientesFiltrados.map(c => (
                        <div key={c.id} className="card">
                            <div className="card-avatar">
                                {c.nombre[0]}{c.apellido[0]}
                            </div>
                            <div className="card-info">
                                <p className="card-name">{c.nombre} {c.apellido}</p>
                                <p className="card-email">{c.email}</p>
                                {c.telefono && (
                                    <p className="card-phone">{c.telefono}</p>
                                )}
                            </div>
                            <div className="card-actions">
                                <button
                                    className="btn btn-secondary btn-sm"
                                    onClick={() => abrirEditar(c)}
                                >
                                    Editar
                                </button>
                                <button
                                    className="btn btn-danger btn-sm"
                                    onClick={() => eliminar(c.id)}
                                >
                                    Eliminar
                                </button>
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
