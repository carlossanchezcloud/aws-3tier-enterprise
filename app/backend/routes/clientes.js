// routes/clientes.js
const express = require('express');
const { body, param, validationResult } = require('express-validator');
const Cliente = require('../models/Cliente');
const router  = express.Router();

// Middleware reutilizable: devuelve errores de validación
const validate = (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
        return res.status(422).json({ errors: errors.array() });
    }
    next();
};

// GET /api/clientes
router.get('/', async (req, res) => {
    try {
        const clientes = await Cliente.findAll({ order: [['apellido', 'ASC']] });
        res.json(clientes);
    } catch (err) {
        res.status(500).json({ error: 'Error al obtener clientes', detail: err.message });
    }
});

// GET /api/clientes/:id
router.get('/:id',
    param('id').isUUID(),
    validate,
    async (req, res) => {
        try {
            const cliente = await Cliente.findByPk(req.params.id);
            if (!cliente) return res.status(404).json({ error: 'Cliente no encontrado' });
            res.json(cliente);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    }
);

// POST /api/clientes
router.post('/',
    body('nombre').trim().notEmpty().isLength({ max: 100 }),
    body('apellido').trim().notEmpty().isLength({ max: 100 }),
    body('email').isEmail().normalizeEmail(),
    body('telefono').optional().isMobilePhone(),
    validate,
    async (req, res) => {
        try {
            const cliente = await Cliente.create(req.body);
            res.status(201).json(cliente);
        } catch (err) {
            if (err.name === 'SequelizeUniqueConstraintError') {
                return res.status(409).json({ error: 'El email ya está registrado' });
            }
            res.status(500).json({ error: err.message });
        }
    }
);

// PUT /api/clientes/:id
router.put('/:id',
    param('id').isUUID(),
    body('nombre').optional().trim().notEmpty(),
    body('email').optional().isEmail().normalizeEmail(),
    validate,
    async (req, res) => {
        try {
            const cliente = await Cliente.findByPk(req.params.id);
            if (!cliente) return res.status(404).json({ error: 'Cliente no encontrado' });
            await cliente.update(req.body);
            res.json(cliente);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    }
);

// DELETE /api/clientes/:id
router.delete('/:id',
    param('id').isUUID(),
    validate,
    async (req, res) => {
        try {
            const cliente = await Cliente.findByPk(req.params.id);
            if (!cliente) return res.status(404).json({ error: 'Cliente no encontrado' });
            await cliente.destroy();
            res.status(204).send();
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    }
);

module.exports = router;
