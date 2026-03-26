-- ============================================================
-- SALÓN DE BELLEZA — Schema PostgreSQL
-- Ejecutar en RDS después de conectarse vía psql o pgAdmin
-- ============================================================

-- Extensión para UUIDs nativos
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- TABLA: clientes
-- ============================================================
CREATE TABLE clientes (
    id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre        VARCHAR(100)  NOT NULL,
    apellido      VARCHAR(100)  NOT NULL,
    email         VARCHAR(150)  NOT NULL UNIQUE,
    telefono      VARCHAR(20),
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLA: servicios
-- ============================================================
CREATE TABLE servicios (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(100)  NOT NULL,
    descripcion     TEXT,
    duracion_min    INTEGER       NOT NULL CHECK (duracion_min > 0),  -- minutos
    precio          NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    activo          BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLA: turnos
-- ============================================================
CREATE TABLE turnos (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id      UUID          NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
    servicio_id     UUID          NOT NULL REFERENCES servicios(id) ON DELETE RESTRICT,
    fecha_hora      TIMESTAMPTZ   NOT NULL,
    estado          VARCHAR(20)   NOT NULL DEFAULT 'pendiente'
                                  CHECK (estado IN ('pendiente','confirmado','cancelado','completado')),
    notas           TEXT,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ÍNDICES para performance
-- ============================================================
CREATE INDEX idx_turnos_cliente    ON turnos(cliente_id);
CREATE INDEX idx_turnos_servicio   ON turnos(servicio_id);
CREATE INDEX idx_turnos_fecha_hora ON turnos(fecha_hora);
CREATE INDEX idx_turnos_estado     ON turnos(estado);

-- ============================================================
-- FUNCIÓN + TRIGGER: auto-actualizar updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_clientes_updated_at
    BEFORE UPDATE ON clientes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_servicios_updated_at
    BEFORE UPDATE ON servicios
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_turnos_updated_at
    BEFORE UPDATE ON turnos
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- DATOS SEMILLA (seed) — servicios de ejemplo
-- ============================================================
INSERT INTO servicios (nombre, descripcion, duracion_min, precio) VALUES
    ('Corte de cabello',   'Corte y estilizado para dama o caballero', 30,  25000),
    ('Tinte completo',     'Aplicación de color con productos premium', 90, 85000),
    ('Manicure',           'Limpieza, forma y esmaltado de uñas',       45, 30000),
    ('Pedicure',           'Tratamiento completo de pies',               60, 40000),
    ('Alisado brasileño',  'Keratina + alisado con plancha',            120,150000);
