// models/Servicio.js
const { DataTypes } = require('sequelize');
const sequelize    = require('../config/database');

const Servicio = sequelize.define('Servicio', {
    id: {
        type:         DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey:   true
    },
    nombre: {
        type:         DataTypes.STRING(100),
        allowNull:    false,
        validate:     { notEmpty: true }
    },
    descripcion: {
        type:         DataTypes.TEXT,
        allowNull:    true
    },
    duracionMin: {                          // columna BD: duracion_min
        type:         DataTypes.INTEGER,
        allowNull:    false,
        validate:     { min: 1 }
    },
    precio: {
        type:         DataTypes.DECIMAL(10, 2),
        allowNull:    false,
        validate:     { min: 0 }
    },
    activo: {
        type:         DataTypes.BOOLEAN,
        defaultValue: true
    }
}, {
    tableName:   'servicios',
    timestamps:  true,
    underscored: true
});

module.exports = Servicio;
