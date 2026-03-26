// routes/turnos.js
const express  = require('express');
const { body, param, query, validationResult } = require('express-validator');
const Turno    = require('../models/Turno');
const Cliente  = require('../models/Cliente');
const Servicio = require('../models/Servicio');
const { Op }   = require('sequelize');
const router   = express.Router();

const validate = (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });
    next();
};

// GET /api/turnos?fecha=2024-12-01&estado=pendiente
router.get('/', async (req, res) => {
    try {
        const where = {};
        if (req.query.estado) where.estado = req.query.estado;
        if (req.query.fecha) {
            const day = new Date(req.query.fecha);
            const nextDay = new Date(day);
            nextDay.setDate(nextDay.getDate() + 1);
            where.fechaHora = { [Op.gte]: day, [Op.lt]: nextDay };
        }
        const turnos = await Turno.findAll({
            where,
            include: [
                { model: Cliente,  as: 'cliente',  attributes: ['id','nombre','apellido','email','telefono'] },
                { model: Servicio, as: 'servicio', attributes: ['id','nombre','duracionMin','precio'] }
            ],
            order: [['fechaHora', 'ASC']]
        });
        res.json(turnos);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/turnos/:id
router.get('/:id',
    param('id').isUUID(), validate,
    async (req, res) => {
        try {
            const turno = await Turno.findByPk(req.params.id, {
                include: [
                    { model: Cliente,  as: 'cliente'  },
                    { model: Servicio, as: 'servicio' }
                ]
            });
            if (!turno) return res.status(404).json({ error: 'Turno no encontrado' });
            res.json(turno);
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

// POST /api/turnos
router.post('/',
    body('clienteId').isUUID(),
    body('servicioId').isUUID(),
    body('fechaHora').isISO8601().toDate(),
    body('notas').optional().isString().trim(),
    validate,
    async (req, res) => {
        try {
            // Verificar que cliente y servicio existen
            const [cliente, servicio] = await Promise.all([
                Cliente.findByPk(req.body.clienteId),
                Servicio.findByPk(req.body.servicioId)
            ]);
            if (!cliente)  return res.status(404).json({ error: 'Cliente no encontrado' });
            if (!servicio) return res.status(404).json({ error: 'Servicio no encontrado' });
            if (!servicio.activo) return res.status(400).json({ error: 'El servicio no está disponible' });

            // Verificar conflicto de horario (mismo horario en ±duracion del servicio)
            const inicio  = new Date(req.body.fechaHora);
            const fin     = new Date(inicio.getTime() + servicio.duracionMin * 60000);
            const overlap = await Turno.findOne({
                where: {
                    estado:   { [Op.in]: ['pendiente','confirmado'] },
                    fechaHora: { [Op.lt]: fin, [Op.gte]: inicio }
                }
            });
            if (overlap) return res.status(409).json({ error: 'Ese horario ya está reservado' });

            const turno = await Turno.create(req.body);
            res.status(201).json(turno);
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

// PATCH /api/turnos/:id/estado  — cambiar solo el estado
router.patch('/:id/estado',
    param('id').isUUID(),
    body('estado').isIn(['pendiente','confirmado','cancelado','completado']),
    validate,
    async (req, res) => {
        try {
            const turno = await Turno.findByPk(req.params.id);
            if (!turno) return res.status(404).json({ error: 'Turno no encontrado' });
            await turno.update({ estado: req.body.estado });
            res.json(turno);
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

// DELETE /api/turnos/:id
router.delete('/:id',
    param('id').isUUID(), validate,
    async (req, res) => {
        try {
            const turno = await Turno.findByPk(req.params.id);
            if (!turno) return res.status(404).json({ error: 'Turno no encontrado' });
            await turno.destroy();
            res.status(204).send();
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

module.exports = router;
