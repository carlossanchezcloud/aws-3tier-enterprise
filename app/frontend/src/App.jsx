// src/App.jsx
import React from 'react';
import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom';
import Clientes  from './pages/Clientes';
import Servicios from './pages/Servicios';
import Turnos    from './pages/Turnos';
import './index.css';

export default function App() {
    return (
        <BrowserRouter>
            <div className="app-shell">
                <header className="topbar">
                    <div className="brand">
                        <span className="brand-icon">✂</span>
                        <span className="brand-name">Salón Bella Vista</span>
                    </div>
                    <nav className="nav">
                        <NavLink to="/"          className={({ isActive }) => isActive ? 'nav-link active' : 'nav-link'} end>Turnos</NavLink>
                        <NavLink to="/clientes"  className={({ isActive }) => isActive ? 'nav-link active' : 'nav-link'}>Clientes</NavLink>
                        <NavLink to="/servicios" className={({ isActive }) => isActive ? 'nav-link active' : 'nav-link'}>Servicios</NavLink>
                    </nav>
                </header>
                <main className="main-content">
                    <Routes>
                        <Route path="/"          element={<Turnos />}    />
                        <Route path="/clientes"  element={<Clientes />}  />
                        <Route path="/servicios" element={<Servicios />} />
                    </Routes>
                </main>
            </div>
        </BrowserRouter>
    );
}
