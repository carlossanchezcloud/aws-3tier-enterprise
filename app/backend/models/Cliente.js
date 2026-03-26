// models/Cliente.js
const { DataTypes } = require('sequelize');
const sequelize    = require('../config/database');

const Cliente = sequelize.define('Cliente', {
    id: {
        type:         DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey:   true
    },
    nombre: {
        type:         DataTypes.STRING(100),
        allowNull:    false,
        validate:     { notEmpty: true, len: [2, 100] }
    },
    apellido: {
        type:         DataTypes.STRING(100),
        allowNull:    false,
        validate:     { notEmpty: true, len: [2, 100] }
    },
    email: {
        type:         DataTypes.STRING(150),
        allowNull:    false,
        unique:       true,
        validate:     { isEmail: true }
    },
    telefono: {
        type:         DataTypes.STRING(20),
        allowNull:    true
    }
}, {
    tableName:  'clientes',
    timestamps: true,
    underscored: true   // snake_case en BD, camelCase en JS
});

module.exports = Cliente;
