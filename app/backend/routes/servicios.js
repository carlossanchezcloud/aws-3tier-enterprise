// routes/servicios.js
const express  = require('express');
const { body, param, validationResult } = require('express-validator');
const Servicio = require('../models/Servicio');
const router   = express.Router();

const validate = (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });
    next();
};

// GET /api/servicios  (solo activos por defecto)
router.get('/', async (req, res) => {
    try {
        const where = req.query.all === 'true' ? {} : { activo: true };
        const servicios = await Servicio.findAll({ where, order: [['nombre', 'ASC']] });
        res.json(servicios);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/servicios/:id
router.get('/:id',
    param('id').isUUID(), validate,
    async (req, res) => {
        try {
            const s = await Servicio.findByPk(req.params.id);
            if (!s) return res.status(404).json({ error: 'Servicio no encontrado' });
            res.json(s);
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

// POST /api/servicios
router.post('/',
    body('nombre').trim().notEmpty(),
    body('duracionMin').isInt({ min: 1 }),
    body('precio').isFloat({ min: 0 }),
    validate,
    async (req, res) => {
        try {
            const s = await Servicio.create(req.body);
            res.status(201).json(s);
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

// PUT /api/servicios/:id
router.put('/:id',
    param('id').isUUID(),
    body('precio').optional().isFloat({ min: 0 }),
    validate,
    async (req, res) => {
        try {
            const s = await Servicio.findByPk(req.params.id);
            if (!s) return res.status(404).json({ error: 'Servicio no encontrado' });
            await s.update(req.body);
            res.json(s);
        } catch (err) { res.status(500).json({ error: err.message }); }
    }
);

module.exports = router;
