CREATE USER teiserver_dev WITH PASSWORD '123456789';
CREATE DATABASE teiserver_dev;
GRANT ALL PRIVILEGES ON DATABASE teiserver_dev to teiserver_dev;
ALTER USER teiserver_dev WITH SUPERUSER;

CREATE USER teiserver_test WITH PASSWORD '123456789';
CREATE DATABASE teiserver_test;
GRANT ALL PRIVILEGES ON DATABASE teiserver_test to teiserver_test;
ALTER USER teiserver_test WITH SUPERUSER;