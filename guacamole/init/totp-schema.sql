-- TOTP extension schema for Apache Guacamole (PostgreSQL)
-- Apply after initdb.sql if using the TOTP authentication extension
CREATE TABLE IF NOT EXISTS guacamole_user_totp_key (
    user_id    integer  NOT NULL,
    secret     bytea    NOT NULL,
    confirmed  boolean  NOT NULL DEFAULT FALSE,
    PRIMARY KEY (user_id),
    CONSTRAINT guacamole_user_totp_key_ibfk_1
        FOREIGN KEY (user_id)
        REFERENCES guacamole_user (user_id) ON DELETE CASCADE
);
