// config/database.js
// Conexion a RDS MySQL usando variables de entorno
// El backend esta en subred privada → accede a RDS por IP interna (sin pasar por Internet)

require('dotenv').config();
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize(
    process.env.DB_NAME,
    process.env.DB_USER,
    process.env.DB_PASS,
    {
        host:    process.env.DB_HOST,
        port:    Number(process.env.DB_PORT) || 3306,
        dialect: 'mysql',

        // Pool de conexiones: ajustar según carga esperada
        pool: {
            max:     5,    // máximo de conexiones simultáneas
            min:     0,
            acquire: 30000, // ms antes de lanzar error
            idle:    10000  // ms antes de liberar una conexión inactiva
        },

        dialectOptions: {},

        logging: process.env.NODE_ENV === 'development'
            ? (msg) => console.log('[SQL]', msg)
            : false
    }
);

module.exports = sequelize;
