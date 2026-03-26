// server.js — Punto de entrada del backend
// Este proceso corre en la subred PRIVADA (10.0.2.0/24)
// Solo acepta tráfico del Security Group del frontend

require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const sequelize  = require('./config/database');

// Importar rutas
const clientesRouter  = require('./routes/clientes');
const serviciosRouter = require('./routes/servicios');
const turnosRouter    = require('./routes/turnos');

const app  = express();
const PORT = process.env.PORT || 3001;

// ── CORS ────────────────────────────────────────────────────
// Solo permite peticiones desde la IP/DNS del frontend
// En producción esto coincide con el Security Group a nivel de red
app.use(cors({
    origin:      process.env.CORS_ORIGIN,          // ej: http://ec2-xx.compute-1.amazonaws.com
    methods:     ['GET','POST','PUT','PATCH','DELETE','OPTIONS'],
    allowedHeaders: ['Content-Type','Authorization'],
    credentials: true
}));

// ── Middlewares generales ────────────────────────────────────
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// ── Health check (para ALB o monitoreo interno) ──────────────
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        uptime: process.uptime(),
        env:    process.env.NODE_ENV
    });
});

// ── Rutas de la API ──────────────────────────────────────────
app.use('/api/clientes',  clientesRouter);
app.use('/api/servicios', serviciosRouter);
app.use('/api/turnos',    turnosRouter);

// ── Ruta no encontrada ───────────────────────────────────────
app.use((req, res) => {
    res.status(404).json({ error: `Ruta ${req.method} ${req.path} no encontrada` });
});

// ── Manejo global de errores ─────────────────────────────────
app.use((err, req, res, next) => {
    console.error('[ERROR]', err.stack);
    res.status(500).json({ error: 'Error interno del servidor' });
});

// ── Arrancar servidor + verificar conexión a BD ──────────────
(async () => {
    try {
        await sequelize.authenticate();
        console.log('✅ Conexión a RDS PostgreSQL establecida correctamente');

        // En desarrollo: sync({ force: false }) solo agrega columnas nuevas sin borrar datos
        // En producción usar migraciones Sequelize en lugar de sync
        if (process.env.NODE_ENV !== 'production') {
            await sequelize.sync({ alter: false });
            console.log('✅ Modelos sincronizados');
        }

        app.listen(PORT, '0.0.0.0', () => {
            console.log(`🚀 Backend escuchando en puerto ${PORT}`);
            console.log(`   CORS permitido desde: ${process.env.CORS_ORIGIN}`);
        });
    } catch (error) {
        console.error('❌ No se pudo conectar a la base de datos:', error);
        process.exit(1);
    }
})();
