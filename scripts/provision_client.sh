set -e

echo " Script de Provisionamento Odoo Multi-tenant"

if [ -z "$1" ]; then
  echo " Uso: $0 <nome_cliente>"
  echo " Exemplo: $0 alfa"
  exit 1
fi

CLIENT_NAME="$1"
DOMAIN="${CLIENT_NAME}.isy.one"
COMPOSE_FILE="docker-compose-${CLIENT_NAME}.yml"
ENV_FILE=".env.${CLIENT_NAME}"

echo " Provisionando cliente: $CLIENT_NAME"
echo " Domínio: $DOMAIN"

# Verificar se o cliente já existe
if [ -f "$COMPOSE_FILE" ]; then
  echo "  Ambiente para o cliente '$CLIENT_NAME' já existe!"
  exit 1
fi

# Gerar senhas seguras
echo " Gerando senhas seguras..."
POSTGRES_PASSWORD=$(openssl rand -base64 16 | tr -d '/+' | cut -c1-16)
ODOO_ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)

# Criar arquivo .env para o cliente
echo " Criando arquivo de variáveis: $ENV_FILE"
cat > "$ENV_FILE" << ENVEOF
# Ambiente do Cliente ${CLIENT_NAME}
CLIENT_NAME=${CLIENT_NAME}
DOMAIN=${DOMAIN}

# Configurações PostgreSQL
POSTGRES_USER=odoo_${CLIENT_NAME}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=odoo_${CLIENT_NAME}

# Configurações Odoo
ODOO_ADMIN_PASSWORD=${ODOO_ADMIN_PASSWORD}
ENVEOF

# Criar docker-compose específico para o cliente
echo " Criando arquivo Docker Compose: $COMPOSE_FILE"
cat > "$COMPOSE_FILE" << COMPOSEEOF
version: '3.8'

services:
  postgres_${CLIENT_NAME}:
    image: postgres:15
    container_name: postgres_${CLIENT_NAME}
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - pgdata_${CLIENT_NAME}:/var/lib/postgresql/data
    networks:
      - traefik
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "traefik.enable=false"

  odoo_${CLIENT_NAME}:
    image: odoo:18.0
    container_name: odoo_${CLIENT_NAME}
    depends_on:
      - postgres_${CLIENT_NAME}
    environment:
      - HOST=postgres_${CLIENT_NAME}
      - USER=\${POSTGRES_USER}
      - PASSWORD=\${POSTGRES_PASSWORD}
      - DB_NAME=\${POSTGRES_DB}
      - ADMIN_PASSWORD=\${ODOO_ADMIN_PASSWORD}
    volumes:
      - odoo_data_${CLIENT_NAME}:/var/lib/odoo
    networks:
      - traefik
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.odoo_${CLIENT_NAME}.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.odoo_${CLIENT_NAME}.entrypoints=web"
      - "traefik.http.services.odoo_${CLIENT_NAME}.loadbalancer.server.port=8069"
      - "traefik.docker.network=traefik"

volumes:
  pgdata_${CLIENT_NAME}:
    driver: local
  odoo_data_${CLIENT_NAME}:
    driver: local

networks:
  traefik:
    external: true
COMPOSEEOF
