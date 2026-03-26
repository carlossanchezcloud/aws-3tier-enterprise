// models/Turno.js
const { DataTypes } = require('sequelize');
const sequelize    = require('../config/database');
const Cliente      = require('./Cliente');
const Servicio     = require('./Servicio');

const Turno = sequelize.define('Turno', {
    id: {
        type:         DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey:   true
    },
    clienteId: {                            // columna BD: cliente_id
        type:         DataTypes.UUID,
        allowNull:    false,
        references:   { model: 'clientes', key: 'id' }
    },
    servicioId: {                           // columna BD: servicio_id
        type:         DataTypes.UUID,
        allowNull:    false,
        references:   { model: 'servicios', key: 'id' }
    },
    fechaHora: {                            // columna BD: fecha_hora
        type:         DataTypes.DATE,
        allowNull:    false,
        validate:     { isDate: true }
    },
    estado: {
        type:         DataTypes.ENUM('pendiente','confirmado','cancelado','completado'),
        defaultValue: 'pendiente'
    },
    notas: {
        type:         DataTypes.TEXT,
        allowNull:    true
    }
}, {
    tableName:   'turnos',
    timestamps:  true,
    underscored: true
});

// ── Asociaciones ──────────────────────────────────────────
// Un turno pertenece a un cliente y a un servicio
Turno.belongsTo(Cliente,  { foreignKey: 'cliente_id',  as: 'cliente'  });
Turno.belongsTo(Servicio, { foreignKey: 'servicio_id', as: 'servicio' });

// Un cliente puede tener muchos turnos
Cliente.hasMany(Turno,  { foreignKey: 'cliente_id',  as: 'turnos' });
// Un servicio puede tener muchos turnos
Servicio.hasMany(Turno, { foreignKey: 'servicio_id', as: 'turnos' });

module.exports = Turno;
